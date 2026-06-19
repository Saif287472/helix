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
        final keyPair = await ed25519.newKeyPair();
        final pubKey = await keyPair.extractPublicKey();
        final pubKeyStr = _base64UrlEncode(pubKey.bytes);

        final regResult = await client.registerAccount(
          accountId: 'test_account',
          username: 'test_user',
          identityPublicKey: 'test_identity_key',
          deviceId: 'test_device_1',
          devicePublicKey: pubKeyStr,
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
          keyPair: keyPair,
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
        final keyPair = await ed25519.newKeyPair();
        final pubKey = await keyPair.extractPublicKey();
        final pubKeyStr = _base64UrlEncode(pubKey.bytes);

        await client.registerAccount(
          accountId: 'dup_account',
          username: 'dup_user',
          identityPublicKey: 'dup_identity_key',
          deviceId: 'dup_device_1',
          devicePublicKey: pubKeyStr,
          deviceName: 'Dup Phone',
        );

        expect(
          () => client.registerAccount(
            accountId: 'dup_account',
            username: 'dup_user_alt',
            identityPublicKey: 'dup_identity_key_alt',
            deviceId: 'dup_device_2',
            devicePublicKey: pubKeyStr,
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
        final keyPair = await ed25519.newKeyPair();
        final pubKey = await keyPair.extractPublicKey();
        final pubKeyStr = _base64UrlEncode(pubKey.bytes);

        await client.registerAccount(
          accountId: 'bad_sig_account',
          username: 'bad_sig_user',
          identityPublicKey: 'bad_sig_key',
          deviceId: 'bad_sig_device',
          devicePublicKey: pubKeyStr,
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
        final keyPair = await ed25519.newKeyPair();
        final pubKey = await keyPair.extractPublicKey();
        final pubKeyStr = _base64UrlEncode(pubKey.bytes);

        await client.registerAccount(
          accountId: 'prekey_account',
          username: 'prekey_user',
          identityPublicKey: 'prekey_identity',
          deviceId: 'prekey_device',
          devicePublicKey: pubKeyStr,
          deviceName: 'Prekey Phone',
        );

        final challengeResult = await client.getChallenge(
          accountId: 'prekey_account',
          deviceId: 'prekey_device',
        );
        final sig = await ed25519.sign(
          utf8.encode(challengeResult['challenge'] as String),
          keyPair: keyPair,
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

        // Fetch bundle (for another account)
        final registerOther = await (HttpClient()).post(
          '127.0.0.1',
          port,
          '/api/v1/accounts/register',
        );
        registerOther.headers.contentType = ContentType.json;
        registerOther.write(
          jsonEncode({
            'account_id': 'other_account',
            'username': 'other_user',
            'identity_public_key': 'other_identity',
            'device_id': 'other_device',
            'device_public_key': 'other_pub_key',
            'device_name': 'Other Phone',
          }),
        );
        await registerOther.close();

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
