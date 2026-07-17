part of '../database.dart';

extension BackendMessagingRepository on BackendDatabase {
  // Conversations
  void createConversation(
    String conversationId,
    String type,
    String? title,
    List<String> memberAccountIds,
  ) {
    _db.execute('BEGIN TRANSACTION;');
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final convStmt = _db.prepare('''
        INSERT OR REPLACE INTO conversations (conversation_id, type, title, created_at, last_sequence)
        VALUES (?, ?, ?, ?, 0);
      ''');
      convStmt.execute([conversationId, type, title, now]);
      convStmt.close();

      // Clear existing members if replacing
      final clearMemStmt = _db.prepare(
        'DELETE FROM conversation_members WHERE conversation_id = ?;',
      );
      clearMemStmt.execute([conversationId]);
      clearMemStmt.close();
      final clearFedMemStmt = _db.prepare(
        'DELETE FROM federated_conversation_members WHERE conversation_id = ?;',
      );
      clearFedMemStmt.execute([conversationId]);
      clearFedMemStmt.close();

      for (final memberId in memberAccountIds) {
        upsertConversationMemberRow(conversationId, memberId, 'MEMBER');
      }

      _db.execute('COMMIT;');
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  /// Writes a member row to the correct table: `conversation_members` for
  /// local accounts, `federated_conversation_members` (v26 shadow table,
  /// no FK) for accounts qualified as user@domain that don't exist locally.
  /// Shared by DIRECT conversation creation and group membership mutations
  /// so both paths stay consistent about what counts as "external".
  void upsertConversationMemberRow(
    String conversationId,
    String accountId,
    String role,
  ) {
    final at = accountId.lastIndexOf('@');
    if (at > 0 && at < accountId.length - 1 && !accountExists(accountId)) {
      final stmt = _db.prepare('''
        INSERT OR REPLACE INTO federated_conversation_members (
          conversation_id, account_id, domain, role
        )
        VALUES (?, ?, ?, ?);
      ''');
      stmt.execute([
        conversationId,
        accountId,
        accountId.substring(at + 1).toLowerCase(),
        role,
      ]);
      stmt.close();
    } else {
      final stmt = _db.prepare('''
        INSERT OR REPLACE INTO conversation_members (conversation_id, account_id, role)
        VALUES (?, ?, ?);
      ''');
      stmt.execute([conversationId, accountId, role]);
      stmt.close();
    }
  }

  void removeConversationMemberRow(String conversationId, String accountId) {
    final localStmt = _db.prepare(
      'DELETE FROM conversation_members WHERE conversation_id = ? AND account_id = ?;',
    );
    localStmt.execute([conversationId, accountId]);
    localStmt.close();
    final fedStmt = _db.prepare(
      'DELETE FROM federated_conversation_members WHERE conversation_id = ? AND account_id = ?;',
    );
    fedStmt.execute([conversationId, accountId]);
    fedStmt.close();
  }

  bool isConversationMember(String conversationId, String accountId) {
    final stmt = _db.prepare(
      'SELECT 1 FROM conversation_members WHERE conversation_id = ? AND account_id = ?;',
    );
    final res = stmt.select([conversationId, accountId]);
    stmt.close();
    return res.isNotEmpty;
  }

  List<String> getConversationMembers(String conversationId) {
    final stmt = _db.prepare(
      'SELECT account_id FROM conversation_members WHERE conversation_id = ? ORDER BY account_id ASC;',
    );
    final res = stmt.select([conversationId]);
    stmt.close();
    return res.map((row) => row['account_id'] as String).toList();
  }

  // Messaging operations
  int saveMessage({
    required String messageId,
    required String conversationId,
    required String senderAccountId,
    required String senderDeviceId,
    required String recipientDeviceId,
    required String ciphertext,
  }) {
    _db.execute('BEGIN TRANSACTION;');
    try {
      // 1. Get and increment last_sequence for the conversation
      final seqStmt = _db.prepare(
        'SELECT last_sequence FROM conversations WHERE conversation_id = ?;',
      );
      final seqRes = seqStmt.select([conversationId]);
      seqStmt.close();

      int nextSeq = 1;
      if (seqRes.isNotEmpty) {
        nextSeq = (seqRes.first['last_sequence'] as int) + 1;
      }

      final updateSeqStmt = _db.prepare(
        'UPDATE conversations SET last_sequence = ? WHERE conversation_id = ?;',
      );
      updateSeqStmt.execute([nextSeq, conversationId]);
      updateSeqStmt.close();

      // 2. Insert message envelope
      final now = DateTime.now().millisecondsSinceEpoch;
      final msgStmt = _db.prepare('''
        INSERT INTO messages (message_id, conversation_id, sender_account_id, sender_device_id, recipient_device_id, ciphertext, server_sequence, timestamp)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
      ''');
      msgStmt.execute([
        messageId,
        conversationId,
        senderAccountId,
        senderDeviceId,
        recipientDeviceId,
        ciphertext,
        nextSeq,
        now,
      ]);
      msgStmt.close();

      _db.execute('COMMIT;');
      return nextSeq;
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Map<String, dynamic>? getMessage(String messageId) {
    final stmt = _db.prepare(
      'SELECT * FROM messages WHERE message_id = ? LIMIT 1;',
    );
    final res = stmt.select([messageId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'message_id': row['message_id'],
      'conversation_id': row['conversation_id'],
      'sender_account_id': row['sender_account_id'],
      'sender_device_id': row['sender_device_id'],
      'server_sequence': row['server_sequence'],
    };
  }

  void deleteMessage(String messageId) {
    final stmt = _db.prepare('DELETE FROM messages WHERE message_id = ?;');
    stmt.execute([messageId]);
    stmt.close();
  }

  List<Map<String, dynamic>> getMessagesForDevice(
    String deviceId,
    String conversationId,
    int sinceSequence,
  ) {
    final stmt = _db.prepare('''
      SELECT * FROM messages 
      WHERE recipient_device_id = ? AND conversation_id = ? AND server_sequence > ?
      ORDER BY server_sequence ASC;
    ''');
    final res = stmt.select([deviceId, conversationId, sinceSequence]);
    stmt.close();
    return res
        .map(
          (row) => {
            'message_id': row['message_id'],
            'conversation_id': row['conversation_id'],
            'sender_account_id': row['sender_account_id'],
            'sender_device_id': row['sender_device_id'],
            'recipient_device_id': row['recipient_device_id'],
            'ciphertext': row['ciphertext'],
            'server_sequence': row['server_sequence'],
            'timestamp': row['timestamp'],
          },
        )
        .toList();
  }

  // Retrieve messages across all conversations for offline delivery
  List<Map<String, dynamic>> getOfflineMessagesForDevice(String deviceId) {
    final stmt = _db.prepare('''
      SELECT m.* FROM messages m
      LEFT JOIN sync_cursors c ON c.device_id = m.recipient_device_id AND c.conversation_id = m.conversation_id
      WHERE m.recipient_device_id = ? AND (c.last_sequence IS NULL OR m.server_sequence > c.last_sequence)
      ORDER BY m.server_sequence ASC;
    ''');
    final res = stmt.select([deviceId]);
    stmt.close();
    return res
        .map(
          (row) => {
            'message_id': row['message_id'],
            'conversation_id': row['conversation_id'],
            'sender_account_id': row['sender_account_id'],
            'sender_device_id': row['sender_device_id'],
            'recipient_device_id': row['recipient_device_id'],
            'ciphertext': row['ciphertext'],
            'server_sequence': row['server_sequence'],
            'timestamp': row['timestamp'],
          },
        )
        .toList();
  }

  void updateSyncCursor(
    String accountId,
    String deviceId,
    String conversationId,
    int sequence,
  ) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO sync_cursors (account_id, device_id, conversation_id, last_sequence)
      VALUES (?, ?, ?, ?);
    ''');
    stmt.execute([accountId, deviceId, conversationId, sequence]);
    stmt.close();
  }

  List<Map<String, dynamic>> getSyncCursors(String accountId, String deviceId) {
    final stmt = _db.prepare(
      'SELECT * FROM sync_cursors WHERE account_id = ? AND device_id = ?;',
    );
    final res = stmt.select([accountId, deviceId]);
    stmt.close();
    return res
        .map(
          (row) => {
            'conversation_id': row['conversation_id'],
            'last_sequence': row['last_sequence'],
          },
        )
        .toList();
  }

  int writeDeviceEvent({
    required String eventId,
    required String recipientDeviceId,
    required String eventType,
    required String payload,
  }) {
    _db.execute('BEGIN TRANSACTION;');
    try {
      final seqStmt = _db.prepare(
        'SELECT COALESCE(MAX(device_sequence), 0) + 1 FROM device_events WHERE recipient_device_id = ?;',
      );
      final seqRes = seqStmt.select([recipientDeviceId]);
      seqStmt.close();
      final nextSeq = seqRes.first.columnAt(0) as int;

      final now = DateTime.now().millisecondsSinceEpoch;
      final stmt = _db.prepare('''
        INSERT INTO device_events (event_id, recipient_device_id, device_sequence, schema_version, event_type, timestamp, payload)
        VALUES (?, ?, ?, 1, ?, ?, ?);
      ''');
      stmt.execute([
        eventId,
        recipientDeviceId,
        nextSeq,
        eventType,
        now,
        payload,
      ]);
      stmt.close();
      _db.execute('COMMIT;');
      return nextSeq;
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  List<Map<String, dynamic>> getDeviceEvents(
    String deviceId,
    int sinceSequence,
  ) {
    final stmt = _db.prepare('''
      SELECT * FROM device_events
      WHERE recipient_device_id = ? AND device_sequence > ?
      ORDER BY device_sequence ASC;
    ''');
    final res = stmt.select([deviceId, sinceSequence]);
    stmt.close();
    return res
        .map(
          (row) => {
            'event_id': row['event_id'],
            'recipient_device_id': row['recipient_device_id'],
            'device_sequence': row['device_sequence'],
            'schema_version': row['schema_version'],
            'event_type': row['event_type'],
            'timestamp': row['timestamp'],
            'payload': row['payload'],
          },
        )
        .toList();
  }

  int? getLastDeviceSequence(String deviceId) {
    final stmt = _db.prepare(
      'SELECT MAX(device_sequence) FROM device_events WHERE recipient_device_id = ?;',
    );
    final res = stmt.select([deviceId]);
    stmt.close();
    if (res.isEmpty) return null;
    final val = res.first.columnAt(0);
    return val as int?;
  }
}
