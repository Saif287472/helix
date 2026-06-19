import 'dart:convert';

import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';

abstract class RemoteMessageProtector {
  Future<String> encryptText({
    required String conversationId,
    required String messageId,
    required String plaintext,
    required String recipientDeviceId,
  });

  Future<String> decryptText({
    required String conversationId,
    required String messageId,
    required String ciphertext,
  });
}

class RemoteDecryptedMessage {
  const RemoteDecryptedMessage({
    required this.messageId,
    required this.conversationId,
    required this.senderAccountId,
    required this.senderDeviceId,
    required this.text,
    required this.status,
    required this.timestamp,
    this.reactions = const [],
    this.edited = false,
  });

  final String messageId;
  final String conversationId;
  final String senderAccountId;
  final int senderDeviceId;
  final String text;
  final String status;
  final int timestamp;
  final List<String> reactions;
  final bool edited;
}

class RemotePushNotificationPreview {
  const RemotePushNotificationPreview({
    required this.conversationId,
    required this.title,
    required this.body,
  });

  final String conversationId;
  final String title;
  final String body;
}

class RemotePrivacySettings {
  const RemotePrivacySettings({
    required this.searchDiscoverable,
    required this.presenceVisibility,
    required this.lastSeenVisibility,
  });

  final bool searchDiscoverable;
  final String presenceVisibility;
  final String lastSeenVisibility;

  Map<String, dynamic> toJson() => {
    'search_discoverable': searchDiscoverable,
    'presence_visibility': presenceVisibility,
    'last_seen_visibility': lastSeenVisibility,
  };
}

class RemotePresenceSnapshot {
  const RemotePresenceSnapshot({
    required this.accountId,
    required this.visibility,
    this.lastSeenAt,
  });

  final String accountId;
  final String visibility;
  final int? lastSeenAt;
}

