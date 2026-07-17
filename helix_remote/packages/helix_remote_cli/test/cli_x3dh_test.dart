import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:helix_remote_cli/helix_remote_cli.dart';
import 'package:helix_remote_crypto/helix_remote_crypto.dart';
import 'package:helix_remote_backend/src/server_impl.dart';
import 'package:helix_remote_domain/models.dart';

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
    tempLogFile = File('test_server.log');
    final sqliteDb = sqlite.sqlite3.openInMemory();
    server = BackendServer.create(
      sqliteDb: sqliteDb,
      jwtSecret: 'test_jwt_secret_min_32_bytes_x3dh_integration_testing',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
      wsReconnectsPerMinute: 2,
      logFilePath: tempLogFile.path,
    );
    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;

    // 2. Set up clients files
    aliceDbFile = File('alice_db.db');
    if (aliceDbFile.existsSync()) aliceDbFile.deleteSync();
    aliceKeyFile = File('alice_keys.json');
    if (aliceKeyFile.existsSync()) aliceKeyFile.deleteSync();

    bobDbFile = File('bob_db.db');
    if (bobDbFile.existsSync()) bobDbFile.deleteSync();
    bobKeyFile = File('bob_keys.json');
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

  test('Prekey Upload, Bundle Query, and X3DH Session Initiation E2E', () async {
    // 1. Register Alice and Bob
    await aliceClient.register(
      restClient: aliceRestClient,
      accountId: 'alice_acc_1',
      username: 'alice',
      deviceId: 'device_cli_alice',
      deviceName: 'Alice Client',
    );

    await bobClient.register(
      restClient: bobRestClient,
      accountId: 'bob_acc_1',
      username: 'bob',
      deviceId: 'device_cli_bob',
      deviceName: 'Bob Client',
    );

    // 2. Log in Alice and Bob
    await aliceClient.login(restClient: aliceRestClient);
    await bobClient.login(restClient: bobRestClient);

    // Verify auth token is retrieved
    expect(aliceRestClient.accessToken, isNotNull);
    expect(bobRestClient.accessToken, isNotNull);

    // 3. Bob generates and publishes prekeys (Signed Prekey & One-Time Prekeys)
    await bobClient.publishPrekeys(restClient: bobRestClient, oneTimePrekeysCount: 5);

    // Verify Bob's prekeys are stored locally
    final bobPrekeys = bobClient.db.getLocalPrekeys(deviceId: 'device_cli_bob');
    expect(bobPrekeys, isNotEmpty);
    expect(bobPrekeys.where((k) => k['role'] == 'one_time_prekey').length, equals(5));

    // 4. Manually insert each other's device profiles in local DB (simulating directory lookup/sync)
    final aliceIdPub = await aliceClient.storage.readKey('identity_public');
    final aliceDevSignPub = await aliceClient.storage.readKey('device_signing_public');
    final aliceDevAgreePub = await aliceClient.storage.readKey('device_public');

    final bobIdPub = await bobClient.storage.readKey('identity_public');
    final bobDevSignPub = await bobClient.storage.readKey('device_signing_public');
    final bobDevAgreePub = await bobClient.storage.readKey('device_public');

    // Bob records Alice's device
    bobClient.db.upsertAccount(RemoteAccount(
      accountId: 'alice_acc_1',
      username: 'alice',
      identityPublicKey: aliceIdPub!,
      createdAt: DateTime.now(),
    ));
    bobClient.db.upsertDevice('alice_acc_1', RemoteDevice(
      deviceId: 'device_cli_alice',
      deviceName: 'Alice Client',
      deviceSigningPublicKey: aliceDevSignPub!,
      deviceAgreementPublicKey: aliceDevAgreePub!,
      createdAt: DateTime.now(),
    ));

    // Alice records Bob's device
    aliceClient.db.upsertAccount(RemoteAccount(
      accountId: 'bob_acc_1',
      username: 'bob',
      identityPublicKey: bobIdPub!,
      createdAt: DateTime.now(),
    ));
    aliceClient.db.upsertDevice('bob_acc_1', RemoteDevice(
      deviceId: 'device_cli_bob',
      deviceName: 'Bob Client',
      deviceSigningPublicKey: bobDevSignPub!,
      deviceAgreementPublicKey: bobDevAgreePub!,
      createdAt: DateTime.now(),
    ));

    // 5. Alice queries Bob's bundle and initiates E2EE session
    final aliceSession = await aliceClient.initiateSessionWithPeer(
      restClient: aliceRestClient,
      peerAccountId: 'bob_acc_1',
      conversationId: 'conv_123',
    );

    // Retrieve the session parameters saved during X3DH initiation
    final sessionId = 'direct:conv_123:bob_acc_1:device_cli_bob';
    final epPublicBase64 = await aliceClient.storage.readKey('session_init_ephemeral_$sessionId');
    final otkIdStr = await aliceClient.storage.readKey('session_init_otk_id_$sessionId');
    final otkId = otkIdStr != null ? int.parse(otkIdStr) : null;

    expect(epPublicBase64, isNotNull);
    expect(otkId, isNotNull);

    // Alice encrypts a message
    final plaintext = Uint8List.fromList('Hi Bob, this is Alice!'.codeUnits);
    final ciphertext = await aliceSession.encrypt(plaintext);

    // 6. Bob reconstructs the session and decrypts Alice's message
    final bobSession = await bobClient.receiveSessionFromPeer(
      peerAccountId: 'alice_acc_1',
      peerDeviceId: 'device_cli_alice',
      conversationId: 'conv_123',
      aliceEphemeralPublicBase64: epPublicBase64!,
      bobOneTimePrekeyId: otkId,
    );

    final decrypted = await bobSession.decrypt(ciphertext);
    expect(decrypted, equals(plaintext));

    // Verify Bob can encrypt back and Alice decrypts
    final bobReply = Uint8List.fromList('Hello Alice! Received your secure message.'.codeUnits);
    final replyCiphertext = await bobSession.encrypt(bobReply);

    final aliceDecrypted = await aliceSession.decrypt(replyCiphertext);
    expect(aliceDecrypted, equals(bobReply));
  });
}
