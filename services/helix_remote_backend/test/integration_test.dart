import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:helix_remote_backend/helix_remote_backend.dart';

void main() {
  late BackendServer server;
  late int port;
  final ed25519 = crypto.Ed25519();

  setUp(() async {
    // Port 0 selects a random free port
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_for_integration_testing_only',
      rateLimitMaxTokens: 5.0, // small rate limit for testing rate limits
      rateLimitRefillRate: 1.0,
    );
    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;
  });

  tearDown(() async {
    await server.stop();
  });

  test(
    'Complete Registration, Ed25519 Challenge Auth, Prekeys and Message Relay Flow',
    () async {
      final client = HttpClient();

      // 1. Generate keys for Alice & Bob
      final aliceKeyPair = await ed25519.newKeyPair();
      final alicePubKey = await aliceKeyPair.extractPublicKey();
      final alicePubKeyStr = base64UrlEncode(alicePubKey.bytes);

      final bobKeyPair = await ed25519.newKeyPair();
      final bobPubKey = await bobKeyPair.extractPublicKey();
      final bobPubKeyStr = base64UrlEncode(bobPubKey.bytes);

      // 2. Register Alice and Bob
      final regAliceRes = await _postJson(
        client,
        'localhost',
        port,
        '/api/v1/accounts/register',
        {
          'account_id': 'alice',
          'username': 'alice_user',
          'identity_public_key': 'alice_identity_public_key',
          'device_id': 'alice_device_1',
          'device_public_key': alicePubKeyStr,
          'device_name': 'Alice Phone',
        },
      );
      expect(regAliceRes.statusCode, equals(200));

      server.rateLimiter.reset('127.0.0.1');

      final regBobRes = await _postJson(
        client,
        'localhost',
        port,
        '/api/v1/accounts/register',
        {
          'account_id': 'bob',
          'username': 'bob_user',
          'identity_public_key': 'bob_identity_public_key',
          'device_id': 'bob_device_1',
          'device_public_key': bobPubKeyStr,
          'device_name': 'Bob Phone',
        },
      );
      expect(regBobRes.statusCode, equals(200));

      // 3. Challenge Login for Alice
      final challengeAliceRes = await _getJson(
        client,
        'localhost',
        port,
        '/api/v1/accounts/challenge?account_id=alice&device_id=alice_device_1',
      );
      expect(challengeAliceRes.statusCode, equals(200));
      final challengeAliceBody =
          jsonDecode(challengeAliceRes.body) as Map<String, dynamic>;
      final aliceChallenge = challengeAliceBody['challenge'] as String;

      // Sign challenge
      final aliceSig = await ed25519.sign(
        utf8.encode(aliceChallenge),
        keyPair: aliceKeyPair,
      );
      final aliceSigStr = base64UrlEncode(aliceSig.bytes);

      final loginAliceRes = await _postJson(
        client,
        'localhost',
        port,
        '/api/v1/accounts/login',
        {
          'account_id': 'alice',
          'device_id': 'alice_device_1',
          'signature': aliceSigStr,
        },
      );
      expect(loginAliceRes.statusCode, equals(200));
      final loginAliceBody =
          jsonDecode(loginAliceRes.body) as Map<String, dynamic>;
      final aliceToken = loginAliceBody['token'] as String;

      server.rateLimiter.reset('127.0.0.1');

      // 4. Challenge Login for Bob
      final challengeBobRes = await _getJson(
        client,
        'localhost',
        port,
        '/api/v1/accounts/challenge?account_id=bob&device_id=bob_device_1',
      );
      expect(challengeBobRes.statusCode, equals(200));
      final challengeBobBody =
          jsonDecode(challengeBobRes.body) as Map<String, dynamic>;
      final bobChallenge = challengeBobBody['challenge'] as String;

      // Sign challenge
      final bobSig = await ed25519.sign(
        utf8.encode(bobChallenge),
        keyPair: bobKeyPair,
      );
      final bobSigStr = base64UrlEncode(bobSig.bytes);

      final loginBobRes = await _postJson(
        client,
        'localhost',
        port,
        '/api/v1/accounts/login',
        {
          'account_id': 'bob',
          'device_id': 'bob_device_1',
          'signature': bobSigStr,
        },
      );
      expect(loginBobRes.statusCode, equals(200));
      final loginBobBody = jsonDecode(loginBobRes.body) as Map<String, dynamic>;
      final bobToken = loginBobBody['token'] as String;

      // 5. Verify Authenticated Route (List Devices)
      server.rateLimiter.reset('127.0.0.1');
      final devicesRes = await _getJson(
        client,
        'localhost',
        port,
        '/api/v1/accounts/devices',
        token: aliceToken,
      );
      expect(devicesRes.statusCode, equals(200));
      final devicesBody = jsonDecode(devicesRes.body) as Map<String, dynamic>;
      final devicesList = devicesBody['devices'] as List;
      expect((devicesList.first as Map<String, dynamic>)['device_id'], equals('alice_device_1'));

      // 6. Bob Publishes Prekeys
      server.rateLimiter.reset('127.0.0.1');
      final publishPrekeysRes = await _postJson(
        client,
        'localhost',
        port,
        '/api/v1/prekeys/publish',
        {
          'signed_prekey_id': 42,
          'signed_prekey': 'bob_signed_prekey_key_material',
          'signature': 'bob_signed_prekey_signature_material',
          'one_time_prekeys': [
            {'key_id': 1001, 'public_key': 'bob_otk_1001'},
            {'key_id': 1002, 'public_key': 'bob_otk_1002'},
          ],
        },
        token: bobToken,
      );
      expect(publishPrekeysRes.statusCode, equals(200));

      // 7. Alice Fetches Bob's Prekey Bundle (Verify OTK atomic retrieval & deletion)
      server.rateLimiter.reset('127.0.0.1');
      final bundleRes1 = await _getJson(
        client,
        'localhost',
        port,
        '/api/v1/prekeys/bundle?account_id=bob',
        token: aliceToken,
      );
      expect(bundleRes1.statusCode, equals(200));
      final bundle1 = jsonDecode(bundleRes1.body) as Map<String, dynamic>;
      final bobDevices1 = bundle1['devices'] as List;
      expect(bobDevices1.length, equals(1));
      final bobDev1 = bobDevices1.first as Map<String, dynamic>;
      expect((bobDev1['signed_prekey'] as Map<String, dynamic>)['key_id'], equals(42));
      expect((bobDev1['one_time_prekey'] as Map<String, dynamic>)['key_id'], equals(1001));

      // Fetch bundle again - bob_otk_1001 should be consumed, returning bob_otk_1002
      final bundleRes2 = await _getJson(
        client,
        'localhost',
        port,
        '/api/v1/prekeys/bundle?account_id=bob',
        token: aliceToken,
      );
      expect(bundleRes2.statusCode, equals(200));
      final bundle2 = jsonDecode(bundleRes2.body) as Map<String, dynamic>;
      final bobDevices2 = bundle2['devices'] as List;
      final bobDev2 = bobDevices2.first as Map<String, dynamic>;
      expect((bobDev2['one_time_prekey'] as Map<String, dynamic>)['key_id'], equals(1002));

      // Fetch bundle again - both OTKs consumed, should return null for one_time_prekey
      server.rateLimiter.reset('127.0.0.1');
      final bundleRes3 = await _getJson(
        client,
        'localhost',
        port,
        '/api/v1/prekeys/bundle?account_id=bob',
        token: aliceToken,
      );
      expect(bundleRes3.statusCode, equals(200));
      final bundle3 = jsonDecode(bundleRes3.body) as Map<String, dynamic>;
      final bobDevices3 = bundle3['devices'] as List;
      final bobDev3 = bobDevices3.first as Map<String, dynamic>;
      expect(bobDev3['one_time_prekey'], isNull);

      // 8. Create Conversation & Send Message
      server.rateLimiter.reset('127.0.0.1');
      final createConvRes = await _postJson(
        client,
        'localhost',
        port,
        '/api/v1/messages/conversations/create',
        {
          'conversation_id': 'conv_123',
          'type': 'DIRECT',
          'members': ['alice', 'bob'],
        },
        token: aliceToken,
      );
      expect(createConvRes.statusCode, equals(200));

      // Bob connects to WebSocket to receive messages in real time
      final bobWs = await WebSocket.connect(
        'ws://localhost:$port/api/v1/ws?token=$bobToken',
      );
      final wsMessages = <Map<String, dynamic>>[];
      final wsDone = bobWs.listen((data) {
        wsMessages.add(jsonDecode(data as String) as Map<String, dynamic>);
      });

      // Give websocket connection a moment to map
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Alice sends E2EE message envelope
      server.rateLimiter.reset('127.0.0.1');
      final sendMsgRes = await _postJson(
        client,
        'localhost',
        port,
        '/api/v1/messages/send',
        {
          'message_id': 'msg_abc',
          'conversation_id': 'conv_123',
          'envelopes': [
            {
              'recipient_device_id': 'bob_device_1',
              'ciphertext':
                  'alice_encrypted_ciphertext_envelope_for_bob_device_1',
            },
          ],
        },
        token: aliceToken,
      );
      expect(sendMsgRes.statusCode, equals(200));
      final sendMsgBody = jsonDecode(sendMsgRes.body) as Map<String, dynamic>;
      expect(sendMsgBody['sequence'], equals(1));

      // Wait for WebSocket relay
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(wsMessages.length, equals(1));
      final relayedMsg = wsMessages.first;
      expect(relayedMsg['message_id'], equals('msg_abc'));
      expect(
        relayedMsg['ciphertext'],
        equals('alice_encrypted_ciphertext_envelope_for_bob_device_1'),
      );

      // Bob acknowledges message sequence
      bobWs.add(
        jsonEncode({
          'type': 'ack',
          'conversation_id': 'conv_123',
          'sequence': 1,
        }),
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Check that Bob's sync cursor has been updated in DB
      final cursors = server.db.getSyncCursors('bob', 'bob_device_1');
      expect(cursors.length, equals(1));
      expect(cursors.first['conversation_id'], equals('conv_123'));
      expect(cursors.first['last_sequence'], equals(1));

      await bobWs.close();
      await wsDone.asFuture();
      client.close();
    },
  );

  test('Token Bucket Rate Limiting Throttling', () async {
    final client = HttpClient();

    // Trigger rate limits (limiter is initialized with capacity of 5.0)
    for (int i = 0; i < 5; i++) {
      final res = await _getJson(
        client,
        'localhost',
        port,
        '/api/v1/accounts/challenge?account_id=alice&device_id=dev',
      );
      expect(res.statusCode, equals(200));
    }

    // 6th request should fail with 429 Too Many Requests
    final limitRes = await _getJson(
      client,
      'localhost',
      port,
      '/api/v1/accounts/challenge?account_id=alice&device_id=dev',
    );
    expect(limitRes.statusCode, equals(429));

    client.close();
  });
}

// HTTP request helpers
class _Response {
  final int statusCode;
  final String body;
  _Response(this.statusCode, this.body);
}

Future<_Response> _postJson(
  HttpClient client,
  String host,
  int port,
  String path,
  Map<String, dynamic> data, {
  String? token,
}) async {
  final request = await client.post(host, port, path);
  request.headers.contentType = ContentType.json;
  if (token != null) {
    request.headers.set('Authorization', 'Bearer $token');
  }
  request.write(jsonEncode(data));
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  return _Response(response.statusCode, body);
}

Future<_Response> _getJson(
  HttpClient client,
  String host,
  int port,
  String path, {
  String? token,
}) async {
  final request = await client.get(host, port, path);
  if (token != null) {
    request.headers.set('Authorization', 'Bearer $token');
  }
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  return _Response(response.statusCode, body);
}

String base64UrlEncode(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}
