part of '../remote_messaging_service.dart';

mixin RemoteMessageSending on RemoteMessagingServiceBase {
  Future<String> sendText({
    required String conversationId,
    required String plaintext,
    required List<String> recipientDeviceIds,
    String? messageId,
    RemoteReplyReference? replyTo,
  }) {
    final privacy = _privacyForOutgoingContent(conversationId);
    return _sendContent(
      conversationId: conversationId,
      messagePlaintext: RemoteTextContent(
        text: plaintext,
        replyTo: replyTo,
        privacy: privacy,
      ).toPlaintext(),
      recipientDeviceIds: recipientDeviceIds,
      messageId: messageId,
      privacy: privacy,
    );
  }

  Future<String> _sendContent({
    required String conversationId,
    required String messagePlaintext,
    required List<String> recipientDeviceIds,
    required RemoteContentPrivacy privacy,
    String? messageId,
  }) async {
    final accountId = _requireAccountId();
    final deviceId = _requireDeviceId();
    final id = messageId ?? 'msg_${_clock().microsecondsSinceEpoch}';
    final trace = MessageLatencyRegistry.instance.beginSend(id)
      ..mark('send_tap');

    final localCiphertext = await protector.encryptText(
      conversationId: conversationId,
      messageId: id,
      plaintext: messagePlaintext,
      recipientDeviceId: 'local-history',
    );

    final localMessage = RemoteMessage(
      messageId: id,
      conversationId: conversationId,
      senderAccountId: accountId,
      senderDeviceId: deviceId,
      ciphertext: localCiphertext,
    );
    final sequence = _nextLocalSequence(conversationId);
    final timestamp = _clock().millisecondsSinceEpoch;
    final uniqueRecipientDeviceIds = recipientDeviceIds.toSet().toList();

    var transactionOpen = false;
    try {
      db.rawExecute('BEGIN IMMEDIATE;');
      transactionOpen = true;
      db.ensureConversationExists(
        conversationId: conversationId,
        senderAccountId: accountId,
        serverSequence: sequence,
        timestamp: timestamp,
      );
      db.saveMessage(localMessage, sequence, timestamp, 'PENDING');
      db.setMessagePrivacyMetadata(
        messageId: id,
        expiresAt: privacy.expiresAt,
        retentionDeadline: privacy.deliveryRetentionDeadline,
        viewOnce: privacy.viewOnce,
        keepInChat: privacy.keepInChat,
      );

      trace.mark('x3dh_start');
      final envelopes = await _buildX3dhEnvelopes(
        conversationId: conversationId,
        messageId: id,
        plaintext: messagePlaintext,
        recipientDeviceIds: uniqueRecipientDeviceIds,
        senderAccountId: accountId,
        senderDeviceId: deviceId,
      );
      trace.mark('x3dh_complete');

      db.enqueueOperation(
        'send_message_$id',
        'SEND_MESSAGE',
        jsonEncode({
          'message_id': id,
          'conversation_id': conversationId,
          'sender_account_id': accountId,
          'sender_device_id': deviceId,
          'protocol_version': 1,
          'content_envelope_version': 1,
          if (privacy.deliveryRetentionDeadline != null)
            'retention_deadline': privacy.deliveryRetentionDeadline,
          if (privacy.viewOnce) 'view_once': true,
          'envelopes': envelopes,
        }),
        idempotencyKey: 'message:$id',
      );
      db.rawExecute('COMMIT;');
      transactionOpen = false;
      trace.mark('queue_insertion');
      _emitChange(
        RemoteSyncChange(
          areas: const {
            RemoteSyncChangeArea.messages,
            RemoteSyncChangeArea.conversations,
            RemoteSyncChangeArea.outbox,
          },
          conversationId: conversationId,
        ),
      );
    } on SecureSessionUnavailableException {
      if (transactionOpen) {
        db.rawExecute('ROLLBACK;');
        transactionOpen = false;
      }
      db.ensureConversationExists(
        conversationId: conversationId,
        senderAccountId: accountId,
        serverSequence: sequence,
        timestamp: timestamp,
      );
      db.saveMessage(
        localMessage,
        sequence,
        timestamp,
        'SECURE_SESSION_UNAVAILABLE',
      );
      db.setMessagePrivacyMetadata(
        messageId: id,
        expiresAt: privacy.expiresAt,
        retentionDeadline: privacy.deliveryRetentionDeadline,
        viewOnce: privacy.viewOnce,
        keepInChat: privacy.keepInChat,
      );
      _emitChange(
        RemoteSyncChange(
          areas: const {
            RemoteSyncChangeArea.messages,
            RemoteSyncChangeArea.conversations,
          },
          conversationId: conversationId,
        ),
      );
    } catch (e, st) {
      if (transactionOpen) {
        db.rawExecute('ROLLBACK;');
        transactionOpen = false;
      }
      AppLogger.instance.error(
        'MessageSend',
        'sendText failed conv=$conversationId ${e.runtimeType}: $e',
        st,
      );
      db.ensureConversationExists(
        conversationId: conversationId,
        senderAccountId: accountId,
        serverSequence: sequence,
        timestamp: timestamp,
      );
      db.saveMessage(localMessage, sequence, timestamp, 'FAILED');
      db.setMessagePrivacyMetadata(
        messageId: id,
        expiresAt: privacy.expiresAt,
        retentionDeadline: privacy.deliveryRetentionDeadline,
        viewOnce: privacy.viewOnce,
        keepInChat: privacy.keepInChat,
      );
      _emitChange(
        RemoteSyncChange(
          areas: const {
            RemoteSyncChangeArea.messages,
            RemoteSyncChangeArea.conversations,
          },
          conversationId: conversationId,
        ),
      );
      rethrow;
    }

    return id;
  }

  Future<String> sendAttachment({
    required String conversationId,
    required RemoteAttachmentManifest manifest,
    required String filename,
    required String keyDeliverySecret,
    required List<String> recipientDeviceIds,
    String? messageId,
    bool viewOnce = false,
  }) {
    final privacy = _privacyForOutgoingContent(
      conversationId,
      viewOnce: viewOnce,
      forceNoExport: viewOnce,
    );
    final content = RemoteAttachmentContent(
      fileId: manifest.fileId,
      filename: filename,
      fileSize: manifest.fileSize,
      fileHash: manifest.fileHash,
      mimeType: manifest.mimeType,
      keyDeliverySecret: keyDeliverySecret,
      thumbnailFileId: manifest.thumbnailFileId,
      thumbnailFileSize: manifest.thumbnailFileSize,
      thumbnailFileHash: manifest.thumbnailFileHash,
      privacy: privacy,
    );
    return _sendContent(
      conversationId: conversationId,
      messagePlaintext: content.toPlaintext(),
      recipientDeviceIds: recipientDeviceIds,
      messageId: messageId,
      privacy: privacy,
    );
  }

  Future<String> sendRichMedia({
    required String conversationId,
    required String kind,
    required RemoteAttachmentManifest manifest,
    required String filename,
    required String keyDeliverySecret,
    required List<String> recipientDeviceIds,
    String? caption,
    int? durationMs,
    List<int> waveform = const [],
    List<RemoteMediaCollectionItem> items = const [],
    String? messageId,
    bool viewOnce = false,
  }) {
    final privacy = _privacyForOutgoingContent(
      conversationId,
      viewOnce: viewOnce,
      forceNoExport: viewOnce,
    );
    final attachment = RemoteAttachmentContent(
      fileId: manifest.fileId,
      filename: filename,
      fileSize: manifest.fileSize,
      fileHash: manifest.fileHash,
      mimeType: manifest.mimeType,
      keyDeliverySecret: keyDeliverySecret,
      thumbnailFileId: manifest.thumbnailFileId,
      thumbnailFileSize: manifest.thumbnailFileSize,
      thumbnailFileHash: manifest.thumbnailFileHash,
      privacy: privacy,
    );
    final content = RemoteMediaContent(
      kind: kind,
      attachment: attachment,
      caption: caption ?? '',
      durationMs: durationMs,
      waveform: waveform,
      items: items,
      privacy: privacy,
    );
    return _sendContent(
      conversationId: conversationId,
      messagePlaintext: content.toPlaintext(),
      recipientDeviceIds: recipientDeviceIds,
      messageId: messageId,
      privacy: privacy,
    );
  }

  Future<String> sendVoiceNote({
    required String conversationId,
    required RemoteAttachmentManifest manifest,
    required String filename,
    required String keyDeliverySecret,
    required List<String> recipientDeviceIds,
    required int durationMs,
    required List<int> waveform,
    String? messageId,
    bool viewOnce = false,
  }) {
    return sendRichMedia(
      conversationId: conversationId,
      kind: RemoteMediaContent.voiceNoteKind,
      manifest: manifest,
      filename: filename,
      keyDeliverySecret: keyDeliverySecret,
      recipientDeviceIds: recipientDeviceIds,
      durationMs: durationMs,
      waveform: waveform,
      messageId: messageId,
      viewOnce: viewOnce,
    );
  }

  Future<String> sendPoll({
    required String conversationId,
    required String question,
    required List<String> options,
    required List<String> recipientDeviceIds,
    String? pollId,
    String? messageId,
    bool allowMultipleVotes = false,
  }) {
    if (options.length < 2) {
      throw ArgumentError('Polls require at least two options');
    }
    final id = pollId ?? 'poll_${_clock().microsecondsSinceEpoch}';
    final now = _clock().millisecondsSinceEpoch;
    final content = RemotePollContent(
      pollId: id,
      question: question,
      creatorAccountId: _requireAccountId(),
      createdAt: now,
      allowMultipleVotes: allowMultipleVotes,
      options: [
        for (var i = 0; i < options.length; i++)
          RemotePollOption(optionId: 'opt_${i + 1}', text: options[i]),
      ],
    );
    return _sendContent(
      conversationId: conversationId,
      messagePlaintext: content.toPlaintext(),
      recipientDeviceIds: recipientDeviceIds,
      messageId: messageId,
      privacy: _privacyForOutgoingContent(conversationId),
    );
  }

  Future<void> castPollVote({
    required String conversationId,
    required String pollId,
    required List<String> optionIds,
    required bool allowMultipleVotes,
  }) async {
    final accountId = _requireAccountId();
    final normalized = allowMultipleVotes
        ? optionIds.toSet().toList()
        : optionIds.take(1).toList();
    final now = _clock().millisecondsSinceEpoch;
    final plaintext = jsonEncode({
      'type': 'helix.remote.poll-vote.v1',
      'poll_id': pollId,
      'account_id': accountId,
      'option_ids': normalized,
      'updated_at': now,
      'withdrawn': normalized.isEmpty,
    });
    final encryptedPayload = await protector.encryptText(
      conversationId: conversationId,
      messageId: pollId,
      plaintext: plaintext,
      recipientDeviceId: 'local-history',
    );
    final signature = _collaborationSignature(plaintext);
    db.savePollVote(
      pollId: pollId,
      accountId: accountId,
      optionIds: normalized,
      encryptedPayload: encryptedPayload,
      signature: signature,
      updatedAt: now,
    );
    db.enqueueOperation(
      'poll_vote_${pollId}_$accountId',
      'POLL_VOTE',
      jsonEncode({
        'poll_id': pollId,
        'conversation_id': conversationId,
        'account_id': accountId,
        'encrypted_payload': encryptedPayload,
        'signature': signature,
      }),
      idempotencyKey: 'poll_vote:$pollId:$accountId',
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
  }

  RemotePollResults pollResults(String pollId) => db.pollResults(pollId);

  Future<String> sendEventContent({
    required String conversationId,
    required String title,
    required int startsAt,
    required String timeZone,
    required List<String> recipientDeviceIds,
    String? eventId,
    String? messageId,
    int? endsAt,
    String locationText = '',
    bool plusOneAllowed = false,
    bool pinned = false,
    bool attendeeListPrivate = true,
  }) {
    final id = eventId ?? 'event_${_clock().microsecondsSinceEpoch}';
    final content = RemoteEventContent(
      eventId: id,
      title: title,
      creatorAccountId: _requireAccountId(),
      startsAt: startsAt,
      endsAt: endsAt,
      timeZone: timeZone,
      locationText: locationText,
      plusOneAllowed: plusOneAllowed,
      pinned: pinned,
      attendeeListPrivate: attendeeListPrivate,
    );
    return _sendContent(
      conversationId: conversationId,
      messagePlaintext: content.toPlaintext(),
      recipientDeviceIds: recipientDeviceIds,
      messageId: messageId,
      privacy: _privacyForOutgoingContent(conversationId),
    );
  }

  Future<void> updateEventRsvp({
    required String conversationId,
    required String eventId,
    required String state,
    bool plusOne = false,
  }) async {
    final accountId = _requireAccountId();
    final now = _clock().millisecondsSinceEpoch;
    final plaintext = jsonEncode({
      'type': 'helix.remote.event-rsvp.v1',
      'event_id': eventId,
      'account_id': accountId,
      'state': state,
      'plus_one': plusOne,
      'updated_at': now,
    });
    final encryptedPayload = await protector.encryptText(
      conversationId: conversationId,
      messageId: eventId,
      plaintext: plaintext,
      recipientDeviceId: 'local-history',
    );
    db.saveEventRsvp(
      eventId: eventId,
      accountId: accountId,
      state: state,
      plusOne: plusOne,
      encryptedPayload: encryptedPayload,
      updatedAt: now,
    );
    db.enqueueOperation(
      'event_rsvp_${eventId}_$accountId',
      'EVENT_RSVP',
      jsonEncode({
        'event_id': eventId,
        'conversation_id': conversationId,
        'account_id': accountId,
        'encrypted_payload': encryptedPayload,
      }),
      idempotencyKey: 'event_rsvp:$eventId:$accountId',
    );
  }

  Map<String, String> eventRsvpStates(String eventId) =>
      db.eventRsvpStates(eventId);

  Future<void> scheduleEventReminder({
    required String conversationId,
    required String eventId,
    required int remindAt,
    required String note,
    String? reminderId,
  }) async {
    final id = reminderId ?? 'reminder_${_clock().microsecondsSinceEpoch}';
    final encryptedNote = await protector.encryptText(
      conversationId: conversationId,
      messageId: eventId,
      plaintext: note,
      recipientDeviceId: 'local-history',
    );
    db.saveEventReminder(
      RemoteEventReminder(
        reminderId: id,
        eventId: eventId,
        conversationId: conversationId,
        remindAt: remindAt,
        encryptedNote: encryptedNote,
        status: 'scheduled',
        updatedAt: _clock().millisecondsSinceEpoch,
      ),
    );
  }

  List<RemoteEventReminder> dueEventReminders(int nowMs) =>
      db.dueEventReminders(nowMs);

  Future<String> sendStaticLocation({
    required String conversationId,
    required int latitudeE7,
    required int longitudeE7,
    required int accuracyMeters,
    required List<String> recipientDeviceIds,
    String label = '',
    String? locationId,
    String? messageId,
  }) {
    final content = RemoteLocationContent(
      locationId: locationId ?? 'loc_${_clock().microsecondsSinceEpoch}',
      latitudeE7: latitudeE7,
      longitudeE7: longitudeE7,
      accuracyMeters: accuracyMeters,
      createdAt: _clock().millisecondsSinceEpoch,
      label: label,
    );
    return _sendContent(
      conversationId: conversationId,
      messagePlaintext: content.toPlaintext(),
      recipientDeviceIds: recipientDeviceIds,
      messageId: messageId,
      privacy: _privacyForOutgoingContent(conversationId),
    );
  }

  Future<String> startLiveLocation({
    required String conversationId,
    required int latitudeE7,
    required int longitudeE7,
    required int accuracyMeters,
    required Duration duration,
    required List<String> recipientDeviceIds,
    String? sessionId,
    String? messageId,
    Duration updateInterval = const Duration(seconds: 30),
  }) async {
    final now = _clock().millisecondsSinceEpoch;
    final id = sessionId ?? 'live_${_clock().microsecondsSinceEpoch}';
    final expiresAt = now + duration.inMilliseconds;
    final msgId = await _sendContent(
      conversationId: conversationId,
      messagePlaintext: RemoteLocationContent(
        locationId: id,
        latitudeE7: latitudeE7,
        longitudeE7: longitudeE7,
        accuracyMeters: accuracyMeters,
        createdAt: now,
        live: true,
        expiresAt: expiresAt,
      ).toPlaintext(),
      recipientDeviceIds: recipientDeviceIds,
      messageId: messageId,
      privacy: _privacyForOutgoingContent(
        conversationId,
        forcedExpiresAt: expiresAt,
      ),
    );
    db.saveLiveLocationSession(
      RemoteLiveLocationSession(
        sessionId: id,
        conversationId: conversationId,
        messageId: msgId,
        startedAt: now,
        expiresAt: expiresAt,
        updateIntervalMs: updateInterval.inMilliseconds,
        status: 'active',
        lastUpdateAt: now,
      ),
    );
    return id;
  }

  Future<bool> publishLiveLocationUpdate({
    required String sessionId,
    required int latitudeE7,
    required int longitudeE7,
    required int accuracyMeters,
  }) async {
    final session = db.liveLocationSession(sessionId);
    final now = _clock().millisecondsSinceEpoch;
    if (session == null ||
        session.status != 'active' ||
        now >= session.expiresAt) {
      db.expireLiveLocationSessions(now);
      return false;
    }
    if (now - session.lastUpdateAt < session.updateIntervalMs) return false;
    final plaintext = jsonEncode({
      'type': 'helix.remote.live-location-update.v1',
      'session_id': sessionId,
      'latitude_e7': latitudeE7,
      'longitude_e7': longitudeE7,
      'accuracy_meters': accuracyMeters,
      'created_at': now,
    });
    final encryptedPayload = await protector.encryptText(
      conversationId: session.conversationId,
      messageId: session.messageId,
      plaintext: plaintext,
      recipientDeviceId: 'local-history',
    );
    db.saveLiveLocationUpdate(
      sessionId: sessionId,
      latitudeE7: latitudeE7,
      longitudeE7: longitudeE7,
      accuracyMeters: accuracyMeters,
      createdAt: now,
      encryptedPayload: encryptedPayload,
    );
    db.enqueueOperation(
      'live_location_${sessionId}_$now',
      'LIVE_LOCATION_UPDATE',
      jsonEncode({
        'session_id': sessionId,
        'conversation_id': session.conversationId,
        'encrypted_payload': encryptedPayload,
      }),
      idempotencyKey: 'live_location:$sessionId:$now',
    );
    return true;
  }

  void stopLiveLocation(String sessionId) {
    db.stopLiveLocationSession(sessionId, _clock().millisecondsSinceEpoch);
  }

  int expireLiveLocations() =>
      db.expireLiveLocationSessions(_clock().millisecondsSinceEpoch);

  String _collaborationSignature(String plaintext) {
    final key = _devicePrivateKey ?? utf8.encode(_requireDeviceId());
    return crypto_hash.Hmac(
      crypto_hash.sha256,
      key,
    ).convert(utf8.encode(plaintext)).toString();
  }

  Future<String> sendViewOnceAttachment({
    required String conversationId,
    required RemoteAttachmentManifest manifest,
    required String filename,
    required String keyDeliverySecret,
    required List<String> recipientDeviceIds,
    String? messageId,
  }) {
    return sendAttachment(
      conversationId: conversationId,
      manifest: manifest,
      filename: filename,
      keyDeliverySecret: keyDeliverySecret,
      recipientDeviceIds: recipientDeviceIds,
      messageId: messageId,
      viewOnce: true,
    );
  }

  Future<void> publishTyping({
    required String conversationId,
    required bool isTyping,
  }) {
    return gateway.sendOutboundOperation(
      opId: 'typing_${conversationId}_${_clock().microsecondsSinceEpoch}',
      type: 'TYPING',
      payload: {
        'conversation_id': conversationId,
        'account_id': _requireAccountId(),
        'device_id': _requireDeviceId(),
        'is_typing': isTyping,
      },
    );
  }

  Future<void> editMessage({
    required String messageId,
    required String conversationId,
    required String plaintext,
  }) async {
    final message = db.getMessageById(messageId);
    final sentAt = message?['timestamp'] as int? ?? 0;
    if (_clock().millisecondsSinceEpoch - sentAt >
        const Duration(minutes: 15).inMilliseconds) {
      throw StateError('Edit window expired');
    }
    final revisionId = 'edit_${messageId}_${_clock().microsecondsSinceEpoch}';
    final ciphertext = await protector.encryptText(
      conversationId: conversationId,
      messageId: messageId,
      plaintext: RemoteTextContent(text: plaintext).toPlaintext(),
      recipientDeviceId: 'local-history',
    );

    db.saveMessageRevision(
      revisionId: revisionId,
      messageId: messageId,
      type: 'EDIT',
      authorId: _requireAccountId(),
      payload: jsonEncode({'ciphertext': ciphertext}),
      timestamp: _clock().millisecondsSinceEpoch,
    );
    db.enqueueOperation(
      revisionId,
      'EDIT_MESSAGE',
      jsonEncode({
        'message_id': messageId,
        'conversation_id': conversationId,
        'revision_id': revisionId,
        'ciphertext': ciphertext,
        'protocol_version': 1,
        'sender_device_id': _requireDeviceId(),
      }),
      idempotencyKey: 'edit:$revisionId',
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
  }

  void addReaction({required String messageId, required String reaction}) {
    final accountId = _requireAccountId();
    final revisionId = 'reaction_${messageId}_$accountId';
    db.saveMessageRevision(
      revisionId: revisionId,
      messageId: messageId,
      type: 'REACTION',
      authorId: accountId,
      payload: jsonEncode({'reaction': reaction, 'account_id': accountId}),
      timestamp: _clock().millisecondsSinceEpoch,
    );
    db.enqueueOperation(
      revisionId,
      'REACTION',
      jsonEncode({
        'message_id': messageId,
        'revision_id': revisionId,
        'reaction': reaction,
        'account_id': accountId,
      }),
      idempotencyKey: 'reaction:$revisionId',
    );
    _emitChange(
      const RemoteSyncChange(
        areas: {RemoteSyncChangeArea.messages, RemoteSyncChangeArea.outbox},
      ),
    );
  }

  void deleteForSelf(String messageId) {
    db.saveTombstone(messageId, 'MESSAGE');
    db.deleteMessage(messageId);
    _emitChange(const RemoteSyncChange(areas: {RemoteSyncChangeArea.messages}));
  }

  void deleteForEveryone({
    required String messageId,
    required String conversationId,
    bool productContractApproved = true,
  }) {
    if (!productContractApproved) {
      throw StateError(
        'Delete-for-everyone requires product contract approval',
      );
    }

    final message = db.getMessageById(messageId);
    final sentAt = message?['timestamp'] as int? ?? 0;
    if (_clock().millisecondsSinceEpoch - sentAt >
        const Duration(days: 2).inMilliseconds) {
      throw StateError('Delete-for-everyone window expired');
    }
    db.saveTombstone(messageId, 'MESSAGE');
    db.deleteMessage(messageId);
    db.enqueueOperation(
      'delete_$messageId',
      'DELETE_MESSAGE',
      jsonEncode({
        'message_id': messageId,
        'conversation_id': conversationId,
        'protocol_version': 1,
        'sender_device_id': _requireDeviceId(),
      }),
      idempotencyKey: 'delete:$messageId',
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
  }

  RemotePushNotificationPreview notificationPreview(String conversationId) {
    final privacy = db.getConversationPrivacy(conversationId);
    final previewsAllowed =
        db.getNotificationPreviewsEnabled() && !privacy.isLocked;
    return RemotePushNotificationPreview(
      conversationId: conversationId,
      title: 'Helix Remote',
      body: previewsAllowed ? 'New encrypted message' : 'New message',
    );
  }

  bool canExportAttachment({
    required String conversationId,
    required RemoteAttachmentContent attachment,
  }) {
    final privacy = db.getConversationPrivacy(conversationId);
    if (!privacy.exportAllowed || !privacy.externalSaveAllowed) return false;
    if (attachment.privacy?.viewOnce == true) return false;
    if (attachment.privacy?.exportAllowed == false ||
        attachment.privacy?.externalSaveAllowed == false) {
      return false;
    }
    return true;
  }

  RemoteContentPrivacy _privacyForOutgoingContent(
    String conversationId, {
    bool viewOnce = false,
    bool forceNoExport = false,
    int? forcedExpiresAt,
  }) {
    final conversationPrivacy = db.getConversationPrivacy(conversationId);
    final seconds = conversationPrivacy.disappearingSeconds > 0
        ? conversationPrivacy.disappearingSeconds
        : db.getAccountDefaultDisappearingSeconds();
    final now = _clock().millisecondsSinceEpoch;
    final expiresAt =
        forcedExpiresAt ?? (seconds > 0 ? now + seconds * 1000 : null);
    return RemoteContentPrivacy(
      expiresAt: expiresAt,
      deliveryRetentionDeadline: expiresAt,
      viewOnce: viewOnce,
      exportAllowed: !forceNoExport && conversationPrivacy.exportAllowed,
      externalSaveAllowed:
          !forceNoExport && conversationPrivacy.externalSaveAllowed,
      forwardingAllowed: !viewOnce && conversationPrivacy.forwardingAllowed,
      automaticMediaSaveAllowed:
          !viewOnce && conversationPrivacy.automaticMediaSaveAllowed,
      aiProcessingAllowed: conversationPrivacy.aiProcessingAllowed,
    );
  }

  int _nextLocalSequence(String conversationId) {
    final rows = db.getMessages(conversationId, limit: 1);
    if (rows.isEmpty) {
      return 1;
    }
    return (rows.first['server_sequence'] as int) + 1;
  }
}
