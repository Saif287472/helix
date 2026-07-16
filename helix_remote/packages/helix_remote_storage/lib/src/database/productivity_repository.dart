part of '../database.dart';

class RemoteUnreadSummary {
  const RemoteUnreadSummary({
    required this.conversationId,
    required this.unreadCount,
    required this.mentionCount,
    required this.lastReadSequence,
  });

  final String conversationId;
  final int unreadCount;
  final int mentionCount;
  final int lastReadSequence;
}

class RemoteSearchResult {
  const RemoteSearchResult({
    required this.section,
    required this.conversationId,
    this.messageId,
    required this.text,
    this.metadata = const {},
  });

  final String section;
  final String conversationId;
  final String? messageId;
  final String text;
  final Map<String, dynamic> metadata;
}

class RemoteStorageSummary {
  const RemoteStorageSummary({
    required this.conversationId,
    required this.totalBytes,
    required this.attachmentCount,
    required this.downloadedBytes,
    required this.largeAttachmentCount,
  });

  final String conversationId;
  final int totalBytes;
  final int attachmentCount;
  final int downloadedBytes;
  final int largeAttachmentCount;
}

mixin RemoteProductivityRepository on HelixRemoteDatabaseBase {
  void markConversationRead({
    required String conversationId,
    required String deviceId,
    required int lastReadSequence,
    int mentionCount = 0,
    required int updatedAt,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO conversation_read_state (
        conversation_id,
        device_id,
        last_read_sequence,
        mention_count,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(conversation_id, device_id) DO UPDATE SET
        last_read_sequence = excluded.last_read_sequence,
        mention_count = excluded.mention_count,
        updated_at = excluded.updated_at;
    ''');
    stmt.execute([
      conversationId,
      deviceId,
      lastReadSequence,
      mentionCount,
      updatedAt,
    ]);
    stmt.close();
  }

  RemoteUnreadSummary unreadSummary(String conversationId, String deviceId) {
    final readRows = _db.select(
      '''
      SELECT last_read_sequence, mention_count
      FROM conversation_read_state
      WHERE conversation_id = ? AND device_id = ?;
      ''',
      [conversationId, deviceId],
    );
    final lastRead = readRows.isEmpty
        ? 0
        : readRows.first['last_read_sequence'] as int;
    final mentionCount = readRows.isEmpty
        ? 0
        : readRows.first['mention_count'] as int;
    final unreadRows = _db.select(
      '''
      SELECT COUNT(*) AS count FROM messages
      WHERE conversation_id = ? AND server_sequence > ?;
      ''',
      [conversationId, lastRead],
    );
    return RemoteUnreadSummary(
      conversationId: conversationId,
      unreadCount: unreadRows.first['count'] as int,
      mentionCount: mentionCount,
      lastReadSequence: lastRead,
    );
  }

  Map<String, RemoteUnreadSummary> unreadSummaries(String deviceId) {
    final summaries = <String, RemoteUnreadSummary>{};
    for (final row in _db.select(
      'SELECT conversation_id FROM conversations;',
    )) {
      final id = row['conversation_id'] as String;
      summaries[id] = unreadSummary(id, deviceId);
    }
    return summaries;
  }

  void setConversationFavorite(
    String conversationId, {
    required bool favorite,
  }) {
    final stmt = _db.prepare(
      'UPDATE conversations SET is_favorite = ? WHERE conversation_id = ?;',
    );
    stmt.execute([favorite ? 1 : 0, conversationId]);
    stmt.close();
  }

  void upsertConversationList({
    required String listId,
    required String name,
    required String kind,
    required int sortOrder,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO conversation_lists (list_id, name, kind, sort_order)
      VALUES (?, ?, ?, ?);
    ''');
    stmt.execute([listId, name, kind, sortOrder]);
    stmt.close();
  }

  void addConversationToList({
    required String listId,
    required String conversationId,
    required int sortOrder,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO conversation_list_members (
        list_id,
        conversation_id,
        sort_order
      )
      VALUES (?, ?, ?);
    ''');
    stmt.execute([listId, conversationId, sortOrder]);
    stmt.close();
  }

  List<RemoteConversation> conversationsForList({
    required String kind,
    String? listId,
    String? deviceId,
  }) {
    if (kind == 'unread') {
      final all = getConversations();
      if (deviceId == null) return const [];
      return all
          .where(
            (conversation) =>
                unreadSummary(
                  conversation.conversationId,
                  deviceId,
                ).unreadCount >
                0,
          )
          .toList();
    }
    if (kind == 'groups') {
      return getConversations().where((c) => c.type == 'Group').toList();
    }
    if (kind == 'favorites') {
      return _conversationRows('''
        SELECT * FROM conversations
        WHERE hidden_from_list = 0 AND is_favorite = 1
        ORDER BY last_sequence DESC;
        ''');
    }
    if (kind == 'custom' && listId != null) {
      return _conversationRows(
        '''
        SELECT c.* FROM conversations c
        JOIN conversation_list_members m
          ON m.conversation_id = c.conversation_id
        WHERE c.hidden_from_list = 0 AND m.list_id = ?
        ORDER BY m.sort_order ASC, c.last_sequence DESC;
        ''',
        [listId],
      );
    }
    return getConversations();
  }

  void upsertSearchIndex({
    required String conversationId,
    String? messageId,
    required String section,
    required String text,
    Map<String, dynamic> metadata = const {},
    required int updatedAt,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO search_index (
        conversation_id,
        message_id,
        section,
        text,
        metadata_json,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      conversationId,
      messageId,
      section,
      text,
      jsonEncode(metadata),
      updatedAt,
    ]);
    stmt.close();
  }

  void removeSearchIndexForMessage(String messageId) {
    final stmt = _db.prepare('DELETE FROM search_index WHERE message_id = ?;');
    stmt.execute([messageId]);
    stmt.close();
  }

  List<RemoteSearchResult> searchLocalIndex(String query, {int limit = 50}) {
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) return const [];
    final rows = _db.select(
      '''
      SELECT s.* FROM search_index s
      JOIN conversations c ON c.conversation_id = s.conversation_id
      WHERE c.hidden_from_list = 0
        AND lower(s.text) LIKE ?
      ORDER BY s.updated_at DESC
      LIMIT ?;
      ''',
      ['%$normalized%', limit],
    );
    return rows.map((row) {
      Map<String, dynamic> metadata = const {};
      try {
        final decoded = jsonDecode(row['metadata_json'] as String? ?? '{}');
        if (decoded is Map<String, dynamic>) metadata = decoded;
      } catch (_) {}
      return RemoteSearchResult(
        section: row['section'] as String,
        conversationId: row['conversation_id'] as String,
        messageId: row['message_id'] as String?,
        text: row['text'] as String,
        metadata: metadata,
      );
    }).toList();
  }

  RemoteStorageSummary storageSummary(String conversationId) {
    final rows = _db.select('SELECT * FROM attachments;');
    var total = 0;
    var downloaded = 0;
    var large = 0;
    for (final row in rows) {
      final size = row['size_bytes'] as int;
      total += size;
      if ((row['local_path'] as String?)?.isNotEmpty == true) {
        downloaded += size;
      }
      if (size >= 5 * 1024 * 1024) large++;
    }
    return RemoteStorageSummary(
      conversationId: conversationId,
      totalBytes: total,
      attachmentCount: rows.length,
      downloadedBytes: downloaded,
      largeAttachmentCount: large,
    );
  }

  void clearMediaForConversation(String conversationId) {
    final rows = _db.select('SELECT attachment_id FROM attachments;');
    for (final row in rows) {
      final id = row['attachment_id'] as String;
      final attachment = getAttachment(id);
      if (attachment == null) continue;
      saveAttachment(
        attachmentId: id,
        filename: attachment['filename'] as String,
        sizeBytes: attachment['size_bytes'] as int,
        encryptedKey: attachment['encrypted_key'] as String,
        localPath: null,
        importedSourcePath: attachment['imported_source_path'] as String?,
        encryptedCachePath: null,
        downloadedCiphertextPath: null,
        exportedPlaintextPath: attachment['exported_plaintext_path'] as String?,
        status: 'MEDIA_CLEARED',
      );
    }
  }

  bool safeLinkPreviewAllowed(String url, {required bool optedIn}) {
    if (!optedIn) return false;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return false;
    if (uri.scheme != 'https' && uri.scheme != 'http') return false;
    final host = uri.host.toLowerCase();
    if (host == 'localhost' ||
        host.startsWith('127.') ||
        host.startsWith('10.') ||
        host.startsWith('192.168.') ||
        host.endsWith('.local')) {
      return false;
    }
    return true;
  }

  void cacheLinkPreview({
    required String url,
    required String title,
    String description = '',
    String imageUrl = '',
    required int fetchedAt,
    required int expiresAt,
    String status = 'READY',
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO link_previews (
        url,
        title,
        description,
        image_url,
        fetched_at,
        expires_at,
        status
      )
      VALUES (?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      url,
      title,
      description,
      imageUrl,
      fetchedAt,
      expiresAt,
      status,
    ]);
    stmt.close();
  }

  String createContactLink({
    required String linkId,
    required String accountId,
    required String nonce,
    required int expiresAt,
    required String signature,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO contact_links (
        link_id,
        account_id,
        nonce,
        expires_at,
        signature,
        used_at
      )
      VALUES (?, ?, ?, ?, ?, 0);
    ''');
    stmt.execute([linkId, accountId, nonce, expiresAt, signature]);
    stmt.close();
    return 'helix://contact/add?v=1&id=$linkId&a=$accountId&n=$nonce&e=$expiresAt&s=$signature';
  }

  bool verifyContactLink(
    String link, {
    required String expectedSignature,
    required int now,
  }) {
    final uri = Uri.tryParse(link);
    if (uri == null || uri.scheme != 'helix' || uri.host != 'contact') {
      return false;
    }
    final params = uri.queryParameters;
    final linkId = params['id'];
    final accountId = params['a'];
    final nonce = params['n'];
    final expiresAt = int.tryParse(params['e'] ?? '');
    final signature = params['s'];
    if (linkId == null ||
        accountId == null ||
        nonce == null ||
        expiresAt == null ||
        signature == null ||
        now > expiresAt) {
      return false;
    }
    if (expectedSignature != signature) return false;
    final rows = _db.select(
      'SELECT used_at FROM contact_links WHERE link_id = ?;',
      [linkId],
    );
    if (rows.isNotEmpty && (rows.first['used_at'] as int? ?? 0) > 0) {
      return false;
    }
    return true;
  }

  void markContactLinkUsed(String linkId, int usedAt) {
    final stmt = _db.prepare(
      'UPDATE contact_links SET used_at = ? WHERE link_id = ?;',
    );
    stmt.execute([usedAt, linkId]);
    stmt.close();
  }

  List<RemoteConversation> _conversationRows(
    String sql, [
    List<Object?> params = const [],
  ]) {
    final rows = _db.select(sql, params);
    return rows
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
}
