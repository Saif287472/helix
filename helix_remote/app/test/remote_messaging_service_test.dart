import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote_api/api/realtime_envelope.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:helix_remote_sync/helix_remote_sync.dart';
import 'package:path/path.dart' as p;

class _FakeProtector implements RemoteMessageProtector {
  @override
  Future<String> encryptText({
    required String conversationId,
    required String messageId,
    required String plaintext,
    required String recipientDeviceId,
  }) async {
    final envelope = jsonEncode({
      'conversation_id': conversationId,
      'message_id': messageId,
      'recipient_device_id': recipientDeviceId,
      'body': plaintext,
    });
    return 'cipher:${base64UrlEncode(utf8.encode(envelope))}';
  }

  @override
  Future<String> decryptText({
    required String conversationId,
    required String messageId,
    required String ciphertext,
  }) async {
    if (!ciphertext.startsWith('cipher:')) {
      throw FormatException('Unexpected ciphertext envelope');
    }
    final envelope =
        jsonDecode(
              utf8.decode(
                base64Url.decode(ciphertext.substring('cipher:'.length)),
              ),
            )
            as Map<String, dynamic>;
    expect(envelope['conversation_id'], conversationId);
    expect(envelope['message_id'], messageId);
    return envelope['body'] as String;
  }
}

class _FakeRestClient implements HelixRemoteRestClient {
  _FakeRestClient({Map<String, Map<String, dynamic>>? bundles})
    : bundles = bundles ?? {};

  final Map<String, Map<String, dynamic>> bundles;

  @override
  set accessToken(String? token) {}
  @override
  Future<void> close() async {}
  @override
  Future<Map<String, dynamic>> registerAccount({
    required String accountId,
    required String phoneHash,
    required String otpCode,
    required String inviteCode,
    required String displayName,
    required String accountIdentityPublicKey,
    required String deviceId,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
    required String accountRegistrationSignature,
    required String deviceRegistrationSignature,
    required String deviceName,
    String phoneLast4 = '',
  }) async => {};
  @override
  Future<Map<String, dynamic>> fetchDiscoverySalt() async => {};
  @override
  Future<Map<String, dynamic>> requestPhoneOtp({
    required String phoneHash,
    required String phoneNumber,
  }) async => {};
  @override
  Future<Map<String, dynamic>> lookupInvite({
    required String inviteCode,
  }) async => {};
  @override
  Future<Map<String, dynamic>> autoIssueGlobalInvite() async => {};

  @override
  Future<Map<String, dynamic>> getServerInfo() async => {'server_name': ''};

  @override
  Future<Map<String, dynamic>> matchPhoneHashes(
    List<String> phoneHashes, {
    bool fullSync = false,
  }) async => {};
  @override
  Future<Map<String, dynamic>> getChallenge({
    required String accountId,
    required String deviceId,
  }) async => {};
  @override
  Future<Map<String, dynamic>> loginDevice({
    required String accountId,
    required String deviceId,
    required String signature,
  }) async => {};
  @override
  Future<Map<String, dynamic>> refreshToken({
    required String refreshToken,
  }) async => {};
  @override
  Future<List<RemoteDevice>> listDevices() async => [];

  @override
  Future<Map<String, dynamic>> requestNewDeviceLink({
    required String accountId,
    required String deviceId,
    required String deviceName,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
  }) async => {};

  @override
  Future<Map<String, dynamic>> approveDeviceLink({
    required String linkId,
    required String verificationCode,
  }) async => {};

  @override
  Future<Map<String, dynamic>> rejectDeviceLink({
    required String linkId,
    required String verificationCode,
  }) async => {};

  @override
  Future<Map<String, dynamic>> completeNewDeviceLink({
    required String linkId,
    required String signature,
  }) async => {};

  @override
  Future<void> renameDevice({
    required String deviceId,
    required String deviceName,
  }) async {}
  @override
  Future<void> revokeDevice(String deviceId) async {}
  @override
  Future<void> reportLostDevice(String deviceId) async {}
  @override
  Future<List<Map<String, dynamic>>> getDeviceSecurityHistory(
    String deviceId,
  ) async => [];
  @override
  Future<void> uploadPreKeys({
    required int signedPrekeyId,
    required String signedPrekey,
    required String signedPrekeySignature,
    required List<Map<String, dynamic>> oneTimePrekeys,
  }) async {}
  @override
  Future<Map<String, dynamic>> getPreKeyBundle({
    required String accountId,
  }) async => bundles[accountId] ?? {'devices': <Map<String, dynamic>>[]};
  @override
  Future<Map<String, dynamic>> sendContactRequest({
    required String peerAccountId,
  }) async => {};
  @override
  Future<void> acceptContactRequest(String requestId) async {}
  @override
  Future<Map<String, dynamic>> requestAttachmentUpload({
    required int fileSize,
    required String fileHash,
  }) async => {};
  @override
  Future<Map<String, dynamic>> requestAttachmentDownload(String fileId) async =>
      {};
  @override
  Future<void> requestAccountDeletion({required String confirmation}) async {}
  @override
  Future<Map<String, dynamic>> exportData() async => {};
  @override
  Future<Map<String, dynamic>> uploadBackup({
    required String backupId,
    required String backupData,
    required int version,
    required String kdf,
    required String salt,
    String backupKeyHint = '',
    int deletionWatermark = 0,
  }) async => {};
  @override
  Future<Map<String, dynamic>> downloadBackup() async => {};

  @override
  Future<Map<String, dynamic>> requestBackupMediaUpload({
    required String objectId,
    required int byteSize,
    required String sha256,
  }) async => {};

  @override
  Future<Map<String, dynamic>> getBackupMediaStatus(String objectId) async =>
      {};

