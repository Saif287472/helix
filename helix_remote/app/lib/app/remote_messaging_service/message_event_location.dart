part of '../remote_messaging_service.dart';

mixin RemoteEventLocationSending
    on RemoteMessagingServiceBase, RemoteMessageSending {
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
}
