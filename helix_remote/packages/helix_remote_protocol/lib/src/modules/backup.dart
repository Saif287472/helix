import 'dart:typed_data';

import 'package:helix_remote_protocol/src/json.dart';

/// `PUT`/`GET /v1/backups/history`: the automatic, AIK-keyed text history
/// backup (CRYPTO_V2.md §13). Opaque to the server; at most [maxBytes].
final class HistoryBackup {
  const HistoryBackup({
    required this.version,
    required this.data,
    this.updatedAt,
  });

  static const maxBytes = 16 * 1024 * 1024;

  /// Increases on every upload; `PUT` with an older version is refused
  /// (`version_conflict`), so a stale device cannot overwrite a newer backup.
  final int version;
  final Uint8List data;
  final DateTime? updatedAt;

  JsonMap toJson() => compact({
    'version': version,
    'data': encodeBytes(data),
    'updated_at': updatedAt == null ? null : toWireTime(updatedAt!),
  });

  factory HistoryBackup.fromJson(JsonReader json) => HistoryBackup(
    version: json.integer('version'),
    data: json.bytes('data'),
    updatedAt: json.optTime('updated_at'),
  );
}

/// `PUT`/`GET /v1/backups/full`: the user-secret backup envelope (F2,
/// envelope v3). The server checks only shape and size; it refuses bodies
/// that carry `backup_key`, `passphrase` or `recovery_phrase` fields.
final class FullBackup {
  const FullBackup({
    required this.backupId,
    required this.version,
    required this.envelope,
    this.mediaIds = const [],
    this.updatedAt,
  });

  static const maxEnvelopeBytes = 64 * 1024 * 1024;
  static const forbiddenFields = {
    'backup_key',
    'passphrase',
    'recovery_phrase',
  };

  final String backupId;
  final int version;

  /// The encrypted envelope (opaque JSON object).
  final JsonMap envelope;

  /// `backup` media objects this backup references (their retention is
  /// refreshed on upload).
  final List<String> mediaIds;
  final DateTime? updatedAt;

  JsonMap toJson() => compact({
    'backup_id': backupId,
    'version': version,
    'envelope': envelope,
    'media_ids': mediaIds,
    'updated_at': updatedAt == null ? null : toWireTime(updatedAt!),
  });

  factory FullBackup.fromJson(JsonReader json) => FullBackup(
    backupId: json.nonEmpty('backup_id'),
    version: json.integer('version'),
    envelope: json.object('envelope').json,
    mediaIds: json.optStrings('media_ids'),
    updatedAt: json.optTime('updated_at'),
  );
}
