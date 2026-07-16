part of '../database.dart';

mixin RemoteMessagesRepository on HelixRemoteDatabaseBase {
  // ---------------------------------------------------------------------------
  // Message operations
  // ---------------------------------------------------------------------------

  void saveMessage(
    RemoteMessage message,
    int sequence,
    int timestamp,
    String status,
  ) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO messages (message_id, conversation_id, sender_account_id, sender_device_id, ciphertext_blob, server_sequence, timestamp, status)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      message.messageId,
      message.conversationId,
      message.senderAccountId,
      message.senderDeviceId,
      message.ciphertext,
      sequence,
      timestamp,
      status,
    ]);
    stmt.close();
  }

  List<Map<String, dynamic>> getMessages(
    String conversationId, {
    int limit = 50,
    int offset = 0,
  }) {
    cleanupExpiredMessages(DateTime.now().millisecondsSinceEpoch);
    final stmt = _db.prepare('''
      SELECT * FROM messages
      WHERE conversation_id = ?
      ORDER BY server_sequence DESC
      LIMIT ? OFFSET ?;
    ''');
    final res = stmt.select([conversationId, limit, offset]);
    stmt.close();
    return res
        .map(
          (row) => {
            'message_id': row['message_id'],
            'conversation_id': row['conversation_id'],
            'sender_account_id': row['sender_account_id'],
            'sender_device_id': row['sender_device_id'],
            'ciphertext_blob': row['ciphertext_blob'],
            'server_sequence': row['server_sequence'],
            'timestamp': row['timestamp'],
            'status': row['status'],
            'expires_at': row['expires_at'] ?? 0,
            'retention_deadline': row['retention_deadline'] ?? 0,
            'view_once': row['view_once'] ?? 0,
            'view_once_opened_at': row['view_once_opened_at'] ?? 0,
            'keep_in_chat': row['keep_in_chat'] ?? 0,
          },
        )
        .toList();
  }

  Map<String, dynamic>? getMessageById(String messageId) {
    final stmt = _db.prepare('SELECT * FROM messages WHERE message_id = ?;');
    final res = stmt.select([messageId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'message_id': row['message_id'],
      'conversation_id': row['conversation_id'],
      'sender_account_id': row['sender_account_id'],
      'sender_device_id': row['sender_device_id'],
      'ciphertext_blob': row['ciphertext_blob'],
      'server_sequence': row['server_sequence'],
      'timestamp': row['timestamp'],
      'status': row['status'],
      'expires_at': row['expires_at'] ?? 0,
      'retention_deadline': row['retention_deadline'] ?? 0,
      'view_once': row['view_once'] ?? 0,
      'view_once_opened_at': row['view_once_opened_at'] ?? 0,
      'keep_in_chat': row['keep_in_chat'] ?? 0,
    };
  }

  @override
  void deleteMessage(String messageId) {
    final stmt = _db.prepare('DELETE FROM messages WHERE message_id = ?;');
    stmt.execute([messageId]);
    stmt.close();
  }

  /// Upgrades a message's status along PENDING→SENT→DELIVERED→READ.
  /// Never downgrades — if the stored status already has higher priority
  /// the UPDATE is a no-op.
  void updateMessageStatus(String messageId, String status) {
    const priorities = {'SENT': 2, 'DELIVERED': 3, 'READ': 4};
    final newPriority = priorities[status];
    if (newPriority == null) return;
    final stmt = _db.prepare('''
      UPDATE messages SET status = ?
      WHERE message_id = ?
        AND CASE status
          WHEN 'PENDING'   THEN 1
          WHEN 'SENT'      THEN 2
          WHEN 'DELIVERED' THEN 3
          WHEN 'READ'      THEN 4
          ELSE 0
        END < ?;
    ''');
    stmt.execute([status, messageId, newPriority]);
    stmt.close();
  }

  void saveMessageAndOperation({
    required RemoteMessage message,
    required int sequence,
    required int timestamp,
    required String status,
    required String opId,
    required String type,
    required String payload,
    required String idempotencyKey,
  }) {
    _db.execute('SAVEPOINT save_message_and_operation;');
    try {
      saveMessage(message, sequence, timestamp, status);
      enqueueOperation(opId, type, payload, idempotencyKey: idempotencyKey);
      _db.execute('RELEASE SAVEPOINT save_message_and_operation;');
    } catch (_) {
      _db.execute('ROLLBACK TO SAVEPOINT save_message_and_operation;');
      _db.execute('RELEASE SAVEPOINT save_message_and_operation;');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Message revisions
  // ---------------------------------------------------------------------------

  void saveMessageRevision({
    required String revisionId,
    required String messageId,
    required String type,
    required String authorId,
    required String payload,
    required int timestamp,
    int serverSequence = 0,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO revisions (
        revision_id,
        message_id,
        type,
        author_id,
        payload,
        timestamp,
        server_sequence
      )
      VALUES (?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      revisionId,
      messageId,
      type,
      authorId,
      payload,
      timestamp,
      serverSequence,
    ]);
    stmt.close();
  }

  // P4-05: Order by server_sequence first (server wins over wall-clock),
  // then timestamp as tie-breaker for locally-generated revisions.
  List<Map<String, dynamic>> getMessageRevisions(String messageId) {
    final stmt = _db.prepare(
      'SELECT * FROM revisions WHERE message_id = ? ORDER BY server_sequence ASC, timestamp ASC;',
    );
    final res = stmt.select([messageId]);
    stmt.close();
    return res
        .map(
          (row) => {
            'revision_id': row['revision_id'],
            'message_id': row['message_id'],
            'type': row['type'],
            'author_id': row['author_id'],
            'payload': row['payload'],
            'timestamp': row['timestamp'],
            'server_sequence': row['server_sequence'] ?? 0,
          },
        )
        .toList();
  }

  void saveMessageReceipt({
    required String receiptId,
    required String messageId,
    required String conversationId,
    required String accountId,
    required String receiptType,
    required int timestamp,
    String? deviceId,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO message_receipts (
        receipt_id,
        message_id,
        conversation_id,
        account_id,
        device_id,
        receipt_type,
        timestamp
      )
      VALUES (?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      receiptId,
      messageId,
      conversationId,
      accountId,
      deviceId,
      receiptType,
      timestamp,
    ]);
    stmt.close();
  }

  List<Map<String, dynamic>> getMessageReceipts(String messageId) {
    final stmt = _db.prepare(
      'SELECT * FROM message_receipts WHERE message_id = ? ORDER BY timestamp ASC;',
    );
    final res = stmt.select([messageId]);
    stmt.close();
    return res
        .map(
          (row) => {
            'receipt_id': row['receipt_id'],
            'message_id': row['message_id'],
            'conversation_id': row['conversation_id'],
            'account_id': row['account_id'],
            'device_id': row['device_id'],
            'receipt_type': row['receipt_type'],
            'timestamp': row['timestamp'],
          },
        )
        .toList();
  }
}
