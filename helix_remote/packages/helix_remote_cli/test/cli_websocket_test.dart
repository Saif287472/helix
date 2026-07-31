import 'dart:io';
import 'package:test/test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:helix_remote_cli/helix_remote_cli.dart';
import 'package:helix_remote_backend/src/server_impl.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/invite_codes.dart';
import 'package:helix_remote_domain/models.dart';

String _seedInvite(BackendServer server) {
  final code = generateInviteCode();
  final now = DateTime.now().millisecondsSinceEpoch;
  server.db.createInviteCredential(
    inviteId: generateInviteId(),
    inviteCodeHash: hashInviteCode(code),
    serverAddress: 'https://test.local',
    issuerType: 'ADMIN',
    issuerLabel: 'cli-websocket-test-harness',
    createdAt: now,
    expiresAt: now + const Duration(days: 7).inMilliseconds,
  );
  return code;
}

void main() {
  late BackendServer server;
  late int port;
  late File aliceDbFile;
  late File aliceKeyFile;
  late File bobDbFile;
  late File bobKeyFile;
  late File tempLogFile;

  late HelixCliClient aliceClient;
  late HelixCliClient bobClient;

  late CliRestClient aliceRestClient;
  late CliRestClient bobRestClient;

  setUp(() async {
    // 1. Spin up backend server
    tempLogFile = File('test_ws_server.log');
    final sqliteDb = sqlite.sqlite3.openInMemory();
    server = BackendServer.create(
      sqliteDb: sqliteDb,
      jwtSecret: 'test_jwt_secret_min_32_bytes_websocket_integration_testing',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
      wsReconnectsPerMinute: 2,
      logFilePath: tempLogFile.path,
    );
    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;

    // 2. Set up clients files
    aliceDbFile = File('alice_ws_db.db');
    if (aliceDbFile.existsSync()) aliceDbFile.deleteSync();
    aliceKeyFile = File('alice_ws_keys.json');
    if (aliceKeyFile.existsSync()) aliceKeyFile.deleteSync();

    bobDbFile = File('bob_ws_db.db');
    if (bobDbFile.existsSync()) bobDbFile.deleteSync();
    bobKeyFile = File('bob_ws_keys.json');
    if (bobKeyFile.existsSync()) bobKeyFile.deleteSync();

    aliceClient = HelixCliClient(dbFile: aliceDbFile, keyFile: aliceKeyFile);
    bobClient = HelixCliClient(dbFile: bobDbFile, keyFile: bobKeyFile);

    aliceRestClient = CliRestClient(baseUrl: 'http://127.0.0.1:$port');
    bobRestClient = CliRestClient(baseUrl: 'http://127.0.0.1:$port');
  });

  tearDown(() async {
    aliceClient.close();
    bobClient.close();
    await server.stop();

    if (aliceDbFile.existsSync()) aliceDbFile.deleteSync();
    if (aliceKeyFile.existsSync()) aliceKeyFile.deleteSync();
    if (bobDbFile.existsSync()) bobDbFile.deleteSync();
    if (bobKeyFile.existsSync()) bobKeyFile.deleteSync();
    if (tempLogFile.existsSync()) tempLogFile.deleteSync();
  });

  test(
    'Real-time Message Exchange over WebSockets and Outbox Processing',
    () async {
      // 1. Register Alice and Bob
      const alicePhoneNumber = '+15550000001';
      const bobPhoneNumber = '+15550000002';
      final salt =
          (await aliceRestClient.fetchDiscoverySalt())['salt'] as String;
      final aliceOtp = await aliceRestClient.requestPhoneOtp(
        phoneHash: cliPhoneHash(salt, alicePhoneNumber),
      );
      await aliceClient.register(
        restClient: aliceRestClient,
        accountId: 'alice_acc_1',
        phoneNumber: alicePhoneNumber,
        displayName: 'Alice',
        otpCode: aliceOtp['code'] as String,
        inviteCode: _seedInvite(server),
        deviceId: 'device_cli_alice',
        deviceName: 'Alice Client',
      );

      final bobOtp = await bobRestClient.requestPhoneOtp(
        phoneHash: cliPhoneHash(salt, bobPhoneNumber),
      );
      await bobClient.register(
        restClient: bobRestClient,
        accountId: 'bob_acc_1',
        phoneNumber: bobPhoneNumber,
        displayName: 'Bob',
        otpCode: bobOtp['code'] as String,
        inviteCode: _seedInvite(server),
        deviceId: 'device_cli_bob',
        deviceName: 'Bob Client',
      );

      // 2. Log in Alice and Bob
      await aliceClient.login(restClient: aliceRestClient);
      await bobClient.login(restClient: bobRestClient);

      // 3. Alice and Bob publish prekeys
      await aliceClient.publishPrekeys(
        restClient: aliceRestClient,
        oneTimePrekeysCount: 5,
      );
      await bobClient.publishPrekeys(
        restClient: bobRestClient,
        oneTimePrekeysCount: 5,
      );

      // 4. Manually insert each other's device profiles in local DB (simulating directory lookup/sync)
      final aliceIdPub = await aliceClient.storage.readKey('identity_public');
      final aliceDevSignPub = await aliceClient.storage.readKey(
        'device_signing_public',
      );
      final aliceDevAgreePub = await aliceClient.storage.readKey(
        'device_public',
      );

      final bobIdPub = await bobClient.storage.readKey('identity_public');
      final bobDevSignPub = await bobClient.storage.readKey(
        'device_signing_public',
      );
      final bobDevAgreePub = await bobClient.storage.readKey('device_public');

      // Bob records Alice's device
      bobClient.db.upsertAccount(
        RemoteAccount(
          accountId: 'alice_acc_1',
          identityPublicKey: aliceIdPub!,
          createdAt: DateTime.now(),
        ),
      );
      bobClient.db.upsertDevice(
        'alice_acc_1',
        RemoteDevice(
          deviceId: 'device_cli_alice',
          deviceName: 'Alice Client',
          deviceSigningPublicKey: aliceDevSignPub!,
          deviceAgreementPublicKey: aliceDevAgreePub!,
          createdAt: DateTime.now(),
        ),
      );

      // Alice records Bob's device
      aliceClient.db.upsertAccount(
        RemoteAccount(
          accountId: 'bob_acc_1',
          identityPublicKey: bobIdPub!,
          createdAt: DateTime.now(),
        ),
      );
      aliceClient.db.upsertDevice(
        'bob_acc_1',
        RemoteDevice(
          deviceId: 'device_cli_bob',
          deviceName: 'Bob Client',
          deviceSigningPublicKey: bobDevSignPub!,
          deviceAgreementPublicKey: bobDevAgreePub!,
          createdAt: DateTime.now(),
        ),
      );

      // 5. Create the conversation in both clients' databases (local prerequisite) and server
      await aliceRestClient.createConversation(
        conversationId: 'conv_123',
        type: 'DIRECT',
        title: 'Alice & Bob',
        members: ['alice_acc_1', 'bob_acc_1'],
      );

      final conv = RemoteConversation(
        conversationId: 'conv_123',
        type: 'OneToOne',
        title: 'Alice & Bob',
        createdAt: DateTime.now(),
        lastActivitySequence: 1,
      );
      aliceClient.db.upsertConversation(conv, ['alice_acc_1', 'bob_acc_1']);
      bobClient.db.upsertConversation(conv, ['alice_acc_1', 'bob_acc_1']);

      aliceClient.db.saveMessage(
        const RemoteMessage(
          messageId: 'seed',
          conversationId: 'conv_123',
          senderAccountId: 'system',
          senderDeviceId: 'system',
          ciphertext: '',
        ),
        1,
        DateTime.now().millisecondsSinceEpoch,
        'SENT',
      );
      bobClient.db.saveMessage(
        const RemoteMessage(
          messageId: 'seed',
          conversationId: 'conv_123',
          senderAccountId: 'system',
          senderDeviceId: 'system',
          ciphertext: '',
        ),
        1,
        DateTime.now().millisecondsSinceEpoch,
        'SENT',
      );

      // 6. Connect WebSockets for both clients
      final aliceReceived = <String, String>{};
      final bobReceived = <String, String>{};

      await aliceClient.connectWebSocket(
        restClient: aliceRestClient,
        onMessageReceived: (messageId, plaintext) {
          aliceReceived[messageId] = plaintext;
        },
      );

      await bobClient.connectWebSocket(
        restClient: bobRestClient,
        onMessageReceived: (messageId, plaintext) {
          bobReceived[messageId] = plaintext;
        },
      );

      // 7. Alice enqueues a message
      aliceClient.enqueueSendMessage(
        messageId: 'msg_001',
        conversationId: 'conv_123',
        peerAccountId: 'bob_acc_1',
        plaintext: 'Hello Bob! Sending this over WebSocket.',
      );

      // Alice outbox worker runs
      await aliceClient.processOutbox(aliceRestClient);

      // Wait for WebSocket event delivery to Bob
      await Future<void>.delayed(const Duration(seconds: 1));

      // Verify Bob received and decrypted the message!
      expect(
        bobReceived['msg_001'],
        equals('Hello Bob! Sending this over WebSocket.'),
      );

      // Verify Bob has the message saved locally
      final bobLocalMsg = bobClient.db.getMessageById('msg_001');
      expect(bobLocalMsg, isNotNull);
      expect(bobLocalMsg!['status'], equals('RECEIVED'));

      // 8. Bob replies back
      bobClient.enqueueSendMessage(
        messageId: 'msg_002',
        conversationId: 'conv_123',
        peerAccountId: 'alice_acc_1',
        plaintext: 'Hi Alice! Received and decrypted successfully.',
      );

      // Bob outbox worker runs
      await bobClient.processOutbox(bobRestClient);

      // Wait for WebSocket event delivery to Alice
      await Future<void>.delayed(const Duration(seconds: 1));

      // Verify Alice received and decrypted the reply!
      expect(
        aliceReceived['msg_002'],
        equals('Hi Alice! Received and decrypted successfully.'),
      );

      // Verify Alice has Bob's reply saved locally
      final aliceLocalMsg = aliceClient.db.getMessageById('msg_002');
      expect(aliceLocalMsg, isNotNull);
      expect(aliceLocalMsg!['status'], equals('RECEIVED'));
    },
  );
}
