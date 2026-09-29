part of '../remote_messaging_service.dart';

/// Text-only history for the automatic backup: plain text messages with
/// their reply references, and the conversations they belong to. Media,
/// polls, locations and stickers are left out, and so is anything its sender
/// did not want kept - view-once, disappearing, or marked not exportable -
/// along with locked and hidden chats.
mixin RemoteHistoryBackup on RemoteMessagingServiceBase, RemoteHistoryReceipts {
  Future<Map<String, dynamic>> exportTextHistory() async {
    final locked = {
      for (final c in db.getLockedConversations()) c.conversationId,
    };
    final conversations = <String, dynamic>{};
    final messages = <Map<String, dynamic>>[];
    for (final conversation in db.getConversations()) {
      final id = conversation.conversationId;
      if (locked.contains(id)) continue;
      final history = await messageHistory(id, limit: 1 << 30);
      final texts = history.where(_isBackedUp).toList();
      if (texts.isEmpty) continue;
      conversations[id] = {
        'title': conversation.title,
        'type': conversation.type,
        'members': db.getConversationMembers(id),
      };
      for (final m in texts) {
        messages.add({
          'id': m.messageId,
          'conversation_id': id,
          'sender_account_id': m.senderAccountId,
          'sender_device_id': m.senderDeviceId,
          'ts': m.timestamp,
          'status': m.status,
          'text': m.text,
          if (m.replyTo != null) 'reply_to': m.replyTo!.toJson(),
        });
      }
    }
    return {
      'v': 1,
      'created_at': _clock().millisecondsSinceEpoch,
      'conversations': conversations,
      'messages': messages,
    };
  }

  bool _isBackedUp(RemoteDecryptedMessage m) =>
      m.attachment == null &&
      m.media == null &&
      m.poll == null &&
      m.event == null &&
      m.location == null &&
      m.sticker == null &&
      !m.viewOnce &&
      m.expiresAt == null &&
      m.exportAllowed &&
      m.status != 'SECURE_SESSION_UNAVAILABLE' &&
      m.status != 'FAILED' &&
      m.text.isNotEmpty &&
      m.text != RemoteHistoryReceipts._unreadablePlaceholder;

  /// Adds the backup's messages that this device does not have. Restored
  /// messages are numbered at or below zero, oldest lowest, so they sort
  /// before everything this device received itself and never count as
  /// unread. Returns how many were added.
  Future<int> importTextHistory(Map<String, dynamic> snapshot) async {
    final conversations =
        snapshot['conversations'] as Map<String, dynamic>? ?? const {};
    for (final entry in conversations.entries) {
      final info = entry.value as Map<String, dynamic>;
      final members = (info['members'] as List? ?? const [])
          .whereType<String>()
          .toList();
      if (db.getConversationMembers(entry.key).isEmpty) {
        db.upsertConversation(
          RemoteConversation(
            conversationId: entry.key,
            type: info['type'] as String? ?? 'DIRECT',
            title: info['title'] as String? ?? '',
            createdAt: _clock(),
            lastActivitySequence: 0,
          ),
          members,
        );
      } else {
        db.ensureConversationExists(
          conversationId: entry.key,
          senderAccountId: members.isEmpty
              ? _requireAccountId()
              : members.first,
          serverSequence: 0,
          timestamp: _clock().millisecondsSinceEpoch,
          memberAccountIds: members,
        );
      }
    }

    final incoming =
        (snapshot['messages'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .where(
              (m) =>
                  db.getMessageById(m['id'] as String) == null &&
                  !db.isTombstoned(m['id'] as String, 'MESSAGE') &&
                  conversations.containsKey(m['conversation_id']),
            )
            .toList()
          ..sort((a, b) => (a['ts'] as int).compareTo(b['ts'] as int));

    var sequence = -incoming.length;
    for (final m in incoming) {
      final id = m['id'] as String;
      final conversationId = m['conversation_id'] as String;
      final plaintext = RemoteTextContent(
        text: m['text'] as String,
        replyTo: RemoteReplyReference.tryParse(m['reply_to']),
      ).toPlaintext();
      final ciphertext = await protector.encryptText(
        conversationId: conversationId,
        messageId: id,
        plaintext: plaintext,
        recipientDeviceId: 'local-history',
      );
      db.saveMessage(
        RemoteMessage(
          messageId: id,
          conversationId: conversationId,
          senderAccountId: m['sender_account_id'] as String,
          senderDeviceId: m['sender_device_id'] as String? ?? 'restored',
          ciphertext: ciphertext,
        ),
        ++sequence,
        m['ts'] as int,
        m['status'] as String? ?? 'DELIVERED',
      );
    }
    if (incoming.isNotEmpty) {
      _emitChange(
        const RemoteSyncChange(
          areas: {
            RemoteSyncChangeArea.messages,
            RemoteSyncChangeArea.conversations,
          },
        ),
      );
    }
    return incoming.length;
  }
}
