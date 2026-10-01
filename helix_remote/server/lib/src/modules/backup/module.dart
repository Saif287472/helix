import 'dart:convert';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/identity/api.dart';
import 'package:helix_remote_server/src/modules/media/api.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/module.dart';
import 'package:shelf/shelf.dart';

/// Encrypted backups (F2, CRYPTO_V2.md §13). The server stores ciphertext
/// it cannot open. The automatic history backup is keyed by the account
/// identity key, so it is deleted whenever that key changes.
final class BackupModule extends ModuleBase {
  BackupModule(
    super.context, {
    required IdentityApi identity,
    required this.media,
  }) {
    identity
      ..onIdentityKeyChanged(
        (tx, accountId, _) => _deleteHistory(tx, accountId),
      )
      ..onAccountDeleted((tx, accountId) async {
        await _deleteHistory(tx, accountId);
        await tx.execute(
          'DELETE FROM $schema.full_backups WHERE account_id = @a:uuid',
          {'a': accountId},
        );
      });
  }

  final MediaApi media;

  @override
  String get name => 'backup';

  @override
  List<Migration> get migrations => const [
    Migration(1, 'backup_baseline', _baseline),
  ];

  static String _baseline(String s) =>
      '''
CREATE TABLE $s.history_backups (
  account_id uuid PRIMARY KEY,
  version integer NOT NULL,
  data bytea NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE $s.full_backups (
  account_id uuid PRIMARY KEY,
  backup_id uuid NOT NULL,
  version integer NOT NULL,
  envelope jsonb NOT NULL,
  media_ids uuid[] NOT NULL DEFAULT '{}',
  updated_at timestamptz NOT NULL DEFAULT now()
);
''';

  Future<void> _deleteHistory(SqlSession db, String accountId) => db.execute(
    'DELETE FROM $schema.history_backups WHERE account_id = @a:uuid',
    {'a': accountId},
  );

  @override
  void routes(RouteRegistry r) {
    // Base64 inflates bodies by a third, plus JSON framing.
    const historyBody = HistoryBackup.maxBytes * 4 ~/ 3 + 64 * 1024;
    const fullBody = FullBackup.maxEnvelopeBytes + 64 * 1024;
    r
      ..add(
        name,
        Routes.putHistoryBackup,
        _putHistory,
        maxBodyBytes: historyBody,
      )
      ..add(name, Routes.getHistoryBackup, _getHistory, allowSuspended: true)
      ..add(
        name,
        Routes.deleteHistoryBackup,
        _deleteHistoryRoute,
        allowSuspended: true,
      )
      ..add(name, Routes.putFullBackup, _putFull, maxBodyBytes: fullBody)
      ..add(name, Routes.getFullBackup, _getFull, allowSuspended: true)
      ..add(name, Routes.deleteFullBackup, _deleteFull, allowSuspended: true);
  }

  Future<Response> _putHistory(HelixRequest q) async {
    final req = q.json(HistoryBackup.fromJson);
    if (req.data.length > HistoryBackup.maxBytes) {
      throw const ApiError(ErrorCode.payloadTooLarge);
    }
    final n = await context.db.execute(
      'INSERT INTO $schema.history_backups (account_id, version, data) VALUES (@a:uuid, @v:int4, @d:bytea) '
      'ON CONFLICT (account_id) DO UPDATE SET version = excluded.version, data = excluded.data, updated_at = now() '
      'WHERE $schema.history_backups.version < excluded.version',
      {'a': q.device.accountId, 'v': req.version, 'd': req.data},
    );
    if (n == 0) {
      throw const ApiError(
        ErrorCode.versionConflict,
        message: 'a newer backup exists',
      );
    }
    return noContent();
  }

  Future<Response> _getHistory(HelixRequest q) async {
    final r = await context.db.queryOne(
      'SELECT version, data, updated_at FROM $schema.history_backups WHERE account_id = @a:uuid',
      {'a': q.device.accountId},
    );
    if (r == null) throw const ApiError(ErrorCode.notFound);
    return jsonResponse(
      HistoryBackup(
        version: r.integer('version'),
        data: r.bytes('data'),
        updatedAt: r.time('updated_at'),
      ).toJson(),
    );
  }

  Future<Response> _deleteHistoryRoute(HelixRequest q) async {
    await _deleteHistory(context.db, q.device.accountId);
    return noContent();
  }

  /// Refuses envelopes that carry a plaintext secret at any depth: a client
  /// bug must not upload the key that opens the backup.
  static bool _carriesSecret(Object? value) => switch (value) {
    final Map<Object?, Object?> m => m.entries.any(
      (e) =>
          FullBackup.forbiddenFields.contains(e.key) || _carriesSecret(e.value),
    ),
    final List<Object?> l => l.any(_carriesSecret),
    _ => false,
  };

  Future<Response> _putFull(HelixRequest q) async {
    final req = q.json(FullBackup.fromJson);
    if (!Uuid.isValid(req.backupId) ||
        req.mediaIds.any((id) => !Uuid.isValid(id))) {
      throw const ApiError(ErrorCode.invalidField);
    }
    if (_carriesSecret(req.envelope)) {
      throw const ApiError(
        ErrorCode.invalidField,
        message:
            'backups must not contain backup_key, passphrase or recovery_phrase',
      );
    }
    await context.db.tx((tx) async {
      final n = await tx.execute(
        'INSERT INTO $schema.full_backups (account_id, backup_id, version, envelope, media_ids) '
        'VALUES (@a:uuid, @b:uuid, @v:int4, @e:jsonb, @m:_uuid) '
        'ON CONFLICT (account_id) DO UPDATE SET backup_id = excluded.backup_id, version = excluded.version, '
        'envelope = excluded.envelope, media_ids = excluded.media_ids, updated_at = now() '
        'WHERE $schema.full_backups.version < excluded.version',
        {
          'a': q.device.accountId,
          'b': req.backupId,
          'v': req.version,
          'e': jsonEncode(req.envelope),
          'm': req.mediaIds,
        },
      );
      if (n == 0) {
        throw const ApiError(
          ErrorCode.versionConflict,
          message: 'a newer backup exists',
        );
      }
      await media.extendBackupMedia(tx, q.device.accountId, req.mediaIds);
    });
    return noContent();
  }

  Future<Response> _getFull(HelixRequest q) async {
    final r = await context.db.queryOne(
      'SELECT backup_id, version, envelope, media_ids, updated_at FROM $schema.full_backups WHERE account_id = @a:uuid',
      {'a': q.device.accountId},
    );
    if (r == null) throw const ApiError(ErrorCode.notFound);
    return jsonResponse(
      FullBackup(
        backupId: r.string('backup_id'),
        version: r.integer('version'),
        envelope: r.json('envelope'),
        mediaIds: r.strings('media_ids'),
        updatedAt: r.time('updated_at'),
      ).toJson(),
    );
  }

  Future<Response> _deleteFull(HelixRequest q) async {
    await context.db.execute(
      'DELETE FROM $schema.full_backups WHERE account_id = @a:uuid',
      {'a': q.device.accountId},
    );
    return noContent();
  }
}
