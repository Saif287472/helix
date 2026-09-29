// A failed refresh used to purge the device's keys, so every expired or
// replayed refresh token cost the user a new SMS code. The app now signs in
// again with the device key it already holds, and only purges when the
// server says the device was actually signed out.

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_config.dart';

class _InMemoryKeyValueStore implements KeyValueStore {
  final _store = <String, String>{};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;

  @override
  Future<void> delete(String key) async => _store.remove(key);
}

RemoteProductConfig _productConfig(String dir) => RemoteProductConfig(
  displayName: 'Helix Remote',
  packageId: 'com.helix.remote',
  secureStoragePrefix: 'helix_remote_v1_',
  methodChannelNamespace: 'com.helix.remote',
  logNamespace: 'helix_remote',
  databaseDirectory: dir,
);

RemoteDevelopmentConfig _devConfig(String dir, Uri restBaseUri) =>
    RemoteDevelopmentConfig(
      profile: RemoteRuntimeProfile.localWindows,
      restBaseUri: restBaseUri,
      webSocketUri: Uri.parse('ws://127.0.0.1:9/api/v1/ws'),
      allowInsecureTransport: true,
      backendHostMode: 'same-pc',
      requestTimeoutMs: 500,
      reconnectPolicy: const ReconnectPolicy(),
      databaseDirectory: dir,
      attachmentCacheDir: '$dir/attachments_cache',
      diagnosticLevel: DiagnosticLevel.info,
    );

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// A backend stand-in whose refresh endpoint fails with [refreshStatus] /
/// [refreshCode], and whose challenge login verifies the real Ed25519
/// signature against [signingPublicKey].
class _FakeAuthServer {
  _FakeAuthServer._(this._server, this.signingPublicKey);

  final HttpServer _server;
  final SimplePublicKey signingPublicKey;
  int refreshStatus = 403;
  String? refreshCode;
  int loginStatus = 200;
  String? loginCode;
  int loginCalls = 0;

  int get port => _server.port;

  static Future<_FakeAuthServer> start(SimplePublicKey key) async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    final fake = _FakeAuthServer._(server, key);
    server.listen(fake._handle);
    return fake;
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    final response = request.response;
    if (path.endsWith('/accounts/refresh')) {
      await request.drain<void>();
      response.statusCode = refreshStatus;
      response.write(
        jsonEncode({'error': 'refresh refused', 'code': ?refreshCode}),
      );
    } else if (path.endsWith('/accounts/challenge')) {
      response.write(jsonEncode({'challenge': 'challenge-payload'}));
    } else if (path.endsWith('/accounts/login')) {
      loginCalls++;
      final body =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
      final signature = Signature(
        base64Url.decode(base64Url.normalize(body['signature'] as String)),
        publicKey: signingPublicKey,
      );
      final valid = await Ed25519().verify(
        utf8.encode('challenge-payload'),
        signature: signature,
      );
      if (!valid) {
        response.statusCode = 403;
        response.write(jsonEncode({'error': 'Invalid signature'}));
      } else if (loginStatus != 200) {
        response.statusCode = loginStatus;
        response.write(jsonEncode({'error': 'refused', 'code': ?loginCode}));
      } else {
        response.write(
          jsonEncode({
            'token': 'relogin-access',
            'refresh_token': 'relogin-refresh',
          }),
        );
      }
    } else {
      response.statusCode = 404;
    }
    await response.close();
  }

  Future<void> close() => _server.close(force: true);
}

Future<void> _seedSession(
  _InMemoryKeyValueStore store,
  SimpleKeyPair signing, {
  bool withRefreshToken = true,
}) async {
  final signingPublic = await signing.extractPublicKey();
  await store.write('access_token', 'expired-access');
  if (withRefreshToken) await store.write('refresh_token', 'refresh-1');
  await store.write('account_id', 'acc-relogin');
  await store.write('phone_number', '+15550000009');
  await store.write('identity_public_key', 'identity-pk');
  await store.write('device_id', 'dev_00aabbcc');
  await store.write('device_signing_public_key', _b64(signingPublic.bytes));
  await store.write(
    'device_signing_private_key',
    _b64(await signing.extractPrivateKeyBytes()),
  );
  await store.write('device_agreement_public_key', 'agreement-pk');
}

void main() {
  late Directory dir;
  late SimpleKeyPair signing;
  late _FakeAuthServer server;
  late _InMemoryKeyValueStore store;
  late RemoteCompositionRoot root;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('device_key_relogin_');
    signing = await Ed25519().newKeyPair();
    server = await _FakeAuthServer.start(await signing.extractPublicKey());
    store = _InMemoryKeyValueStore();
    root = RemoteCompositionRoot.withConfig(
      _productConfig(dir.path),
      devConfig: _devConfig(
        dir.path,
        Uri.parse('http://127.0.0.1:${server.port}'),
      ),
      keyValueStore: store,
    );
  });

  tearDown(() async {
    root.dispose();
    await server.close();
    dir.deleteSync(recursive: true);
  });

  test('an expired refresh token signs in again with the device key', () async {
    await _seedSession(store, signing);
    await root.initialize();

    expect(await root.tryRestoreSession(), isTrue);

    expect(server.loginCalls, 1);
    expect(root.startupState, RemoteStartupState.authenticatedAndSyncing);
    expect(await store.read('access_token'), 'relogin-access');
    expect(await store.read('refresh_token'), 'relogin-refresh');
    expect(await store.read('device_signing_private_key'), isNotNull);
  });

  test('a missing refresh token also recovers with the device key', () async {
    await _seedSession(store, signing, withRefreshToken: false);
    await root.initialize();

    expect(await root.tryRestoreSession(), isTrue);
    expect(await store.read('refresh_token'), 'relogin-refresh');
  });

  test('a revoked device is signed out and its keys purged', () async {
    server.refreshCode = 'device_revoked';
    await _seedSession(store, signing);
    await root.initialize();

    expect(await root.tryRestoreSession(), isFalse);

    expect(server.loginCalls, 0);
    expect(root.startupState, RemoteStartupState.unauthenticated);
    expect(await store.read('refresh_token'), isNull);
    expect(await store.read('device_signing_private_key'), isNull);
  });

  test('a device the login refuses is signed out', () async {
    server.loginStatus = 403;
    server.loginCode = 'device_revoked';
    await _seedSession(store, signing);
    await root.initialize();

    expect(await root.tryRestoreSession(), isFalse);

    expect(server.loginCalls, 1);
    expect(root.startupState, RemoteStartupState.unauthenticated);
    expect(await store.read('device_signing_private_key'), isNull);
  });

  test('a server error during re-login keeps the session for later', () async {
    server.loginStatus = 503;
    await _seedSession(store, signing);
    await root.initialize();

    // The app still opens on this device's data; the device signs in again
    // when the server is back.
    expect(await root.tryRestoreSession(), isTrue);

    expect(root.startupState, RemoteStartupState.authenticatedAndSyncing);
    expect(await store.read('device_signing_private_key'), isNotNull);
    expect(await store.read('refresh_token'), 'refresh-1');
  });
}
