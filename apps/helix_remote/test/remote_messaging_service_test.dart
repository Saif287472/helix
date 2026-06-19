import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/remote_messaging_service.dart';
import 'package:helix_remote_api/api/realtime_envelope.dart';
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
        deviceId: 1,
        deviceName: 'Alice phone',
        devicePublicKey: 'alice_device_key',
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
          deviceId: 2,
          deviceName: 'Alice laptop',
          devicePublicKey: 'alice_laptop_key',
          createdAt: clock(),
        ),
      );
      service.verifyDevice(accountId: 'alice', deviceId: 2);
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
          'sender_device_id': 1,
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
          'sender_device_id': 1,
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
}
