import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'test_registration.dart';

void main() {
  group('Phase 1 auth and session contract', () {
    late BackendServer server;
    late HttpClient client;
    late int port;
    var now = DateTime.utc(2026, 6, 20, 0, 0);

    setUp(() async {
      now = DateTime.utc(2026, 6, 20, 0, 0);
      server = BackendServer.create(
        sqliteDb: sqlite3.openInMemory(),
        jwtSecret: 'phase1_auth_test_secret_at_least_32_bytes',
        rateLimitMaxTokens: 1000,
        rateLimitRefillRate: 1000,
        now: () => now,
      );
      await server.start('127.0.0.1', 0);
      port = server.httpServer!.port;
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.stop();
    });

    Future<_Response> postJson(
      String path,
      Map<String, dynamic> body, {
      String? token,
    }) async {
      final request = await client.post('127.0.0.1', port, path);
      request.headers.contentType = ContentType.json;
      if (token != null) {
        request.headers.set('Authorization', 'Bearer $token');
      }
      request.write(jsonEncode(body));
      final response = await request.close();
      return _Response(
        response.statusCode,
        await response.transform(utf8.decoder).join(),
      );
    }

    Future<TestRegistrationMaterial> register({
      required String accountId,
      required String username,
      required String deviceId,
      required String deviceName,
    }) async {
      final material = await createTestRegistrationMaterial(
        accountId: accountId,
        username: username,
        deviceId: deviceId,
        deviceName: deviceName,
      );
      final response = await postJson(
        '/api/v1/accounts/register',
        registrationBody(
          accountId: accountId,
          username: username,
          deviceId: deviceId,
          deviceName: deviceName,
          material: material,
        ),
      );
      expect(response.statusCode, equals(200));
      return material;
    }

    Future<String> challenge(
      String accountId,
      String deviceId, {
      String purpose = 'login',
    }) async {
      final request = await client.get(
        '127.0.0.1',
        port,
        '/api/v1/accounts/challenge?account_id=$accountId&device_id=$deviceId&purpose=$purpose',
      );
      final response = await request.close();
      expect(response.statusCode, equals(200));
      final body =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      return body['challenge'] as String;
    }

    Future<String> signChallenge(
      String challenge,
      crypto.SimpleKeyPair deviceSigningKeyPair,
    ) async {
      final signature = await crypto.Ed25519().sign(
        utf8.encode(challenge),
        keyPair: deviceSigningKeyPair,
      );
      return testBase64Url(signature.bytes);
    }

    Future<Map<String, dynamic>> login({
      required String accountId,
      required String deviceId,
      required TestRegistrationMaterial material,
    }) async {
      final loginChallenge = await challenge(accountId, deviceId);
      final signature = await signChallenge(
        loginChallenge,
        material.deviceSigningKeyPair,
      );
      final response = await postJson('/api/v1/accounts/login', {
        'account_id': accountId,
        'device_id': deviceId,
        'signature': signature,
      });
      expect(response.statusCode, equals(200));
      return jsonDecode(response.body) as Map<String, dynamic>;
    }

    Future<_Response> getJson(String path, {String? token}) async {
      final request = await client.get('127.0.0.1', port, path);
      if (token != null) {
        request.headers.set('Authorization', 'Bearer $token');
      }
      final response = await request.close();
      return _Response(
        response.statusCode,
        await response.transform(utf8.decoder).join(),
      );
    }

    test(
      'rejects swapped signing and agreement keys at registration',
      () async {
        final material = await createTestRegistrationMaterial(
          accountId: 'swap_account',
          username: 'swap_user',
          deviceId: 'swap_device',
          deviceName: 'Swap Phone',
        );
        final body = registrationBody(
          accountId: 'swap_account',
          username: 'swap_user',
          deviceId: 'swap_device',
          deviceName: 'Swap Phone',
          material: material,
        );
        final signing = body['device_signing_public_key'];
        body['device_signing_public_key'] = body['device_agreement_public_key'];
        body['device_agreement_public_key'] = signing;

        final response = await postJson('/api/v1/accounts/register', body);
        expect(response.statusCode, equals(400));
      },
    );

    test(
      'registration rejects a mangled account or device signature',
      () async {
        final material = await createTestRegistrationMaterial(
          accountId: 'forged_account',
          username: 'forged_user',
          deviceId: 'forged_device',
          deviceName: 'Forged Phone',
        );

        final tamperedAccountSig = registrationBody(
          accountId: 'forged_account',
          username: 'forged_user',
          deviceId: 'forged_device',
          deviceName: 'Forged Phone',
          material: material,
        );
        tamperedAccountSig['account_registration_signature'] =
            testBase64Url(List.filled(64, 7));
        final accountSigResponse = await postJson(
          '/api/v1/accounts/register',
          tamperedAccountSig,
        );
        expect(accountSigResponse.statusCode, equals(400));

        final tamperedDeviceSig = registrationBody(
          accountId: 'forged_account',
          username: 'forged_user',
          deviceId: 'forged_device',
          deviceName: 'Forged Phone',
          material: material,
        );
        tamperedDeviceSig['device_registration_signature'] = testBase64Url(
          List.filled(64, 7),
        );
        final deviceSigResponse = await postJson(
          '/api/v1/accounts/register',
          tamperedDeviceSig,
        );
        expect(deviceSigResponse.statusCode, equals(400));
      },
    );

    test(
      'registration rejects usernames and display names outside policy',
      () async {
        Future<_Response> attempt({
          required String accountId,
          required String username,
          required String displayName,
        }) async {
          final material = await createTestRegistrationMaterial(
            accountId: accountId,
            username: username,
            deviceId: '${accountId}_device',
            deviceName: 'Policy Phone',
          );
          return postJson(
            '/api/v1/accounts/register',
            registrationBody(
              accountId: accountId,
              username: username,
              displayName: displayName,
              deviceId: '${accountId}_device',
              deviceName: 'Policy Phone',
              material: material,
            ),
          );
        }

        expect(
          (await attempt(
            accountId: 'bad_upper',
            username: 'Bad_User',
            displayName: 'Bad User',
          )).statusCode,
          equals(400),
        );
        expect(
          (await attempt(
            accountId: 'bad_reserved',
            username: 'helix_admin',
            displayName: 'Reserved User',
          )).statusCode,
          equals(400),
        );
        expect(
          (await attempt(
            accountId: 'bad_display',
            username: 'bad_display',
            displayName: '',
          )).statusCode,
          equals(400),
        );
        expect(
          (await attempt(
            accountId: 'long_display',
            username: 'long_display',
            displayName: List.filled(81, 'a').join(),
          )).statusCode,
          equals(400),
        );
      },
    );

    test(
      'registration exact replay is idempotent only for same device',
      () async {
        final material = await createTestRegistrationMaterial(
          accountId: 'replay_account',
          username: 'replay_user',
          deviceId: 'replay_device',
          deviceName: 'Replay Phone',
        );
        final body = registrationBody(
          accountId: 'replay_account',
          username: 'replay_user',
          deviceId: 'replay_device',
          deviceName: 'Replay Phone',
          material: material,
        )..['display_name'] = 'Replay User';

        final first = await postJson('/api/v1/accounts/register', body);
        expect(first.statusCode, equals(200));

        final replay = await postJson('/api/v1/accounts/register', body);
        expect(replay.statusCode, equals(200));
        expect(server.db.getDevices('replay_account'), hasLength(1));

        final otherMaterial = await createTestRegistrationMaterial(
          accountId: 'replay_account',
          username: 'replay_user',
          deviceId: 'replay_device_2',
          deviceName: 'Replay Tablet',
        );
        final otherDevice = await postJson(
          '/api/v1/accounts/register',
          registrationBody(
            accountId: 'replay_account',
            username: 'replay_user',
            deviceId: 'replay_device_2',
            deviceName: 'Replay Tablet',
            material: otherMaterial,
          )..['display_name'] = 'Replay User',
        );
        expect(otherDevice.statusCode, equals(403));
      },
    );

    test('login challenge is single-use and purpose-bound', () async {
      final material = await register(
        accountId: 'alice',
        username: 'alice_user',
        deviceId: 'alice_device',
        deviceName: 'Alice Phone',
      );
      final loginChallenge = await challenge('alice', 'alice_device');
      final signature = await signChallenge(
        loginChallenge,
        material.deviceSigningKeyPair,
      );

      final firstLogin = await postJson('/api/v1/accounts/login', {
        'account_id': 'alice',
        'device_id': 'alice_device',
        'signature': signature,
      });
      expect(firstLogin.statusCode, equals(200));

      final replay = await postJson('/api/v1/accounts/login', {
        'account_id': 'alice',
        'device_id': 'alice_device',
        'signature': signature,
      });
      expect(replay.statusCode, equals(403));

      final wrongPurposeChallenge = await challenge(
        'alice',
        'alice_device',
        purpose: 'link_device',
      );
      final wrongPurposeSignature = await signChallenge(
        wrongPurposeChallenge,
        material.deviceSigningKeyPair,
      );
      final wrongPurpose = await postJson('/api/v1/accounts/login', {
        'account_id': 'alice',
        'device_id': 'alice_device',
        'purpose': 'link_device',
        'signature': wrongPurposeSignature,
      });
      expect(wrongPurpose.statusCode, equals(403));
    });

    test('expired challenges and wrong devices fail login', () async {
      final material = await register(
        accountId: 'bob',
        username: 'bob_user',
        deviceId: 'bob_device',
        deviceName: 'Bob Phone',
      );
      final loginChallenge = await challenge('bob', 'bob_device');
      final signature = await signChallenge(
        loginChallenge,
        material.deviceSigningKeyPair,
      );
      final wrongDevice = await postJson('/api/v1/accounts/login', {
        'account_id': 'bob',
        'device_id': 'other_device',
        'signature': signature,
      });
      expect(wrongDevice.statusCode, equals(403));

      final expiredChallenge = await challenge('bob', 'bob_device');
      now = now.add(const Duration(minutes: 6));
      final expiredSignature = await signChallenge(
        expiredChallenge,
        material.deviceSigningKeyPair,
      );
      final expired = await postJson('/api/v1/accounts/login', {
        'account_id': 'bob',
        'device_id': 'bob_device',
        'signature': expiredSignature,
      });
      expect(expired.statusCode, equals(403));
    });

    test(
      'WebSocket authenticates with bearer header and rejects URL tokens',
      () async {
        final material = await register(
          accountId: 'carol',
          username: 'carol_user',
          deviceId: 'carol_device',
          deviceName: 'Carol Phone',
        );
        final loginResult = await login(
          accountId: 'carol',
          deviceId: 'carol_device',
          material: material,
        );
        final token = loginResult['token'] as String;
        final ws = await WebSocket.connect(
          'ws://127.0.0.1:$port/api/v1/ws',
          headers: {'Authorization': 'Bearer $token'},
        );
        await ws.close();

        await expectLater(
          WebSocket.connect('ws://127.0.0.1:$port/api/v1/ws?token=$token'),
          throwsA(isA<WebSocketException>()),
        );
      },
    );

    test(
      'black-box register login refresh restore websocket and revoke',
      () async {
        final material = await register(
          accountId: 'dave',
          username: 'dave_user',
          deviceId: 'dave_device',
          deviceName: 'Dave Phone',
        );
        final loginResult = await login(
          accountId: 'dave',
          deviceId: 'dave_device',
          material: material,
        );
        final accessToken = loginResult['token'] as String;
        final refreshToken = loginResult['refresh_token'] as String;

        final refresh = await postJson('/api/v1/accounts/refresh', {
          'refresh_token': refreshToken,
        });
        expect(refresh.statusCode, equals(200));
        final refreshBody = jsonDecode(refresh.body) as Map<String, dynamic>;
        final restoredAccessToken = refreshBody['token'] as String;
        final restoredRefreshToken = refreshBody['refresh_token'] as String;

        final restoredSession = await getJson(
          '/api/v1/accounts/devices',
          token: restoredAccessToken,
        );
        expect(restoredSession.statusCode, equals(200));

        final ws = await WebSocket.connect(
          'ws://127.0.0.1:$port/api/v1/ws',
          headers: {'Authorization': 'Bearer $restoredAccessToken'},
        );
        await ws.close();

        server.db.registerDevice(
          'dave_recovery_device',
          'dave',
          'recovery_signing_key',
          'recovery_agreement_key',
          'Recovery Device',
        );

        final revoke = await postJson('/api/v1/accounts/devices/revoke', {
          'device_id': 'dave_device',
        }, token: accessToken);
        expect(revoke.statusCode, equals(200));

        final refreshAfterRevoke = await postJson('/api/v1/accounts/refresh', {
          'refresh_token': restoredRefreshToken,
        });
        expect(refreshAfterRevoke.statusCode, equals(403));

        await expectLater(
          WebSocket.connect(
            'ws://127.0.0.1:$port/api/v1/ws',
            headers: {'Authorization': 'Bearer $restoredAccessToken'},
          ),
          throwsA(isA<WebSocketException>()),
        );
      },
    );
  });

  test('JWT helper emits and validates enterprise session claims', () {
    final jwt = JwtHelper(
      'phase1_jwt_claim_test_secret_at_least_32_bytes',
      keyId: 'phase1-test',
      now: () => DateTime.fromMillisecondsSinceEpoch(1000000),
    );
    final token = jwt.generateToken({
      'account_id': 'acc1',
      'device_id': 'dev1',
    }, const Duration(hours: 1));
    final claims = jwt.verifyToken(token)!;
    expect(claims['iss'], equals('helix.remote.backend'));
    expect(claims['aud'], equals('helix.remote.clients'));
    expect(claims['sub'], equals('acc1'));
    expect(claims['device_id'], equals('dev1'));
    expect(claims['jti'], isNotEmpty);
    expect(claims['iat'], isA<int>());
    expect(claims['nbf'], isA<int>());
    expect(claims['exp'], isA<int>());
    expect(claims['token_type'], equals('access'));

    final header =
        jsonDecode(
              utf8.decode(
                base64Url.decode(base64Url.normalize(token.split('.').first)),
              ),
            )
            as Map<String, dynamic>;
    expect(header['kid'], equals('phase1-test'));
  });
}

class _Response {
  const _Response(this.statusCode, this.body);

  final int statusCode;
  final String body;
}
