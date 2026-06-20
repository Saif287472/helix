import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  setUpAll(() {
    if (Platform.isWindows) {
      var dir = Directory.current;
      String? foundPath;
      for (int i = 0; i < 5; i++) {
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
      deviceId: 'device1',
      deviceName: 'Alice iPhone',
      deviceSigningPublicKey: 'alice_device_signing_public_key',
      deviceAgreementPublicKey: 'alice_device_agreement_public_key',
      createdAt: DateTime.now(),
      status: 'Active',
    );

    db.upsertDevice('acc_123', device);

    final devices = db.getDevices('acc_123');
    expect(devices.length, equals(1));
    expect(devices.first.deviceId, equals('device1'));
    expect(devices.first.deviceName, equals('Alice iPhone'));
    expect(
      devices.first.deviceSigningPublicKey,
      equals('alice_device_signing_public_key'),
    );
    expect(
      devices.first.deviceAgreementPublicKey,
      equals('alice_device_agreement_public_key'),
    );
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

    expect(db.getContact('bob_id')!.nickname, equals('Bob Friend'));
    db.deleteContact('bob_id');
    expect(db.getContact('bob_id'), isNull);
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
      senderDeviceId: 'device1',
      ciphertext: 'hello bob decrypted text',
    );

    db.saveMessage(
      message,
      1,
      DateTime.now().millisecondsSinceEpoch,
      'DELIVERED',
    );

    final messages = db.getMessages('conv_123');
    expect(messages.length, equals(1));
    expect(
      messages.first['ciphertext_blob'],
      equals('hello bob decrypted text'),
    );
    expect(messages.first['server_sequence'], equals(1));

    // Update cursor
    db.updateSyncCursor('conv_123', 5);
    final cursor = db.getSyncCursor('conv_123');
    expect(cursor, equals(5));
  });

  test('P1 v6 migration converts integer device identifiers to text', () {
    final dir = Directory.systemTemp.createTempSync('helix_remote_v5_');
    final file = File(p.join(dir.path, 'remote.db'));
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final oldDb = sqlite.sqlite3.open(file.path);
    oldDb
      ..execute('''
        CREATE TABLE accounts (
          account_id TEXT PRIMARY KEY,
          username TEXT NOT NULL,
          identity_public_key TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          status TEXT NOT NULL
        );
      ''')
      ..execute('''
        CREATE TABLE devices (
          device_id INTEGER NOT NULL,
          account_id TEXT NOT NULL,
          device_name TEXT NOT NULL,
          device_public_key TEXT NOT NULL,
          status TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          PRIMARY KEY (account_id, device_id)
        );
      ''')
      ..execute('''
        CREATE TABLE conversations (
          conversation_id TEXT PRIMARY KEY,
          title TEXT,
          type TEXT NOT NULL,
          last_sequence INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        );
      ''')
      ..execute('''
        CREATE TABLE messages (
          message_id TEXT PRIMARY KEY,
          conversation_id TEXT NOT NULL,
          sender_account_id TEXT NOT NULL,
          sender_device_id INTEGER NOT NULL,
          ciphertext_blob TEXT NOT NULL,
          server_sequence INTEGER NOT NULL,
          timestamp INTEGER NOT NULL,
          status TEXT NOT NULL
        );
      ''')
      ..execute('''
        CREATE TABLE message_receipts (
          receipt_id TEXT PRIMARY KEY,
          message_id TEXT NOT NULL,
          conversation_id TEXT NOT NULL,
          account_id TEXT NOT NULL,
          device_id INTEGER,
          receipt_type TEXT NOT NULL,
          timestamp INTEGER NOT NULL
        );
      ''')
      ..execute('''
        INSERT INTO accounts VALUES ('acc_v5', 'alice', 'identity', 1000, 'Active');
      ''')
      ..execute('''
        INSERT INTO devices VALUES (1, 'acc_v5', 'Legacy Phone', 'legacy_key', 'Active', 1000);
      ''')
      ..execute('''
        INSERT INTO conversations VALUES ('conv_v5', 'Legacy', 'DIRECT', 1, 1000);
      ''')
      ..execute('''
        INSERT INTO messages VALUES ('msg_v5', 'conv_v5', 'acc_v5', 1, 'cipher', 1, 1001, 'DELIVERED');
      ''')
      ..execute('''
        INSERT INTO message_receipts VALUES ('receipt_v5', 'msg_v5', 'conv_v5', 'acc_v5', 1, 'READ', 1002);
      ''')
      ..execute('PRAGMA user_version = 5;')
      ..close();

    final migrated = HelixRemoteDatabase(file);
    migrated.initialize();
    addTearDown(migrated.close);

    expect(migrated.schemaVersion, equals(11));
    final devices = migrated.getDevices('acc_v5');
    expect(devices.single.deviceId, equals('1'));
    expect(devices.single.deviceSigningPublicKey, equals('legacy_key'));
    expect(devices.single.deviceAgreementPublicKey, equals('legacy_key'));
    expect(migrated.getMessageById('msg_v5')!['sender_device_id'], equals('1'));
    expect(
      migrated.getMessageReceipts('msg_v5').single['device_id'],
      equals('1'),
    );
  });

  test('P2-01 encrypted database rejects wrong key and hides markers', () {
    final dir = Directory.systemTemp.createTempSync('helix_remote_p2_enc_');
    final file = File(p.join(dir.path, 'remote.db'));
    const key = 'correct horse battery staple';
    const marker = 'p2_plaintext_marker_alice_secret';
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final encrypted = HelixRemoteDatabase(file, password: key);
    encrypted.initialize();
    encrypted.upsertAccount(
      RemoteAccount(
        accountId: 'acc_p2',
        username: marker,
        identityPublicKey: 'identity_p2',
        createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
        status: 'Active',
      ),
    );
    encrypted.close();

    final wrongKey = HelixRemoteDatabase(file, password: 'wrong key');
    expect(
      wrongKey.initialize,
      throwsA(isA<RemoteDatabaseEncryptionException>()),
    );
    expect(_opensWithoutKey(file), isFalse);
    expect(_databaseFilesContain(file, marker), isFalse);
  });

  test('P2-01 migrates plaintext database to encrypted SQLCipher file', () {
    final dir = Directory.systemTemp.createTempSync('helix_remote_p2_migrate_');
    final file = File(p.join(dir.path, 'remote.db'));
    const key = 'migration key';
    const marker = 'p2_migration_marker_bob_secret';
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    _createPlaintextV6Database(file, marker);
    expect(_hasPlaintextSqliteHeader(file), isTrue);

    final migrated = HelixRemoteDatabase(file, password: key);
    migrated.initialize();
    addTearDown(migrated.close);

    expect(migrated.getAccount('acc_plain')!.username, equals(marker));
    expect(migrated.schemaVersion, equals(11));
    expect(_opensWithoutKey(file), isFalse);
    expect(_databaseFilesContain(file, marker), isFalse);
  });

  test('P2-01 migration crash injection rolls back plaintext source', () {
    for (final fault in RemoteDatabaseMigrationFault.values) {
      final dir = Directory.systemTemp.createTempSync('helix_remote_p2_fault_');
      final file = File(p.join(dir.path, 'remote.db'));
      const key = 'fault migration key';
      final marker = 'p2_fault_marker_${fault.name}';
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      _createPlaintextV6Database(file, marker);

      final failing = HelixRemoteDatabase(
        file,
        password: key,
        migrationFault: fault,
      );
      expect(
        failing.initialize,
        throwsA(isA<RemoteDatabaseMigrationException>()),
      );

      expect(file.existsSync(), isTrue);
      expect(_hasPlaintextSqliteHeader(file), isTrue);
      expect(File('${file.path}.p2-encrypted-temp').existsSync(), isFalse);
      expect(File('${file.path}.p2-plaintext-backup').existsSync(), isFalse);
      expect(_readPlaintextUsername(file), equals(marker));

      final retry = HelixRemoteDatabase(file, password: key);
      retry.initialize();
      retry.close();
      expect(_opensWithoutKey(file), isFalse);
      expect(_databaseFilesContain(file, marker), isFalse);
    }
  });

  test('P2-04/P2-08 crypto session and trust state persist across restart', () {
    final dir = Directory.systemTemp.createTempSync('helix_remote_p2_state_');
    final file = File(p.join(dir.path, 'remote.db'));
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final first = HelixRemoteDatabase(file);
    first.initialize();
    final seed = first.getOrCreateLocalHistorySessionSeed('conv_persist');
    first.upsertCryptoSession(
      sessionId: 'peer:conv_persist:bob_device',
      conversationId: 'conv_persist',
      role: 'x3dh_v1',
      protocolVersion: 1,
      rootKey: 'root_key',
      sendingChainKey: 'send_key',
      receivingChainKey: 'recv_key',
      peerAccountId: 'bob',
      peerDeviceId: 'bob_device',
      sendCount: 3,
      receiveCount: 2,
      createdAt: 1000,
      updatedAt: 2000,
    );
    first.upsertTrustDecision(
      accountId: 'bob',
      deviceId: 'bob_device',
      identityFingerprint: 'fingerprint',
      safetyNumber: 'safety',
      status: 'trusted',
      timestamp: 3000,
    );
    first.saveLocalPrekey(
      keyId: 1,
      role: 'one_time_prekey',
      deviceId: 'alice_device',
      publicKey: 'public',
      privateKeyRef: 'secure_ref',
      createdAt: 4000,
      rotationState: 'active',
    );
    first.close();

    final reopened = HelixRemoteDatabase(file);
    reopened.initialize();
    addTearDown(reopened.close);

    expect(reopened.schemaVersion, equals(11));
    expect(
      reopened.getOrCreateLocalHistorySessionSeed('conv_persist'),
      equals(seed),
    );
    final session = reopened.getCryptoSession('peer:conv_persist:bob_device')!;
    expect(session['send_count'], equals(3));
    expect(session['receive_count'], equals(2));
    expect(
      reopened.getTrustDecision(
        accountId: 'bob',
        deviceId: 'bob_device',
      )!['safety_number'],
      equals('safety'),
    );
    expect(reopened.countActiveOneTimePrekeys('alice_device'), equals(1));
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

  test(
    'P17 backup snapshot restores history and filters tombstoned messages',
    () {
      final account = RemoteAccount(
        accountId: 'acc_restore',
        username: 'restore_user',
        identityPublicKey: 'restore_identity',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        status: 'Active',
      );
      db.upsertAccount(account);
      db.upsertDevice(
        'acc_restore',
        RemoteDevice(
          deviceId: 'device1',
          deviceName: 'Restore Phone',
          deviceSigningPublicKey: 'restore_device_signing_key',
          deviceAgreementPublicKey: 'restore_device_agreement_key',
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
      );
      db.upsertConversation(
        RemoteConversation(
          conversationId: 'conv_restore',
          title: 'Restored chat',
          type: 'DIRECT',
          lastActivitySequence: 2,
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
        ['acc_restore'],
      );
      db.saveMessage(
        RemoteMessage(
          messageId: 'msg_keep',
          conversationId: 'conv_restore',
          senderAccountId: 'acc_restore',
          senderDeviceId: 'device1',
          ciphertext: 'ciphertext_to_keep',
        ),
        1,
        1001,
        'DELIVERED',
      );
      db.saveMessage(
        RemoteMessage(
          messageId: 'msg_deleted',
          conversationId: 'conv_restore',
          senderAccountId: 'acc_restore',
          senderDeviceId: 'device1',
          ciphertext: 'ciphertext_to_remove',
        ),
        2,
        1002,
        'DELIVERED',
      );
      db.saveTombstone('msg_deleted', 'MESSAGE');

      final snapshot = db.exportBackupSnapshot();
      final restored = HelixRemoteDatabase(File(':memory:'));
      restored.initialize();
      addTearDown(restored.close);

      restored.restoreBackupSnapshot(snapshot);

      expect(
        restored.getAccount('acc_restore')!.username,
        equals('restore_user'),
      );
      expect(
        restored.getDevices('acc_restore').single.deviceName,
        equals('Restore Phone'),
      );
      final messages = restored.getMessages('conv_restore');
      expect(messages.length, equals(1));
      expect(messages.single['message_id'], equals('msg_keep'));
      expect(restored.isTombstoned('msg_deleted', 'MESSAGE'), isTrue);
    },
  );

  test('P6 group epoch keys persist and round-trip through backup', () {
    db.saveGroupEpochKey(
      groupId: 'group_secure',
      epoch: 0,
      keyId: 'gk_zero',
      keyMaterial: 'base64url_sender_key_seed',
      createdAt: 1000,
    );
    db.saveGroupEpochKey(
      groupId: 'group_secure',
      epoch: 1,
      keyId: 'gk_one',
      keyMaterial: 'base64url_sender_key_seed_rotated',
      createdAt: 2000,
    );

    expect(
      db.getGroupEpochKey('group_secure', 0)!['key_material'],
      equals('base64url_sender_key_seed'),
    );
    expect(db.getGroupEpochKeys('group_secure'), hasLength(2));

    final restored = HelixRemoteDatabase(File(':memory:'));
    restored.initialize();
    addTearDown(restored.close);
    restored.restoreBackupSnapshot(db.exportBackupSnapshot());

    expect(
      restored.getGroupEpochKey('group_secure', 1)!['key_id'],
      equals('gk_one'),
    );
  });

  test('P17 restore rejects unsupported snapshot versions atomically', () {
    final before = db.getConversations();
    expect(
      () => db.restoreBackupSnapshot('{"version": 99, "accounts": []}'),
      throwsUnsupportedError,
    );
    expect(db.getConversations(), equals(before));
  });

  test('P10 operational retention purges bounded completed rows only', () {
    final futureCutoff = DateTime.now().millisecondsSinceEpoch + 60000;

    db.enqueueOperation('op_done', 'send', '{}');
    db.updateOperationStatus('op_done', 'COMPLETED', 0);
    db.enqueueOperation('op_pending', 'send', '{}');
    db.saveTombstone('msg_old', 'MESSAGE');
    db.saveQuarantinedEvent(
      eventId: 'bad_event',
      serverSequence: 1,
      eventType: 'chat_message',
      rawPayload: '{}',
      failureReason: 'test',
    );

    final purged = db.purgeOperationalRecords(
      completedOperationsOlderThan: futureCutoff,
      tombstonesOlderThan: futureCutoff,
      quarantineOlderThan: futureCutoff,
    );

    expect(purged['pending_operations'], equals(1));
    expect(purged['tombstones'], equals(1));
    expect(purged['quarantine_events'], equals(1));
    expect(db.getOperationById('op_done'), isNull);
    expect(db.getOperationById('op_pending'), isNotNull);
  });
}

void _createPlaintextV6Database(File file, String marker) {
  final oldDb = sqlite.sqlite3.open(file.path);
  oldDb
    ..execute('''
      CREATE TABLE accounts (
        account_id TEXT PRIMARY KEY,
        username TEXT NOT NULL,
        identity_public_key TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        status TEXT NOT NULL
      );
    ''')
    ..execute('''
      INSERT INTO accounts VALUES (
        'acc_plain',
        '$marker',
        'identity_plain',
        3000,
        'Active'
      );
    ''')
    ..execute('PRAGMA user_version = 6;')
    ..close();
}

String _readPlaintextUsername(File file) {
  final raw = sqlite.sqlite3.open(file.path);
  try {
    return raw
            .select(
              "SELECT username FROM accounts WHERE account_id = 'acc_plain';",
            )
            .first['username']
        as String;
  } finally {
    raw.close();
  }
}

bool _opensWithoutKey(File file) {
  sqlite.Database? raw;
  try {
    raw = sqlite.sqlite3.open(file.path);
    raw.select('SELECT count(*) FROM sqlite_master;');
    return true;
  } catch (_) {
    return false;
  } finally {
    raw?.close();
  }
}

bool _hasPlaintextSqliteHeader(File file) {
  if (!file.existsSync() || file.lengthSync() < 16) {
    return false;
  }
  final handle = file.openSync()..setPositionSync(0);
  try {
    return ascii.decode(handle.readSync(16), allowInvalid: true) ==
        'SQLite format 3\u0000';
  } finally {
    handle.closeSync();
  }
}

bool _databaseFilesContain(File databaseFile, String marker) {
  final needle = utf8.encode(marker);
  for (final suffix in const ['', '-wal', '-shm']) {
    final file = File('${databaseFile.path}$suffix');
    if (file.existsSync() && _bytesContain(file.readAsBytesSync(), needle)) {
      return true;
    }
  }
  return false;
}

bool _bytesContain(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || haystack.length < needle.length) {
    return false;
  }
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var matches = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return true;
    }
  }
  return false;
}
