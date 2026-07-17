// Phase 04 — HXA-004, logout portion of HXA-014.
//
// Verifies:
//   P04-L01  restart refresh rotates stored tokens before authentication.
//   P04-L02  revoked/replayed refresh token returns to setup and clears session.
//   P04-L03  refresh network failure is recoverable and preserves session.
//   P04-L04  logout clears local session without deleting app data.

import 'dart:convert';
import 'dart:io';

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
      requestTimeoutMs: 300,
      reconnectPolicy: const ReconnectPolicy(),
      databaseDirectory: dir,
      attachmentCacheDir: '$dir/attachments_cache',
      diagnosticLevel: DiagnosticLevel.info,
    );

Future<void> _seedSession(_InMemoryKeyValueStore store) async {
  await store.write('access_token', 'expired-access');
  await store.write('refresh_token', 'refresh-1');
  await store.write('account_id', 'acc-p04');
  await store.write('username', 'phase4');
  await store.write('identity_public_key', 'identity-pk');
  await store.write('device_id', 'dev_00aabbcc');
  await store.write('device_signing_public_key', 'signing-pk');
  await store.write('device_agreement_public_key', 'agreement-pk');
}

Future<HttpServer> _refreshServer({
  int statusCode = 200,
  String accessFixture = 'fresh-access',
  String refreshFixture = 'refresh-2',
}) async {
  final server = await HttpServer.bind('127.0.0.1', 0);
  server.listen((request) async {
    if (request.uri.path.endsWith('/accounts/refresh')) {
      await request.drain<void>();
      request.response.statusCode = statusCode;
      if (statusCode == 200) {
        request.response.write(
          jsonEncode({'token': accessFixture, 'refresh_token': refreshFixture}),
        );
      } else {
        request.response.write(jsonEncode({'error': 'revoked'}));
      }
    } else {
      request.response.statusCode = 404;
    }
    await request.response.close();
  });
  return server;
}