class RemoteMessagingService {
  RemoteMessagingService({
    required this.db,
    required this.syncEngine,
    required this.gateway,
    required this.protector,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final HelixRemoteDatabase db;
  final RemoteSyncEngine syncEngine;
  final SyncGateway gateway;
  final RemoteMessageProtector protector;
  final DateTime Function() _clock;

  String? _accountId;
  int? _deviceId;
  bool _readReceiptsEnabled = true;
  RemotePrivacySettings _privacySettings = const RemotePrivacySettings(
    searchDiscoverable: true,
    presenceVisibility: 'CONTACTS',
    lastSeenVisibility: 'CONTACTS',
  );
  final List<int> _contactRequestTimestamps = [];

  bool get readReceiptsEnabled => _readReceiptsEnabled;
  RemotePrivacySettings get privacySettings => _privacySettings;

  Future<void> setupAccount({
    required RemoteAccount account,
    required RemoteDevice device,
  }) async {
    db.upsertAccount(account);
    db.upsertDevice(account.accountId, device);
    _accountId = account.accountId;
    _deviceId = device.deviceId;
  }

  void setReadReceiptsEnabled(bool enabled) {
    _readReceiptsEnabled = enabled;
  }

  void verifyDevice({required String accountId, required int deviceId}) {
    final device = db
        .getDevices(accountId)
        .where((candidate) => candidate.deviceId == deviceId);
    if (device.isEmpty) {
      throw StateError('Remote device verification failed: unknown device');
    }

    final current = device.first;
    db.upsertDevice(
      accountId,
      RemoteDevice(
        deviceId: current.deviceId,
        deviceName: current.deviceName,
        devicePublicKey: current.devicePublicKey,
        createdAt: current.createdAt,
        status: 'Verified',
      ),
    );
  }

  void addContact({required String peerAccountId, required String nickname}) {
    db.upsertContact(
      RemoteContact(
        peerAccountId: peerAccountId,
        nickname: nickname,
        status: 'Accepted',
      ),
    );
  }

  void sendContactRequest({
    required String peerAccountId,
    String nickname = '',
    String? requestId,
  }) {
    _enforceContactRequestQuota();
    final id = requestId ?? 'cr_${_clock().microsecondsSinceEpoch}';
    db.upsertContact(
      RemoteContact(
        peerAccountId: peerAccountId,
        nickname: nickname,
        status: 'PendingSent',
      ),
    );
    db.enqueueOperation(
      id,
      'CONTACT_REQUEST',
      jsonEncode({
        'request_id': id,
        'peer_account_id': peerAccountId,
        'nickname': nickname,
      }),
      idempotencyKey: 'contact_request:$id',
    );
    _contactRequestTimestamps.add(_clock().millisecondsSinceEpoch);
  }

  void acceptContactRequest({
    required String requestId,
    required String peerAccountId,
    String nickname = '',
  }) {
    db.upsertContact(
      RemoteContact(
        peerAccountId: peerAccountId,
        nickname: nickname,
        status: 'Accepted',
      ),
    );
    db.enqueueOperation(
      'accept_$requestId',
      'CONTACT_REQUEST_ACCEPT',
      jsonEncode({'request_id': requestId}),
      idempotencyKey: 'contact_accept:$requestId',
    );
  }

  void rejectContactRequest({
    required String requestId,
    required String peerAccountId,
  }) {
    db.deleteContact(peerAccountId);
    db.enqueueOperation(
      'reject_$requestId',
      'CONTACT_REQUEST_REJECT',
      jsonEncode({'request_id': requestId}),
      idempotencyKey: 'contact_reject:$requestId',
    );
  }

  void cancelContactRequest({
    required String requestId,
    required String peerAccountId,
  }) {
    db.deleteContact(peerAccountId);
    db.enqueueOperation(
      'cancel_$requestId',
      'CONTACT_REQUEST_CANCEL',
      jsonEncode({'request_id': requestId}),
      idempotencyKey: 'contact_cancel:$requestId',
    );
  }

  void removeContact(String peerAccountId) {
    db.deleteContact(peerAccountId);
    db.enqueueOperation(
      'remove_contact_${peerAccountId}_${_clock().microsecondsSinceEpoch}',
      'CONTACT_REMOVE',
      jsonEncode({'peer_account_id': peerAccountId}),
      idempotencyKey: 'contact_remove:$peerAccountId',
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
      jsonEncode({'peer_account_id': peerAccountId}),
      idempotencyKey: 'contact_block:$peerAccountId',
    );
  }

  void unblockContact(String peerAccountId) {
    db.deleteContact(peerAccountId);
    db.enqueueOperation(
      'unblock_contact_${peerAccountId}_${_clock().microsecondsSinceEpoch}',
      'CONTACT_UNBLOCK',
      jsonEncode({'peer_account_id': peerAccountId}),
      idempotencyKey: 'contact_unblock:$peerAccountId',
    );
  }

  void changeUsername(String username) {
    if (!_isValidUsername(username)) {
      throw StateError('Invalid Remote username');
    }
    db.enqueueOperation(
      'username_${_clock().microsecondsSinceEpoch}',
      'USERNAME_CHANGE',
      jsonEncode({'username': username}),
      idempotencyKey: 'username:${_requireAccountId()}:$username',
    );
  }

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
    return snapshot;
  }

  void updateProfile({required String displayName}) {
    db.enqueueOperation(
      'profile_${_clock().microsecondsSinceEpoch}',
      'PROFILE_UPDATE',
      jsonEncode({'display_name': displayName}),
      idempotencyKey: 'profile:${_requireAccountId()}',
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
  }

  String createDirectConversation({
    required String peerAccountId,
    String? conversationId,
    String? title,
  }) {
    final accountId = _requireAccountId();
    final id =
        conversationId ?? _stableDirectConversationId(accountId, peerAccountId);

    db.upsertConversation(
      RemoteConversation(
        conversationId: id,
        type: 'DIRECT',
        title: title ?? peerAccountId,
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
      }),
      idempotencyKey: 'conversation:$id',
    );

    return id;
  }

  Future<String> sendText({
    required String conversationId,
    required String plaintext,
    required List<String> recipientDeviceIds,
    String? messageId,
  }) async {
    final accountId = _requireAccountId();
    final deviceId = _requireDeviceId();
    final id = messageId ?? 'msg_${_clock().microsecondsSinceEpoch}';

    final localCiphertext = await protector.encryptText(
      conversationId: conversationId,
      messageId: id,
      plaintext: plaintext,
      recipientDeviceId: 'local-history',
    );

    final envelopes = <Map<String, dynamic>>[];
    for (final recipientDeviceId in recipientDeviceIds) {
      envelopes.add({
        'recipient_device_id': recipientDeviceId,
        'ciphertext': await protector.encryptText(
          conversationId: conversationId,
          messageId: id,
          plaintext: plaintext,
          recipientDeviceId: recipientDeviceId,
        ),
      });
    }

    db.saveMessage(
      RemoteMessage(
        messageId: id,
        conversationId: conversationId,
        senderAccountId: accountId,
        senderDeviceId: deviceId,
        ciphertext: localCiphertext,
      ),
      _nextLocalSequence(conversationId),
      _clock().millisecondsSinceEpoch,
      'PENDING',
    );

    db.enqueueOperation(
      'send_message_$id',
      'SEND_MESSAGE',
      jsonEncode({
        'message_id': id,
        'conversation_id': conversationId,
        'envelopes': envelopes,
      }),
      idempotencyKey: 'message:$id',
    );

    return id;
  }

  Future<int> syncInbound() => syncEngine.syncInbound(gateway);

  Future<int> processOutboundQueue() =>
      syncEngine.processOutboundQueue(gateway);

  List<RemoteConversation> conversationList() => db.getConversations();

  Future<List<RemoteDecryptedMessage>> messageHistory(
    String conversationId, {
    int limit = 50,
    int offset = 0,
  }) {
    return _decodeRows(
      db.getMessages(conversationId, limit: limit, offset: offset),
    );
  }

  Future<List<RemoteDecryptedMessage>> searchDecryptedHistory({
    required String conversationId,
    required String query,
  }) async {
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
      }),
      idempotencyKey: 'delivery:$receiptId',
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
      }),
      idempotencyKey: 'read:$receiptId',
    );
    return true;
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
    final revisionId = 'edit_${messageId}_${_clock().microsecondsSinceEpoch}';
    final ciphertext = await protector.encryptText(
      conversationId: conversationId,
      messageId: messageId,
      plaintext: plaintext,
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
      }),
      idempotencyKey: 'edit:$revisionId',
    );
  }

  void addReaction({required String messageId, required String reaction}) {
    final revisionId =
        'reaction_${messageId}_${_clock().microsecondsSinceEpoch}';
    db.saveMessageRevision(
      revisionId: revisionId,
      messageId: messageId,
      type: 'REACTION',
      authorId: _requireAccountId(),
      payload: jsonEncode({'reaction': reaction}),
      timestamp: _clock().millisecondsSinceEpoch,
    );
    db.enqueueOperation(
      revisionId,
      'REACTION',
      jsonEncode({
        'message_id': messageId,
        'revision_id': revisionId,
        'reaction': reaction,
      }),
      idempotencyKey: 'reaction:$revisionId',
    );
  }

  void deleteForSelf(String messageId) {
    db.saveTombstone(messageId, 'MESSAGE');
    db.deleteMessage(messageId);
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

    db.saveTombstone(messageId, 'MESSAGE');
    db.deleteMessage(messageId);
    db.enqueueOperation(
      'delete_$messageId',
      'DELETE_MESSAGE',
      jsonEncode({'message_id': messageId, 'conversation_id': conversationId}),
      idempotencyKey: 'delete:$messageId',
    );
  }

  RemotePushNotificationPreview notificationPreview(String conversationId) {
    return RemotePushNotificationPreview(
      conversationId: conversationId,
      title: 'Helix Remote',
      body: 'New encrypted message',
    );
  }

  Future<List<RemoteDecryptedMessage>> _decodeRows(
    List<Map<String, dynamic>> rows,
  ) async {
    final decoded = <RemoteDecryptedMessage>[];
    for (final row in rows) {
      final messageId = row['message_id'] as String;
      if (db.isTombstoned(messageId, 'MESSAGE')) {
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

      decoded.add(
        RemoteDecryptedMessage(
          messageId: messageId,
          conversationId: conversationId,
          senderAccountId: row['sender_account_id'] as String,
          senderDeviceId: row['sender_device_id'] as int,
          text: await protector.decryptText(
            conversationId: conversationId,
            messageId: messageId,
            ciphertext: ciphertext,
          ),
          status: row['status'] as String,
          timestamp: row['timestamp'] as int,
          reactions: reactions,
          edited: edited,
        ),
      );
    }
    return decoded;
  }

  int _nextLocalSequence(String conversationId) {
    final rows = db.getMessages(conversationId, limit: 1);
    if (rows.isEmpty) {
      return 1;
    }
    return (rows.first['server_sequence'] as int) + 1;
  }

  String _requireAccountId() {
    final accountId = _accountId;
    if (accountId == null) {
      throw StateError('Remote messaging account is not set up');
    }
    return accountId;
  }

  int _requireDeviceId() {
    final deviceId = _deviceId;
    if (deviceId == null) {
      throw StateError('Remote messaging device is not set up');
    }
    return deviceId;
  }

  String _stableDirectConversationId(String a, String b) {
    final members = [a, b]..sort();
    return 'dm_${base64UrlEncode(utf8.encode(members.join('|'))).replaceAll('=', '')}';
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

  bool _isValidUsername(String username) {
    if (username.length < 3 || username.length > 30) return false;
    if (username.startsWith('helix_')) return false;
    return RegExp(r'^[a-z0-9_]+$').hasMatch(username);
  }

  void _validateVisibility(String visibility) {
    const allowed = {'EVERYONE', 'CONTACTS', 'NOBODY'};
    if (!allowed.contains(visibility)) {
      throw StateError('Invalid Remote privacy visibility');
    }
  }
}
