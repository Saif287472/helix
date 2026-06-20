// Phase 03 — HXA-003, HXA-006, HXA-015, HXA-023.
//
// Verifies:
//   P03-A01  startupStateChanges emits transitions during initialize().
//   P03-A02  resetRequired state is preserved through the initialize() catch block.
//   P03-A03  tryRestoreSession() emits authenticatedAndSyncing via the stream.
//   P03-A04  performReset() returns state to idle and allows re-initialization.
//   P03-A05  performReset() deletes the database file.
//   P03-A06  performReset() clears all secure storage keys.
//   P03-A07  startupStateChanges supports multiple concurrent listeners.
//   P03-A08  purgeAfterAccountDeletion() transitions to unauthenticated via stream.

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

RemoteProductConfig _validConfig(String dir) => RemoteProductConfig(
  displayName: 'Helix Remote',
  packageId: 'com.helix.remote',
  secureStoragePrefix: 'helix_remote_v1_',
  methodChannelNamespace: 'com.helix.remote',
  logNamespace: 'helix_remote',
  databaseDirectory: dir,
);

RemoteDevelopmentConfig _devConfig(String dir) => RemoteDevelopmentConfig(
  profile: RemoteRuntimeProfile.localWindows,
  restBaseUri: Uri.parse('http://127.0.0.1:8080'),
  webSocketUri: Uri.parse('ws://127.0.0.1:8080/api/v1/ws'),
  allowInsecureTransport: true,
  backendHostMode: 'same-pc',
  requestTimeoutMs: 15000,
  reconnectPolicy: const ReconnectPolicy(),
  databaseDirectory: dir,
  attachmentCacheDir: '$dir/attachments_cache',
  diagnosticLevel: DiagnosticLevel.info,
);

