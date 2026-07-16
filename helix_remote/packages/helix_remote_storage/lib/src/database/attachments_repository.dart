part of '../database.dart';

mixin RemoteAttachmentsRepository on HelixRemoteDatabaseBase {
  // ---------------------------------------------------------------------------
  // Attachment operations
  // ---------------------------------------------------------------------------

  @override
  void saveAttachment({
    required String attachmentId,
    required String filename,
    required int sizeBytes,
    required String encryptedKey,
    String? localPath,
    String? importedSourcePath,
    String? encryptedCachePath,
    String? downloadedCiphertextPath,
    String? exportedPlaintextPath,
    required String status,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO attachments (
        attachment_id,
        filename,
        size_bytes,
        encrypted_key,
        local_path,
        imported_source_path,
        encrypted_cache_path,
        downloaded_ciphertext_path,
        exported_plaintext_path,
        status
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      attachmentId,
      filename,
      sizeBytes,
      encryptedKey,
      localPath,
      importedSourcePath,
      encryptedCachePath,
      downloadedCiphertextPath,
      exportedPlaintextPath,
      status,
    ]);
    stmt.close();
  }

  @override
  Map<String, dynamic>? getAttachment(String attachmentId) {
    final stmt = _db.prepare(
      'SELECT * FROM attachments WHERE attachment_id = ?;',
    );
    final res = stmt.select([attachmentId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'attachment_id': row['attachment_id'],
      'filename': row['filename'],
      'size_bytes': row['size_bytes'],
      'encrypted_key': row['encrypted_key'],
      'local_path': row['local_path'],
      'imported_source_path': row['imported_source_path'],
      'encrypted_cache_path': row['encrypted_cache_path'],
      'downloaded_ciphertext_path': row['downloaded_ciphertext_path'],
      'exported_plaintext_path': row['exported_plaintext_path'],
      'status': row['status'],
    };
  }
}
