part of '../remote_messaging_service.dart';

mixin RemoteHistoryReceipts on RemoteMessagingServiceBase {
  // In-memory plaintext cache: avoids re-running expensive X3DH/HKDF crypto
  // on every messageHistory() call triggered by sync events.
  // Key = messageId; value = (ciphertextHashCode, decryptedPlaintext).
  // Invalidated automatically when the ciphertext changes (e.g. after an edit).
  final Map<String, (int, String)> _decryptCache = {};
  void recordTrustDecision({
    required String accountId,
    required String deviceId,
    required String identityFingerprint,
    required String safetyNumber,
    String status = 'trusted',
  }) {
    db.upsertTrustDecision(
      accountId: accountId,
      deviceId: deviceId,
      identityFingerprint: identityFingerprint,
      safetyNumber: safetyNumber,
      status: status,
      timestamp: _clock().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic>? trustDecision({
    required String accountId,
    required String deviceId,
  }) {
    return db.getTrustDecision(accountId: accountId, deviceId: deviceId);
  }

  Future<List<RemoteDecryptedMessage>> messageHistory(
    String conversationId, {
    int limit = 50,
    int offset = 0,
  }) {
    db.cleanupExpiredMessages(_clock().millisecondsSinceEpoch);
    return _decodeRows(
      db.getMessages(conversationId, limit: limit, offset: offset),
    );
  }

  Future<List<RemoteDecryptedMessage>> searchDecryptedHistory({
    required String conversationId,
    required String query,
  }) async {
    final privacy = db.getConversationPrivacy(conversationId);
    if (privacy.isLocked && privacy.hiddenFromList) return const [];
    final normalized = query.toLowerCase();
    final messages = await messageHistory(conversationId, limit: 500);
    return messages
        .where((message) => message.text.toLowerCase().contains(normalized))
        .toList();
  }

  Future<bool> markDelivered({
    required String messageId,
    required String conversationId,
  }) async {
    final receiptId =
        'delivery_${messageId}_${_clock().microsecondsSinceEpoch}';
    db.saveMessageReceipt(
      receiptId: receiptId,
      messageId: messageId,
      conversationId: conversationId,
      accountId: _requireAccountId(),
      deviceId: _requireDeviceId(),
      receiptType: 'DELIVERY',
      timestamp: _clock().millisecondsSinceEpoch,
    );
    db.enqueueOperation(
      receiptId,
      'DELIVERY_RECEIPT',
      jsonEncode({
        'message_id': messageId,
        'conversation_id': conversationId,
        'account_id': _requireAccountId(),
        'device_id': _requireDeviceId(),
        'protocol_version': 1,
      }),
      idempotencyKey: 'delivery:$receiptId',
    );
    _emitChange(
      RemoteSyncChange(
        areas: const {
          RemoteSyncChangeArea.messages,
          RemoteSyncChangeArea.outbox,
        },
        conversationId: conversationId,
      ),
    );
    return true;
  }

  Future<bool> markRead({
    required String messageId,
    required String conversationId,
  }) async {
    if (!_readReceiptsEnabled) {
      return false;
    }

    final receiptId = 'read_${messageId}_${_clock().microsecondsSinceEpoch}';
    db.saveMessageReceipt(
      receiptId: receiptId,
      messageId: messageId,
      conversationId: conversationId,
      accountId: _requireAccountId(),
      deviceId: _requireDeviceId(),
      receiptType: 'READ',
      timestamp: _clock().millisecondsSinceEpoch,
    );
    db.enqueueOperation(
      receiptId,
      'READ_RECEIPT',
      jsonEncode({
        'message_id': messageId,
        'conversation_id': conversationId,
        'account_id': _requireAccountId(),
        'device_id': _requireDeviceId(),
        'protocol_version': 1,
      }),
      idempotencyKey: 'read:$receiptId',
    );
    _emitChange(
      RemoteSyncChange(
        areas: const {
          RemoteSyncChangeArea.messages,
          RemoteSyncChangeArea.outbox,
        },
        conversationId: conversationId,
      ),
    );
    return true;
  }

  Future<List<RemoteDecryptedMessage>> _decodeRows(
    List<Map<String, dynamic>> rows,
  ) async {
    final decoded = <RemoteDecryptedMessage>[];
    for (final row in rows) {
      final messageId = row['message_id'] as String;
      if (db.isTombstoned(messageId, 'MESSAGE')) {
        _decryptCache.remove(messageId);
        continue;
      }

      final conversationId = row['conversation_id'] as String;
      var ciphertext = row['ciphertext_blob'] as String;
      var edited = false;
      final reactions = <String>[];

      for (final revision in db.getMessageRevisions(messageId)) {
        final payload =
            jsonDecode(revision['payload'] as String) as Map<String, dynamic>;
        switch (revision['type'] as String) {
          case 'EDIT':
            ciphertext = payload['ciphertext'] as String;
            edited = true;
            break;
          case 'REACTION':
            final reaction = payload['reaction'];
            if (reaction is String) {
              reactions.add(reaction);
            }
            break;
        }
      }

      final cipherHash = ciphertext.hashCode;
      final cached = _decryptCache[messageId];
      String plaintext;
      if (cached != null && cached.$1 == cipherHash) {
        plaintext = cached.$2;
      } else {
        plaintext = await _decryptMessage(
          conversationId: conversationId,
          messageId: messageId,
          ciphertext: ciphertext,
        );
        _decryptCache[messageId] = (cipherHash, plaintext);
      }
      final parsedMedia = RemoteMediaContent.tryParse(plaintext);
      final parsedPoll = RemotePollContent.tryParse(plaintext);
      final parsedEvent = RemoteEventContent.tryParse(plaintext);
      final parsedLocation = RemoteLocationContent.tryParse(plaintext);
      final parsedSticker = RemoteStickerContent.tryParse(plaintext);
      final parsedAttachment =
          parsedMedia?.attachment ??
          parsedSticker?.attachment ??
          RemoteAttachmentContent.tryParse(plaintext);
      final textContent =
          parsedAttachment == null &&
              parsedPoll == null &&
              parsedEvent == null &&
              parsedLocation == null &&
              parsedSticker == null
          ? RemoteTextContent.parse(plaintext)
          : null;
      final contentPrivacy =
          parsedMedia?.privacy ??
          parsedAttachment?.privacy ??
          textContent?.privacy;
      final expiresAt =
          contentPrivacy?.expiresAt ?? row['expires_at'] as int? ?? 0;
      final retentionDeadline =
          contentPrivacy?.deliveryRetentionDeadline ??
          row['retention_deadline'] as int? ??
          0;
      final viewOnce =
          contentPrivacy?.viewOnce ?? ((row['view_once'] as int? ?? 0) != 0);
      final viewOnceOpened = (row['view_once_opened_at'] as int? ?? 0) > 0;
      final keepInChat =
          contentPrivacy?.keepInChat ??
          ((row['keep_in_chat'] as int? ?? 0) != 0);
      if (contentPrivacy != null) {
        db.setMessagePrivacyMetadata(
          messageId: messageId,
          expiresAt: contentPrivacy.expiresAt,
          retentionDeadline: contentPrivacy.deliveryRetentionDeadline,
          viewOnce: contentPrivacy.viewOnce,
          keepInChat: contentPrivacy.keepInChat,
        );
      }
      if (!keepInChat &&
          ((expiresAt > 0 && expiresAt <= _clock().millisecondsSinceEpoch) ||
              viewOnceOpened)) {
        db.saveTombstone(messageId, 'MESSAGE');
        db.deleteMessage(messageId);
        _decryptCache.remove(messageId);
        continue;
      }
      final localAttachment = parsedAttachment == null
          ? null
          : db.getAttachment(parsedAttachment.fileId);
      final attachment = parsedAttachment?.withLocalState(
        status: localAttachment?['status'] as String?,
        path: localAttachment?['local_path'] as String?,
      );
      final media = parsedMedia == null
          ? null
          : RemoteMediaContent(
              kind: parsedMedia.kind,
              attachment: attachment ?? parsedMedia.attachment,
              caption: parsedMedia.caption,
              durationMs: parsedMedia.durationMs,
              waveform: parsedMedia.waveform,
              items: parsedMedia.items,
              privacy: parsedMedia.privacy,
            );

      decoded.add(
        RemoteDecryptedMessage(
          messageId: messageId,
          conversationId: conversationId,
          senderAccountId: row['sender_account_id'] as String,
          senderDeviceId: row['sender_device_id'] as String,
          text:
              _collaborationDisplayText(
                poll: parsedPoll,
                event: parsedEvent,
                location: parsedLocation,
              ) ??
              parsedSticker?.displayText ??
              media?.displayText ??
              attachment?.displayText ??
              textContent?.text ??
              plaintext,
          status: row['status'] as String,
          timestamp: row['timestamp'] as int,
          reactions: reactions,
          edited: edited,
          attachment: attachment,
          media: media,
          poll: parsedPoll,
          event: parsedEvent,
          location: parsedLocation,
          sticker: parsedSticker,
          replyTo: textContent?.replyTo,
          expiresAt: expiresAt == 0 ? null : expiresAt,
          retentionDeadline: retentionDeadline == 0 ? null : retentionDeadline,
          viewOnce: viewOnce,
          viewOnceOpened: viewOnceOpened,
          keepInChat: keepInChat,
          exportAllowed: contentPrivacy?.exportAllowed ?? true,
          externalSaveAllowed: contentPrivacy?.externalSaveAllowed ?? true,
          forwardingAllowed: contentPrivacy?.forwardingAllowed ?? true,
        ),
      );
      db.upsertSearchIndex(
        conversationId: conversationId,
        messageId: messageId,
        section: parsedPoll != null
            ? 'polls'
            : parsedEvent != null
            ? 'events'
            : parsedLocation != null
            ? 'locations'
            : parsedSticker != null
            ? 'stickers'
            : attachment == null
            ? 'messages'
            : 'media',
        text:
            parsedPoll?.question ??
            parsedEvent?.title ??
            (parsedLocation == null || parsedLocation.live
                ? null
                : parsedLocation.label) ??
            parsedSticker?.altText ??
            (media?.caption.isNotEmpty == true
                ? '${media!.caption} ${media.attachment.filename}'
                : attachment?.filename ?? textContent?.text ?? plaintext),
        metadata: {
          'timestamp': row['timestamp'],
          if (attachment != null) 'mime_type': attachment.mimeType,
          if (media != null) 'media_kind': media.kind,
          if (parsedPoll != null) 'poll_id': parsedPoll.pollId,
          if (parsedEvent != null) 'event_id': parsedEvent.eventId,
          if (parsedLocation != null) 'location_id': parsedLocation.locationId,
          if (parsedSticker != null) 'sticker_id': parsedSticker.stickerId,
        },
        updatedAt: _clock().millisecondsSinceEpoch,
      );
    }
    return decoded;
  }

  String? _collaborationDisplayText({
    RemotePollContent? poll,
    RemoteEventContent? event,
    RemoteLocationContent? location,
  }) {
    if (poll != null) return 'Poll: ${poll.question}';
    if (event != null) {
      return event.isCancelled
          ? 'Cancelled event: ${event.title}'
          : 'Event: ${event.title}';
    }
    if (location != null) {
      if (location.live) return 'Live location';
      return location.label.isEmpty
          ? 'Location'
          : 'Location: ${location.label}';
    }
    return null;
  }

  Future<List<RemoteSearchResult>> unifiedLocalSearch(String query) async {
    for (final conversation in db.getConversations()) {
      await messageHistory(conversation.conversationId, limit: 200);
      db.upsertSearchIndex(
        conversationId: conversation.conversationId,
        section: 'conversations',
        text: conversation.title,
        updatedAt: _clock().millisecondsSinceEpoch,
      );
    }
    return db.searchLocalIndex(query);
  }

  List<RemoteReactionDetail> reactionDetails(String messageId) {
    final byAccount = <String, RemoteReactionDetail>{};
    for (final revision in db.getMessageRevisions(messageId)) {
      if (revision['type'] != 'REACTION') continue;
      final payload =
          jsonDecode(revision['payload'] as String) as Map<String, dynamic>;
      final reaction = payload['reaction'];
      final accountId = payload['account_id'] ?? revision['author_id'];
      if (reaction is! String || accountId is! String || reaction.isEmpty) {
        continue;
      }
      byAccount[accountId] = RemoteReactionDetail(
        accountId: accountId,
        reaction: reaction,
        timestamp: revision['timestamp'] as int,
      );
    }
    return byAccount.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  Future<RemoteDecryptedMessage?> consumeViewOnceMessage({
    required String conversationId,
    required String messageId,
  }) async {
    final messages = await messageHistory(conversationId, limit: 500);
    RemoteDecryptedMessage? message;
    for (final candidate in messages) {
      if (candidate.messageId == messageId) {
        message = candidate;
        break;
      }
    }
    if (message == null || !message.viewOnce || message.viewOnceOpened) {
      return null;
    }
    db.markViewOnceOpened(messageId, _clock().millisecondsSinceEpoch);
    db.cleanupExpiredMessages(_clock().millisecondsSinceEpoch);
    _decryptCache.remove(messageId);
    _emitChange(
      RemoteSyncChange(
        areas: const {RemoteSyncChangeArea.messages},
        conversationId: conversationId,
      ),
    );
    return message;
  }
}
