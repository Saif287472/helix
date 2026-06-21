import 'dart:async';
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
    this.attachment,
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
  final RemoteAttachmentContent? attachment;
}

class RemoteAttachmentContent {
  const RemoteAttachmentContent({
    required this.fileId,
    required this.filename,
    required this.fileSize,
    required this.fileHash,
    required this.mimeType,
    required this.keyDeliverySecret,
    this.thumbnailFileId,
    this.thumbnailFileSize,
    this.thumbnailFileHash,
    this.localStatus,
    this.localPath,
  });

  static const messageType = 'helix.remote.attachment.v1';

  final String fileId;
  final String filename;
  final int fileSize;
  final String fileHash;
  final String mimeType;
  final String keyDeliverySecret;
  final String? thumbnailFileId;
  final int? thumbnailFileSize;
  final String? thumbnailFileHash;
  final String? localStatus;
  final String? localPath;

  String get displayText => 'Attachment: $filename';

  RemoteAttachmentManifest get manifest => RemoteAttachmentManifest(
    fileId: fileId,
    fileSize: fileSize,
    fileHash: fileHash,
    mimeType: mimeType,
    thumbnailFileId: thumbnailFileId,
    thumbnailFileSize: thumbnailFileSize,
    thumbnailFileHash: thumbnailFileHash,
  );

  Map<String, dynamic> toMessageJson() => {
    'type': messageType,
    'version': 1,
    'filename': filename,
    'manifest': manifest.toJson(),
    'key_delivery': {
      'scheme': 'x3dh-message-envelope',
      'secret': keyDeliverySecret,
    },
  };

  RemoteAttachmentContent withLocalState({
    required String? status,
    required String? path,
  }) {
    return RemoteAttachmentContent(
      fileId: fileId,
      filename: filename,
      fileSize: fileSize,
      fileHash: fileHash,
      mimeType: mimeType,
      keyDeliverySecret: keyDeliverySecret,
      thumbnailFileId: thumbnailFileId,
      thumbnailFileSize: thumbnailFileSize,
      thumbnailFileHash: thumbnailFileHash,
      localStatus: status,
      localPath: path,
    );
  }

  static RemoteAttachmentContent? tryParse(String plaintext) {
    try {
      final decoded = jsonDecode(plaintext);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['type'] != messageType) return null;
      final manifest = RemoteAttachmentManifest.fromJson(
        decoded['manifest'] as Map<String, dynamic>,
      );
      final keyDelivery = decoded['key_delivery'] as Map<String, dynamic>;
      return RemoteAttachmentContent(
        fileId: manifest.fileId,
        filename: decoded['filename'] as String,
        fileSize: manifest.fileSize,
        fileHash: manifest.fileHash,
        mimeType: manifest.mimeType,
        keyDeliverySecret: keyDelivery['secret'] as String,
        thumbnailFileId: manifest.thumbnailFileId,
        thumbnailFileSize: manifest.thumbnailFileSize,
        thumbnailFileHash: manifest.thumbnailFileHash,
      );
    } catch (_) {
      return null;
    }
  }
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

class RemoteOutboxSummary {
  const RemoteOutboxSummary({
    required this.queuedCount,
    required this.retryScheduledCount,
    required this.failedCount,
    this.nextRetryAt,
  });

  final int queuedCount;
  final int retryScheduledCount;
  final int failedCount;
  final DateTime? nextRetryAt;

  bool get hasVisibleWork =>
      queuedCount > 0 || retryScheduledCount > 0 || failedCount > 0;
}

