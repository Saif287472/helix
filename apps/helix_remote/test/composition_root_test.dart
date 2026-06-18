// Phase 5 Remote composition tests.
// P5-013: RemoteCompositionRoot smoke test.
// P5-014: Startup failure tests for missing/invalid configuration.

import 'package:test/test.dart';

import 'package:helix_remote/app/composition_root.dart';

void main() {
  group('RemoteCompositionRoot', () {
    test('P5-013: production() instantiates with correct config', () {
      final root = RemoteCompositionRoot.production();

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
          const RemoteProductConfig(
            displayName: '',
            packageId: 'com.helix.remote',
            secureStoragePrefix: 'helix_remote_v1_',
            methodChannelNamespace: 'com.helix.remote',
            logNamespace: 'helix_remote',
          ),
        ),
        throwsStateError,
      );
    });

    test('P5-014: throws StateError when packageId is empty', () {
      expect(
        () => RemoteCompositionRoot.withConfig(
          const RemoteProductConfig(
            displayName: 'Helix Remote',
            packageId: '',
            secureStoragePrefix: 'helix_remote_v1_',
            methodChannelNamespace: 'com.helix.remote',
            logNamespace: 'helix_remote',
          ),
        ),
        throwsStateError,
      );
    });

    test('P5-014: throws StateError when secureStoragePrefix lacks trailing _', () {
      expect(
        () => RemoteCompositionRoot.withConfig(
          const RemoteProductConfig(
            displayName: 'Helix Remote',
            packageId: 'com.helix.remote',
            secureStoragePrefix: 'helix_remote_v1',
            methodChannelNamespace: 'com.helix.remote',
            logNamespace: 'helix_remote',
          ),
        ),
        throwsStateError,
      );
    });

    test('P5-014: throws StateError when secureStoragePrefix is empty', () {
      expect(
        () => RemoteCompositionRoot.withConfig(
          const RemoteProductConfig(
            displayName: 'Helix Remote',
            packageId: 'com.helix.remote',
            secureStoragePrefix: '',
            methodChannelNamespace: 'com.helix.remote',
            logNamespace: 'helix_remote',
          ),
        ),
        throwsStateError,
      );
    });

    test('P5-019: two Remote roots are independent objects', () {
      final root1 = RemoteCompositionRoot.production();
      final root2 = RemoteCompositionRoot.production();

      // Each call produces a distinct root instance — no shared singleton.
      expect(root1, isNot(same(root2)));

      root1.dispose();
      root2.dispose();
      // Disposing one root must not affect the other (both complete normally).
    });
  });
}
