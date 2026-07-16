part of '../database.dart';

extension BackendBackupsOutboxRepository on BackendDatabase {
  // Backup operations
  void setBackup(
    String accountId,
    String backupData, {
    required String backupId,
    required int version,
    required String kdf,
    required String salt,
    required String backupKeyHint,
    int deletionWatermark = 0,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO backups (
        account_id,
        backup_id,
        version,
        kdf,
        salt,
        backup_key_hint,
        backup_data,
        created_at,
        deletion_watermark,
        requires_reupload
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0);
    ''');
    stmt.execute([
      accountId,
      backupId,
      version,
      kdf,
      salt,
      backupKeyHint,
      backupData,
      now,
      deletionWatermark,
    ]);
    stmt.close();
  }

  Map<String, dynamic>? getBackup(String accountId) {
    final stmt = _db.prepare('SELECT * FROM backups WHERE account_id = ?;');
    final res = stmt.select([accountId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'account_id': row['account_id'],
      'backup_id': row['backup_id'],
      'version': row['version'],
      'kdf': row['kdf'],
      'salt': row['salt'],
      'backup_key_hint': row['backup_key_hint'],
      'backup_data': row['backup_data'],
      'created_at': row['created_at'],
      'deletion_watermark': row['deletion_watermark'],
      'requires_reupload': row['requires_reupload'],
    };
  }

  void markBackupNeedsReupload(String accountId, int deletionWatermark) {
    final stmt = _db.prepare('''
      UPDATE backups
      SET deletion_watermark = ?,
          requires_reupload = 1
      WHERE account_id = ?;
    ''');
    stmt.execute([deletionWatermark, accountId]);
    stmt.close();
  }

  void createBackupMediaObject({
    required String objectId,
    required String accountId,
    required int byteSize,
    required String sha256,
    int? retentionUntil,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO backup_media_objects (
        object_id,
        account_id,
        byte_size,
        sha256,
        uploaded_bytes,
        status,
        created_at,
        updated_at,
        retention_until
      )
      VALUES (?, ?, ?, ?, 0, 'PENDING', ?, ?, ?);
    ''');
    stmt.execute([
      objectId,
      accountId,
      byteSize,
      sha256,
      now,
      now,
      retentionUntil ?? 0,
    ]);
    stmt.close();
  }

  Map<String, dynamic>? getBackupMediaObject(String objectId) {
    final stmt = _db.prepare(
      'SELECT * FROM backup_media_objects WHERE object_id = ?;',
    );
    final res = stmt.select([objectId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'object_id': row['object_id'],
      'account_id': row['account_id'],
      'byte_size': row['byte_size'],
      'sha256': row['sha256'],
      'uploaded_bytes': row['uploaded_bytes'],
      'status': row['status'],
      'created_at': row['created_at'],
      'updated_at': row['updated_at'],
      'retention_until': row['retention_until'],
    };
  }

  void updateBackupMediaProgress({
    required String objectId,
    required int uploadedBytes,
    required String status,
  }) {
    final stmt = _db.prepare('''
      UPDATE backup_media_objects
      SET uploaded_bytes = ?, status = ?, updated_at = ?
      WHERE object_id = ?;
    ''');
    stmt.execute([
      uploadedBytes,
      status,
      DateTime.now().millisecondsSinceEpoch,
      objectId,
    ]);
    stmt.close();
  }

  List<String> getExpiredBackupMediaObjectIds(int now) {
    final stmt = _db.prepare('''
      SELECT object_id FROM backup_media_objects
      WHERE retention_until > 0 AND retention_until < ?;
    ''');
    final res = stmt.select([now]);
    stmt.close();
    return res.map((row) => row['object_id'] as String).toList();
  }

  int getBackupMediaUsage(String accountId) {
    final stmt = _db.prepare('''
      SELECT COALESCE(SUM(byte_size), 0) AS total
      FROM backup_media_objects
      WHERE account_id = ? AND status != 'FAILED';
    ''');
    final res = stmt.select([accountId]);
    stmt.close();
    if (res.isEmpty) return 0;
    return res.first['total'] as int;
  }

  void deleteBackupMediaObject(String objectId) {
    final stmt = _db.prepare(
      'DELETE FROM backup_media_objects WHERE object_id = ?;',
    );
    stmt.execute([objectId]);
    stmt.close();
  }

  // Outbox operations
  void enqueueOutbox(String eventId, String type, String payload) {
    if (type == 'PUSH_NOTIFICATION' && _containsForbiddenPayloadKey(payload)) {
      throw ArgumentError(
        'Push notification payload must not contain plaintext',
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO outbox (event_id, type, payload, status, retries, created_at)
      VALUES (?, ?, ?, 'PENDING', 0, ?);
    ''');
    stmt.execute([eventId, type, payload, now]);
    stmt.close();
  }

  List<Map<String, dynamic>> getPendingOutbox() {
    final stmt = _db.prepare(
      "SELECT * FROM outbox WHERE status = 'PENDING' OR (status = 'FAILED' AND retries < 5);",
    );
    final res = stmt.select();
    stmt.close();
    return res
        .map(
          (row) => {
            'event_id': row['event_id'],
            'type': row['type'],
            'payload': row['payload'],
            'status': row['status'],
            'retries': row['retries'],
            'created_at': row['created_at'],
          },
        )
        .toList();
  }

  void updateOutboxStatus(String eventId, String status, int retries) {
    final stmt = _db.prepare(
      'UPDATE outbox SET status = ?, retries = ? WHERE event_id = ?;',
    );
    stmt.execute([status, retries, eventId]);
    stmt.close();
  }
}
