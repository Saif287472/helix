import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

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
  @override
  set accessToken(String? token) {}
  @override
  Future<void> close() async {}
  @override
  Future<Map<String, dynamic>> registerAccount({
    required String accountId,
    required String username,
    required String accountIdentityPublicKey,
    required String deviceId,
    required String deviceSigningPublicKey,
    required String deviceAgreementPublicKey,
    required String accountRegistrationSignature,
    required String deviceRegistrationSignature,
    required String deviceName,
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
  Future<void> revokeDevice(String deviceId) async {}
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
  }) async => {};
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
  Future<Map<String, dynamic>> sendCallSignal({
    required String targetDeviceId,
    required Map<String, dynamic> payload,
  }) async => {};
}

class _FakeGateway implements SyncGateway {
  final inbound = <RemoteRealtimeEnvelope>[];
  final sent = <Map<String, dynamic>>[];

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
        username: 'alice',
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

      final pendingPayload = jsonEncode(db.getPendingOperations());
      expect(pendingPayload, isNot(contains('train leaves')));

      final processed = await service.processOutboundQueue();
      expect(processed, 2);
      expect(jsonEncode(gateway.sent), isNot(contains('train leaves')));

      final history = await service.messageHistory(conversationId);
      expect(history.single.text, 'the train leaves at nine');
      expect(history.single.status, 'PENDING');

      final matches = await service.searchDecryptedHistory(
        conversationId: conversationId,
        query: 'train',
      );
      expect(matches.single.messageId, 'msg_1');
    },
  );

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

  test('Phase 13 contact lifecycle, privacy, presence, and reports', () {
    service.sendContactRequest(
      requestId: 'cr_1',
      peerAccountId: 'bob',
      nickname: 'Bob',
    );
    expect(db.getContact('bob')!.status, 'PendingSent');

    service.acceptContactRequest(
      requestId: 'cr_from_carol',
      peerAccountId: 'carol',
      nickname: 'Carol',
    );
    expect(db.getContact('carol')!.status, 'Accepted');

    service.rejectContactRequest(
      requestId: 'cr_from_dan',
      peerAccountId: 'dan',
    );
    service.cancelContactRequest(
      requestId: 'cr_to_erin',
      peerAccountId: 'erin',
    );
    expect(db.getContact('dan'), isNull);
    expect(db.getContact('erin'), isNull);

    service.removeContact('carol');
    expect(db.getContact('carol'), isNull);

    service.blockContact('mallory');
    expect(db.getContact('mallory')!.status, 'Blocked');
    service.unblockContact('mallory');
    expect(db.getContact('mallory'), isNull);

    service.changeUsername('alice_new');
    expect(() => service.changeUsername('Helix Bad'), throwsStateError);
    expect(() => service.changeUsername('helix_admin'), throwsStateError);

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

    service.updateProfile(displayName: 'Alice Remote');
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
    expect(payloads, contains('USERNAME_CHANGE'));
    expect(payloads, contains('PRIVACY_UPDATE'));
    expect(payloads, contains('PRESENCE_UPDATE'));
    expect(payloads, contains('PROFILE_UPDATE'));
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
}
