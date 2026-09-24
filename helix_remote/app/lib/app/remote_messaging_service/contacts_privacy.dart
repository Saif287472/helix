part of '../remote_messaging_service.dart';

mixin RemoteContactsPrivacy on RemoteMessagingServiceBase {
  void addContact({required String peerAccountId, required String nickname}) {
    db.upsertContact(
      RemoteContact(
        peerAccountId: peerAccountId,
        nickname: nickname,
        status: 'Accepted',
      ),
    );
    _emitChange(const RemoteSyncChange(areas: {RemoteSyncChangeArea.contacts}));
  }

  void notifyContactsChanged() {
    _emitChange(const RemoteSyncChange(areas: {RemoteSyncChangeArea.contacts}));
  }

  void sendContactRequest({
    required String peerAccountId,
    String nickname = '',
    String? requestId,
  }) {
    _enforceContactRequestQuota();
    _assertCanSendContactRequest(peerAccountId);
    final id = requestId ?? 'cr_${_clock().microsecondsSinceEpoch}';
    final now = _clock().millisecondsSinceEpoch;
    db.upsertContact(
      RemoteContact(
        peerAccountId: peerAccountId,
        nickname: nickname,
        status: 'PendingSent',
      ),
    );
    db.upsertContactRequest(
      RemoteContactRequest(
        requestId: id,
        peerAccountId: peerAccountId,
        direction: 'sent',
        status: 'Pending',
        updatedAt: now,
        nickname: nickname,
      ),
    );
    db.enqueueOperation(
      id,
      'CONTACT_REQUEST',
      jsonEncode({
        'request_id': id,
        'peer_account_id': peerAccountId,
        'nickname': nickname,
        'protocol_version': 1,
        'sender_device_id': _deviceId,
      }),
      idempotencyKey: 'contact_request:$id',
    );
    _contactRequestTimestamps.add(now);
    _emitChange(
      const RemoteSyncChange(
        areas: {RemoteSyncChangeArea.contacts, RemoteSyncChangeArea.outbox},
      ),
    );
  }

  void recordIncomingContactRequest({
    required String requestId,
    required String peerAccountId,
    String nickname = '',
  }) {
    db.upsertContact(
      RemoteContact(
        peerAccountId: peerAccountId,
        nickname: nickname,
        status: 'PendingReceived',
      ),
    );
    db.upsertContactRequest(
      RemoteContactRequest(
        requestId: requestId,
        peerAccountId: peerAccountId,
        direction: 'received',
        status: 'Pending',
        updatedAt: _clock().millisecondsSinceEpoch,
        nickname: nickname,
      ),
    );
    _emitChange(const RemoteSyncChange(areas: {RemoteSyncChangeArea.contacts}));
  }

  void acceptContactRequest({
    required String requestId,
    required String peerAccountId,
    String nickname = '',
  }) {
    _assertOpenRequest(requestId, peerAccountId, 'received');
    db.upsertContact(
      RemoteContact(
        peerAccountId: peerAccountId,
        nickname: nickname,
        status: 'Accepted',
      ),
    );
    db.updateContactRequestStatus(
      requestId,
      'Accepted',
      _clock().millisecondsSinceEpoch,
    );
    db.enqueueOperation(
      'accept_$requestId',
      'CONTACT_REQUEST_ACCEPT',
      jsonEncode({
        'request_id': requestId,
        'protocol_version': 1,
        'sender_device_id': _deviceId,
      }),
      idempotencyKey: 'contact_accept:$requestId',
    );
    _emitChange(
      const RemoteSyncChange(
        areas: {RemoteSyncChangeArea.contacts, RemoteSyncChangeArea.outbox},
      ),
    );
  }

  void rejectContactRequest({
    required String requestId,
    required String peerAccountId,
  }) {
    _assertOpenRequest(requestId, peerAccountId, 'received');
    db.deleteContact(peerAccountId);
    db.updateContactRequestStatus(
      requestId,
      'Rejected',
      _clock().millisecondsSinceEpoch,
    );
    db.enqueueOperation(
      'reject_$requestId',
      'CONTACT_REQUEST_REJECT',
      jsonEncode({
        'request_id': requestId,
        'protocol_version': 1,
        'sender_device_id': _deviceId,
      }),
      idempotencyKey: 'contact_reject:$requestId',
    );
    _emitChange(
      const RemoteSyncChange(
        areas: {RemoteSyncChangeArea.contacts, RemoteSyncChangeArea.outbox},
      ),
    );
  }

  void cancelContactRequest({
    required String requestId,
    required String peerAccountId,
  }) {
    _assertOpenRequest(requestId, peerAccountId, 'sent');
    db.deleteContact(peerAccountId);
    db.updateContactRequestStatus(
      requestId,
      'Cancelled',
      _clock().millisecondsSinceEpoch,
    );
    db.enqueueOperation(
      'cancel_$requestId',
      'CONTACT_REQUEST_CANCEL',
      jsonEncode({
        'request_id': requestId,
        'protocol_version': 1,
        'sender_device_id': _deviceId,
      }),
      idempotencyKey: 'contact_cancel:$requestId',
    );
    _emitChange(
      const RemoteSyncChange(
        areas: {RemoteSyncChangeArea.contacts, RemoteSyncChangeArea.outbox},
      ),
    );
  }

  void removeContact(String peerAccountId) {
    db.deleteContact(peerAccountId);
    db.enqueueOperation(
      'remove_contact_${peerAccountId}_${_clock().microsecondsSinceEpoch}',
      'CONTACT_REMOVE',
      jsonEncode({
        'peer_account_id': peerAccountId,
        'protocol_version': 1,
        'sender_device_id': _deviceId,
      }),
      idempotencyKey: 'contact_remove:$peerAccountId',
    );
    _emitChange(
      const RemoteSyncChange(
        areas: {RemoteSyncChangeArea.contacts, RemoteSyncChangeArea.outbox},
      ),
    );
  }

  void blockContact(String peerAccountId) {
    db.upsertContact(
      RemoteContact(
        peerAccountId: peerAccountId,
        nickname: '',
        status: 'Blocked',
      ),
    );
    db.enqueueOperation(
      'block_contact_${peerAccountId}_${_clock().microsecondsSinceEpoch}',
      'CONTACT_BLOCK',
      jsonEncode({
        'peer_account_id': peerAccountId,
        'protocol_version': 1,
        'sender_device_id': _deviceId,
      }),
      idempotencyKey: 'contact_block:$peerAccountId',
    );
    _emitChange(
      const RemoteSyncChange(
        areas: {RemoteSyncChangeArea.contacts, RemoteSyncChangeArea.outbox},
      ),
    );
  }

  void unblockContact(String peerAccountId) {
    db.deleteContact(peerAccountId);
    db.enqueueOperation(
      'unblock_contact_${peerAccountId}_${_clock().microsecondsSinceEpoch}',
      'CONTACT_UNBLOCK',
      jsonEncode({
        'peer_account_id': peerAccountId,
        'protocol_version': 1,
        'sender_device_id': _deviceId,
      }),
      idempotencyKey: 'contact_unblock:$peerAccountId',
    );
    _emitChange(
      const RemoteSyncChange(
        areas: {RemoteSyncChangeArea.contacts, RemoteSyncChangeArea.outbox},
      ),
    );
  }

  /// Records phone-book display names learned from matching the device's
  /// contacts against the backend's /contacts/match endpoint. These are
  /// local-only overrides that feed into [peerDisplayName] - they exist
  /// independently of the `contacts` table since a match can be found for
  /// an account that isn't a Helix contact yet.
  void recordPhoneContactMatches(Map<String, String> accountIdToPhoneBookName) {
    if (accountIdToPhoneBookName.isEmpty) return;
    final now = _clock().millisecondsSinceEpoch;
    accountIdToPhoneBookName.forEach((accountId, phoneBookName) {
      final trimmed = phoneBookName.trim();
      if (trimmed.isEmpty) return;
      db.savePhoneContactName(
        peerAccountId: accountId,
        phoneBookName: trimmed,
        updatedAt: now,
      );
    });
    _emitChange(const RemoteSyncChange(areas: {RemoteSyncChangeArea.contacts}));
  }

  /// The device's own phone-book label for [peerAccountId], if a contacts
  /// sync has matched it. Null when no override is known.
  String? phoneBookNameFor(String peerAccountId) =>
      db.phoneContactName(peerAccountId);

  /// Every persisted phone-book override, keyed by account ID. Includes
  /// accounts that aren't Helix contacts yet - the Contacts screen uses
  /// this to surface matched-but-not-added phone-book suggestions, and it
  /// survives across app restarts since it's read straight from local
  /// storage rather than a single sync's in-memory result.
  Map<String, String> phoneContactOverrides() => db.phoneContactNames();

  /// Records the phone-book contacts that matched no Helix account.
  ///
  /// Call only for a complete sync: this replaces the stored list wholesale,
  /// and a budget-truncated sync has no opinion about the contacts it never
  /// looked up.
  void recordUnmatchedPhoneContacts(List<String> phoneBookNames) {
    db.replaceUnmatchedPhoneContacts(
      phoneBookNames: phoneBookNames,
      syncedAt: _clock().millisecondsSinceEpoch,
    );
    _emitChange(const RemoteSyncChange(areas: {RemoteSyncChangeArea.contacts}));
  }

  /// The stored "not on Helix yet" list. Survives leaving the screen and
  /// restarting the app, unlike the sync result it came from.
  List<String> unmatchedPhoneContacts() => db.unmatchedPhoneContactNames();

  /// When that list was last rebuilt, or null if no complete sync has ever
  /// run on this device.
  int? unmatchedPhoneContactsSyncedAt() => db.unmatchedPhoneContactsSyncedAt();

  List<RemoteContact> searchLocalContacts(String query) {
    final normalized = query.toLowerCase();
    return db
        .getContacts()
        .where(
          (contact) =>
              contact.peerAccountId.toLowerCase().contains(normalized) ||
              contact.nickname.toLowerCase().contains(normalized),
        )
        .toList();
  }

  List<RemoteContact> acceptedContacts() =>
      db.getContacts().where((c) => c.status == 'Accepted').toList();

  List<RemoteContactRequest> contactRequests() => db.getContactRequests();

  void updatePrivacy(RemotePrivacySettings settings) {
    _validateVisibility(settings.presenceVisibility);
    _validateVisibility(settings.lastSeenVisibility);
    _privacySettings = settings;
    db.enqueueOperation(
      'privacy_${_clock().microsecondsSinceEpoch}',
      'PRIVACY_UPDATE',
      jsonEncode(settings.toJson()),
      idempotencyKey: 'privacy:${_requireAccountId()}',
    );
    _emitChange(
      const RemoteSyncChange(
        areas: {RemoteSyncChangeArea.contacts, RemoteSyncChangeArea.outbox},
      ),
    );
  }

  RemotePresenceSnapshot updatePresence() {
    final snapshot = RemotePresenceSnapshot(
      accountId: _requireAccountId(),
      visibility: _privacySettings.presenceVisibility,
      lastSeenAt: _privacySettings.lastSeenVisibility == 'NOBODY'
          ? null
          : _clock().millisecondsSinceEpoch,
    );
    db.enqueueOperation(
      'presence_${_clock().microsecondsSinceEpoch}',
      'PRESENCE_UPDATE',
      jsonEncode({
        'account_id': snapshot.accountId,
        'visibility': snapshot.visibility,
        'last_seen_at': snapshot.lastSeenAt,
      }),
      idempotencyKey: 'presence:${snapshot.accountId}',
    );
    _emitChange(
      const RemoteSyncChange(
        areas: {RemoteSyncChangeArea.contacts, RemoteSyncChangeArea.outbox},
      ),
    );
    return snapshot;
  }

  void updateProfile({required String displayName}) {
    final normalized = RemoteAccountValidation.normalizeDisplayName(
      displayName,
    );
    final error = RemoteAccountValidation.displayNameError(normalized);
    if (error != null) throw StateError(error);
    db.enqueueOperation(
      'profile_${_clock().microsecondsSinceEpoch}',
      'PROFILE_UPDATE',
      jsonEncode({'display_name': normalized}),
      idempotencyKey: 'profile:${_requireAccountId()}',
    );
    _emitChange(
      const RemoteSyncChange(
        areas: {RemoteSyncChangeArea.contacts, RemoteSyncChangeArea.outbox},
      ),
    );
  }

  void reportAccount({
    required String subjectAccountId,
    required String category,
    required String reasonCode,
    required String contextHash,
    String? reportId,
  }) {
    final id = reportId ?? 'r_${_clock().microsecondsSinceEpoch}';
    db.enqueueOperation(
      id,
      'SAFETY_REPORT',
      jsonEncode({
        'report_id': id,
        'subject_account_id': subjectAccountId,
        'category': category,
        'reason_code': reasonCode,
        'context_hash': contextHash,
      }),
      idempotencyKey: 'report:$id',
    );
    _emitChange(const RemoteSyncChange(areas: {RemoteSyncChangeArea.outbox}));
  }

  void _enforceContactRequestQuota() {
    final cutoff = _clock()
        .subtract(const Duration(days: 1))
        .millisecondsSinceEpoch;
    _contactRequestTimestamps.removeWhere((timestamp) => timestamp < cutoff);
    if (_contactRequestTimestamps.length >= 20) {
      throw StateError('Remote contact request quota exceeded');
    }
  }

  void _assertCanSendContactRequest(String peerAccountId) {
    final existing = db.getContact(peerAccountId);
    if (existing == null) return;
    switch (existing.status) {
      case 'Accepted':
        throw StateError('Contact already accepted');
      case 'PendingSent':
      case 'PendingReceived':
        throw StateError('Contact request already pending');
      case 'Blocked':
        throw StateError('Blocked contacts cannot be requested');
    }
  }

  void _assertOpenRequest(
    String requestId,
    String peerAccountId,
    String direction,
  ) {
    final request = db.getContactRequest(requestId);
    if (request == null ||
        request.peerAccountId != peerAccountId ||
        request.direction != direction ||
        request.status != 'Pending') {
      throw StateError('Contact request is no longer pending');
    }
  }

  void _validateVisibility(String visibility) {
    const allowed = {'EVERYONE', 'CONTACTS', 'NOBODY'};
    if (!allowed.contains(visibility)) {
      throw StateError('Invalid Remote privacy visibility');
    }
  }
}