void main() {
  group('Remote auth refresh lifecycle (Phase 04)', () {
    test(
      'P04-L01: restart refresh rotates tokens before authentication',
      () async {
        final dir = Directory.systemTemp.createTempSync('p04_l01_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final server = await _refreshServer();
        addTearDown(() => server.close(force: true));

        final store = _InMemoryKeyValueStore();
        await _seedSession(store);
        final root = RemoteCompositionRoot.withConfig(
          _productConfig(dir.path),
          devConfig: _devConfig(
            dir.path,
            Uri.parse('http://127.0.0.1:${server.port}'),
          ),
          keyValueStore: store,
        );
        addTearDown(root.dispose);

        await root.initialize();
        final restored = await root.tryRestoreSession();

        expect(restored, isTrue);
        expect(root.startupState, RemoteStartupState.authenticatedAndSyncing);
        expect(await store.read('access_token'), equals('fresh-access'));
        expect(await store.read('refresh_token'), equals('refresh-2'));
        expect(await store.read('token_rotation.pending'), isNull);
      },
    );

    test(
      'P04-L02: revoked refresh token clears session and returns to setup',
      () async {
        final dir = Directory.systemTemp.createTempSync('p04_l02_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final server = await _refreshServer(statusCode: 403);
        addTearDown(() => server.close(force: true));

        final store = _InMemoryKeyValueStore();
        await _seedSession(store);
        final root = RemoteCompositionRoot.withConfig(
          _productConfig(dir.path),
          devConfig: _devConfig(
            dir.path,
            Uri.parse('http://127.0.0.1:${server.port}'),
          ),
          keyValueStore: store,
        );
        addTearDown(root.dispose);

        await root.initialize();
        final restored = await root.tryRestoreSession();

        expect(restored, isFalse);
        expect(root.startupState, RemoteStartupState.unauthenticated);
        expect(await store.read('access_token'), isNull);
        expect(await store.read('refresh_token'), isNull);
      },
    );

    test('P04-L03: refresh network failure is recoverable', () async {
      final dir = Directory.systemTemp.createTempSync('p04_l03_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final store = _InMemoryKeyValueStore();
      await _seedSession(store);
      final root = RemoteCompositionRoot.withConfig(
        _productConfig(dir.path),
        devConfig: _devConfig(dir.path, Uri.parse('http://127.0.0.1:9')),
        keyValueStore: store,
      );
      addTearDown(root.dispose);

      await root.initialize();
      final restored = await root.tryRestoreSession();

      expect(restored, isFalse);
      expect(root.startupState, RemoteStartupState.recoverableFailure);
      expect(
        root.lastError,
        anyOf(
          contains('Helix Remote server is unreachable'),
          contains('did not respond in time'),
        ),
      );
      expect(root.lastError, isNot(contains('network recovers')));
      expect(await store.read('access_token'), equals('expired-access'));
      expect(await store.read('refresh_token'), equals('refresh-1'));
    });

    test(
      'P04-L05: interrupted token rotation is recovered on next startup',
      () async {
        // Simulate a crash that happened after writing .pending keys but before
        // the main keys were overwritten or .pending was cleaned up.
        final dir = Directory.systemTemp.createTempSync('p04_l05_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final server = await _refreshServer(
          accessFixture: 'rotated-access',
          refreshFixture: 'rotated-refresh',
        );
        addTearDown(() => server.close(force: true));

        final store = _InMemoryKeyValueStore();
        await store.write('access_token', 'stale-access');
        await store.write('refresh_token', 'stale-refresh');
        // Pending pair left over from a crash mid-rotation.
        await store.write(
          'token_rotation.pending',
          jsonEncode({
            'access_token': 'recovered-access',
            'refresh_token': 'recovered-refresh',
          }),
        );
        await store.write('account_id', 'acc-p04');
        await store.write('username', 'phase4');
        await store.write('identity_public_key', 'identity-pk');
        await store.write('device_id', 'dev_00aabbcc');
        await store.write('device_signing_public_key', 'signing-pk');
        await store.write('device_agreement_public_key', 'agreement-pk');

        final root = RemoteCompositionRoot.withConfig(
          _productConfig(dir.path),
          devConfig: _devConfig(
            dir.path,
            Uri.parse('http://127.0.0.1:${server.port}'),
          ),
          keyValueStore: store,
        );
        addTearDown(root.dispose);

        await root.initialize();
        final restored = await root.tryRestoreSession();

        expect(restored, isTrue);
        // Pending key must be gone after recovery.
        expect(await store.read('token_rotation.pending'), isNull);
        // Main keys should hold the server-returned fresh tokens.
        expect(await store.read('access_token'), equals('rotated-access'));
        expect(await store.read('refresh_token'), equals('rotated-refresh'));
      },
    );

    test(
      'P04-L04: logout clears local session without deleting app data',
      () async {
        final dir = Directory.systemTemp.createTempSync('p04_l04_');
        addTearDown(() => dir.deleteSync(recursive: true));

        final store = _InMemoryKeyValueStore();
        await _seedSession(store);
        final root = RemoteCompositionRoot.withConfig(
          _productConfig(dir.path),
          devConfig: _devConfig(dir.path, Uri.parse('http://127.0.0.1:9')),
          keyValueStore: store,
        );
        addTearDown(root.dispose);

        await root.initialize();
        root.setAuthenticated('active-access');
        final dbFile = File(
          '${dir.path}${Platform.pathSeparator}helix_remote.db',
        );
        expect(dbFile.existsSync(), isTrue);

        await root.logout();

        expect(root.startupState, RemoteStartupState.unauthenticated);
        expect(await store.read('access_token'), isNull);
        expect(await store.read('refresh_token'), isNull);
        expect(dbFile.existsSync(), isTrue);
      },
    );

    test(
      'P04-L06: logout clears pending outbox operations from the database',
      () async {
        final dir = Directory.systemTemp.createTempSync('p04_l06_');
        addTearDown(() => dir.deleteSync(recursive: true));

        final store = _InMemoryKeyValueStore();
        await _seedSession(store);
        final root = RemoteCompositionRoot.withConfig(
          _productConfig(dir.path),
          devConfig: _devConfig(dir.path, Uri.parse('http://127.0.0.1:9')),
          keyValueStore: store,
        );
        addTearDown(root.dispose);

        await root.initialize();
        root.setAuthenticated('active-access');

        // Enqueue a pending operation to simulate an unsent outbox item.
        root.database.enqueueOperation(
          'op_test_001',
          'send_message',
          '{"message_id":"msg_001"}',
          idempotencyKey: 'message:msg_001',
        );
        final pendingBefore = root.database.getPendingOperations().length;
        expect(pendingBefore, greaterThan(0));

        await root.logout();

        expect(root.startupState, RemoteStartupState.unauthenticated);
        expect(await store.read('access_token'), isNull);
        // Database survives session-only logout but outbox is cleared.
        final pendingAfter = root.database.getPendingOperations().length;
        expect(pendingAfter, equals(0));
      },
    );
  });
}
