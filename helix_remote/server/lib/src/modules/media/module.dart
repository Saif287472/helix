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
  MediaModule(super.context, {required this.identity}) {
    api = _MediaFacade(this);
    identity.onAccountDeleted(
      (tx, accountId) =>
          context.outbox.enqueue(tx, purgeJob, {'account': accountId}),
    );
    // Reserved sizes, so uploads in progress count before their bytes land.
    context.storage.report(
      name,
      () async => (await context.db.queryOne(
        'SELECT coalesce(sum(size), 0)::int8 AS n FROM $schema.objects',
      ))!.integer('n'),
    );
  }

  late final MediaApi api;

  /// Only for the reconcile's "does this owner still exist" question; media
  /// never otherwise looks at identity (ADR-026).
  final IdentityApi identity;

  static const purgeJob = 'media.purge_account';

  /// A blob with no row is deleted by the weekly sweep once it is this old,
  /// so an upload whose row is being written is never touched.
  static const orphanGrace = Duration(days: 1);
  static const persistentMaxBytes = 5 * 1024 * 1024;
  static const backupMaxBytes = 100 * 1024 * 1024;
  static const attachmentQuota = 4 * 1024 * 1024 * 1024;
  static const persistentQuota = 50 * 1024 * 1024;
  static const backupQuota = 1024 * 1024 * 1024;

  /// The byte quota does not bound row count: the smallest legal object is
  /// one byte, so 4 GiB could be millions of rows that every sweep then has
  /// to delete one blob at a time (AUD-5-3). A generous cap, counted per
  /// kind, keeps a normal library far below it.
  static const maxObjectsPerKind = 100000;

  /// Rows the account export lists of the media section.
  static const exportLimit = 5000;

  /// How many rows one sweep batch reads. Small enough that a batch is a
  /// pause between deadline checks, not an unbounded run.
  static const sweepBatch = 500;

  static const _noId = '00000000-0000-0000-0000-000000000000';

  /// How long one expire sweep may run before it stops and leaves the rest
  /// to the next tick. Below the periodic scheduler's timeout for this job,
  /// so the sweep ends itself cleanly instead of being killed mid-delete.
  /// Each object's blob and row commit before the next starts, so a stopped
  /// run still made progress (AUD-5-3).
  Duration expireBudget = const Duration(minutes: 4);

  /// The account purge's budget: below the outbox runner's 60-second job
  /// timeout. A purge with rows left at its budget throws - progress is
  /// committed and the job retries the rest (AUD-5-3).
  Duration purgeBudget = const Duration(seconds: 45);

  /// How long a request that deletes a dropped backup's media may spend on
  /// blobs before it answers and leaves the rest to the expiry sweep
  /// (AUD-5-2). A normal backup names a handful; the cap is for a
  /// pathological one.
  Duration deleteBudget = const Duration(seconds: 10);

  /// How many distinct owners one reconcile batch examines.
  static const reconcileAccounts = 200;

  /// The reconcile's budget: below the periodic scheduler's timeout, so a
  /// run stops cleanly and the next one continues (AUD-5-1).
  Duration reconcileBudget = const Duration(minutes: 4);

  /// Where the sweeps read their deadline from. Null is the module's clock;
  /// a test replaces it to move time without sleeping.
  DateTime Function()? sweepClock;

  static const presignTtl = Duration(minutes: 15);

  static Duration? retention(MediaKind kind) => switch (kind) {
    MediaKind.attachment => const Duration(days: 30),
    MediaKind.backup => const Duration(days: 90),
    MediaKind.persistent => null,
  };

  /// Sizes and dates of stored objects (contents are client-encrypted).
  @override
  Future<Object?> exportAccount(SqlSession s, String accountId) async {
    // The smallest legal object is a byte, so an account's row count is not
    // bounded by its quota: the section lists the newest [exportLimit] and
    // says how many there are (owner ruling Q3, AUD-7-2).
    final rows = await s.query(
      'SELECT id, kind, size, completed_at, created_at, expires_at FROM $schema.objects '
      'WHERE owner_account = @a:uuid ORDER BY id DESC LIMIT @n:int4',
      {'a': accountId, 'n': exportLimit},
    );
    final total = await s.queryOne(
      'SELECT count(*)::int8 AS n FROM $schema.objects WHERE owner_account = @a:uuid',
      {'a': accountId},
    );
    return {
      'objects': [
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
      ],
      'total': total!.integer('n'),
      'truncated': total.integer('n') > rows.length,
    };
  }

  @override
  String get name => 'media';

  @override
  List<Migration> get migrations => const [
    Migration(1, 'media_baseline', _baseline),
    Migration(2, 'media_usage', _usage),
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

  /// The reserved bytes and object count per account and kind. Kept in its
  /// own row so a create can reserve both in one statement, which is what
  /// makes the quota hold under concurrent creates (AUD-5-4). Backfilled
  /// from what is already stored.
  static String _usage(String s) =>
      '''
CREATE TABLE $s.account_usage (
  account_id uuid NOT NULL,
  kind text NOT NULL CHECK (kind IN ('attachment', 'persistent', 'backup')),
  bytes bigint NOT NULL CHECK (bytes >= 0),
  objects bigint NOT NULL CHECK (objects >= 0),
  PRIMARY KEY (account_id, kind)
);
INSERT INTO $s.account_usage (account_id, kind, bytes, objects)
  SELECT owner_account, kind, coalesce(sum(size), 0)::bigint, count(*)::bigint
  FROM $s.objects GROUP BY owner_account, kind;
''';

  String get s => schema;

  ObjectStorage get _blobs => context.blobs;

  String _key(MediaKind kind, String id) => '${kind.wire}/$id';

  @override
  Map<String, JobHandler> get jobs => {purgeJob: _purgeAccount};

  @override
  List<PeriodicJob> get periodic => [
    PeriodicJob(
      'media.expire',
      const Duration(minutes: 30),
      expire,
      timeout: const Duration(minutes: 5),
    ),
    PeriodicJob(
      'media.sweep_orphans',
      const Duration(days: 7),
      () => sweepOrphans(),
    ),
    PeriodicJob(
      'media.reconcile',
      const Duration(days: 7),
      reconcile,
      timeout: const Duration(minutes: 5),
    ),
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
    // The server-wide budget first: per-account quotas add up on one disk.
    await context.storage.check();
    final quota = switch (req.kind) {
      MediaKind.attachment => attachmentQuota,
      MediaKind.persistent => persistentQuota,
      MediaKind.backup => backupQuota,
    };
    final id = Uuid.v7();
    final keep = retention(req.kind);
    await context.db.tx((tx) async {
      // Reserve bytes and the row atomically. A read-then-insert let two
      // concurrent creates both see the old sum and both insert (AUD-5-4);
      // the row lock on the usage row serializes them, and the guard is
      // re-evaluated after the wait.
      final reserved = await tx.queryOne(
        'INSERT INTO $s.account_usage AS usage (account_id, kind, bytes, objects) '
        'VALUES (@a:uuid, @k:text, @n:int8, 1) '
        'ON CONFLICT (account_id, kind) DO UPDATE SET '
        'bytes = usage.bytes + excluded.bytes, '
        'objects = usage.objects + 1 '
        'WHERE usage.bytes + excluded.bytes <= @quota:int8 '
        'AND usage.objects + 1 <= @cap:int8 '
        'RETURNING bytes, objects',
        {
          'a': q.device.accountId,
          'k': req.kind.wire,
          'n': req.size,
          'quota': quota,
          'cap': maxObjectsPerKind,
        },
      );
      if (reserved == null) {
        throw ApiError(
          ErrorCode.quotaExceeded,
          details: {'quota_bytes': quota, 'quota_objects': maxObjectsPerKind},
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
            url: _blobs
                .presignPut(
                  _key(req.kind, id),
                  presignTtl,
                  contentLength: req.size,
                )
                .toString(),
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

  /// `bytes=a-b`, `bytes=a-` or `bytes=-n`; null if unsatisfiable. A header
  /// that does not parse (including numbers too long for an int) is ignored.
  static (int, int)? _parseRange(String? header, int size) {
    if (header == null) return (0, size - 1);
    final m = RegExp(
      r'^bytes=(\d{0,18})-(\d{0,18})$',
    ).firstMatch(header.trim());
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
    await context.db.tx((tx) async {
      // Only the delete that removed the row gives the bytes back: a second
      // deleter racing it (a retried request, the sweep) would otherwise
      // release them twice and let the account exceed its quota.
      final removed = await tx.execute(
        'DELETE FROM $s.objects WHERE id = @id:uuid',
        {'id': id},
      );
      if (removed != 1) return;
      await _release(
        tx,
        object.string('owner_account'),
        _kind(object),
        object.integer('size'),
      );
    });
    return noContent();
  }

  /// Gives an object's bytes and row back to the account's quota.
  /// `greatest` keeps a counter that drifted low from going negative; the
  /// weekly reconcile repairs drift the other way.
  Future<void> _release(
    SqlSession db,
    String account,
    MediaKind kind,
    int size,
  ) => db.execute(
    'UPDATE $s.account_usage SET bytes = greatest(bytes - @n:int8, 0), '
    'objects = greatest(objects - 1, 0) '
    'WHERE account_id = @a:uuid AND kind = @k:text',
    {'a': account, 'k': kind.wire, 'n': size},
  );

  DateTime _sweepNow() => (sweepClock ?? context.clock.now)();

  /// Expired objects, and uploads abandoned for a day. Each blob goes
  /// before its row (review A-10): a blob that cannot be deleted (a file an
  /// antivirus scan holds open) keeps its row, so the next run tries again
  /// instead of forgetting the file.
  ///
  /// Keyset batches with a deadline (AUD-5-3): one blob delete per object
  /// against a store with no answer would otherwise run past the scheduler's
  /// timeout and be killed mid-sweep. The run stops at [expireBudget] with
  /// every finished object committed, and the next run starts at the rows
  /// that are left (public for tests).
  Future<void> expire() async {
    final deadline = _sweepNow().add(expireBudget);
    var after = _noId;
    var deleted = 0;
    var failed = 0;
    while (true) {
      final rows = await context.db.query(
        'SELECT id, owner_account, kind, size FROM $s.objects WHERE id > @after:uuid AND '
        "(expires_at < now() OR (completed_at IS NULL AND created_at < now() - interval '1 day')) "
        'ORDER BY id LIMIT $sweepBatch',
        {'after': after},
      );
      for (final r in rows) {
        if (_sweepNow().isAfter(deadline)) {
          log.info('media_expire_stopped', {
            'deleted': deleted,
            'failed': failed,
          });
          return;
        }
        if (await _deleteObject(r)) {
          deleted++;
        } else {
          failed++;
        }
      }
      if (rows.length < sweepBatch) break;
      after = rows.last.string('id');
    }
    if (failed > 0) log.warn('media_delete_failed', {'count': failed});
  }

  /// Every object of a deleted account, blob before row, in keyset batches.
  /// Throws when a blob could not be deleted or [purgeBudget] ran out before
  /// the last row, so the job retries what is left; whatever it did delete
  /// is committed, and the usage row stays for the rest (AUD-5-3).
  Future<void> _purgeAccount(Map<String, Object?> payload) async {
    final account = payload['account']! as String;
    final result = await _deleteAccountObjects(
      account,
      deadline: _sweepNow().add(purgeBudget),
    );
    if (!result.done) {
      throw StateError(
        'media purge of $account stopped at its budget with rows left',
      );
    }
    if (result.failed > 0) {
      throw StateError('${result.failed} media blobs could not be deleted');
    }
    // Every row is gone, so the account has no usage left to count. A
    // deletion that stopped on a blob failure keeps its rows (and counter)
    // for the retry.
    await context.db.execute(
      'DELETE FROM $s.account_usage WHERE account_id = @a:uuid',
      {'a': account},
    );
  }

  /// Deletes every object row of [account] in keyset batches, blob before
  /// row, until the rows run out or [deadline] passes. A blob that cannot
  /// be deleted keeps its row and is counted in [failed].
  Future<({int deleted, int failed, bool done})> _deleteAccountObjects(
    String account, {
    DateTime? deadline,
  }) async {
    var after = _noId;
    var deleted = 0;
    var failed = 0;
    while (true) {
      final rows = await context.db.query(
        'SELECT id, owner_account, kind, size FROM $s.objects '
        'WHERE owner_account = @a:uuid AND id > @after:uuid ORDER BY id '
        'LIMIT $sweepBatch',
        {'a': account, 'after': after},
      );
      if (rows.isEmpty) {
        return (deleted: deleted, failed: failed, done: true);
      }
      for (final r in rows) {
        if (deadline != null && _sweepNow().isAfter(deadline)) {
          return (deleted: deleted, failed: failed, done: false);
        }
        if (await _deleteObject(r)) {
          deleted++;
        } else {
          failed++;
        }
      }
      after = rows.last.string('id');
      if (rows.length < sweepBatch) {
        return (deleted: deleted, failed: failed, done: true);
      }
    }
  }

  /// Deletes the media of accounts that no longer exist, blob before row,
  /// and reports quota counters that disagree with the rows. Weekly and
  /// bounded: the backstop for an account purge that dead-lettered or was
  /// killed with objects left, since `persistent` rows never expire and a
  /// dead row still keeps its blob from looking like an orphan (AUD-5-1).
  /// Live accounts are never touched - existence is asked through
  /// [IdentityApi], not SQL. Returns what it examined and found (public for
  /// tests).
  Future<({int accounts, int deleted, int failed, int drift})>
  reconcile() async {
    final deadline = _sweepNow().add(reconcileBudget);
    var after = _noId;
    var accounts = 0;
    var deleted = 0;
    var failed = 0;
    var stopped = false;
    while (!stopped) {
      final owners = await context.db.query(
        'SELECT DISTINCT owner_account FROM $s.objects '
        'WHERE owner_account > @after:uuid ORDER BY owner_account '
        'LIMIT $reconcileAccounts',
        {'after': after},
      );
      if (owners.isEmpty) break;
      for (final owner in owners) {
        if (_sweepNow().isAfter(deadline)) {
          stopped = true;
          break;
        }
        final account = owner.string('owner_account');
        accounts++;
        if (await identity.account(context.db, account) != null) continue;
        final result = await _deleteAccountObjects(account, deadline: deadline);
        deleted += result.deleted;
        failed += result.failed;
        if (!result.done) {
          stopped = true;
          break;
        }
        // No account, no quota: its counters have nothing left to describe.
        await context.db.execute(
          'DELETE FROM $s.account_usage WHERE account_id = @a:uuid',
          {'a': account},
        );
      }
      after = owners.last.string('owner_account');
      if (owners.length < reconcileAccounts) break;
    }
    final drift = await quotaDrift();
    if (deleted > 0 || failed > 0 || drift > 0) {
      log.info('media_reconciled', {
        'accounts': accounts,
        'deleted': deleted,
        'failed': failed,
        'drift': drift,
      });
    }
    return (accounts: accounts, deleted: deleted, failed: failed, drift: drift);
  }

  /// Counter rows whose bytes or object count disagree with the objects
  /// actually stored. Reported, never silently corrected: a disagreement is
  /// a bug or a crash between a reservation and its release, and
  /// overwriting it would hide that.
  Future<int> quotaDrift() async => (await context.db.queryOne('''
SELECT count(*)::int8 AS n FROM $s.account_usage u
LEFT JOIN (
  SELECT owner_account, kind, sum(size)::bigint AS bytes, count(*)::bigint AS objects
  FROM $s.objects GROUP BY owner_account, kind
) o ON o.owner_account = u.account_id AND o.kind = u.kind
WHERE u.bytes <> coalesce(o.bytes, 0) OR u.objects <> coalesce(o.objects, 0)
'''))!.integer('n');

  /// Deletes one object's blob, then its row. False (row kept) when the
  /// blob delete failed.
  Future<bool> _deleteObject(Row r) async {
    final id = r.string('id');
    try {
      await _blobs.delete(_key(_kind(r), id));
    } on Object {
      return false;
    }
    await context.db.tx((tx) async {
      // Released only by the delete that removed the row (see `_delete`).
      final removed = await tx.execute(
        'DELETE FROM $s.objects WHERE id = @id:uuid',
        {'id': id},
      );
      if (removed != 1) return;
      await _release(
        tx,
        r.string('owner_account'),
        _kind(r),
        r.integer('size'),
      );
    });
    return true;
  }

  /// Blobs with no row, older than [orphanGrace]: left by a crash between
  /// the two deletes, or by a delete that failed before rows were kept for
  /// a retry. Weekly; returns how many were deleted (public for tests).
  Future<int> sweepOrphans() async {
    var removed = 0;
    final cutoff = context.clock.now().subtract(orphanGrace);
    for (final kind in MediaKind.values) {
      final batch = <String, StoredObject>{};
      Future<void> flush() async {
        if (batch.isEmpty) return;
        final known = {
          for (final r in await context.db.query(
            'SELECT id FROM $s.objects WHERE id = ANY(@ids:_uuid)',
            {'ids': batch.keys.toList()},
          ))
            r.string('id'),
        };
        for (final MapEntry(key: id, value: object) in batch.entries) {
          if (known.contains(id)) continue;
          try {
            await _blobs.delete(object.key);
            removed++;
          } on Object {
            // Tried again next week.
          }
        }
        batch.clear();
      }

      await for (final object in _blobs.list('${kind.wire}/')) {
        final id = object.key.substring(kind.wire.length + 1);
        if (!Uuid.isValid(id) || object.modified.isAfter(cutoff)) continue;
        batch[id] = object;
        if (batch.length >= 500) await flush();
      }
      await flush();
    }
    if (removed > 0) log.info('media_orphans_removed', {'count': removed});
    return removed;
  }
}

final class _MediaFacade implements MediaApi {
  _MediaFacade(this._m);

  final MediaModule _m;

  /// An empty `ANY(...)` would make an untyped array parameter; no object
  /// has this id (ids are server-generated v7).
  static const _noIds = ['00000000-0000-0000-0000-000000000000'];

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

  @override
  Future<List<String>> expireBackupMedia(
    Tx tx,
    String accountId,
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const [];
    return _expiredIds(
      await tx.query(
        'UPDATE ${_m.s}.objects SET expires_at = now() '
        "WHERE owner_account = @a:uuid AND kind = 'backup' AND id = ANY(@ids:_uuid) "
        'AND (expires_at IS NULL OR expires_at > now()) RETURNING id',
        {'a': accountId, 'ids': ids},
      ),
    );
  }

  @override
  Future<List<String>> expireBackupMediaExcept(
    Tx tx,
    String accountId,
    List<String> keep, {
    required DateTime createdBy,
  }) async => _expiredIds(
    await tx.query(
      'UPDATE ${_m.s}.objects SET expires_at = now() '
      "WHERE owner_account = @a:uuid AND kind = 'backup' "
      'AND NOT (id = ANY(@keep:_uuid)) AND created_at <= @by:timestamptz '
      'AND (expires_at IS NULL OR expires_at > now()) RETURNING id',
      {'a': accountId, 'keep': keep.isEmpty ? _noIds : keep, 'by': createdBy},
    ),
  );

  static List<String> _expiredIds(List<Row> rows) => [
    for (final r in rows) r.string('id'),
  ];

  @override
  Future<int> deleteBackupMedia(
    SqlSession db,
    String accountId,
    List<String> ids,
  ) async {
    if (ids.isEmpty) return 0;
    final deadline = _m._sweepNow().add(_m.deleteBudget);
    var deleted = 0;
    while (true) {
      final rows = await db.query(
        'SELECT id, owner_account, kind, size FROM ${_m.s}.objects '
        "WHERE owner_account = @a:uuid AND kind = 'backup' AND id = ANY(@ids:_uuid) "
        'ORDER BY id LIMIT ${MediaModule.sweepBatch}',
        {'a': accountId, 'ids': ids},
      );
      if (rows.isEmpty) break;
      var failed = 0;
      for (final r in rows) {
        if (_m._sweepNow().isAfter(deadline)) return deleted;
        if (await _m._deleteObject(r)) {
          deleted++;
        } else {
          failed++;
        }
      }
      // A blob that could not be deleted keeps its row (already expired by
      // the caller); the sweep retries it rather than this loop spinning.
      if (failed > 0 || rows.length < MediaModule.sweepBatch) break;
    }
    return deleted;
  }
}