void main() {
  group('RemoteCompositionRoot lifecycle (Phase 03)', () {
    test(
      'P03-A01: startupStateChanges emits transitions during initialize()',
      () async {
        final dir = Directory.systemTemp.createTempSync('p03_a01_');
        addTearDown(() => dir.deleteSync(recursive: true));

        final root = RemoteCompositionRoot.withConfig(
          _validConfig(dir.path),
          devConfig: _devConfig(dir.path),
          keyValueStore: _InMemoryKeyValueStore(),
        );
        addTearDown(root.dispose);

        final emitted = <RemoteStartupState>[];
        root.startupStateChanges.listen(emitted.add);

        await root.initialize();

        expect(emitted, contains(RemoteStartupState.loadingConfiguration));
        expect(emitted, contains(RemoteStartupState.openingSecureStorage));
        expect(emitted, contains(RemoteStartupState.firstRunInitialization));
        expect(emitted, contains(RemoteStartupState.openingDatabase));
        expect(emitted, contains(RemoteStartupState.restoringSession));
        expect(emitted, contains(RemoteStartupState.unauthenticated));
        expect(emitted.last, RemoteStartupState.unauthenticated);
      },
    );

    test(
      'P03-A02: resetRequired state is not overwritten by the catch block',
      () async {
        final dir = Directory.systemTemp.createTempSync('p03_a02_');
        addTearDown(() => dir.deleteSync(recursive: true));

        final dbFile = File(
          '${dir.path}${Platform.pathSeparator}helix_remote.db',
        );
        dbFile.createSync();

        final root = RemoteCompositionRoot.withConfig(
          _validConfig(dir.path),
          devConfig: _devConfig(dir.path),
          keyValueStore: _InMemoryKeyValueStore(),
        );
        addTearDown(root.dispose);

        final emitted = <RemoteStartupState>[];
        root.startupStateChanges.listen(emitted.add);

        Object? caught;
        try {
          await root.initialize();
        } catch (e) {
          caught = e;
        }

        expect(caught, isA<StateError>());
        expect(root.startupState, RemoteStartupState.resetRequired);
        expect(emitted, contains(RemoteStartupState.resetRequired));
        expect(emitted, isNot(contains(RemoteStartupState.recoverableFailure)));
      },
    );

    test(
      'P03-A03: tryRestoreSession() emits authenticatedAndSyncing via stream',
      () async {
        final dir = Directory.systemTemp.createTempSync('p03_a03_');
        addTearDown(() => dir.deleteSync(recursive: true));

        final store = _InMemoryKeyValueStore();
        await store.write('access_token', 'tok-abc');
        await store.write('account_id', 'acc-123');
        await store.write('username', 'testuser');
        await store.write('identity_public_key', 'aabbcc');
        await store.write('device_id', 'dev_00112233');
        await store.write('device_signing_public_key', 'ddeegg');
        await store.write('device_agreement_public_key', 'hhiijj');

        final root = RemoteCompositionRoot.withConfig(
          _validConfig(dir.path),
          devConfig: _devConfig(dir.path),
          keyValueStore: store,
        );
        addTearDown(root.dispose);

        final emitted = <RemoteStartupState>[];
        root.startupStateChanges.listen(emitted.add);

        await root.initialize();
        final restored = await root.tryRestoreSession();

        expect(restored, isTrue);
        expect(root.startupState, RemoteStartupState.authenticatedAndSyncing);
        expect(emitted, contains(RemoteStartupState.authenticatedAndSyncing));
      },
    );

    test(
      'P03-A04: performReset() returns state to idle and allows re-initialization',
      () async {
        final dir = Directory.systemTemp.createTempSync('p03_a04_');
        addTearDown(() {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });

        final root = RemoteCompositionRoot.withConfig(
          _validConfig(dir.path),
          devConfig: _devConfig(dir.path),
          keyValueStore: _InMemoryKeyValueStore(),
        );
        addTearDown(root.dispose);

        await root.initialize();
        expect(root.startupState, RemoteStartupState.unauthenticated);

        await root.performReset();
        expect(root.startupState, RemoteStartupState.idle);

        await root.initialize();
        expect(root.startupState, RemoteStartupState.unauthenticated);
      },
    );

    test('P03-A05: performReset() deletes the database file', () async {
      final dir = Directory.systemTemp.createTempSync('p03_a05_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final root = RemoteCompositionRoot.withConfig(
        _validConfig(dir.path),
        devConfig: _devConfig(dir.path),
        keyValueStore: _InMemoryKeyValueStore(),
      );
      addTearDown(root.dispose);

      await root.initialize();
      final dbFile = File(
        '${dir.path}${Platform.pathSeparator}helix_remote.db',
      );
      expect(dbFile.existsSync(), isTrue);

      await root.performReset();
      expect(dbFile.existsSync(), isFalse);
    });

    test(
      'P03-A06: performReset() clears db_key and credential keys from secure storage',
      () async {
        final dir = Directory.systemTemp.createTempSync('p03_a06_');
        addTearDown(() {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });

        final store = _InMemoryKeyValueStore();
        final root = RemoteCompositionRoot.withConfig(
          _validConfig(dir.path),
          devConfig: _devConfig(dir.path),
          keyValueStore: store,
        );
        addTearDown(root.dispose);

        await root.initialize();
        expect(await store.read('db_key'), isNotNull);

        await root.performReset();

        expect(await store.read('db_key'), isNull);
        expect(await store.read('access_token'), isNull);
        expect(await store.read('account_id'), isNull);
        expect(await store.read('attachment_key_wrapping_key'), isNull);
      },
    );

    test(
      'P03-A07: startupStateChanges supports multiple concurrent listeners',
      () async {
        final dir = Directory.systemTemp.createTempSync('p03_a07_');
        addTearDown(() => dir.deleteSync(recursive: true));

        final root = RemoteCompositionRoot.withConfig(
          _validConfig(dir.path),
          devConfig: _devConfig(dir.path),
          keyValueStore: _InMemoryKeyValueStore(),
        );
        addTearDown(root.dispose);

        final l1 = <RemoteStartupState>[];
        final l2 = <RemoteStartupState>[];
        root.startupStateChanges.listen(l1.add);
        root.startupStateChanges.listen(l2.add);

        await root.initialize();

        expect(l1, isNotEmpty);
        expect(l2, equals(l1));
      },
    );

    test(
      'P03-A08: purgeAfterAccountDeletion() transitions to unauthenticated via stream',
      () async {
        final dir = Directory.systemTemp.createTempSync('p03_a08_');
        addTearDown(() {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });

        final store = _InMemoryKeyValueStore();
        await store.write('access_token', 'tok-xyz');
        await store.write('account_id', 'acc-xyz');
        await store.write('username', 'userxyz');
        await store.write('identity_public_key', 'pk');
        await store.write('device_id', 'dev_00aabbcc');
        await store.write('device_signing_public_key', 'spk');
        await store.write('device_agreement_public_key', 'apk');

        final root = RemoteCompositionRoot.withConfig(
          _validConfig(dir.path),
          devConfig: _devConfig(dir.path),
          keyValueStore: store,
        );
        addTearDown(root.dispose);

        final emitted = <RemoteStartupState>[];
        root.startupStateChanges.listen(emitted.add);

        await root.initialize();
        await root.tryRestoreSession();
        expect(root.startupState, RemoteStartupState.authenticatedAndSyncing);

        await root.purgeAfterAccountDeletion();

        expect(root.startupState, RemoteStartupState.unauthenticated);
        expect(emitted.last, RemoteStartupState.unauthenticated);
      },
    );
  });
}
