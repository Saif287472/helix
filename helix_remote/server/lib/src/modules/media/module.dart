import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/identity/api.dart';
import 'package:helix_remote_server/src/modules/media/api.dart';
import 'package:helix_remote_server/src/platform/blobs/object_storage.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/jobs/jobs.dart';
import 'package:helix_remote_server/src/platform/module.dart';
import 'package:shelf/shelf.dart';

/// Encrypted media objects (CRYPTO_V2.md §12). Random ids, no link to the
/// messages that use them, expiry instead of reference counting.
final class MediaModule extends ModuleBase implements ProvidesAccountExport {
  MediaModule(super.context, {required IdentityApi identity}) {
    api = _MediaFacade(this);
    identity.onAccountDeleted(
      (tx, accountId) =>
          context.outbox.enqueue(tx, purgeJob, {'account': accountId}),
    );
  }

  late final MediaApi api;

  static const purgeJob = 'media.purge_account';
  static const persistentMaxBytes = 5 * 1024 * 1024;
  static const backupMaxBytes = 100 * 1024 * 1024;
  static const attachmentQuota = 4 * 1024 * 1024 * 1024;
  static const persistentQuota = 50 * 1024 * 1024;
  static const backupQuota = 1024 * 1024 * 1024;
  static const presignTtl = Duration(minutes: 15);

  static Duration? retention(MediaKind kind) => switch (kind) {
    MediaKind.attachment => const Duration(days: 30),
    MediaKind.backup => const Duration(days: 90),
    MediaKind.persistent => null,
  };

  /// Sizes and dates of stored objects (contents are client-encrypted).
  @override
  Future<Object?> exportAccount(SqlSession s, String accountId) async {
    final rows = await s.query(
      'SELECT id, kind, size, completed_at, created_at, expires_at FROM $schema.objects '
      'WHERE owner_account = @a:uuid ORDER BY id',
      {'a': accountId},
    );
    return [
      for (final r in rows)
        compact({
          'media_id': r.string('id'),
          'kind': r.string('kind'),
          'size': r.integer('size'),
          'completed': !r.isNull('completed_at'),
          'created_at': toWireTime(r.time('created_at')),
          'expires_at': r.isNull('expires_at')
              ? null
              : toWireTime(r.time('expires_at')),
        }),
    ];
  }

  @override
  String get name => 'media';

  @override
  List<Migration> get migrations => const [
    Migration(1, 'media_baseline', _baseline),
  ];

  static String _baseline(String s) =>
      '''
CREATE TABLE $s.objects (
  id uuid PRIMARY KEY,
  owner_account uuid NOT NULL,
  owner_device uuid NOT NULL,
  kind text NOT NULL CHECK (kind IN ('attachment', 'persistent', 'backup')),
  size bigint NOT NULL,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz
);
CREATE INDEX objects_owner ON $s.objects (owner_account, kind);
CREATE INDEX objects_expires ON $s.objects (expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX objects_incomplete ON $s.objects (created_at) WHERE completed_at IS NULL;
''';

  String get s => schema;

  ObjectStorage get _blobs => context.blobs;

  String _key(MediaKind kind, String id) => '${kind.wire}/$id';

  @override
  Map<String, JobHandler> get jobs => {purgeJob: _purgeAccount};

  @override
  List<PeriodicJob> get periodic => [
    PeriodicJob('media.expire', const Duration(minutes: 30), _expire),
  ];

  @override
  void routes(RouteRegistry r) {
    r
      ..add(name, Routes.createUpload, _create)
      ..add(name, Routes.uploadContent, _upload, streamBody: true)
      ..add(name, Routes.uploadStatus, _status)
      ..add(name, Routes.downloadContent, _download)
      ..add(name, Routes.deleteMedia, _delete);
  }

