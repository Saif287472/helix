part of '../database.dart';

mixin RemoteConversationsRepository on HelixRemoteDatabaseBase {
  // ---------------------------------------------------------------------------
  // Conversation operations
  // ---------------------------------------------------------------------------

  void upsertConversation(
    RemoteConversation conversation,
    List<String> memberIds,
  ) {
    _db.execute('SAVEPOINT upsert_conversation;');
    try {
      final stmt = _db.prepare('''
        INSERT INTO conversations (conversation_id, title, type, last_sequence, created_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(conversation_id) DO UPDATE SET
          title = excluded.title,
          type = excluded.type,
          last_sequence = excluded.last_sequence;
      ''');
      stmt.execute([
        conversation.conversationId,
        conversation.title,
        conversation.type,
        conversation.lastActivitySequence,
        conversation.createdAt.millisecondsSinceEpoch,
      ]);
      stmt.close();

      final clearStmt = _db.prepare(
        'DELETE FROM members WHERE conversation_id = ?;',
      );
      clearStmt.execute([conversation.conversationId]);
      clearStmt.close();

      final memStmt = _db.prepare('''
        INSERT INTO members (conversation_id, account_id)
        VALUES (?, ?);
      ''');
      for (final memId in memberIds) {
        memStmt.execute([conversation.conversationId, memId]);
      }
      memStmt.close();

      _db.execute('RELEASE SAVEPOINT upsert_conversation;');
    } catch (_) {
      _db.execute('ROLLBACK TO SAVEPOINT upsert_conversation;');
      _db.execute('RELEASE SAVEPOINT upsert_conversation;');
      rethrow;
    }
  }

  @override
  List<RemoteConversation> getConversations() {
    final stmt = _db.prepare('''
      SELECT * FROM conversations
      WHERE hidden_from_list = 0
      ORDER BY is_pinned DESC, last_sequence DESC;
      ''');
    final res = stmt.select();
    stmt.close();
    return res
        .map(
          (row) => RemoteConversation(
            conversationId: row['conversation_id'] as String,
            title: row['title'] as String? ?? '',
            type: row['type'] as String,
            lastActivitySequence: row['last_sequence'] as int,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['created_at'] as int,
            ),
            isPinned: (row['is_pinned'] as int? ?? 0) != 0,
            isMuted: (row['is_muted'] as int? ?? 0) != 0,
            isFavorite: (row['is_favorite'] as int? ?? 0) != 0,
          ),
        )
        .toList();
  }

  List<String> getConversationMembers(String conversationId) {
    final stmt = _db.prepare(
      'SELECT account_id FROM members WHERE conversation_id = ?;',
    );
    final res = stmt.select([conversationId]);
    stmt.close();
    return res.map((row) => row['account_id'] as String).toList();
  }

  void upsertConversationMember(
    String conversationId,
    String accountId, {
    String role = 'MEMBER',
  }) {
    final stmt = _db.prepare('''
      INSERT INTO members (conversation_id, account_id, role)
      VALUES (?, ?, ?)
      ON CONFLICT(conversation_id, account_id) DO UPDATE SET
        role = excluded.role;
    ''');
    stmt.execute([conversationId, accountId, role]);
    stmt.close();
  }

  void removeConversationMember(String conversationId, String accountId) {
    final stmt = _db.prepare(
      'DELETE FROM members WHERE conversation_id = ? AND account_id = ?;',
    );
    stmt.execute([conversationId, accountId]);
    stmt.close();
  }

  void setConversationPinned(String conversationId, {required bool pinned}) {
    final stmt = _db.prepare(
      'UPDATE conversations SET is_pinned = ? WHERE conversation_id = ?;',
    );
    stmt.execute([pinned ? 1 : 0, conversationId]);
    stmt.close();
  }

  void setConversationMuted(String conversationId, {required bool muted}) {
    final stmt = _db.prepare(
      'UPDATE conversations SET is_muted = ? WHERE conversation_id = ?;',
    );
    stmt.execute([muted ? 1 : 0, conversationId]);
    stmt.close();
  }

  void clearConversationMessages(String conversationId) {
    final stmt = _db.prepare('DELETE FROM messages WHERE conversation_id = ?;');
    stmt.execute([conversationId]);
    stmt.close();
  }

  void deleteConversation(String conversationId) {
    // ON DELETE CASCADE removes members and messages automatically.
    final stmt = _db.prepare(
      'DELETE FROM conversations WHERE conversation_id = ?;',
    );
    stmt.execute([conversationId]);
    stmt.close();
  }

  /// Creates a minimal conversation row and adds the sender as a member only
  /// if neither exists yet (INSERT OR IGNORE). Used by the inbound message
  /// event handler to satisfy the FK constraint before saving the message,
  /// in case the receiver hasn't yet processed a conversation_created event.
  void ensureConversationExists({
    required String conversationId,
    required String senderAccountId,
    required int serverSequence,
    required int timestamp,
  }) {
    final stmt = _db.prepare('''
      INSERT OR IGNORE INTO conversations (conversation_id, title, type, last_sequence, created_at)
      VALUES (?, '', 'DIRECT', ?, ?);
    ''');
    stmt.execute([conversationId, serverSequence, timestamp]);
    stmt.close();

    final memStmt = _db.prepare('''
      INSERT OR IGNORE INTO members (conversation_id, account_id, role)
      VALUES (?, ?, 'MEMBER');
    ''');
    memStmt.execute([conversationId, senderAccountId]);
    memStmt.close();
  }
}
