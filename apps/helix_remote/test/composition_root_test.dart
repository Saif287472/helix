// Phase 5 Remote composition tests.
// P5-013: RemoteCompositionRoot smoke test.
// P5-014: Startup failure tests for missing/invalid configuration.

import 'dart:io';
import 'package:test/test.dart';

import 'package:helix_remote/app/composition_root.dart';

const _tmpDir = '/tmp';

RemoteProductConfig _validConfig({
  String displayName = 'Helix Remote',
  String packageId = 'com.helix.remote',
  String secureStoragePrefix = 'helix_remote_v1_',
  String methodChannelNamespace = 'com.helix.remote',
  String logNamespace = 'helix_remote',
  String databaseDirectory = _tmpDir,
}) => RemoteProductConfig(
  displayName: displayName,
  packageId: packageId,
  secureStoragePrefix: secureStoragePrefix,
  methodChannelNamespace: methodChannelNamespace,
  logNamespace: logNamespace,
  databaseDirectory: databaseDirectory,
);

void main() {
  group('RemoteCompositionRoot', () {
    test('P5-013: production() instantiates with correct config', () {
      final root = RemoteCompositionRoot.production(
        databaseDirectory: Directory.systemTemp.path,
      );

      expect(root.config.displayName, equals('Helix Remote'));
      expect(root.config.packageId, equals('com.helix.remote'));
      expect(root.config.secureStoragePrefix, equals('helix_remote_v1_'));
      expect(root.config.methodChannelNamespace, equals('com.helix.remote'));
      expect(root.config.logNamespace, equals('helix_remote'));

      root.dispose();
    });

    test('P5-014: throws StateError when displayName is empty', () {
      expect(
        () => RemoteCompositionRoot.withConfig(
          _validConfig(displayName: ''),
        ),
        throwsStateError,
      );
    });

    test('P5-014: throws StateError when packageId is empty', () {
      expect(
        () => RemoteCompositionRoot.withConfig(
          _validConfig(packageId: ''),
        ),
        throwsStateError,
      );
    });

    test('P5-014: throws StateError when secureStoragePrefix lacks trailing _', () {
      expect(
        () => RemoteCompositionRoot.withConfig(
          _validConfig(secureStoragePrefix: 'helix_remote_v1'),
        ),
        throwsStateError,
      );
    });

    test('P5-014: throws StateError when secureStoragePrefix is empty', () {
      expect(
        () => RemoteCompositionRoot.withConfig(
          _validConfig(secureStoragePrefix: ''),
        ),
        throwsStateError,
      );
    });

    test('P5-014: throws StateError when databaseDirectory is empty', () {
      expect(
        () => RemoteCompositionRoot.withConfig(
          _validConfig(databaseDirectory: ''),
        ),
        throwsStateError,
      );
    });

    test('Startup state is idle before initialize()', () {
      final root = RemoteCompositionRoot.production(
        databaseDirectory: Directory.systemTemp.path,
      );
      expect(root.startupState, RemoteStartupState.idle);
      root.dispose();
    });

    test('Service accessors throw StateError before initialize()', () {
      final root = RemoteCompositionRoot.production(
        databaseDirectory: Directory.systemTemp.path,
      );
      expect(() => root.database, throwsStateError);
      expect(() => root.syncEngine, throwsStateError);
      expect(() => root.keyStorage, throwsStateError);
      root.dispose();
    });

    test('P5-019: two Remote roots are independent objects', () {
      final root1 = RemoteCompositionRoot.production(
        databaseDirectory: Directory.systemTemp.path,
      );
      final root2 = RemoteCompositionRoot.production(
        databaseDirectory: Directory.systemTemp.path,
      );

      expect(root1, isNot(same(root2)));

      root1.dispose();
      root2.dispose();
    });
  });
}
