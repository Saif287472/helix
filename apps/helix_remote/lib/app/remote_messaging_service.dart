import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_crypto/helix_remote_crypto.dart';
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

class SecureSessionUnavailableException implements Exception {
  const SecureSessionUnavailableException(this.reason);

  final String reason;

  @override
  String toString() => 'SecureSessionUnavailableException: $reason';
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
  final String senderDeviceId;
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
    required this.restClient,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final HelixRemoteDatabase db;
  final RemoteSyncEngine syncEngine;
  final SyncGateway gateway;
  final RemoteMessageProtector protector;
  final HelixRemoteRestClient restClient;
  final DateTime Function() _clock;

  String? _accountId;
  String? _deviceId;

  Uint8List? _devicePrivateKey;
  Uint8List? _devicePublicKey;

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

  void setCryptoKeys({
    required Uint8List devicePrivateKey,
    required Uint8List devicePublicKey,
  }) {
    _devicePrivateKey = devicePrivateKey;
    _devicePublicKey = devicePublicKey;
  }

  void setReadReceiptsEnabled(bool enabled) {
    _readReceiptsEnabled = enabled;
  }

  void verifyDevice({required String accountId, required String deviceId}) {
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
        deviceSigningPublicKey: current.deviceSigningPublicKey,
        deviceAgreementPublicKey: current.deviceAgreementPublicKey,
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
        'protocol_version': 1,
        'sender_device_id': _deviceId,
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
      jsonEncode({
        'request_id': requestId,
        'protocol_version': 1,
        'sender_device_id': _deviceId,
      }),
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
      jsonEncode({
        'request_id': requestId,
        'protocol_version': 1,
        'sender_device_id': _deviceId,
      }),
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
      jsonEncode({
        'request_id': requestId,
        'protocol_version': 1,
        'sender_device_id': _deviceId,
      }),
      idempotencyKey: 'contact_cancel:$requestId',
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
    final deviceId = _requireDeviceId();
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
        'protocol_version': 1,
        'sender_device_id': deviceId,
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
    final hasRemoteMember = conversationMemberIds(
      conversationId,
    ).any((memberId) => memberId != accountId);
    if (hasRemoteMember && uniqueRecipientDeviceIds.isEmpty) {
      db.saveMessage(
        localMessage,
        sequence,
        timestamp,
        'SECURE_SESSION_UNAVAILABLE',
      );
      return id;
    }

    try {
      final envelopes = await _buildX3dhEnvelopes(
        conversationId: conversationId,
        messageId: id,
        plaintext: plaintext,
        recipientDeviceIds: uniqueRecipientDeviceIds,
        senderAccountId: accountId,
        senderDeviceId: deviceId,
      );

      db.saveMessageAndOperation(
        message: localMessage,
        sequence: sequence,
        timestamp: timestamp,
        status: 'PENDING',
        opId: 'send_message_$id',
        type: 'SEND_MESSAGE',
        payload: jsonEncode({
          'message_id': id,
          'conversation_id': conversationId,
          'sender_account_id': accountId,
          'sender_device_id': deviceId,
          'protocol_version': 1,
          'envelopes': envelopes,
        }),
        idempotencyKey: 'message:$id',
      );
    } on SecureSessionUnavailableException {
      db.saveMessage(
        localMessage,
        sequence,
        timestamp,
        'SECURE_SESSION_UNAVAILABLE',
      );
    }

    return id;
  }

