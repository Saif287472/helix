part of '../database.dart';

extension BackendAttachmentsRepository on BackendDatabase {
  // ---------------------------------------------------------------------------
  // Attachment operations
  // ---------------------------------------------------------------------------

  void createAttachment({
    required String fileId,
    required String accountId,
    required int fileSize,
    required String fileHash,
    int? createdAt,
  }) {
    final time = createdAt ?? DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO attachments (file_id, account_id, file_size, file_hash, uploaded_bytes, status, created_at)
      VALUES (?, ?, ?, ?, 0, 'PENDING', ?)
      ON CONFLICT(file_id) DO UPDATE SET
        account_id = excluded.account_id,
        file_size = excluded.file_size,
        file_hash = excluded.file_hash,
        uploaded_bytes = 0,
        status = 'PENDING',
        created_at = excluded.created_at
      WHERE attachments.status != 'COMPLETED';
    ''');
    stmt.execute([fileId, accountId, fileSize, fileHash, time]);
    stmt.close();
  }

  List<String> getOrphanAttachmentIds(int olderThanTimestamp) {
    final stmt = _db.prepare('''
      SELECT file_id FROM attachments 
      WHERE status != 'COMPLETED' AND created_at < ?;
    ''');
    final res = stmt.select([olderThanTimestamp]);
    stmt.close();
    return res.map((row) => row['file_id'] as String).toList();
  }

  List<String> getAttachmentsOlderThan(int olderThanTimestamp) {
    final stmt = _db.prepare('''
      SELECT file_id FROM attachments 
      WHERE status = 'COMPLETED' AND created_at < ?;
    ''');
    final res = stmt.select([olderThanTimestamp]);
    stmt.close();
    return res.map((row) => row['file_id'] as String).toList();
  }

  Map<String, dynamic>? getAttachment(String fileId) {
    final stmt = _db.prepare('SELECT * FROM attachments WHERE file_id = ?;');
    final result = stmt.select([fileId]);
    stmt.close();
    if (result.isEmpty) return null;
    final row = result.first;
    return {
      'file_id': row['file_id'],
      'account_id': row['account_id'],
      'file_size': row['file_size'],
      'file_hash': row['file_hash'],
      'uploaded_bytes': row['uploaded_bytes'],
      'status': row['status'],
    };
  }

  void updateAttachmentProgress(
    String fileId,
    int uploadedBytes,
    String status,
  ) {
    final stmt = _db.prepare('''
      UPDATE attachments SET uploaded_bytes = ?, status = ? WHERE file_id = ?;
    ''');
    stmt.execute([uploadedBytes, status, fileId]);
    stmt.close();
  }

  void registerAttachmentReference(String fileId, String messageId) {
    final stmt = _db.prepare('''
      INSERT OR IGNORE INTO attachment_references (file_id, message_id)
      VALUES (?, ?);
    ''');
    stmt.execute([fileId, messageId]);
    stmt.close();
  }

  void grantAttachmentAccess({
    required String fileId,
    required String accountId,
    int? grantedAt,
  }) {
    final time = grantedAt ?? DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT OR IGNORE INTO attachment_recipient_grants (file_id, account_id, granted_at)
      VALUES (?, ?, ?);
    ''');
    stmt.execute([fileId, accountId, time]);
    stmt.close();
  }

  bool canAccessAttachment(String fileId, String accountId) {
    final attachment = getAttachment(fileId);
    if (attachment == null) return false;
    if (attachment['account_id'] == accountId) return true;

    final stmt = _db.prepare('''
      SELECT 1 FROM attachment_recipient_grants
      WHERE file_id = ? AND account_id = ?
      LIMIT 1;
    ''');
    final res = stmt.select([fileId, accountId]);
    stmt.close();
    return res.isNotEmpty;
  }

  int getAttachmentReferenceCount(String fileId) {
    final stmt = _db.prepare('''
      SELECT COUNT(*) FROM attachment_references WHERE file_id = ?;
    ''');
    final res = stmt.select([fileId]);
    stmt.close();
    if (res.isEmpty) return 0;
    return res.first.columnAt(0) as int;
  }

  void deleteAttachmentReferences(String messageId) {
    final stmt = _db.prepare(
      'DELETE FROM attachment_references WHERE message_id = ?;',
    );
    stmt.execute([messageId]);
    stmt.close();
  }

  List<String> getReferencedFileIds(String messageId) {
    final stmt = _db.prepare(
      'SELECT file_id FROM attachment_references WHERE message_id = ?;',
    );
    final res = stmt.select([messageId]);
    stmt.close();
    return res.map((row) => row['file_id'] as String).toList();
  }

  void deleteAttachmentRow(String fileId) {
    final stmt = _db.prepare('DELETE FROM attachments WHERE file_id = ?;');
    stmt.execute([fileId]);
    stmt.close();
  }

  int getAccountStorageUsage(String accountId) {
    final stmt = _db.prepare('''
      SELECT SUM(file_size) FROM attachments 
      WHERE account_id = ? AND status = 'COMPLETED';
    ''');
    final res = stmt.select([accountId]);
    stmt.close();
    if (res.isEmpty) return 0;
    final val = res.first.columnAt(0);
    return val is int ? val : 0;
  }
}