  Future<Response> _create(HelixRequest q) async {
    final req = q.json(CreateUploadRequest.fromJson);
    final max = switch (req.kind) {
      MediaKind.attachment => context.config.maxAttachmentBytes,
      MediaKind.persistent => persistentMaxBytes,
      MediaKind.backup => backupMaxBytes,
    };
    if (req.size <= 0 || req.size > max) {
      throw ApiError(ErrorCode.payloadTooLarge, details: {'max_bytes': max});
    }
    final quota = switch (req.kind) {
      MediaKind.attachment => attachmentQuota,
      MediaKind.persistent => persistentQuota,
      MediaKind.backup => backupQuota,
    };
    final id = Uuid.v7();
    final keep = retention(req.kind);
    await context.db.tx((tx) async {
      final used = await tx.queryOne(
        'SELECT coalesce(sum(size), 0)::int8 AS n FROM $s.objects WHERE owner_account = @a:uuid AND kind = @k:text',
        {'a': q.device.accountId, 'k': req.kind.wire},
      );
      if (used!.integer('n') + req.size > quota) {
        throw ApiError(
          ErrorCode.quotaExceeded,
          details: {'quota_bytes': quota},
        );
      }
      await tx.execute(
        'INSERT INTO $s.objects (id, owner_account, owner_device, kind, size, expires_at) '
        'VALUES (@id:uuid, @a:uuid, @d:uuid, @k:text, @n:int8, '
        '${keep == null ? 'NULL' : "now() + make_interval(secs => @keep:int8)"})',
        {
          'id': id,
          'a': q.device.accountId,
          'd': q.device.deviceId,
          'k': req.kind.wire,
          'n': req.size,
          if (keep != null) 'keep': keep.inSeconds,
        },
      );
    });
    final expires = context.clock.now().add(presignTtl);
    final target = _blobs.supportsPresign
        ? UploadTarget(
            mediaId: id,
            url: _blobs.presignPut(_key(req.kind, id), presignTtl).toString(),
            expiresAt: expires,
            resumable: false,
          )
        : UploadTarget(
            mediaId: id,
            url: Routes.uploadContent.expand({'media_id': id}),
            expiresAt: expires,
          );
    return jsonResponse(target.toJson(), status: 201);
  }

  Future<Row?> _object(String id) => context.db.queryOne(
    'SELECT id, owner_account, kind, size, completed_at FROM $s.objects WHERE id = @id:uuid '
    'AND (expires_at IS NULL OR expires_at > now())',
    {'id': id},
  );

  MediaKind _kind(Row r) =>
      MediaKind.values.firstWhere((k) => k.wire == r.string('kind'));