  @override
  Future<List<Map<String, dynamic>>> searchContacts(String query) async =>
      const [];
  @override
  Future<Map<String, dynamic>> getMyProfile() async => {};
  @override
  Future<Map<String, dynamic>> updateDisplayName(String displayName) async =>
      {};
  @override
  Future<Map<String, dynamic>> sendCallSignal({
    String? targetAccountId,
    String? targetDeviceId,
    required Map<String, dynamic> payload,
    String? requestId,
  }) async => {};
  @override
  Future<Map<String, dynamic>> getPendingCalls() async => {'calls': []};
  @override
  Future<Map<String, dynamic>> acceptPendingCall(String callId) async => {};
  @override
  Future<Map<String, dynamic>> declinePendingCall(String callId) async => {};
  @override
  Future<Map<String, dynamic>> cancelPendingCall(String callId) async => {};
  @override
  Future<Map<String, dynamic>> getTurnCredentials() async => {};
}

class _FakeGateway implements SyncGateway {
  final inbound = <RemoteRealtimeEnvelope>[];
  final sent = <Map<String, dynamic>>[];
  bool failSends = false;

  @override
  Future<List<RemoteRealtimeEnvelope>> fetchInboundEvents({
    required int sinceSequence,
  }) async {
    return inbound
        .where((event) => (event.serverSequence ?? 0) > sinceSequence)
        .toList();
  }

