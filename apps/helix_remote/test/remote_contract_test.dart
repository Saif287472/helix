import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote/app/remote_rest_client.dart';

String _base64UrlEncode(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}

class _RegistrationMaterial {
  const _RegistrationMaterial({
    required this.deviceSigningKeyPair,
    required this.accountIdentityPublicKey,
    required this.deviceSigningPublicKey,
    required this.deviceAgreementPublicKey,
    required this.accountRegistrationSignature,
    required this.deviceRegistrationSignature,
  });

  final crypto.SimpleKeyPair deviceSigningKeyPair;
  final String accountIdentityPublicKey;
  final String deviceSigningPublicKey;
  final String deviceAgreementPublicKey;
  final String accountRegistrationSignature;
  final String deviceRegistrationSignature;
}

Future<_RegistrationMaterial> _registrationMaterial({
  required String accountId,
  required String username,
  required String deviceId,
  required String deviceName,
}) async {
  final ed25519 = crypto.Ed25519();
  final accountKeyPair = await ed25519.newKeyPair();
  final accountPublicKey = await accountKeyPair.extractPublicKey();
  final deviceSigningKeyPair = await ed25519.newKeyPair();
  final deviceSigningPublicKey = await deviceSigningKeyPair.extractPublicKey();
  final agreementKeyPair = await crypto.X25519().newKeyPair();
  final agreementPublicKey = await agreementKeyPair.extractPublicKey();

  final accountIdentityPublicKey = _base64UrlEncode(accountPublicKey.bytes);
  final deviceSigningPublicKeyStr = _base64UrlEncode(
    deviceSigningPublicKey.bytes,
  );
  final deviceAgreementPublicKey = _base64UrlEncode(agreementPublicKey.bytes);
  final transcript = [
    'helix.remote.registration.v2',
    accountId,
    username,
    accountIdentityPublicKey,
    deviceId,
    deviceSigningPublicKeyStr,
    deviceAgreementPublicKey,
    deviceName,
  ].join('\n');
  final accountSignature = await ed25519.sign(
    utf8.encode(transcript),
    keyPair: accountKeyPair,
  );
  final deviceSignature = await ed25519.sign(
    utf8.encode(transcript),
    keyPair: deviceSigningKeyPair,
  );

  return _RegistrationMaterial(
    deviceSigningKeyPair: deviceSigningKeyPair,
    accountIdentityPublicKey: accountIdentityPublicKey,
    deviceSigningPublicKey: deviceSigningPublicKeyStr,
    deviceAgreementPublicKey: deviceAgreementPublicKey,
    accountRegistrationSignature: _base64UrlEncode(accountSignature.bytes),
    deviceRegistrationSignature: _base64UrlEncode(deviceSignature.bytes),
  );
}

Future<_RegistrationMaterial> _register(
  HelixRemoteRestClient client, {
  required String accountId,
  required String username,
  required String deviceId,
  required String deviceName,
}) async {
  final material = await _registrationMaterial(
    accountId: accountId,
    username: username,
    deviceId: deviceId,
    deviceName: deviceName,
  );
  await client.registerAccount(
    accountId: accountId,
    username: username,
    accountIdentityPublicKey: material.accountIdentityPublicKey,
    deviceId: deviceId,
    deviceSigningPublicKey: material.deviceSigningPublicKey,
    deviceAgreementPublicKey: material.deviceAgreementPublicKey,
    accountRegistrationSignature: material.accountRegistrationSignature,
    deviceRegistrationSignature: material.deviceRegistrationSignature,
    deviceName: deviceName,
  );
  return material;
}

