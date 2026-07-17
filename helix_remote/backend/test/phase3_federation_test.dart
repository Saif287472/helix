import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_backend/src/server_identity.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'test_registration.dart';

void main() {
  late FederationDirectoryServer directory;
  late BackendServer serverA;
  late BackendServer serverB;
  late ServerIdentity identityA;
  late ServerIdentity identityB;
  late int directoryPort;
  late int portA;
  late int portB;

  setUp(() async {
    directory = FederationDirectoryServer();
    await directory.start('127.0.0.1', 0);
    directoryPort = directory.httpServer!.port;
    final directoryUrl = 'http://127.0.0.1:$directoryPort';

    serverA = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_for_phase3_server_a',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
      federationDomain: 'a.test',
      federationDirectoryUrl: directoryUrl,
    );
    identityA = await ServerIdentity.loadOrCreate(serverA.db);
    serverA.serverIdentity = identityA;
    await serverA.start('127.0.0.1', 0);
    portA = serverA.httpServer!.port;

    serverB = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_for_phase3_server_b',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
      federationDomain: 'b.test',
      federationDirectoryUrl: directoryUrl,
    );
    identityB = await ServerIdentity.loadOrCreate(serverB.db);
    serverB.serverIdentity = identityB;
    await serverB.start('127.0.0.1', 0);
    portB = serverB.httpServer!.port;
  });

  tearDown(() async {
    await serverA.stop();
    await serverB.stop();
    await directory.stop();
  });

  test(
    'proxies remote prekeys and delivers a federated 1-on-1 message',
    () async {
      final client = HttpClient();
      try {
        final aliceMaterial = await registerTestAccount(
          client: client,
          host: '127.0.0.1',
          port: portA,
          accountId: 'alice',
          username: 'alice_user',
          deviceId: 'alice_device',
          deviceName: 'Alice Phone',
        );
        final aliceLogin = await loginTestAccount(
          client: client,
          host: '127.0.0.1',
          port: portA,
          accountId: 'alice',
          deviceId: 'alice_device',
          deviceSigningKeyPair: aliceMaterial.deviceSigningKeyPair,
        );
        final aliceToken = aliceLogin['token'] as String;

        final bobMaterial = await registerTestAccount(
          client: client,
          host: '127.0.0.1',
          port: portB,
          accountId: 'bob',
          username: 'bob_user',
          deviceId: 'bob_device',
          deviceName: 'Bob Phone',
        );
        final bobLogin = await loginTestAccount(
          client: client,
          host: '127.0.0.1',
          port: portB,
          accountId: 'bob',
          deviceId: 'bob_device',
          deviceSigningKeyPair: bobMaterial.deviceSigningKeyPair,
        );
        final bobToken = bobLogin['token'] as String;

        serverB.db.publishPrekeys(
          accountId: 'bob',
          deviceId: 'bob_device',
          signedPrekeyId: 7,
          signedPrekey: 'bob_signed_prekey',
          signature: 'bob_signed_prekey_signature',
          oneTimePrekeys: [
            {'key_id': 7001, 'public_key': 'bob_one_time_prekey'},
          ],
        );

        await _registerServer(
          server: serverA,
          identity: identityA,
          domain: 'a.test',
          address: 'http://127.0.0.1:$portA',
          directoryUrl: 'http://127.0.0.1:$directoryPort',
          users: ['alice@a.test'],
        );
        await _registerServer(
          server: serverB,
          identity: identityB,
          domain: 'b.test',
          address: 'http://127.0.0.1:$portB',
          directoryUrl: 'http://127.0.0.1:$directoryPort',
          users: ['bob@b.test'],
        );

        final remoteBundle = await _getJson(
          client,
          portA,
          '/api/v1/prekeys/bundle?account_id=bob@b.test',
          token: aliceToken,
        );
        expect(remoteBundle.statusCode, equals(200));
        final bundleBody =
            jsonDecode(remoteBundle.body) as Map<String, dynamic>;
        expect(bundleBody['qualified_account_id'], equals('bob@b.test'));
        final devices = bundleBody['devices'] as List<dynamic>;
        expect(devices, hasLength(1));
        expect(
          ((devices.first as Map<String, dynamic>)['signed_prekey']
              as Map<String, dynamic>)['key_id'],
          equals(7),
        );

        final createConversation = await _postJson(
          client,
          portA,
          '/api/v1/messages/conversations/create',
          {
            'conversation_id': 'conv_fed_1',
            'type': 'DIRECT',
            'members': ['alice', 'bob@b.test'],
          },
          token: aliceToken,
        );
        expect(createConversation.statusCode, equals(200));

        final send = await _postJson(client, portA, '/api/v1/messages/send', {
          'message_id': 'msg_fed_1',
          'conversation_id': 'conv_fed_1',
          'envelopes': [
            {
              'recipient_account_id': 'bob@b.test',
              'recipient_device_id': 'bob_device',
              'ciphertext': 'ciphertext_for_bob',
            },
          ],
        }, token: aliceToken);
        expect(send.statusCode, equals(200), reason: send.body);
        final sendBody = jsonDecode(send.body) as Map<String, dynamic>;
        expect(sendBody['federated_envelopes_count'], equals(1));

        final events = await _getJson(
          client,
          portB,
          '/api/v1/messages/device-events?since_sequence=0',
          token: bobToken,
        );
        expect(events.statusCode, equals(200));
        final eventsBody = jsonDecode(events.body) as Map<String, dynamic>;
        final event =
            (eventsBody['events'] as List<dynamic>).single
                as Map<String, dynamic>;
        expect(event['type'], equals('chat_message'));
        final payload = event['payload'] as Map<String, dynamic>;
        expect(payload['message_id'], equals('msg_fed_1'));
        expect(payload['sender_account_id'], equals('alice@a.test'));
        expect(payload['recipient_account_id'], equals('bob'));
        expect(payload['ciphertext'], equals('ciphertext_for_bob'));
        expect(payload['federated'], isTrue);
      } finally {
        client.close(force: true);
      }
    },
  );
}

Future<void> _registerServer({
  required BackendServer server,
  required ServerIdentity identity,
  required String domain,
  required String address,
  required String directoryUrl,
  required List<String> users,
}) async {
  final client = FederationClient(
    db: server.db,
    identity: identity,
    directoryUrl: directoryUrl,
  );
  await client.registerDirectory(
    domain: domain,
    address: address,
    users: users,
  );
}

Future<_Response> _getJson(
  HttpClient client,
  int port,
  String path, {
  String? token,
}) async {
  final request = await client.get('127.0.0.1', port, path);
  if (token != null) {
    request.headers.set('Authorization', 'Bearer $token');
  }
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  return _Response(response.statusCode, body);
}

Future<_Response> _postJson(
  HttpClient client,
  int port,
  String path,
  Map<String, dynamic> data, {
  String? token,
}) async {
  final request = await client.post('127.0.0.1', port, path);
  request.headers.contentType = ContentType.json;
  if (token != null) {
    request.headers.set('Authorization', 'Bearer $token');
  }
  request.write(jsonEncode(data));
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  return _Response(response.statusCode, body);
}

class _Response {
  const _Response(this.statusCode, this.body);

  final int statusCode;
  final String body;
}
