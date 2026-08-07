part of '../remote_messaging_service.dart';

mixin RemoteConversationManagement on RemoteMessagingServiceBase {
  String createDirectConversation({
    required String peerAccountId,
    String? conversationId,
    String? title,
  }) {
    final accountId = _requireAccountId();
    final deviceId = _requireDeviceId();
    final contact = db.getContact(peerAccountId);
    if (contact == null || contact.status != 'Accepted') {
      throw StateError(
        'Direct conversations require an accepted Remote contact',
      );
    }
    final id =
        conversationId ?? _stableDirectConversationId(accountId, peerAccountId);

    db.upsertConversation(
      RemoteConversation(
        conversationId: id,
        type: 'DIRECT',
        title: title ?? '',
        createdAt: _clock(),
        lastActivitySequence: 0,
      ),
      [accountId, peerAccountId],
    );

    db.enqueueOperation(
      'create_conversation_$id',
      'CREATE_CONVERSATION',
      jsonEncode({
        'conversation_id': id,
        'type': 'DIRECT',
        'title': title,
        'members': [accountId, peerAccountId],
        'protocol_version': 1,
        'sender_device_id': deviceId,
      }),
      idempotencyKey: 'conversation:$id',
    );

    _emitChange(
      RemoteSyncChange(
        areas: const {
          RemoteSyncChangeArea.conversations,
          RemoteSyncChangeArea.outbox,
        },
        conversationId: id,
      ),
    );

    return id;
  }

  List<RemoteConversation> conversationList() => db.getConversations();

  List<RemoteConversation> conversationListByKind(
    String kind, {
    String? listId,
  }) {
    return db.conversationsForList(
      kind: kind,
      listId: listId,
      deviceId: _deviceId,
    );
  }

  void pinConversation(String conversationId, {required bool pinned}) {
    db.setConversationPinned(conversationId, pinned: pinned);
    _emitChange(
      RemoteSyncChange(
        areas: const {RemoteSyncChangeArea.conversations},
        conversationId: conversationId,
      ),
    );
  }

  void favoriteConversation(String conversationId, {required bool favorite}) {
    db.setConversationFavorite(conversationId, favorite: favorite);
    _emitChange(
      RemoteSyncChange(
        areas: const {RemoteSyncChangeArea.conversations},
        conversationId: conversationId,
      ),
    );
  }

  void createCustomConversationList({
    required String listId,
    required String name,
    required int sortOrder,
  }) {
    db.upsertConversationList(
      listId: listId,
      name: name,
      kind: 'custom',
      sortOrder: sortOrder,
    );
    _emitChange(
      const RemoteSyncChange(areas: {RemoteSyncChangeArea.conversations}),
    );
  }

  void addConversationToCustomList({
    required String listId,
    required String conversationId,
    required int sortOrder,
  }) {
    db.addConversationToList(
      listId: listId,
      conversationId: conversationId,
      sortOrder: sortOrder,
    );
    _emitChange(
      RemoteSyncChange(
        areas: const {RemoteSyncChangeArea.conversations},
        conversationId: conversationId,
      ),
    );
  }

  void muteConversation(String conversationId, {required bool muted}) {
    db.setConversationMuted(conversationId, muted: muted);
    _emitChange(
      RemoteSyncChange(
        areas: const {RemoteSyncChangeArea.conversations},
        conversationId: conversationId,
      ),
    );
  }

  void clearChat(String conversationId) {
    db.clearConversationMessages(conversationId);
    _emitChange(
      RemoteSyncChange(
        areas: const {RemoteSyncChangeArea.conversations},
        conversationId: conversationId,
      ),
    );
  }

  void markConversationRead(String conversationId) {
    final deviceId = _requireDeviceId();
    final messages = db.getMessages(conversationId, limit: 1);
    final lastSequence = messages.isEmpty
        ? 0
        : messages.first['server_sequence'] as int;
    db.markConversationRead(
      conversationId: conversationId,
      deviceId: deviceId,
      lastReadSequence: lastSequence,
      updatedAt: _clock().millisecondsSinceEpoch,
    );
    // Deliberately not enqueued to the outbox: 'MARK_CONVERSATION_READ' was
    // never added to RemoteOutboundOperation.values (remote_sync_gateway.dart),
    // so RemoteOutboundOperationRegistry.require() throws for it every
    // single time - there is no server endpoint for cross-device read-state
    // sync yet. Every call to this method therefore added a permanently
    // failed outbox row (see migration 27, which clears out whatever
    // already piled up from this). The local read-state write above already
    // covers this device's own unread badges/counts, which is all that
    // currently reads it.
    _emitChange(
      RemoteSyncChange(
        areas: const {RemoteSyncChangeArea.conversations},
        conversationId: conversationId,
      ),
    );
  }

  RemoteUnreadSummary unreadSummary(String conversationId) =>
      db.unreadSummary(conversationId, _requireDeviceId());

  RemoteStorageSummary storageSummary(String conversationId) =>
      db.storageSummary(conversationId);

  void clearConversationMedia(String conversationId) {
    db.clearMediaForConversation(conversationId);
    _emitChange(
      RemoteSyncChange(
        areas: const {RemoteSyncChangeArea.messages},
        conversationId: conversationId,
      ),
    );
  }

  RemoteMediaDraft startMediaDraft({
    required String conversationId,
    required String kind,
    required String localPath,
    String caption = '',
    int durationMs = 0,
    List<int> waveform = const [],
    bool viewOnce = false,
  }) {
    final now = _clock().millisecondsSinceEpoch;
    final draft = RemoteMediaDraft(
      draftId: 'draft_${_clock().microsecondsSinceEpoch}',
      conversationId: conversationId,
      kind: kind,
      status: 'recording',
      localPath: localPath,
      caption: caption,
      durationMs: durationMs,
      waveform: waveform,
      viewOnce: viewOnce,
      createdAt: now,
      updatedAt: now,
    );
    db.upsertMediaDraft(draft);
    return draft;
  }

  void pauseMediaDraft(String draftId) {
    db.updateMediaDraftStatus(
      draftId: draftId,
      status: 'paused',
      updatedAt: _clock().millisecondsSinceEpoch,
    );
  }

  void resumeMediaDraft(String draftId) {
    db.updateMediaDraftStatus(
      draftId: draftId,
      status: 'recording',
      updatedAt: _clock().millisecondsSinceEpoch,
    );
  }

  void markMediaDraftReady(String draftId) {
    db.updateMediaDraftStatus(
      draftId: draftId,
      status: 'ready',
      updatedAt: _clock().millisecondsSinceEpoch,
    );
  }

  void cancelMediaDraft(String draftId) {
    final draft = db.mediaDraft(draftId);
    db.deleteMediaDraft(draftId);
    final path = draft?.localPath;
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (file.existsSync()) {
      try {
        file.deleteSync();
      } catch (e) {
        // The draft row is already gone, so a failure here leaves decrypted
        // media on disk with nothing pointing at it - a retention problem
        // that was previously invisible.
        AppLogger.instance.warn(
          'conversations',
          'discarded media draft file could not be deleted: $e',
        );
      }
    }
  }

  List<RemoteMediaDraft> mediaDrafts(String conversationId) =>
      db.mediaDrafts(conversationId);

  void saveMediaPlaybackState({
    required String messageId,
    required int positionMs,
    double speed = 1.0,
  }) {
    final clampedSpeed = speed == 1.5 || speed == 2.0 ? speed : 1.0;
    db.savePlaybackState(
      messageId: messageId,
      positionMs: math.max(0, positionMs),
      speed: clampedSpeed,
      updatedAt: _clock().millisecondsSinceEpoch,
    );
  }

  RemoteMediaPlaybackState? mediaPlaybackState(String messageId) =>
      db.playbackState(messageId);

  void saveMediaTransferPolicy({
    required String attachmentId,
    bool backgroundAllowed = true,
    int expiresAt = 0,
    int retryCount = 0,
    String status = 'ready',
  }) {
    db.saveMediaTransferPolicy(
      attachmentId: attachmentId,
      backgroundAllowed: backgroundAllowed,
      expiresAt: expiresAt,
      retryCount: retryCount,
      status: status,
      updatedAt: _clock().millisecondsSinceEpoch,
    );
  }

  bool safeLinkPreviewAllowed(String url, {required bool optedIn}) =>
      db.safeLinkPreviewAllowed(url, optedIn: optedIn);

  String createSignedContactLink({
    required String linkId,
    required String nonce,
    required Duration ttl,
  }) {
    final accountId = _requireAccountId();
    final expiresAt = _clock().add(ttl).millisecondsSinceEpoch;
    final signature = _contactLinkSignature(
      accountId: accountId,
      nonce: nonce,
      expiresAt: expiresAt,
    );
    return db.createContactLink(
      linkId: linkId,
      accountId: accountId,
      nonce: nonce,
      expiresAt: expiresAt,
      signature: signature,
    );
  }

  bool verifySignedContactLink(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null ||
        uri.scheme != 'helix' ||
        uri.host != 'contact' ||
        uri.pathSegments.firstOrNull != 'add') {
      return false;
    }
    final params = uri.queryParameters;
    final accountId = params['a'];
    final nonce = params['n'];
    final expiresAt = int.tryParse(params['e'] ?? '');
    final signature = params['s'];
    if (params['v'] != '1' ||
        accountId == null ||
        accountId.isEmpty ||
        nonce == null ||
        nonce.isEmpty ||
        expiresAt == null ||
        signature == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(signature)) {
      return false;
    }
    return db.verifyContactLinkPayload(
      link,
      now: _clock().millisecondsSinceEpoch,
    );
  }

  String _contactLinkSignature({
    required String accountId,
    required String nonce,
    required int expiresAt,
  }) {
    final key = _devicePrivateKey ?? utf8.encode(_requireDeviceId());
    final payload = utf8.encode('$accountId|$nonce|$expiresAt');
    return crypto_hash.Hmac(
      crypto_hash.sha256,
      key,
    ).convert(payload).toString();
  }

  void deleteConversation(String conversationId) {
    db.deleteConversation(conversationId);
    _emitChange(
      RemoteSyncChange(
        areas: const {RemoteSyncChangeArea.conversations},
        conversationId: conversationId,
      ),
    );
  }

  String? peerAccountIdForConversation(String conversationId) {
    final myId = _accountId;
    if (myId == null) return null;
    final members = db.getConversationMembers(conversationId);
    final peerId = members.firstWhere((id) => id != myId, orElse: () => '');
    return peerId.isEmpty ? null : peerId;
  }

  @override
  List<String> conversationMemberIds(String conversationId) =>
      db.getConversationMembers(conversationId);

  /// Returns the display name to show for a DM conversation.
  /// For a 1-to-1 conversation it prefers a phone-book name learned from
  /// contacts sync, then the peer's nickname from contacts, falling back to
  /// the raw account ID if neither is known. Returns null for group
  /// conversations.
  String? peerDisplayName(String conversationId) {
    final myId = _accountId;
    if (myId == null) return null;
    final members = db.getConversationMembers(conversationId);
    final peerId = members.firstWhere((id) => id != myId, orElse: () => '');
    if (peerId.isEmpty) return null;
    final phoneBookName = db.phoneContactName(peerId);
    if (phoneBookName != null && phoneBookName.isNotEmpty) {
      return phoneBookName;
    }
    final contact = db.getContacts().firstWhere(
      (c) => c.peerAccountId == peerId,
      orElse: () =>
          RemoteContact(peerAccountId: peerId, nickname: peerId, status: ''),
    );
    return contact.nickname.isNotEmpty ? contact.nickname : peerId;
  }

  List<String> recipientDeviceIdsForConversation(String conversationId) {
    final members = db.getConversationMembers(conversationId);
    final accountId = _requireAccountId();
    final ids = <String>[];
    for (final memberId in members) {
      if (memberId == accountId) continue;
      for (final device in db.getDevices(memberId)) {
        ids.add(device.deviceId.toString());
      }
    }
    return ids;
  }

  String _stableDirectConversationId(String a, String b) =>
      directConversationIdFor(a, b);

  String directConversationIdFor(String a, String b) {
    final members = [a, b]..sort();
    return 'dm_${base64UrlEncode(utf8.encode(members.join('|'))).replaceAll('=', '')}';
  }

  /// Returns the DM conversation ID for a peer, using the current account.
  String? conversationIdForPeer(String peerAccountId) {
    final myId = _accountId;
    if (myId == null) return null;
    return directConversationIdFor(myId, peerAccountId);
  }
}
