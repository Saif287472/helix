import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:helix_remote_backend/helix_remote_backend.dart';

import 'test_registration.dart';

final ed25519 = crypto.Ed25519();

String _b64u(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

class _Response {
  final int statusCode;
  final String body;
  _Response(this.statusCode, this.body);
}

Future<_Response> _postJson(
  String host,
  int port,
  String path,
  Map<String, dynamic> data, {
  String? token,
}) async {
  final client = HttpClient();
  try {
    final request = await client.post(host, port, path);
    request.headers.contentType = ContentType.json;
    if (token != null) request.headers.set('Authorization', 'Bearer $token');
    request.write(jsonEncode(data));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    return _Response(response.statusCode, body);
  } finally {
    client.close();
  }
}

Future<_Response> _getJson(
  String host,
  int port,
  String path, {
  String? token,
}) async {
  final client = HttpClient();
  try {
    final request = await client.get(host, port, path);
    if (token != null) request.headers.set('Authorization', 'Bearer $token');
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    return _Response(response.statusCode, body);
  } finally {
    client.close();
  }
}

Future<String> _registerAndLogin(
  int port,
  String accountId,
  String username,
  String deviceId,
  crypto.SimpleKeyPair ignoredKeyPair,
  crypto.SimplePublicKey ignoredPubKey,
) async {
  final material = await createTestRegistrationMaterial(
    accountId: accountId,
    username: username,
    deviceId: deviceId,
    deviceName: '$username phone',
  );
  await _postJson('127.0.0.1', port, '/api/v1/accounts/register', {
    ...registrationBody(
      accountId: accountId,
      username: username,
      deviceId: deviceId,
      deviceName: '$username phone',
      material: material,
    ),
  });

  return _loginDevice(port, accountId, deviceId, material.deviceSigningKeyPair);
}

Future<String> _loginDevice(
  int port,
  String accountId,
  String deviceId,
  crypto.SimpleKeyPair keyPair,
) async {
  final challengeRes = await _getJson(
    '127.0.0.1',
    port,
    '/api/v1/accounts/challenge?account_id=$accountId&device_id=$deviceId',
  );
  final challengeBody = jsonDecode(challengeRes.body) as Map<String, dynamic>;
  final challenge = challengeBody['challenge'] as String;

  final sig = await ed25519.sign(utf8.encode(challenge), keyPair: keyPair);
  final sigStr = _b64u(sig.bytes);

  final loginRes = await _postJson(
    '127.0.0.1',
    port,
    '/api/v1/accounts/login',
    {'account_id': accountId, 'device_id': deviceId, 'signature': sigStr},
  );
  final loginBody = jsonDecode(loginRes.body) as Map<String, dynamic>;
  return loginBody['token'] as String;
}

void main() {
  late BackendServer server;
  late int port;

  setUp(() async {
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_for_device_events',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 100,
    );
    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;
  });

  tearDown(() async {
    await server.stop();
  });

  test(
    'device_events table stores and retrieves events in order',
    () async {
      final aliceKeys = await ed25519.newKeyPair();
      final alicePub = await aliceKeys.extractPublicKey();
      final bobKeys = await ed25519.newKeyPair();
      final bobPub = await bobKeys.extractPublicKey();

      final aliceToken = await _registerAndLogin(
        port,
        'alice_dev',
        'alice_user',
        'alice_device_1',
        aliceKeys,
        alicePub,
      );
      await _registerAndLogin(
        port,
        'bob_dev',
        'bob_user',
        'bob_device_1',
        bobKeys,
        bobPub,
      );

      server.rateLimiter.reset('127.0.0.1');

      // Create a conversation with both members
      await _postJson(
        '127.0.0.1',
        port,
        '/api/v1/messages/conversations/create',
        {
          'conversation_id': 'conv_dm',
          'type': 'DIRECT',
          'members': ['alice_dev', 'bob_dev'],
        },
        token: aliceToken,
      );

      server.rateLimiter.reset('127.0.0.1');

      await _postJson('127.0.0.1', port, '/api/v1/messages/send', {
        'message_id': 'msg_1',
        'conversation_id': 'conv_dm',
        'envelopes': [
          {
            'recipient_device_id': 'bob_device_1',
            'ciphertext': 'encrypted_payload',
          },
        ],
      }, token: aliceToken);

      final bobEvents = server.db.getDeviceEvents('bob_device_1', 0);
      expect(bobEvents, hasLength(1));
      expect(bobEvents.first['event_type'], equals('chat_message'));

      final bobSeqAfter = server.db.getLastDeviceSequence('bob_device_1');
      expect(bobSeqAfter, equals(1));

      final aliceEvents = server.db.getDeviceEvents('alice_device_1', 0);
      expect(aliceEvents, isEmpty);

      server.rateLimiter.reset('127.0.0.1');

      await _postJson('127.0.0.1', port, '/api/v1/messages/send', {
        'message_id': 'msg_2',
        'conversation_id': 'conv_dm',
        'envelopes': [
          {
            'recipient_device_id': 'bob_device_1',
            'ciphertext': 'encrypted_payload_2',
          },
        ],
      }, token: aliceToken);

      final bobEvents2 = server.db.getDeviceEvents('bob_device_1', 0);
      expect(bobEvents2, hasLength(2));

      final bobEventsSince1 = server.db.getDeviceEvents('bob_device_1', 1);
      expect(bobEventsSince1, hasLength(1));
      expect(bobEventsSince1.first['device_sequence'], equals(2));
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );

  test(
    'device-events REST endpoint returns proper envelope format',
    () async {
      final aliceKeys = await ed25519.newKeyPair();
      final alicePub = await aliceKeys.extractPublicKey();
      final bobKeys = await ed25519.newKeyPair();
      final bobPub = await bobKeys.extractPublicKey();

      final aliceToken = await _registerAndLogin(
        port,
        'alice_rest',
        'alice_rest_user',
        'alice_device_1',
        aliceKeys,
        alicePub,
      );
      final bobToken = await _registerAndLogin(
        port,
        'bob_rest',
        'bob_rest_user',
        'bob_device_1',
        bobKeys,
        bobPub,
      );

      server.rateLimiter.reset('127.0.0.1');

      await _postJson(
        '127.0.0.1',
        port,
        '/api/v1/messages/conversations/create',
        {
          'conversation_id': 'conv_test',
          'type': 'DIRECT',
          'members': ['alice_rest', 'bob_rest'],
        },
        token: aliceToken,
      );

      server.rateLimiter.reset('127.0.0.1');

      await _postJson('127.0.0.1', port, '/api/v1/messages/send', {
        'message_id': 'msg_abc',
        'conversation_id': 'conv_test',
        'envelopes': [
          {
            'recipient_device_id': 'bob_device_1',
            'ciphertext': 'bob_ciphertext',
          },
        ],
      }, token: aliceToken);

      server.rateLimiter.reset('127.0.0.1');

      final eventsRes = await _getJson(
        '127.0.0.1',
        port,
        '/api/v1/messages/device-events?since_sequence=0',
        token: bobToken,
      );
      expect(eventsRes.statusCode, equals(200));
      final body = jsonDecode(eventsRes.body) as Map<String, dynamic>;
      expect(body['events'], hasLength(1));

      final event =
          (body['events'] as List<dynamic>).first as Map<String, dynamic>;
      expect(event['event_id'], startsWith('evt_msg_abc_'));
      expect(event['schema_version'], equals(1));
      expect(event['type'], equals('chat_message'));
      expect(event['timestamp'], isNotNull);
      expect(event['server_sequence'], isNotNull);
      expect(
        (event['payload'] as Map<String, dynamic>)['message_id'],
        equals('msg_abc'),
      );
      expect(
        (event['payload'] as Map<String, dynamic>)['ciphertext'],
        equals('bob_ciphertext'),
      );
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );
}
