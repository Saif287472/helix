import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:helix_remote_backend/helix_remote_backend.dart';

import 'test_registration.dart';

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

      // 1. Register Alice and Bob
      final aliceMaterial = await createTestRegistrationMaterial(
        accountId: 'alice',
        username: 'alice_user',
        deviceId: 'alice_device_1',
        deviceName: 'Alice Phone',
      );
      final aliceOtpRes = await _postJson(
        client,
        'localhost',
        port,
        '/api/v1/accounts/phone/otp/request',
        {'phone_hash': 'alice_user'},
      );
      final aliceOtpCode =
          (jsonDecode(aliceOtpRes.body) as Map<String, dynamic>)['code']
              as String;
      final regAliceRes = await _postJson(
        client,
        'localhost',
        port,
        '/api/v1/accounts/register',
        registrationBody(
          accountId: 'alice',
          username: 'alice_user',
          deviceId: 'alice_device_1',
          deviceName: 'Alice Phone',
          material: aliceMaterial,
          otpCode: aliceOtpCode,
        ),
      );
      expect(regAliceRes.statusCode, equals(200));

      server.rateLimiter.reset('127.0.0.1');

      final bobMaterial = await createTestRegistrationMaterial(
        accountId: 'bob',
        username: 'bob_user',
        deviceId: 'bob_device_1',
        deviceName: 'Bob Phone',
      );
      final bobOtpRes = await _postJson(
        client,
        'localhost',
        port,
        '/api/v1/accounts/phone/otp/request',
        {'phone_hash': 'bob_user'},
      );
      final bobOtpCode =
          (jsonDecode(bobOtpRes.body) as Map<String, dynamic>)['code']
              as String;
      final regBobRes = await _postJson(
        client,
        'localhost',
        port,
        '/api/v1/accounts/register',
        registrationBody(
          accountId: 'bob',
          username: 'bob_user',
          deviceId: 'bob_device_1',
          deviceName: 'Bob Phone',
          material: bobMaterial,
          otpCode: bobOtpCode,
        ),
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
        keyPair: aliceMaterial.deviceSigningKeyPair,
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
        keyPair: bobMaterial.deviceSigningKeyPair,
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
      expect(
        (devicesList.first as Map<String, dynamic>)['device_id'],
        equals('alice_device_1'),
      );

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
      expect(
        (bobDev1['signed_prekey'] as Map<String, dynamic>)['key_id'],
        equals(42),
      );
      expect(
        (bobDev1['one_time_prekey'] as Map<String, dynamic>)['key_id'],
        equals(1001),
      );

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
      expect(
        (bobDev2['one_time_prekey'] as Map<String, dynamic>)['key_id'],
        equals(1002),
      );

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
        'ws://localhost:$port/api/v1/ws',
        headers: {'Authorization': 'Bearer $bobToken'},
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
      expect(relayedMsg['type'], equals('chat_message'));
      expect(relayedMsg['event_id'], startsWith('evt_msg_abc_'));
      final msgPayload = relayedMsg['payload'] as Map<String, dynamic>;
      expect(msgPayload['message_id'], equals('msg_abc'));
      expect(
        msgPayload['ciphertext'],
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

  test('Refresh Token Rotation and Reuse Detection', () async {
    final client = HttpClient();

    // 1. Register a device for a new account "carol"
    final carolMaterial = await createTestRegistrationMaterial(
      accountId: 'carol',
      username: 'carol_user',
      deviceId: 'carol_device_1',
      deviceName: 'Carol Phone',
    );
    final carolOtpRes = await _postJson(
      client,
      'localhost',
      port,
      '/api/v1/accounts/phone/otp/request',
      {'phone_hash': 'carol_user'},
    );
    final carolOtpCode =
        (jsonDecode(carolOtpRes.body) as Map<String, dynamic>)['code']
            as String;
    final regRes = await _postJson(
      client,
      'localhost',
      port,
      '/api/v1/accounts/register',
      registrationBody(
        accountId: 'carol',
        username: 'carol_user',
        deviceId: 'carol_device_1',
        deviceName: 'Carol Phone',
        material: carolMaterial,
        otpCode: carolOtpCode,
      ),
    );
    expect(regRes.statusCode, equals(200));

    // 2. Challenge and Login
    final challengeRes = await _getJson(
      client,
      'localhost',
      port,
      '/api/v1/accounts/challenge?account_id=carol&device_id=carol_device_1',
    );
    expect(challengeRes.statusCode, equals(200));
    final challenge =
        (jsonDecode(challengeRes.body) as Map<String, dynamic>)['challenge']
            as String;

    final sig = await ed25519.sign(
      utf8.encode(challenge),
      keyPair: carolMaterial.deviceSigningKeyPair,
    );
    final sigStr = base64UrlEncode(sig.bytes);

    final loginRes = await _postJson(
      client,
      'localhost',
      port,
      '/api/v1/accounts/login',
      {
        'account_id': 'carol',
        'device_id': 'carol_device_1',
        'signature': sigStr,
      },
    );
    expect(loginRes.statusCode, equals(200));
    final loginBody = jsonDecode(loginRes.body) as Map<String, dynamic>;
    final token1 = loginBody['token'] as String;
    final refresh1 = loginBody['refresh_token'] as String;

    expect(token1, isNotEmpty);
    expect(refresh1, isNotEmpty);

    // 3. Refresh token rotation (use refresh1 to get access token 2 + refresh token 2)
    server.rateLimiter.reset('127.0.0.1');
    final refreshRes = await _postJson(
      client,
      'localhost',
      port,
      '/api/v1/accounts/refresh',
      {'refresh_token': refresh1},
    );
    expect(refreshRes.statusCode, equals(200));
    final refreshBody = jsonDecode(refreshRes.body) as Map<String, dynamic>;
    final token2 = refreshBody['token'] as String;
    final refresh2 = refreshBody['refresh_token'] as String;

    expect(token2, isNotEmpty);
    expect(refresh2, isNotEmpty);

    // 4. Replay attack: try using refresh1 again, should fail and invalidate refresh2
    server.rateLimiter.reset('127.0.0.1');
    final replayRes = await _postJson(
      client,
      'localhost',
      port,
      '/api/v1/accounts/refresh',
      {'refresh_token': refresh1},
    );
    expect(replayRes.statusCode, equals(403));

    // Try using refresh2 now - should also fail because it was invalidated due to reuse detection
    server.rateLimiter.reset('127.0.0.1');
    final invalidRes = await _postJson(
      client,
      'localhost',
      port,
      '/api/v1/accounts/refresh',
      {'refresh_token': refresh2},
    );
    expect(invalidRes.statusCode, equals(403));

    client.close();
  });

  test('Message Deletion and Tombstones', () async {
    final client = HttpClient();

    // 1. Get tokens for Alice
    // Register & Login Alice
    final aliceDelMaterial = await createTestRegistrationMaterial(
      accountId: 'alice_del_test',
      username: 'alice_del',
      deviceId: 'alice_device_del',
      deviceName: 'Alice Phone',
    );
    final aliceDelOtpRes = await _postJson(
      client,
      'localhost',
      port,
      '/api/v1/accounts/phone/otp/request',
      {'phone_hash': 'alice_del'},
    );
    final aliceDelOtpCode =
        (jsonDecode(aliceDelOtpRes.body) as Map<String, dynamic>)['code']
            as String;
    await _postJson(
      client,
      'localhost',
      port,
      '/api/v1/accounts/register',
      registrationBody(
        accountId: 'alice_del_test',
        username: 'alice_del',
        deviceId: 'alice_device_del',
        deviceName: 'Alice Phone',
        material: aliceDelMaterial,
        otpCode: aliceDelOtpCode,
      ),
    );

    final challengeRes = await _getJson(
      client,
      'localhost',
      port,
      '/api/v1/accounts/challenge?account_id=alice_del_test&device_id=alice_device_del',
    );
    final challenge =
        (jsonDecode(challengeRes.body) as Map<String, dynamic>)['challenge']
            as String;
    final sig = await ed25519.sign(
      utf8.encode(challenge),
      keyPair: aliceDelMaterial.deviceSigningKeyPair,
    );
    final loginRes =
        await _postJson(client, 'localhost', port, '/api/v1/accounts/login', {
          'account_id': 'alice_del_test',
          'device_id': 'alice_device_del',
          'signature': base64UrlEncode(sig.bytes),
        });
    final aliceToken =
        (jsonDecode(loginRes.body) as Map<String, dynamic>)['token'] as String;

    // 2. Create conversation
    server.rateLimiter.reset('127.0.0.1');
    await _postJson(
      client,
      'localhost',
      port,
      '/api/v1/messages/conversations/create',
      {
        'conversation_id': 'conv_del_1',
        'type': 'DIRECT',
        'title': 'Delete Chat',
        'members': ['alice_del_test'],
      },
      token: aliceToken,
    );

    // 3. Send message
    server.rateLimiter.reset('127.0.0.1');
    await _postJson(client, 'localhost', port, '/api/v1/messages/send', {
      'message_id': 'msg_del_1',
      'conversation_id': 'conv_del_1',
      'envelopes': [
        {
          'recipient_device_id': 'alice_device_del',
          'ciphertext': 'ciphertext_payload',
        },
      ],
    }, token: aliceToken);

    // 4. Delete message
    server.rateLimiter.reset('127.0.0.1');
    final delRes = await _postJson(
      client,
      'localhost',
      port,
      '/api/v1/messages/delete',
      {'message_id': 'msg_del_1'},
      token: aliceToken,
    );
    expect(delRes.statusCode, equals(200));

    // Verify it is tombstoned
    expect(server.db.isTombstoned('msg_del_1', 'MESSAGE'), isTrue);

    client.close();
  });

  test('Mailbox Quota Enforcement', () async {
    final client = HttpClient();

    // Fill the messages table to simulate quota limit or simulate using a mock limit.
    // In our implementation, we enforce outstandingCount >= 5000.
    final testDeviceId = 'quota_test_device';
    server.db.createAccount(
      'alice',
      'alice_quota_target',
      'alice_quota_target_key',
    );
    server.db.registerDevice(
      testDeviceId,
      'alice',
      'dummy_pub_key',
      'Quota Device',
    );

    // Create conversation
    server.db.createConversation('conv_quota', 'DIRECT', 'Quota Chat', [
      'alice',
    ]);

    // Directly insert 5000 messages to hit quota
    for (int i = 0; i < 5000; i++) {
      server.db.saveMessage(
        messageId: 'msg_quota_$i',
        conversationId: 'conv_quota',
        senderAccountId: 'alice',
        senderDeviceId: testDeviceId,
        recipientDeviceId: testDeviceId,
        ciphertext: 'dummy ciphertext',
      );
    }

    // Now try to send a message via API, should be rejected due to mailbox quota
    final aliceQuotaMaterial = await createTestRegistrationMaterial(
      accountId: 'alice_quota',
      username: 'alice_quota_user',
      deviceId: 'alice_quota_device',
      deviceName: 'Alice Quota Phone',
    );
    final aliceQuotaOtpRes = await _postJson(
      client,
      'localhost',
      port,
      '/api/v1/accounts/phone/otp/request',
      {'phone_hash': 'alice_quota_user'},
    );
    final aliceQuotaOtpCode =
        (jsonDecode(aliceQuotaOtpRes.body) as Map<String, dynamic>)['code']
            as String;
    await _postJson(
      client,
      'localhost',
      port,
      '/api/v1/accounts/register',
      registrationBody(
        accountId: 'alice_quota',
        username: 'alice_quota_user',
        deviceId: 'alice_quota_device',
        deviceName: 'Alice Quota Phone',
        material: aliceQuotaMaterial,
        otpCode: aliceQuotaOtpCode,
      ),
    );

    final challengeRes = await _getJson(
      client,
      'localhost',
      port,
      '/api/v1/accounts/challenge?account_id=alice_quota&device_id=alice_quota_device',
    );
    final challenge =
        (jsonDecode(challengeRes.body) as Map<String, dynamic>)['challenge']
            as String;
    final sig = await ed25519.sign(
      utf8.encode(challenge),
      keyPair: aliceQuotaMaterial.deviceSigningKeyPair,
    );
    final loginRes =
        await _postJson(client, 'localhost', port, '/api/v1/accounts/login', {
          'account_id': 'alice_quota',
          'device_id': 'alice_quota_device',
          'signature': base64UrlEncode(sig.bytes),
        });
    final aliceToken =
        (jsonDecode(loginRes.body) as Map<String, dynamic>)['token'] as String;

    server.rateLimiter.reset('127.0.0.1');
    final sendRes = await _postJson(
      client,
      'localhost',
      port,
      '/api/v1/messages/send',
      {
        'message_id': 'msg_quota_fail',
        'conversation_id': 'conv_quota',
        'envelopes': [
          {
            'recipient_device_id': testDeviceId,
            'ciphertext': 'ciphertext_payload',
          },
        ],
      },
      token: aliceToken,
    );

    // It should fail with HTTP 403 Forbidden due to quota limit exceeded
    expect(sendRes.statusCode, equals(403));

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