void main() {
  late BackendServer server;
  late int port;
  final ed25519 = crypto.Ed25519();

  setUp(() async {
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_for_contract_testing_only',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 100,
    );
    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;
  });

  tearDown(() async {
    await server.stop();
  });

  group('HelixRemoteRestClient contract', () {
    late HelixRemoteRestClient client;

    setUp(() {
      client = HelixRemoteRestClientImpl(
        baseUri: Uri.parse('http://127.0.0.1:$port'),
        timeoutMs: 5000,
      );
    });

    tearDown(() {
      client.close();
    });

    test(
      'register -> challenge -> login roundtrip',
      () async {
        final material = await _registrationMaterial(
          accountId: 'test_account',
          username: 'test_user',
          deviceId: 'test_device_1',
          deviceName: 'Test Phone',
        );
        final regResult = await client.registerAccount(
          accountId: 'test_account',
          username: 'test_user',
          accountIdentityPublicKey: material.accountIdentityPublicKey,
          deviceId: 'test_device_1',
          deviceSigningPublicKey: material.deviceSigningPublicKey,
          deviceAgreementPublicKey: material.deviceAgreementPublicKey,
          accountRegistrationSignature: material.accountRegistrationSignature,
          deviceRegistrationSignature: material.deviceRegistrationSignature,
          deviceName: 'Test Phone',
        );
        expect(regResult['message'], equals('Registration successful'));
        expect(regResult['account_id'], equals('test_account'));

        final challengeResult = await client.getChallenge(
          accountId: 'test_account',
          deviceId: 'test_device_1',
        );
        expect(challengeResult['challenge'], isNotEmpty);

        final challenge = challengeResult['challenge'] as String;
        final sig = await ed25519.sign(
          utf8.encode(challenge),
          keyPair: material.deviceSigningKeyPair,
        );
        final sigStr = _base64UrlEncode(sig.bytes);

        final loginResult = await client.loginDevice(
          accountId: 'test_account',
          deviceId: 'test_device_1',
          signature: sigStr,
        );
        expect(loginResult['token'], isNotEmpty);
        expect(loginResult['refresh_token'], isNotEmpty);

        final token = loginResult['token'] as String;
        client.accessToken = token;

        final refreshToken = loginResult['refresh_token'] as String;
        final refreshResult = await client.refreshToken(
          refreshToken: refreshToken,
        );
        expect(refreshResult['token'], isNotEmpty);
        expect(refreshResult['refresh_token'], isNotEmpty);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'register rejects duplicate account',
      () async {
        await _register(
          client,
          accountId: 'dup_account',
          username: 'dup_user',
          deviceId: 'dup_device_1',
          deviceName: 'Dup Phone',
        );

        expect(
          () => _register(
            client,
            accountId: 'dup_account',
            username: 'dup_user_alt',
            deviceId: 'dup_device_2',
            deviceName: 'Dup Phone 2',
          ),
          throwsA(isA<HttpException>()),
        );
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'login fails with wrong signature',
      () async {
        await _register(
          client,
          accountId: 'bad_sig_account',
          username: 'bad_sig_user',
          deviceId: 'bad_sig_device',
          deviceName: 'Bad Sig Phone',
        );

        await client.getChallenge(
          accountId: 'bad_sig_account',
          deviceId: 'bad_sig_device',
        );

        final badSigStr = _base64UrlEncode(List<int>.generate(64, (_) => 0));

        expect(
          () => client.loginDevice(
            accountId: 'bad_sig_account',
            deviceId: 'bad_sig_device',
            signature: badSigStr,
          ),
          throwsA(isA<HttpException>()),
        );
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'unauthenticated requests fail',
      () async {
        expect(() => client.listDevices(), throwsA(isA<HttpException>()));
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'prekey publish and bundle fetch',
      () async {
        final material = await _register(
          client,
          accountId: 'prekey_account',
          username: 'prekey_user',
          deviceId: 'prekey_device',
          deviceName: 'Prekey Phone',
        );

        final challengeResult = await client.getChallenge(
          accountId: 'prekey_account',
          deviceId: 'prekey_device',
        );
        final sig = await ed25519.sign(
          utf8.encode(challengeResult['challenge'] as String),
          keyPair: material.deviceSigningKeyPair,
        );
        final loginResult = await client.loginDevice(
          accountId: 'prekey_account',
          deviceId: 'prekey_device',
          signature: _base64UrlEncode(sig.bytes),
        );
        client.accessToken = loginResult['token'] as String;

        // Publish prekeys
        await client.uploadPreKeys(
          signedPrekeyId: 1,
          signedPrekey: 'test_signed_prekey',
          signedPrekeySignature: 'test_signature',
          oneTimePrekeys: [
            {'key_id': 1, 'public_key': 'otk_1'},
            {'key_id': 2, 'public_key': 'otk_2'},
          ],
        );

        await _register(
          client,
          accountId: 'other_account',
          username: 'other_user',
          deviceId: 'other_device',
          deviceName: 'Other Phone',
        );

        final bundleResult = await client.getPreKeyBundle(
          accountId: 'prekey_account',
        );
        expect(bundleResult['account_id'], equals('prekey_account'));
        expect(bundleResult['devices'], isNotEmpty);
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });
}