class RemoteMessagingService {
  RemoteMessagingService({
    required this.db,
    required this.syncEngine,
    required this.gateway,
    required this.protector,
    required this.restClient,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _syncChangeSub = syncEngine.changes.listen(_emitChange);
  }

  final HelixRemoteDatabase db;
  final RemoteSyncEngine syncEngine;
  final SyncGateway gateway;
  final RemoteMessageProtector protector;
  final HelixRemoteRestClient restClient;
  final DateTime Function() _clock;
  late final StreamSubscription<RemoteSyncChange> _syncChangeSub;
  late final StreamController<RemoteSyncChange> _changeController =
      StreamController<RemoteSyncChange>.broadcast(
        sync: true,
        onListen: () => _changeListenerCount++,
        onCancel: () => _changeListenerCount--,
      );
  int _changeListenerCount = 0;

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
  Stream<RemoteSyncChange> get changes => _changeController.stream;
  int get debugChangeListenerCount => _changeListenerCount;

  Future<void> setupAccount({
    required RemoteAccount account,
    required RemoteDevice device,
  }) async {
    db.upsertAccount(account);
    db.upsertDevice(account.accountId, device);
    _accountId = account.accountId;
    _deviceId = device.deviceId;
    _emitChange(const RemoteSyncChange(areas: {RemoteSyncChangeArea.devices}));
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
    _emitChange(const RemoteSyncChange(areas: {RemoteSyncChangeArea.devices}));
  }

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
    db.enqueueOperation(
      'profile_${_clock().microsecondsSinceEpoch}',
      'PROFILE_UPDATE',
      jsonEncode({'display_name': displayName}),
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
      db.saveMessage(
        localMessage,
        sequence,
        timestamp,
        'SECURE_SESSION_UNAVAILABLE',
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
  }) {
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
    );
    return sendText(
      conversationId: conversationId,
      plaintext: jsonEncode(content.toMessageJson()),
      recipientDeviceIds: recipientDeviceIds,
      messageId: messageId,
    );
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

    // Build device_id -> bundle map and persist discovered peer devices so
    // future sends do not require pre-seeded local device metadata.
    final deviceBundleMap = <String, Map<String, dynamic>>{};
    for (var i = 0; i < bundleResults.length; i++) {
      final accountId = otherMembers[i];
      final result = bundleResults[i];
      final devices = result['devices'] as List<dynamic>? ?? [];
      final firstDevice = devices.isEmpty
          ? null
          : devices.first as Map<String, dynamic>;
      db.upsertAccount(
        RemoteAccount(
          accountId: accountId,
          username: accountId,
          identityPublicKey:
              result['account_identity_key'] as String? ??
              firstDevice?['identity_key'] as String? ??
              '',
          createdAt: _clock(),
        ),
      );
      for (final device in devices) {
        final d = device as Map<String, dynamic>;
        final deviceId = d['device_id'] as String;
        deviceBundleMap[deviceId] = d;
        db.upsertDevice(
          accountId,
          RemoteDevice(
            deviceId: deviceId,
            deviceName: d['device_name'] as String? ?? deviceId,
            deviceSigningPublicKey: d['identity_key'] as String? ?? '',
            deviceAgreementPublicKey: d['device_key'] as String? ?? '',
            createdAt: _clock(),
          ),
        );
      }
    }

    final targetDeviceIds = recipientDeviceIds.isEmpty
        ? deviceBundleMap.keys.toList()
        : recipientDeviceIds;
    if (otherMembers.isNotEmpty && targetDeviceIds.isEmpty) {
      throw const SecureSessionUnavailableException(
        'no active recipient devices found',
      );
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

    for (final recipientDeviceId in targetDeviceIds) {
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

  RemoteOutboxSummary outboxSummary() {
    final now = DateTime.now().millisecondsSinceEpoch;
    var queued = 0;
    var retryScheduled = 0;
    var failed = 0;
    int? nextRetryAt;
    for (final op in db.getOutboxOperations()) {
      final status = op['status'] as String;
      final retries = op['retries'] as int;
      final nextAttempt = op['next_attempt_at'] as int;
      if (status == 'FAILED') {
        failed++;
        continue;
      }
      if (status == 'PENDING' && nextAttempt > now && retries > 0) {
        retryScheduled++;
        nextRetryAt = nextRetryAt == null || nextAttempt < nextRetryAt
            ? nextAttempt
            : nextRetryAt;
      } else {
        queued++;
      }
    }
    return RemoteOutboxSummary(
      queuedCount: queued,
      retryScheduledCount: retryScheduled,
      failedCount: failed,
      nextRetryAt: nextRetryAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(nextRetryAt),
    );
  }

  Future<int> retryFailedOutbox() async {
    var retried = 0;
    for (final op in db.getOutboxOperations()) {
      if (op['status'] == 'FAILED') {
        db.retryOperationNow(op['op_id'] as String);
        retried++;
      }
    }
    if (retried > 0) {
      _emitChange(const RemoteSyncChange(areas: {RemoteSyncChangeArea.outbox}));
      await processOutboundQueue();
    }
    return retried;
  }

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

      final plaintext = await protector.decryptText(
        conversationId: conversationId,
        messageId: messageId,
        ciphertext: ciphertext,
      );
      final parsedAttachment = RemoteAttachmentContent.tryParse(plaintext);
      final localAttachment = parsedAttachment == null
          ? null
          : db.getAttachment(parsedAttachment.fileId);
      final attachment = parsedAttachment?.withLocalState(
        status: localAttachment?['status'] as String?,
        path: localAttachment?['local_path'] as String?,
      );

      decoded.add(
        RemoteDecryptedMessage(
          messageId: messageId,
          conversationId: conversationId,
          senderAccountId: row['sender_account_id'] as String,
          senderDeviceId: row['sender_device_id'] as String,
          text: attachment?.displayText ?? plaintext,
          status: row['status'] as String,
          timestamp: row['timestamp'] as int,
          reactions: reactions,
          edited: edited,
          attachment: attachment,
        ),
      );
    }
    return decoded;
  }

  void _emitChange(RemoteSyncChange change) {
    if (!_changeController.isClosed) {
      _changeController.add(change);
    }
  }

  Future<void> dispose() async {
    await _syncChangeSub.cancel();
    await _changeController.close();
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
