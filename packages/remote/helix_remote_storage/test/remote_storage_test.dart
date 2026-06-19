import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:path/path.dart' as p;

void main() {
  setUpAll(() {
    if (Platform.isWindows) {
      var dir = Directory.current;
      String? foundPath;
      for (int i = 0; i < 5; i++) {
        final possiblePath = p.join(dir.path, '.dart_tool', 'lib', 'sqlite3.dll');
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

  setUp(() {
    db = HelixRemoteDatabase(File(':memory:'));
    db.initialize();
  });

  tearDown(() {
    db.close();
  });

  test('Account and Device persistence operations', () {
    final account = RemoteAccount(
      accountId: 'acc_123',
      username: 'alice',
      identityPublicKey: 'alice_identity_public_key',
      createdAt: DateTime.now(),
      status: 'Active',
    );

    db.upsertAccount(account);

    final retrievedAcc = db.getAccount('acc_123');
    expect(retrievedAcc, isNotNull);
    expect(retrievedAcc!.username, equals('alice'));
    expect(retrievedAcc.identityPublicKey, equals('alice_identity_public_key'));

    final device = RemoteDevice(
      deviceId: 1,
      deviceName: 'Alice iPhone',
      devicePublicKey: 'alice_device_public_key',
      createdAt: DateTime.now(),
      status: 'Active',
    );

    db.upsertDevice('acc_123', device);

    final devices = db.getDevices('acc_123');
    expect(devices.length, equals(1));
    expect(devices.first.deviceId, equals(1));
    expect(devices.first.deviceName, equals('Alice iPhone'));
  });

  test('Contact CRUD and blocking validation', () {
    final contact = RemoteContact(
      peerAccountId: 'bob_id',
      nickname: 'Bob Friend',
      status: 'Accepted',
    );

    db.upsertContact(contact);

    final contacts = db.getContacts();
    expect(contacts.length, equals(1));
    expect(contacts.first.nickname, equals('Bob Friend'));
    expect(contacts.first.status, equals('Accepted'));
  });

  test('Conversations, Messages, and Cursors transactional operations', () {
    final conversation = RemoteConversation(
      conversationId: 'conv_123',
      title: 'Friend chat',
      type: 'DIRECT',
      lastActivitySequence: 10,
      createdAt: DateTime.now(),
    );

    db.upsertConversation(conversation, ['alice', 'bob']);

    final conversations = db.getConversations();
    expect(conversations.length, equals(1));
    expect(conversations.first.title, equals('Friend chat'));

    final members = db.getConversationMembers('conv_123');
    expect(members, containsAll(['alice', 'bob']));

    final message = RemoteMessage(
      messageId: 'msg_1',
      conversationId: 'conv_123',
      senderAccountId: 'alice',
      senderDeviceId: 1,
      ciphertext: 'hello bob decrypted text',
    );

    db.saveMessage(message, 1, DateTime.now().millisecondsSinceEpoch, 'DELIVERED');

    final messages = db.getMessages('conv_123');
    expect(messages.length, equals(1));
    expect(messages.first['text'], equals('hello bob decrypted text'));
    expect(messages.first['server_sequence'], equals(1));

    // Update cursor
    db.updateSyncCursor('conv_123', 5);
    final cursor = db.getSyncCursor('conv_123');
    expect(cursor, equals(5));
  });

  test('Outbound Queue Operations and Tombstones', () {
    db.enqueueOperation('op_1', 'SEND_MESSAGE', '{"message_id": "msg_1"}');

    final pending = db.getPendingOperations();
    expect(pending.length, equals(1));
    expect(pending.first['op_id'], equals('op_1'));
    expect(pending.first['type'], equals('SEND_MESSAGE'));

    db.updateOperationStatus('op_1', 'COMPLETED', 0);
    final emptyPending = db.getPendingOperations();
    expect(emptyPending.isEmpty, isTrue);

    // Tombstones
    db.saveTombstone('msg_1', 'MESSAGE');
    expect(db.isTombstoned('msg_1', 'MESSAGE'), isTrue);
    expect(db.isTombstoned('msg_2', 'MESSAGE'), isFalse);
  });
}