  Future<Response> _upload(HelixRequest q) async {
    final id = q.uuidParam('media_id');
    final object = await _object(id);
    if (object == null ||
        object.string('owner_account') != q.device.accountId) {
      throw const ApiError(ErrorCode.notFound);
    }
    if (!object.isNull('completed_at')) {
      throw const ApiError(ErrorCode.conflict, message: 'already uploaded');
    }
    if (_blobs.supportsPresign) {
      throw const ApiError(
        ErrorCode.badRequest,
        message: 'upload to the presigned URL',
      );
    }
    final offset = int.tryParse(
      q.raw.headers[MediaHeaders.uploadOffset] ?? '0',
    );
    if (offset == null || offset < 0) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'upload-offset'},
      );
    }
    final size = object.integer('size');
    final declared = q.raw.contentLength;
    if (declared != null && offset + declared > size) {
      throw const ApiError(
        ErrorCode.payloadTooLarge,
        message: 'more bytes than declared',
      );
    }
    final int stored;
    try {
      stored = await _blobs.append(
        _key(_kind(object), id),
        q.raw.read(),
        offset: offset,
        maxSize: size,
      );
    } on OffsetMismatch catch (e) {
      throw ApiError(
        ErrorCode.conflict,
        message: 'resume from the stored offset',
        details: {'upload_offset': e.actual},
      );
    } on ObjectTooLarge {
      throw const ApiError(ErrorCode.payloadTooLarge);
    }
    if (stored == size) {
      await context.db.execute(
        'UPDATE $s.objects SET completed_at = now() WHERE id = @id:uuid',
        {'id': id},
      );
    }
    return Response(
      204,
      headers: {
        MediaHeaders.uploadOffset: '$stored',
        MediaHeaders.uploadLength: '$size',
      },
    );
  }

  Future<Response> _status(HelixRequest q) async {
    final id = q.uuidParam('media_id');
    final object = await _object(id);
    if (object == null ||
        object.string('owner_account') != q.device.accountId) {
      throw const ApiError(ErrorCode.notFound);
    }
    final stored = await _blobs.size(_key(_kind(object), id)) ?? 0;
    return Response(
      200,
      headers: {
        MediaHeaders.uploadOffset: '$stored',
        MediaHeaders.uploadLength: '${object.integer('size')}',
      },
    );
  }

  Future<Response> _download(HelixRequest q) async {
    final id = q.uuidParam('media_id');
    final object = await _object(id);
    if (object == null) throw const ApiError(ErrorCode.notFound);
    final key = _key(_kind(object), id);
    final size = object.integer('size');
    if (object.isNull('completed_at')) {
      // Presigned uploads complete without telling the server; check.
      if (!_blobs.supportsPresign || await _blobs.size(key) != size) {
        throw const ApiError(
          ErrorCode.notFound,
          message: 'upload not finished',
        );
      }
      await context.db.execute(
        'UPDATE $s.objects SET completed_at = now() WHERE id = @id:uuid',
        {'id': id},
      );
    }
    if (_blobs.supportsPresign) {
      return Response.found(
        _blobs.presignGet(key, const Duration(minutes: 5)).toString(),
      );
    }
    final range = _parseRange(q.raw.headers['range'], size);
    if (range == null) {
      return Response(416, headers: {'content-range': 'bytes */$size'});
    }
    final (start, end) = range;
    final partial = start != 0 || end != size - 1;
    return Response(
      partial ? 206 : 200,
      body: _blobs.read(key, start: start, endInclusive: end),
      headers: {
        'content-type': 'application/octet-stream',
        'content-length': '${end - start + 1}',
        'accept-ranges': 'bytes',
        if (partial) 'content-range': 'bytes $start-$end/$size',
      },
    );
  }

  /// `bytes=a-b`, `bytes=a-` or `bytes=-n`; null if unsatisfiable.
  static (int, int)? _parseRange(String? header, int size) {
    if (header == null) return (0, size - 1);
    final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (m == null) return (0, size - 1);
    final a = m.group(1)!;
    final b = m.group(2)!;
    int start;
    int end;
    if (a.isEmpty) {
      if (b.isEmpty) return null;
      final n = int.parse(b);
      start = size - n < 0 ? 0 : size - n;
      end = size - 1;
    } else {
      start = int.parse(a);
      end = b.isEmpty ? size - 1 : int.parse(b);
    }
    if (start >= size || start > end) return null;
    return (start, end >= size ? size - 1 : end);
  }

  Future<Response> _delete(HelixRequest q) async {
    final id = q.uuidParam('media_id');
    final object = await _object(id);
    if (object == null ||
        object.string('owner_account') != q.device.accountId) {
      throw const ApiError(ErrorCode.notFound);
    }
    await _blobs.delete(_key(_kind(object), id));
    await context.db.execute('DELETE FROM $s.objects WHERE id = @id:uuid', {
      'id': id,
    });
    return noContent();
  }

  /// Expired objects, and uploads abandoned for a day.
  Future<void> _expire() async {
    while (true) {
      final rows = await context.db.query(
        "DELETE FROM $s.objects WHERE id IN (SELECT id FROM $s.objects WHERE expires_at < now() "
        "OR (completed_at IS NULL AND created_at < now() - interval '1 day') LIMIT 500) "
        'RETURNING id, kind',
      );
      if (rows.isEmpty) return;
      for (final r in rows) {
        await _blobs.delete(_key(_kind(r), r.string('id')));
      }
    }
  }

  Future<void> _purgeAccount(Map<String, Object?> payload) async {
    final account = payload['account']! as String;
    final rows = await context.db.query(
      'DELETE FROM $s.objects WHERE owner_account = @a:uuid RETURNING id, kind',
      {'a': account},
    );
    for (final r in rows) {
      await _blobs.delete(_key(_kind(r), r.string('id')));
    }
  }
}

final class _MediaFacade implements MediaApi {
  _MediaFacade(this._m);

  final MediaModule _m;

  @override
  Future<int> extendBackupMedia(
    SqlSession db,
    String accountId,
    List<String> ids,
  ) async {
    if (ids.isEmpty) return 0;
    return db.execute(
      "UPDATE ${_m.s}.objects SET expires_at = now() + interval '90 days' "
      "WHERE owner_account = @a:uuid AND kind = 'backup' AND id = ANY(@ids:_uuid)",
      {'a': accountId, 'ids': ids},
    );
  }
}