  Future<List<Map<String, dynamic>>> _buildX3dhEnvelopes({
    required String conversationId,
    required String messageId,
    required String plaintext,
    required List<String> recipientDeviceIds,
    required String senderAccountId,
    required String senderDeviceId,
  }) async {
    final envelopes = <Map<String, dynamic>>[];
    final x3dh = X3dhSessionInitiator();
    final x25519 = crypto.X25519();

    final devicePriv = _devicePrivateKey;
    final devicePub = _devicePublicKey;
    if (devicePriv == null || devicePub == null) {
      throw const SecureSessionUnavailableException(
        'local device agreement key is unavailable',
      );
    }

    // Fetch prekey bundles for all unique member accounts
    final allMembers = conversationMemberIds(conversationId);
    final otherMembers = allMembers
        .where((m) => m != senderAccountId)
        .toSet()
        .toList();

    final bundleFutures = otherMembers.map(
      (m) => restClient.getPreKeyBundle(accountId: m),
    );
    final bundleResults = await Future.wait(bundleFutures, eagerError: false);

    // Build device_id -> bundle map
    final deviceBundleMap = <String, Map<String, dynamic>>{};
    for (final result in bundleResults) {
      final devices = result['devices'] as List<dynamic>? ?? [];
      for (final device in devices) {
        final d = device as Map<String, dynamic>;
        deviceBundleMap[d['device_id'] as String] = d;
      }
    }

    // Reconstruct Alice's identity key pair from stored bytes
    final aliceIdentityKey = crypto.SimpleKeyPairData(
      devicePriv,
      publicKey: crypto.SimplePublicKey(
        devicePub,
        type: crypto.KeyPairType.x25519,
      ),
      type: crypto.KeyPairType.x25519,
    );

    for (final recipientDeviceId in recipientDeviceIds) {
      final bundle = deviceBundleMap[recipientDeviceId];
      if (bundle == null) {
        throw SecureSessionUnavailableException(
          'missing prekey bundle for $recipientDeviceId',
        );
      }

      final ephemeralKey = await x25519.newKeyPair();
      final ephemeralPubKey = await ephemeralKey.extractPublicKey();

      final bobIdentityPubKey = crypto.SimplePublicKey(
        base64Decode(bundle['device_key'] as String),
        type: crypto.KeyPairType.x25519,
      );
      final bobSigningPubKey = crypto.SimplePublicKey(
        base64Decode(bundle['identity_key'] as String),
        type: crypto.KeyPairType.ed25519,
      );
      final spk = bundle['signed_prekey'] as Map<String, dynamic>;
      final bobSignedPrekey = crypto.SimplePublicKey(
        base64Decode(spk['public_key'] as String),
        type: crypto.KeyPairType.x25519,
      );
      final bobSig = Uint8List.fromList(
        base64Decode(spk['signature'] as String),
      );

      crypto.SimplePublicKey? bobOpk;
      int? usedOpkId;
      final otk = bundle['one_time_prekey'] as Map<String, dynamic>?;
      if (otk != null) {
        bobOpk = crypto.SimplePublicKey(
          base64Decode(otk['public_key'] as String),
          type: crypto.KeyPairType.x25519,
        );
        usedOpkId = otk['key_id'] as int;
      }

      crypto.SecretKey masterSecret;
      try {
        masterSecret = await x3dh.initiateSession(
          aliceIdentityKey: aliceIdentityKey,
          aliceEphemeralKey: ephemeralKey,
          bobIdentityPublicKey: bobIdentityPubKey,
          bobIdentitySigningPublicKey: bobSigningPubKey,
          bobSignedPrekey: bobSignedPrekey,
          bobSignedPrekeySignature: bobSig,
          bobOneTimePrekey: bobOpk,
          protocolVersion: '1',
          conversationId: conversationId,
          senderDeviceId: senderDeviceId,
          recipientDeviceId: recipientDeviceId,
        );
      } catch (_) {
        throw SecureSessionUnavailableException(
          'signed prekey verification failed for $recipientDeviceId',
        );
      }

      final masterKeyBytes = await masterSecret.extractBytes();
      final aes = crypto.AesGcm.with256bits();
      final aad = _messageAad(
        messageId: messageId,
        conversationId: conversationId,
        senderDeviceId: senderDeviceId,
        recipientDeviceId: recipientDeviceId,
        protocolVersion: 1,
        contentType: 'text',
        counter: 0,
      );
      final nonce = Uint8List.fromList(
        List<int>.generate(12, (_) => math.Random.secure().nextInt(256)),
      );
      final encrypted = await aes.encrypt(
        utf8.encode(plaintext),
        secretKey: crypto.SecretKey(masterKeyBytes),
        nonce: nonce,
        aad: aad,
      );

      final ciphertextBytes = BytesBuilder()
        ..add(nonce)
        ..add(encrypted.cipherText)
        ..add(encrypted.mac.bytes);
      final innerCiphertext = base64Url.encode(ciphertextBytes.toBytes());

      final aliceIdentityPubKey = await aliceIdentityKey.extractPublicKey();
      final x3dhHeader = <String, dynamic>{
        'protocol_version': 1,
        'identity_key': base64Url.encode(aliceIdentityPubKey.bytes),
        'ephemeral_key': base64Url.encode(ephemeralPubKey.bytes),
        'used_one_time_prekey_id': usedOpkId,
        'aad': {
          'message_id': messageId,
          'conversation_id': conversationId,
          'sender_device_id': senderDeviceId,
          'recipient_device_id': recipientDeviceId,
          'content_type': 'text',
          'counter': 0,
        },
      };

      // P4-03: Pack ciphertext + X3DH header into a single opaque blob so the
      // backend can relay both without schema changes. The recipient unpacks
      // this blob to perform X3DH receive and AES-GCM decryption.
      final packedEnvelope = base64Url.encode(
        utf8.encode(
          jsonEncode({'v': 1, 'ct': innerCiphertext, 'h': x3dhHeader}),
        ),
      );

      envelopes.add({
        'recipient_device_id': recipientDeviceId,
        'ciphertext': packedEnvelope,
      });
    }

    return envelopes;
  }

  Future<int> syncInbound() => syncEngine.syncInbound(gateway);

  Future<int> processOutboundQueue() =>
      syncEngine.processOutboundQueue(gateway);

  String? get currentAccountId => _accountId;

  List<RemoteConversation> conversationList() => db.getConversations();

  List<String> conversationMemberIds(String conversationId) =>
      db.getConversationMembers(conversationId);

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
        'protocol_version': 1,
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
        'protocol_version': 1,
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
        'protocol_version': 1,
        'sender_device_id': _requireDeviceId(),
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
      jsonEncode({
        'message_id': messageId,
        'conversation_id': conversationId,
        'protocol_version': 1,
        'sender_device_id': _requireDeviceId(),
      }),
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
          senderDeviceId: row['sender_device_id'] as String,
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

  static List<int> _messageAad({
    required String messageId,
    required String conversationId,
    required String senderDeviceId,
    required String recipientDeviceId,
    required int protocolVersion,
    required String contentType,
    required int counter,
  }) {
    return utf8.encode(
      jsonEncode({
        'domain': 'helix.remote.message.v1',
        'message_id': messageId,
        'conversation_id': conversationId,
        'sender_device_id': senderDeviceId,
        'recipient_device_id': recipientDeviceId,
        'protocol_version': protocolVersion,
        'content_type': contentType,
        'counter': counter,
      }),
    );
  }

  String _requireAccountId() {
    final accountId = _accountId;
    if (accountId == null) {
      throw StateError('Remote messaging account is not set up');
    }
    return accountId;
  }

  String _requireDeviceId() {
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