  @override
  Future<void> sendOutboundOperation({
    required String opId,
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    if (failSends) {
      throw Exception('offline');
    }
    sent.add({'op_id': opId, 'type': type, 'payload': payload});
  }
}

void main() {
  setUpAll(() {
    if (Platform.isWindows) {
      var dir = Directory.current;
      String? foundPath;
      for (var i = 0; i < 5; i++) {
        final possiblePath = p.join(
          dir.path,
          '.dart_tool',
          'lib',
          'sqlite3.dll',
        );
        if (File(possiblePath).existsSync()) {
          foundPath = possiblePath;
          break;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
      if (foundPath != null) {
        DynamicLibrary.open(foundPath);
      }
    }
  });

  late HelixRemoteDatabase db;
  late _FakeGateway gateway;
  late RemoteMessagingService service;
  var tick = 0;

  DateTime clock() => DateTime.fromMillisecondsSinceEpoch(++tick * 1000);

  setUp(() async {
    tick = 0;
    db = HelixRemoteDatabase(File(':memory:'));
    db.initialize();
    gateway = _FakeGateway();
    service = RemoteMessagingService(
      db: db,
      syncEngine: RemoteSyncEngine(db),
      gateway: gateway,
      protector: _FakeProtector(),
      restClient: _FakeRestClient(),
      clock: clock,
    );

    await service.setupAccount(
      account: RemoteAccount(
        accountId: 'alice',
        identityPublicKey: 'alice_identity_key',
        createdAt: clock(),
      ),
      device: RemoteDevice(
        deviceId: 'alice_device_1',
        deviceName: 'Alice phone',
        deviceSigningPublicKey: 'alice_device_signing_key',
        deviceAgreementPublicKey: 'alice_device_agreement_key',
        createdAt: clock(),
      ),
    );
    service.addContact(peerAccountId: 'bob', nickname: 'Bob');
  });

  tearDown(() {
    db.close();
  });

  test(
    'Phase 12 direct send stores local ciphertext and sends no plaintext',
    () async {
      db.upsertDevice(
        'alice',
        RemoteDevice(
          deviceId: 'alice_device_2',
          deviceName: 'Alice laptop',
          deviceSigningPublicKey: 'alice_laptop_signing_key',
          deviceAgreementPublicKey: 'alice_laptop_agreement_key',
          createdAt: clock(),
        ),
      );
      service.verifyDevice(accountId: 'alice', deviceId: 'alice_device_2');
      expect(db.getDevices('alice').last.status, 'Verified');

      service.addContact(peerAccountId: 'bob', nickname: 'Bob');
      final conversationId = service.createDirectConversation(
        peerAccountId: 'bob',
        conversationId: 'dm_alice_bob',
        title: 'Bob',
      );

      final messageId = await service.sendText(
        conversationId: conversationId,
        messageId: 'msg_1',
        plaintext: 'the train leaves at nine',
        recipientDeviceIds: ['bob_device_1'],
      );

      final stored = db.getMessageById(messageId);
      expect(stored, isNotNull);
      expect(stored!['ciphertext_blob'], isNot(contains('train leaves')));
      expect(stored['status'], equals('SECURE_SESSION_UNAVAILABLE'));

      final pendingPayload = jsonEncode(db.getPendingOperations());
      expect(pendingPayload, isNot(contains('train leaves')));
      expect(pendingPayload, isNot(contains('SEND_MESSAGE')));

      final processed = await service.processOutboundQueue();
      expect(processed, 1);
      expect(jsonEncode(gateway.sent), isNot(contains('train leaves')));
      expect(gateway.sent.any((op) => op['type'] == 'SEND_MESSAGE'), isFalse);

      final history = await service.messageHistory(conversationId);
      expect(history.single.text, 'the train leaves at nine');
      expect(history.single.status, 'SECURE_SESSION_UNAVAILABLE');

      final matches = await service.searchDecryptedHistory(
        conversationId: conversationId,
        query: 'train',
      );
      expect(matches.single.messageId, 'msg_1');
    },
  );

  test('reply send stores clean body text with reply metadata', () async {
    final conversationId = service.createDirectConversation(
      peerAccountId: 'bob',
      conversationId: 'dm_reply_metadata',
      title: 'Bob',
    );

    final messageId = await service.sendText(
      conversationId: conversationId,
      messageId: 'msg_reply',
      plaintext: 'this is the reply body',
      recipientDeviceIds: const [],
      replyTo: const RemoteReplyReference(
        messageId: 'msg_original',
        senderAccountId: 'bob',
        snippet: 'original body',
      ),
    );

    final stored = db.getMessageById(messageId);
    expect(stored, isNotNull);
    expect(
      stored!['ciphertext_blob'],
      isNot(contains('this is the reply body')),
    );

    final history = await service.messageHistory(conversationId);
    expect(history.single.text, 'this is the reply body');
    expect(history.single.replyTo, isNotNull);
    expect(history.single.replyTo!.messageId, 'msg_original');
    expect(history.single.replyTo!.senderAccountId, 'bob');
    expect(history.single.replyTo!.snippet, 'original body');
  });

  test(
    'F0 content envelope parser accepts versioned and legacy payloads',
    () async {
      final encoded = const RemoteTextContent(
        text: 'wrapped body',
        replyTo: RemoteReplyReference(
          messageId: 'msg_parent',
          senderAccountId: 'bob',
          snippet: 'parent',
        ),
      ).toPlaintext();

      final decodedEnvelope = (await RemoteMessageContentEnvelope.tryDecode(
        encoded,
      ))!;
      expect(decodedEnvelope.contentType, RemoteCapability.contentTextV1);

      final parsed = await RemoteTextContent.parse(encoded);
      expect(parsed.text, 'wrapped body');
      expect(parsed.replyTo!.messageId, 'msg_parent');

      final legacyReply = jsonEncode({
        'type': 'helix.remote.text.v1',
        'version': 1,
        'text': 'legacy reply',
        'reply_to': {
          'message_id': 'legacy_parent',
          'sender_account_id': 'carol',
          'snippet': 'old',
        },
      });
      expect(
        (await RemoteTextContent.parse(legacyReply)).replyTo!.messageId,
        'legacy_parent',
      );

      final legacyAttachment = jsonEncode({
        'type': RemoteAttachmentContent.legacyMessageType,
        'version': 1,
        'filename': 'legacy.pdf',
        'manifest': const RemoteAttachmentManifest(
          fileId: 'file_legacy',
          fileSize: 7,
          fileHash: 'file_legacy',
          mimeType: 'application/pdf',
        ).toJson(),
        'key_delivery': {
          'scheme': 'x3dh-message-envelope',
          'secret': 'legacy_secret',
        },
      });
      expect(
        (await RemoteAttachmentContent.tryParse(legacyAttachment))!.filename,
        'legacy.pdf',
      );
    },
  );

  test('P2-07 missing secure session never enqueues network send', () async {
    final conversationId = service.createDirectConversation(
      peerAccountId: 'bob',
      conversationId: 'dm_fail_closed',
    );

    await service.sendText(
      conversationId: conversationId,
      messageId: 'msg_no_session',
      plaintext: 'do not downgrade this',
      recipientDeviceIds: ['bob_device_1'],
    );

    final stored = db.getMessageById('msg_no_session')!;
    expect(stored['status'], 'SECURE_SESSION_UNAVAILABLE');
    final pending = db.getPendingOperations();
    expect(pending.any((op) => op['type'] == 'SEND_MESSAGE'), isFalse);
    expect(jsonEncode(pending), isNot(contains('do not downgrade this')));
  });

  test('P12-005 empty recipient device list fails closed locally', () async {
    final conversationId = service.createDirectConversation(
      peerAccountId: 'bob',
      conversationId: 'dm_no_recipient_devices',
    );

    await service.sendText(
      conversationId: conversationId,
      messageId: 'msg_no_devices',
      plaintext: 'no known endpoint',
      recipientDeviceIds: const [],
    );

    final stored = db.getMessageById('msg_no_devices')!;
    expect(stored['status'], 'SECURE_SESSION_UNAVAILABLE');
    final pending = db.getPendingOperations();
    expect(pending.any((op) => op['type'] == 'SEND_MESSAGE'), isFalse);
    expect(jsonEncode(pending), isNot(contains('endpoint')));
  });

  test('P08 first message discovers peer devices from prekey bundle', () async {
    final bundle = await _validPreKeyBundle(deviceId: 'bob_discovered_1');
    service = RemoteMessagingService(
      db: db,
      syncEngine: RemoteSyncEngine(db),
      gateway: gateway,
      protector: _FakeProtector(),
      restClient: _FakeRestClient(bundles: {'bob': bundle}),
      clock: clock,
    );
    await service.setupAccount(
      account: RemoteAccount(
        accountId: 'alice',
        identityPublicKey: 'alice_identity_key',
        createdAt: clock(),
      ),
      device: RemoteDevice(
        deviceId: 'alice_device_1',
        deviceName: 'Alice phone',
        deviceSigningPublicKey: 'alice_device_signing_key',
        deviceAgreementPublicKey: 'alice_device_agreement_key',
        createdAt: clock(),
      ),
    );
    final aliceAgreement = await crypto.X25519().newKeyPair();
    final aliceAgreementPub = await aliceAgreement.extractPublicKey();
    service.setCryptoKeys(
      devicePrivateKey: Uint8List.fromList(
        await aliceAgreement.extractPrivateKeyBytes(),
      ),
      devicePublicKey: Uint8List.fromList(aliceAgreementPub.bytes),
    );
    service.addContact(peerAccountId: 'bob', nickname: 'Bob');
    final conversationId = service.createDirectConversation(
      peerAccountId: 'bob',
      conversationId: 'dm_discovery',
    );

    await service.sendText(
      conversationId: conversationId,
      messageId: 'msg_discovery',
      plaintext: 'first hello',
      recipientDeviceIds: const [],
    );

    expect(
      service.recipientDeviceIdsForConversation(conversationId),
      contains('bob_discovered_1'),
    );
    final pendingSend = db.getPendingOperations().singleWhere(
      (op) => op['type'] == 'SEND_MESSAGE',
    );
    final payload =
        jsonDecode(pendingSend['payload'] as String) as Map<String, dynamic>;
    expect(jsonEncode(payload), isNot(contains('first hello')));
    expect(payload['envelopes'], hasLength(1));
    expect(db.getMessageById('msg_discovery')!['status'], 'PENDING');
  });

  test('P08 invalid discovered signed prekey fails closed', () async {
    final bundle = await _validPreKeyBundle(deviceId: 'bob_bad_spk');
    final devices = bundle['devices'] as List<dynamic>;
    final device = devices.single as Map<String, dynamic>;
    final signedPrekey = device['signed_prekey'] as Map<String, dynamic>;
    signedPrekey['signature'] = base64Encode(List<int>.filled(64, 0));

    service = RemoteMessagingService(
      db: db,
      syncEngine: RemoteSyncEngine(db),
      gateway: gateway,
      protector: _FakeProtector(),
      restClient: _FakeRestClient(bundles: {'bob': bundle}),
      clock: clock,
    );
    await service.setupAccount(
      account: RemoteAccount(
        accountId: 'alice',
        identityPublicKey: 'alice_identity_key',
        createdAt: clock(),
      ),
      device: RemoteDevice(
        deviceId: 'alice_device_1',
        deviceName: 'Alice phone',
        deviceSigningPublicKey: 'alice_device_signing_key',
        deviceAgreementPublicKey: 'alice_device_agreement_key',
        createdAt: clock(),
      ),
    );
    final aliceAgreement = await crypto.X25519().newKeyPair();
    final aliceAgreementPub = await aliceAgreement.extractPublicKey();
    service.setCryptoKeys(
      devicePrivateKey: Uint8List.fromList(
        await aliceAgreement.extractPrivateKeyBytes(),
      ),
      devicePublicKey: Uint8List.fromList(aliceAgreementPub.bytes),
    );
    service.addContact(peerAccountId: 'bob', nickname: 'Bob');
    final conversationId = service.createDirectConversation(
      peerAccountId: 'bob',
      conversationId: 'dm_bad_spk',
    );

    await service.sendText(
      conversationId: conversationId,
      messageId: 'msg_bad_spk',
      plaintext: 'first hello',
      recipientDeviceIds: const [],
    );

    expect(
      db.getMessageById('msg_bad_spk')!['status'],
      'SECURE_SESSION_UNAVAILABLE',
    );
    expect(
      db.getPendingOperations().any((op) => op['type'] == 'SEND_MESSAGE'),
      isFalse,
    );
  });

  test(
    'P10 outbox summary exposes queued, retry, failed and manual retry',
    () async {
      db.updateOperationStatus(
        'create_conversation_dm_alice_bob',
        'COMPLETED',
        0,
      );
      db.enqueueOperation(
        'op_queued',
        'PROFILE_UPDATE',
        jsonEncode({'display_name': 'Alice'}),
        idempotencyKey: 'profile:alice',
      );
      db.enqueueOperation(
        'op_failed',
        'DEVICE_RENAME',
        jsonEncode({'device_name': 'Alice new phone'}),
        idempotencyKey: 'device_rename:alice:alice_device_1',
      );
      db.updateOperationStatus('op_failed', 'FAILED', 5);

      var summary = service.outboxSummary();
      expect(summary.queuedCount, equals(1));
      expect(summary.failedCount, equals(1));
      expect(summary.hasVisibleWork, isTrue);

      gateway.failSends = true;
      await service.processOutboundQueue();
      final retryState = db.getOperationById('op_queued')!;
      expect(retryState['status'], 'PENDING');
      expect(retryState['retries'], equals(1));
      expect(db.getPendingOperations(), isEmpty);

      summary = service.outboxSummary();
      expect(summary.retryScheduledCount, equals(1));
      expect(summary.failedCount, equals(1));
      expect(summary.nextRetryAt, isNotNull);

      gateway.failSends = false;
      final retried = await service.retryFailedOutbox();
      expect(retried, equals(1));
      expect(
        gateway.sent.where((op) => op['op_id'] == 'op_failed'),
        hasLength(1),
      );
      expect(
        db.getOperationById('op_failed')!['idempotency_key'],
        'device_rename:alice:alice_device_1',
      );
    },
  );

  test('P11 attachment metadata is encrypted and rendered locally', () async {
    final bundle = await _validPreKeyBundle(deviceId: 'bob_attachment_1');
    service = RemoteMessagingService(
      db: db,
      syncEngine: RemoteSyncEngine(db),
      gateway: gateway,
      protector: _FakeProtector(),
      restClient: _FakeRestClient(bundles: {'bob': bundle}),
      clock: clock,
    );
    await service.setupAccount(
      account: RemoteAccount(
        accountId: 'alice',
        identityPublicKey: 'alice_identity_key',
        createdAt: clock(),
      ),
      device: RemoteDevice(
        deviceId: 'alice_device_1',
        deviceName: 'Alice phone',
        deviceSigningPublicKey: 'alice_device_signing_key',
        deviceAgreementPublicKey: 'alice_device_agreement_key',
        createdAt: clock(),
      ),
    );
    final aliceAgreement = await crypto.X25519().newKeyPair();
    final aliceAgreementPub = await aliceAgreement.extractPublicKey();
    service.setCryptoKeys(
      devicePrivateKey: Uint8List.fromList(
        await aliceAgreement.extractPrivateKeyBytes(),
      ),
      devicePublicKey: Uint8List.fromList(aliceAgreementPub.bytes),
    );
    service.addContact(peerAccountId: 'bob', nickname: 'Bob');
    final conversationId = service.createDirectConversation(
      peerAccountId: 'bob',
      conversationId: 'dm_attachment',
    );

    const keyDeliverySecret = 'attachment-key-delivery-secret';
    await service.sendAttachment(
      conversationId: conversationId,
      messageId: 'msg_attachment',
      manifest: const RemoteAttachmentManifest(
        fileId: 'file_opaque_hash',
        fileSize: 512,
        fileHash: 'file_opaque_hash',
        mimeType: 'application/pdf',
      ),
      filename: 'contract.pdf',
      keyDeliverySecret: keyDeliverySecret,
      recipientDeviceIds: const [],
    );

    final pendingSend = db.getPendingOperations().singleWhere(
      (op) => op['type'] == 'SEND_MESSAGE',
    );
    final payloadText = pendingSend['payload'] as String;
    expect(payloadText, isNot(contains('contract.pdf')));
    expect(payloadText, isNot(contains(keyDeliverySecret)));
    expect(payloadText, isNot(contains(RemoteAttachmentContent.messageType)));

    final history = await service.messageHistory(conversationId);
    expect(history.single.text, 'Attachment: contract.pdf');
    expect(history.single.attachment, isNotNull);
    expect(history.single.attachment!.fileId, 'file_opaque_hash');
    expect(history.single.attachment!.keyDeliverySecret, keyDeliverySecret);
  });

  test('P2-08 trust decisions persist key change state', () {
    service.recordTrustDecision(
      accountId: 'bob',
      deviceId: 'bob_device_1',
      identityFingerprint: 'fp_old',
      safetyNumber: '12345',
    );
    expect(
      service.trustDecision(
        accountId: 'bob',
        deviceId: 'bob_device_1',
      )!['status'],
      'trusted',
    );

    service.recordTrustDecision(
      accountId: 'bob',
      deviceId: 'bob_device_1',
      identityFingerprint: 'fp_new',
      safetyNumber: '67890',
      status: 'key_changed',
    );
    final changed = service.trustDecision(
      accountId: 'bob',
      deviceId: 'bob_device_1',
    )!;
    expect(changed['identity_fingerprint'], 'fp_new');
    expect(changed['status'], 'key_changed');
  });

  test('Phase 12 offline receive, pagination, receipts, and typing', () async {
    final conversationId = service.createDirectConversation(
      peerAccountId: 'bob',
      conversationId: 'dm_receive',
    );

    Future<String> cipher(String messageId, String text) {
      return _FakeProtector().encryptText(
        conversationId: conversationId,
        messageId: messageId,
        plaintext: text,
        recipientDeviceId: 'alice_device_1',
      );
    }

    gateway.inbound.addAll([
      RemoteRealtimeEnvelope(
        eventId: 'msg_in_1',
        serverSequence: 1,
        schemaVersion: 1,
        timestamp: clock().millisecondsSinceEpoch,
        type: 'chat_message',
        payload: {
          'conversation_id': conversationId,
          'sender_account_id': 'bob',
          'sender_device_id': 'bob_device_1',
          'ciphertext': await cipher('msg_in_1', 'first offline message'),
        },
      ),
      RemoteRealtimeEnvelope(
        eventId: 'msg_in_2',
        serverSequence: 2,
        schemaVersion: 1,
        timestamp: clock().millisecondsSinceEpoch,
        type: 'chat_message',
        payload: {
          'conversation_id': conversationId,
          'sender_account_id': 'bob',
          'sender_device_id': 'bob_device_1',
          'ciphertext': await cipher('msg_in_2', 'second offline message'),
        },
      ),
    ]);

    expect(await service.syncInbound(), 2);
    final latestOnly = await service.messageHistory(conversationId, limit: 1);
    expect(latestOnly.single.messageId, 'msg_in_2');
    final nextPage = await service.messageHistory(
      conversationId,
      limit: 1,
      offset: 1,
    );
    expect(nextPage.single.messageId, 'msg_in_1');

    expect(
      await service.markDelivered(
        messageId: 'msg_in_2',
        conversationId: conversationId,
      ),
      isTrue,
    );

    service.setReadReceiptsEnabled(false);
    final pendingBeforeRead = db.getPendingOperations().length;
    expect(
      await service.markRead(
        messageId: 'msg_in_2',
        conversationId: conversationId,
      ),
      isFalse,
    );
    expect(db.getPendingOperations(), hasLength(pendingBeforeRead));

    await service.publishTyping(conversationId: conversationId, isTyping: true);
    expect(gateway.sent.single['type'], 'TYPING');
    expect(
      db.getPendingOperations().where((op) => op['type'] == 'TYPING'),
      isEmpty,
    );
  });

  test(
    'Phase 12 edits, reactions, deletes, blocking, and notification privacy',
    () async {
      final conversationId = service.createDirectConversation(
        peerAccountId: 'bob',
        conversationId: 'dm_mutations',
      );
      final firstMessageId = await service.sendText(
        conversationId: conversationId,
        messageId: 'msg_edit',
        plaintext: 'draft',
        recipientDeviceIds: ['bob_device_1'],
      );

      await service.editMessage(
        messageId: firstMessageId,
        conversationId: conversationId,
        plaintext: 'corrected',
      );
      service.addReaction(messageId: firstMessageId, reaction: '+1');

      final edited = await service.messageHistory(conversationId);
      expect(edited.single.text, 'corrected');
      expect(edited.single.edited, isTrue);
      expect(edited.single.reactions, contains('+1'));

      service.blockContact('bob');
      expect(db.getContacts().single.status, 'Blocked');

      final preview = service.notificationPreview(conversationId);
      expect(preview.body, 'New encrypted message');
      expect(preview.body, isNot(contains('corrected')));

      service.deleteForSelf(firstMessageId);
      expect(await service.messageHistory(conversationId), isEmpty);
      expect(db.isTombstoned(firstMessageId, 'MESSAGE'), isTrue);

      await service.sendText(
        conversationId: conversationId,
        messageId: 'msg_delete_everyone',
        plaintext: 'remove for all',
        recipientDeviceIds: ['bob_device_1'],
      );
      service.deleteForEveryone(
        messageId: 'msg_delete_everyone',
        conversationId: conversationId,
      );
      expect(db.isTombstoned('msg_delete_everyone', 'MESSAGE'), isTrue);
      expect(
        db.getPendingOperations().any((op) => op['type'] == 'DELETE_MESSAGE'),
        isTrue,
      );
    },
  );

  test(
    'F4 edit/delete windows, reaction replacement, unread, and link signing',
    () async {
      final conversationId = service.createDirectConversation(
        peerAccountId: 'bob',
        conversationId: 'dm_f4_productivity',
        title: 'Bob',
      );
      db.saveMessage(
        const RemoteMessage(
          messageId: 'msg_f4_old_edit',
          conversationId: 'dm_f4_productivity',
          senderAccountId: 'alice',
          senderDeviceId: 'alice_device_1',
          ciphertext: 'cipher old edit',
        ),
        1,
        -const Duration(days: 1).inMilliseconds,
        'SENT',
      );
      await expectLater(
        service.editMessage(
          messageId: 'msg_f4_old_edit',
          conversationId: conversationId,
          plaintext: 'too late',
        ),
        throwsStateError,
      );

      final messageId = await service.sendText(
        conversationId: conversationId,
        messageId: 'msg_f4_react',
        plaintext: 'react here',
        recipientDeviceIds: ['bob_device_1'],
      );
      service.addReaction(messageId: messageId, reaction: '+1');
      service.addReaction(messageId: messageId, reaction: 'heart');
      final reactions = db
          .getMessageRevisions(messageId)
          .where((row) => row['type'] == 'REACTION')
          .toList();
      expect(reactions, hasLength(1));
      final reactionPayload =
          jsonDecode(reactions.single['payload'] as String)
              as Map<String, dynamic>;
      expect(reactionPayload['reaction'], equals('heart'));
      final reactionDetails = service.reactionDetails(messageId);
      expect(reactionDetails, hasLength(1));
      expect(reactionDetails.single.accountId, equals('alice'));
      expect(reactionDetails.single.reaction, equals('heart'));

      db.saveMessage(
        const RemoteMessage(
          messageId: 'msg_f4_old_delete',
          conversationId: 'dm_f4_productivity',
          senderAccountId: 'alice',
          senderDeviceId: 'alice_device_1',
          ciphertext: 'cipher old delete',
        ),
        9,
        -const Duration(days: 3).inMilliseconds,
        'SENT',
      );
      expect(
        () => service.deleteForEveryone(
          messageId: 'msg_f4_old_delete',
          conversationId: conversationId,
        ),
        throwsStateError,
      );

      db.markConversationRead(
        conversationId: conversationId,
        deviceId: 'alice_device_1',
        lastReadSequence: 1,
        updatedAt: 2000,
      );
      expect(service.unreadSummary(conversationId).unreadCount, greaterThan(0));
      service.markConversationRead(conversationId);
      expect(service.unreadSummary(conversationId).unreadCount, equals(0));

      final link = service.createSignedContactLink(
        linkId: 'service_link',
        nonce: 'service_nonce',
        ttl: const Duration(minutes: 5),
      );
      expect(service.verifySignedContactLink(link), isTrue);
      db.markContactLinkUsed(
        'service_link',
        DateTime.now().millisecondsSinceEpoch,
      );
      expect(service.verifySignedContactLink(link), isFalse);
    },
  );

  test(
    'F5 rich media envelopes, voice drafts, playback, and cleanup',
    () async {
      final conversationId = service.createDirectConversation(
        peerAccountId: 'bob',
        conversationId: 'dm_f5_media',
        title: 'Bob',
      );

      final tempDir = Directory.systemTemp.createTempSync('helix_f5_voice_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final recording = File(
        '${tempDir.path}${Platform.pathSeparator}voice.opus',
      )..writeAsStringSync('plaintext voice draft');
      final draft = service.startMediaDraft(
        conversationId: conversationId,
        kind: RemoteMediaContent.voiceNoteKind,
        localPath: recording.path,
        durationMs: 64000,
        waveform: const [5, 20, 60, 100, 25],
        viewOnce: true,
      );
      service.pauseMediaDraft(draft.draftId);
      expect(
        service.mediaDrafts(conversationId).single.status,
        equals('paused'),
      );
      service.resumeMediaDraft(draft.draftId);
      service.markMediaDraftReady(draft.draftId);
      expect(
        service.mediaDrafts(conversationId).single.status,
        equals('ready'),
      );

      final messageId = await service.sendVoiceNote(
        conversationId: conversationId,
        messageId: 'msg_f5_voice',
        manifest: const RemoteAttachmentManifest(
          fileId: 'voice_att',
          fileSize: 1234,
          fileHash: 'voice_att',
          mimeType: 'audio/opus',
          thumbnailFileId: 'voice_wave_thumb',
          thumbnailFileSize: 64,
          thumbnailFileHash: 'voice_wave_thumb',
        ),
        filename: 'voice.opus',
        keyDeliverySecret: 'secret',
        recipientDeviceIds: const ['bob_device_1'],
        durationMs: 64000,
        waveform: const [5, 20, 60, 100, 25],
        viewOnce: true,
      );

      final history = await service.messageHistory(conversationId);
      final voice = history.firstWhere(
        (message) => message.messageId == messageId,
      );
      expect(voice.media!.kind, equals(RemoteMediaContent.voiceNoteKind));
      expect(voice.media!.durationMs, equals(64000));
      expect(voice.media!.waveform, equals([5, 20, 60, 100, 25]));
      expect(voice.viewOnce, isTrue);
      expect(
        jsonEncode(db.getPendingOperations()),
        isNot(contains('voice draft')),
      );

      service.saveMediaPlaybackState(
        messageId: messageId,
        positionMs: 15000,
        speed: 1.5,
      );
      expect(service.mediaPlaybackState(messageId)!.speed, equals(1.5));
      service.saveMediaTransferPolicy(
        attachmentId: 'voice_att',
        backgroundAllowed: true,
        expiresAt: 9000,
        retryCount: 1,
        status: 'retrying',
      );
      expect(
        db.mediaTransferPolicy('voice_att')!['status'],
        equals('retrying'),
      );

      service.cancelMediaDraft(draft.draftId);
      expect(recording.existsSync(), isFalse);
      expect(service.mediaDrafts(conversationId), isEmpty);
    },
  );

  test('F9 polls, events, reminders, and live location stay opaque', () async {
    final conversationId = service.createDirectConversation(
      peerAccountId: 'bob',
      conversationId: 'dm_f9_collab',
      title: 'Bob',
    );

    final pollMessageId = await service.sendPoll(
      conversationId: conversationId,
      pollId: 'poll_f9',
      messageId: 'msg_poll_f9',
      question: 'Where should we meet?',
      options: const ['Cafe', 'Library'],
      recipientDeviceIds: const ['bob_device_1'],
    );
    await service.castPollVote(
      conversationId: conversationId,
      pollId: 'poll_f9',
      optionIds: const ['opt_2'],
      allowMultipleVotes: false,
    );
    expect(service.pollResults('poll_f9').counts['opt_2'], equals(1));

    final eventMessageId = await service.sendEventContent(
      conversationId: conversationId,
      eventId: 'event_f9',
      messageId: 'msg_event_f9',
      title: 'Sprint planning',
      startsAt: 10 * 60 * 60 * 1000,
      endsAt: 11 * 60 * 60 * 1000,
      timeZone: 'Asia/Dhaka',
      locationText: 'Room 3',
      plusOneAllowed: true,
      pinned: true,
      recipientDeviceIds: const ['bob_device_1'],
    );
    await service.updateEventRsvp(
      conversationId: conversationId,
      eventId: 'event_f9',
      state: 'yes',
      plusOne: true,
    );
    expect(service.eventRsvpStates('event_f9')['alice'], equals('yes'));
    await service.scheduleEventReminder(
      conversationId: conversationId,
      eventId: 'event_f9',
      remindAt: 9000,
      note: 'Bring planning notes',
      reminderId: 'reminder_f9',
    );
    expect(service.dueEventReminders(9000).single.reminderId, 'reminder_f9');

    final staticLocationId = await service.sendStaticLocation(
      conversationId: conversationId,
      locationId: 'loc_f9',
      messageId: 'msg_location_f9',
      latitudeE7: 235000000,
      longitudeE7: 901000000,
      accuracyMeters: 10,
      label: 'Office',
      recipientDeviceIds: const ['bob_device_1'],
    );
    final liveSessionId = await service.startLiveLocation(
      conversationId: conversationId,
      sessionId: 'live_f9',
      messageId: 'msg_live_f9',
      latitudeE7: 235000000,
      longitudeE7: 901000000,
      accuracyMeters: 15,
      duration: const Duration(seconds: 60),
      updateInterval: const Duration(milliseconds: 1),
      recipientDeviceIds: const ['bob_device_1'],
    );
    expect(
      await service.publishLiveLocationUpdate(
        sessionId: liveSessionId,
        latitudeE7: 235000010,
        longitudeE7: 901000010,
        accuracyMeters: 12,
      ),
      isTrue,
    );
    service.stopLiveLocation(liveSessionId);
    expect(db.liveLocationSession(liveSessionId)!.status, equals('stopped'));

    final history = await service.messageHistory(conversationId);
    expect(
      history.firstWhere((message) => message.messageId == pollMessageId).poll,
      isNotNull,
    );
    expect(
      history
          .firstWhere((message) => message.messageId == eventMessageId)
          .event,
      isNotNull,
    );
    expect(
      history
          .firstWhere((message) => message.messageId == staticLocationId)
          .location!
          .label,
      equals('Office'),
    );
    final pendingPayload = jsonEncode(db.getPendingOperations());
    expect(pendingPayload, isNot(contains('Where should we meet')));
    expect(pendingPayload, isNot(contains('Sprint planning')));
    expect(pendingPayload, isNot(contains('Office')));
    expect(pendingPayload, isNot(contains('Bring planning notes')));
  });

  test(
    'F10 personalization settings and sticker sending stay local/opaque',
    () async {
      final conversationId = service.createDirectConversation(
        peerAccountId: 'bob',
        conversationId: 'dm_f10_personal',
        title: 'Bob',
      );

      service.saveThemePreference(
        scope: 'conversation',
        scopeId: conversationId,
        mode: 'dark',
        colorSeed: '#1b5e20',
        highContrast: true,
      );
      expect(
        service.themePreference('conversation', conversationId)!.highContrast,
        isTrue,
      );
      expect(
        service.themeContrastAllowed(
          foreground: 0xffffffff,
          background: 0xff000000,
        ),
        isTrue,
      );

      await service.saveAboutNote(
        note: 'On a quiet sprint',
        audience: 'contacts',
        ttl: const Duration(minutes: 10),
        noteId: 'about_f10',
      );
      expect(service.aboutNote('alice')!.audience, equals('contacts'));

      service.saveProfileImage(
        attachmentId: 'avatar_full',
        thumbnailAttachmentId: 'avatar_thumb',
        audience: 'contacts',
        cacheVersion: 1,
      );
      expect(
        service.profileImage('alice')!['attachment_id'],
        equals('avatar_full'),
      );

      db.saveAttachment(
        attachmentId: 'att_sticker',
        filename: 'smile.webp',
        sizeBytes: 120 * 1024,
        encryptedKey: 'wrapped-key',
        status: 'READY',
      );
      service.upsertStickerPack(
        packId: 'pack_f10',
        title: 'Faces',
        manifest: const {'shared': true},
      );
      service.upsertSticker(
        stickerId: 'sticker_f10',
        packId: 'pack_f10',
        kind: 'static',
        attachmentId: 'att_sticker',
        emoji: '😀',
        tags: 'smile happy face',
        sizeBytes: 120 * 1024,
      );
      expect(
        service.stickerSuggestionsForEmoji('😀').single.stickerId,
        equals('sticker_f10'),
      );
      service.favoriteSticker('sticker_f10', favorite: true);

      final messageId = await service.sendSticker(
        conversationId: conversationId,
        stickerId: 'sticker_f10',
        keyDeliverySecret: 'secret',
        recipientDeviceIds: const ['bob_device_1'],
        messageId: 'msg_sticker_f10',
      );
      final history = await service.messageHistory(conversationId);
      expect(
        history.firstWhere((message) => message.messageId == messageId).sticker,
        isNotNull,
      );
      expect(service.recentStickers().single.stickerId, equals('sticker_f10'));

      final pendingPayload = jsonEncode(db.getPendingOperations());
      expect(pendingPayload, isNot(contains('On a quiet sprint')));
      expect(pendingPayload, isNot(contains('smile happy face')));
    },
  );

  test('Phase 13 contact lifecycle, privacy, presence, and reports', () {
    service.sendContactRequest(
      requestId: 'cr_1',
      peerAccountId: 'erin',
      nickname: 'Erin',
    );
    expect(db.getContact('erin')!.status, 'PendingSent');
    expect(db.getContactRequest('cr_1')!.status, 'Pending');

    service.recordIncomingContactRequest(
      requestId: 'cr_from_carol',
      peerAccountId: 'carol',
      nickname: 'Carol',
    );
    service.acceptContactRequest(
      requestId: 'cr_from_carol',
      peerAccountId: 'carol',
      nickname: 'Carol',
    );
    expect(db.getContact('carol')!.status, 'Accepted');
    expect(db.getContactRequest('cr_from_carol')!.status, 'Accepted');

    service.recordIncomingContactRequest(
      requestId: 'cr_from_dan',
      peerAccountId: 'dan',
    );
    service.rejectContactRequest(
      requestId: 'cr_from_dan',
      peerAccountId: 'dan',
    );
    service.sendContactRequest(requestId: 'cr_to_erin', peerAccountId: 'frank');
    service.cancelContactRequest(
      requestId: 'cr_to_erin',
      peerAccountId: 'frank',
    );
    expect(db.getContact('dan'), isNull);
    expect(db.getContact('frank'), isNull);
    expect(db.getContactRequest('cr_from_dan')!.status, 'Rejected');
    expect(db.getContactRequest('cr_to_erin')!.status, 'Cancelled');

    service.removeContact('carol');
    expect(db.getContact('carol'), isNull);

    service.blockContact('mallory');
    expect(db.getContact('mallory')!.status, 'Blocked');
    service.unblockContact('mallory');
    expect(db.getContact('mallory'), isNull);

    service.updatePrivacy(
      const RemotePrivacySettings(
        searchDiscoverable: false,
        presenceVisibility: 'NOBODY',
        lastSeenVisibility: 'NOBODY',
      ),
    );
    final presence = service.updatePresence();
    expect(presence.visibility, 'NOBODY');
    expect(presence.lastSeenAt, isNull);

    service.updateProfile(displayName: ' Alice Remote ');
    expect(() => service.updateProfile(displayName: ''), throwsStateError);
    service.reportAccount(
      reportId: 'r_1',
      subjectAccountId: 'mallory',
      category: 'spam',
      reasonCode: 'unsolicited_request',
      contextHash: 'sha256:abc123',
    );

    final payloads = jsonEncode(db.getPendingOperations());
    expect(payloads, contains('CONTACT_REQUEST'));
    expect(payloads, contains('CONTACT_REQUEST_ACCEPT'));
    expect(payloads, contains('CONTACT_REQUEST_REJECT'));
    expect(payloads, contains('CONTACT_REQUEST_CANCEL'));
    expect(payloads, contains('CONTACT_REMOVE'));
    expect(payloads, contains('CONTACT_BLOCK'));
    expect(payloads, contains('CONTACT_UNBLOCK'));
    expect(payloads, contains('PRIVACY_UPDATE'));
    expect(payloads, contains('PRESENCE_UPDATE'));
    expect(payloads, contains('PROFILE_UPDATE'));
    expect(payloads, contains('\\"display_name\\":\\"Alice Remote\\"'));
    expect(payloads, contains('SAFETY_REPORT'));
    expect(payloads, isNot(contains('message_text')));
    expect(payloads, isNot(contains('plaintext')));
  });

  test('Phase 13 contact request quota is enforced locally', () {
    for (var i = 0; i < 20; i++) {
      service.sendContactRequest(
        requestId: 'quota_$i',
        peerAccountId: 'peer_$i',
      );
    }

    expect(
      () => service.sendContactRequest(
        requestId: 'quota_overflow',
        peerAccountId: 'overflow',
      ),
      throwsStateError,
    );
  });

  test('P07 service preserves pending requests and gates conversations', () {
    service.sendContactRequest(requestId: 'cr_pending', peerAccountId: 'zara');
    expect(
      () => service.createDirectConversation(peerAccountId: 'zara'),
      throwsStateError,
    );
    expect(
      () => service.sendContactRequest(
        requestId: 'cr_duplicate',
        peerAccountId: 'zara',
      ),
      throwsStateError,
    );

    service.recordIncomingContactRequest(
      requestId: 'cr_received',
      peerAccountId: 'yuki',
      nickname: 'Yuki',
    );
    expect(db.getContact('yuki')!.status, 'PendingReceived');
    expect(db.getContactRequest('cr_received')!.direction, 'received');

    service.acceptContactRequest(
      requestId: 'cr_received',
      peerAccountId: 'yuki',
      nickname: 'Yuki',
    );
    final conversationId = service.createDirectConversation(
      peerAccountId: 'yuki',
      conversationId: 'dm_yuki',
    );
    expect(conversationId, 'dm_yuki');
  });

  test('P07 pending contact requests survive database restart', () async {
    final dir = Directory.systemTemp.createTempSync('p07_contacts_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}remote.db');

    final first = HelixRemoteDatabase(file);
    first.initialize();
    first.upsertContact(
      const RemoteContact(
        peerAccountId: 'kai',
        nickname: 'Kai',
        status: 'PendingReceived',
      ),
    );
    first.upsertContactRequest(
      const RemoteContactRequest(
        requestId: 'cr_restart',
        peerAccountId: 'kai',
        direction: 'received',
        status: 'Pending',
        updatedAt: 42,
        nickname: 'Kai',
      ),
    );
    first.close();

    final second = HelixRemoteDatabase(file);
    second.initialize();
    addTearDown(second.close);
    expect(second.getContact('kai')!.status, 'PendingReceived');
    expect(second.getContactRequest('cr_restart')!.peerAccountId, 'kai');
  });
}

Future<Map<String, dynamic>> _validPreKeyBundle({
  required String deviceId,
}) async {
  final ed25519 = crypto.Ed25519();
  final x25519 = crypto.X25519();
  final signing = await ed25519.newKeyPair();
  final signingPub = await signing.extractPublicKey();
  final agreement = await x25519.newKeyPair();
  final agreementPub = await agreement.extractPublicKey();
  final signedPrekey = await x25519.newKeyPair();
  final signedPrekeyPub = await signedPrekey.extractPublicKey();
  final signature = await ed25519.sign(signedPrekeyPub.bytes, keyPair: signing);

  return {
    'devices': [
      {
        'device_id': deviceId,
        'device_key': base64Encode(agreementPub.bytes),
        'identity_key': base64Encode(signingPub.bytes),
        'signed_prekey': {
          'key_id': 1,
          'public_key': base64Encode(signedPrekeyPub.bytes),
          'signature': base64Encode(signature.bytes),
        },
        'one_time_prekey': null,
      },
    ],
  };
}
