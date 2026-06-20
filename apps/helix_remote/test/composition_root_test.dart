import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/composition_root.dart';
import 'package:helix_remote/app/remote_config.dart';

class _InMemoryKeyValueStore implements KeyValueStore {
  final _store = <String, String>{};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }
}

RemoteProductConfig _validConfig({
  String displayName = 'Helix Remote',
  String packageId = 'com.helix.remote',
  String secureStoragePrefix = 'helix_remote_v1_',
  String methodChannelNamespace = 'com.helix.remote',
  String logNamespace = 'helix_remote',
  String databaseDirectory = '/tmp',
}) => RemoteProductConfig(
  displayName: displayName,
  packageId: packageId,
  secureStoragePrefix: secureStoragePrefix,
  methodChannelNamespace: methodChannelNamespace,
  logNamespace: logNamespace,
  databaseDirectory: databaseDirectory,
);

RemoteDevelopmentConfig _devConfig({String databaseDirectory = '/tmp'}) =>
    RemoteDevelopmentConfig(
      profile: RemoteRuntimeProfile.localWindows,
      restBaseUri: Uri.parse('http://127.0.0.1:8080'),
      webSocketUri: Uri.parse('ws://127.0.0.1:8080/api/v1/ws'),
      allowInsecureTransport: true,
      backendHostMode: 'same-pc',
      requestTimeoutMs: 15000,
      reconnectPolicy: const ReconnectPolicy(),
      databaseDirectory: databaseDirectory,
      attachmentCacheDir: '$databaseDirectory/attachments_cache',
      diagnosticLevel: DiagnosticLevel.info,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RemoteCompositionRoot', () {
    test('P5-013: production() instantiates with correct config', () async {
      final root = RemoteCompositionRoot.production(
        databaseDirectory: Directory.systemTemp.path,
        devConfig: _devConfig(databaseDirectory: Directory.systemTemp.path),
      );

      expect(root.config.displayName, equals('Helix Remote'));
      expect(root.config.packageId, equals('com.helix.remote'));
      expect(root.config.secureStoragePrefix, equals('helix_remote_v1_'));
      expect(root.config.methodChannelNamespace, equals('com.helix.remote'));
      expect(root.config.logNamespace, equals('helix_remote'));

      await root.dispose();
    });

    test('P5-014: throws StateError when displayName is empty', () {
      expect(
        () => RemoteCompositionRoot.withConfig(
          _validConfig(displayName: ''),
          devConfig: _devConfig(),
        ),
        throwsStateError,
      );
    });

    test('P5-014: throws StateError when packageId is empty', () {
      expect(
        () => RemoteCompositionRoot.withConfig(
          _validConfig(packageId: ''),
          devConfig: _devConfig(),
        ),
        throwsStateError,
      );
    });

    test(
      'P5-014: throws StateError when secureStoragePrefix lacks trailing _',
      () {
        expect(
          () => RemoteCompositionRoot.withConfig(
            _validConfig(secureStoragePrefix: 'helix_remote_v1'),
            devConfig: _devConfig(),
          ),
          throwsStateError,
        );
      },
    );

    test('P5-014: throws StateError when secureStoragePrefix is empty', () {
      expect(
        () => RemoteCompositionRoot.withConfig(
          _validConfig(secureStoragePrefix: ''),
          devConfig: _devConfig(),
        ),
        throwsStateError,
      );
    });

    test('P5-014: throws StateError when databaseDirectory is empty', () {
      expect(
        () => RemoteCompositionRoot.withConfig(
          _validConfig(databaseDirectory: ''),
          devConfig: _devConfig(),
        ),
        throwsStateError,
      );
    });

    test('Startup state is idle before initialize()', () {
      final root = RemoteCompositionRoot.production(
        databaseDirectory: Directory.systemTemp.path,
        devConfig: _devConfig(databaseDirectory: Directory.systemTemp.path),
      );
      expect(root.startupState, RemoteStartupState.idle);
      root.dispose();
    });

    test('Service accessors throw StateError before initialize()', () {
      final root = RemoteCompositionRoot.production(
        databaseDirectory: Directory.systemTemp.path,
        devConfig: _devConfig(databaseDirectory: Directory.systemTemp.path),
      );
      expect(() => root.database, throwsStateError);
      expect(() => root.syncEngine, throwsStateError);
      expect(() => root.keyStorage, throwsStateError);
      expect(() => root.restClient, throwsStateError);
      expect(() => root.messagingService, throwsStateError);
      expect(() => root.attachmentService, throwsStateError);
      expect(() => root.callService, throwsStateError);
      expect(() => root.groupService, throwsStateError);
      expect(() => root.runtimeCoordinator, throwsStateError);
      root.dispose();
    });

    test('P5-019: two Remote roots are independent objects', () async {
      final root1 = RemoteCompositionRoot.production(
        databaseDirectory: Directory.systemTemp.path,
        devConfig: _devConfig(databaseDirectory: Directory.systemTemp.path),
      );
      final root2 = RemoteCompositionRoot.production(
        databaseDirectory: Directory.systemTemp.path,
        devConfig: _devConfig(databaseDirectory: Directory.systemTemp.path),
      );

      expect(root1, isNot(same(root2)));

      await root1.dispose();
      await root2.dispose();
    });

    test('first run generates key and reaches unauthenticated state', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'helix_remote_first_run_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final store = _InMemoryKeyValueStore();
      final root = RemoteCompositionRoot.withConfig(
        _validConfig(databaseDirectory: tempDir.path),
        devConfig: _devConfig(databaseDirectory: tempDir.path),
        keyValueStore: store,
      );

      await root.initialize();
      expect(root.startupState, RemoteStartupState.unauthenticated);
      expect(() => root.keyStorage, returnsNormally);
      expect(() => root.database, returnsNormally);
      expect(() => root.restClient, returnsNormally);
      expect(() => root.syncEngine, returnsNormally);
      expect(() => root.messagingService, returnsNormally);
      expect(() => root.attachmentService, returnsNormally);
      expect(() => root.callService, returnsNormally);
      expect(() => root.groupService, returnsNormally);
      expect(() => root.runtimeCoordinator, returnsNormally);

      await root.dispose();
    });

    test('second run reuses existing key and data', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'helix_remote_second_run_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final store = _InMemoryKeyValueStore();
      final root1 = RemoteCompositionRoot.withConfig(
        _validConfig(databaseDirectory: tempDir.path),
        devConfig: _devConfig(databaseDirectory: tempDir.path),
        keyValueStore: store,
      );
      await root1.initialize();
      expect(root1.startupState, RemoteStartupState.unauthenticated);
      await root1.dispose();

      final root2 = RemoteCompositionRoot.withConfig(
        _validConfig(databaseDirectory: tempDir.path),
        devConfig: _devConfig(databaseDirectory: tempDir.path),
        keyValueStore: store,
      );
      await root2.initialize();
      expect(root2.startupState, RemoteStartupState.unauthenticated);
      await root2.dispose();
    });

    test('existing database with missing key fails safely', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'helix_remote_missing_key_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final dbFile = File(
        '${tempDir.path}${Platform.pathSeparator}helix_remote.db',
      );
      dbFile.createSync();

      final root = RemoteCompositionRoot.withConfig(
        _validConfig(databaseDirectory: tempDir.path),
        devConfig: _devConfig(databaseDirectory: tempDir.path),
        keyValueStore: _InMemoryKeyValueStore(),
      );

      Object? error;
      try {
        await root.initialize();
      } catch (e) {
        error = e;
      }

      expect(error, isA<StateError>());
      expect(root.startupState, RemoteStartupState.recoverableFailure);
      await root.dispose();
    });

    test('dispose is idempotent', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'helix_remote_dispose_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final root = RemoteCompositionRoot.withConfig(
        _validConfig(databaseDirectory: tempDir.path),
        devConfig: _devConfig(databaseDirectory: tempDir.path),
        keyValueStore: _InMemoryKeyValueStore(),
      );
      await root.initialize();
      await root.dispose();
      expect(root.startupState, RemoteStartupState.idle);
      await root.dispose();
      expect(root.startupState, RemoteStartupState.idle);
    });

    test('no state shared between two roots', () async {
      final tempDir1 = Directory.systemTemp.createTempSync(
        'helix_remote_independent_1_',
      );
      final tempDir2 = Directory.systemTemp.createTempSync(
        'helix_remote_independent_2_',
      );
      addTearDown(() {
        if (tempDir1.existsSync()) tempDir1.deleteSync(recursive: true);
        if (tempDir2.existsSync()) tempDir2.deleteSync(recursive: true);
      });

      final root1 = RemoteCompositionRoot.withConfig(
        _validConfig(databaseDirectory: tempDir1.path),
        devConfig: _devConfig(databaseDirectory: tempDir1.path),
        keyValueStore: _InMemoryKeyValueStore(),
      );
      final root2 = RemoteCompositionRoot.withConfig(
        _validConfig(databaseDirectory: tempDir2.path),
        devConfig: _devConfig(databaseDirectory: tempDir2.path),
        keyValueStore: _InMemoryKeyValueStore(),
      );

      await root1.initialize();
      await root2.initialize();

      expect(
        root1.config.databaseDirectory,
        isNot(root2.config.databaseDirectory),
      );

      await root1.dispose();
      await root2.dispose();
    });
  });
}
