import 'package:flutter_test/flutter_test.dart';
import 'package:helix_local_domain/core/product_descriptor.dart';

void main() {
  group('Storage Path Inventory', () {
    const local = LocalProductDescriptor();
    const remote = RemoteProductDescriptor();

    test('verifies database filenames are distinct and isolated', () {
      expect(local.databaseFilename, equals('helix_local.db'));
      expect(remote.databaseFilename, equals('helix_remote.db'));
      expect(local.databaseFilename, isNot(equals(remote.databaseFilename)));
    });

    test('verifies appData folders are distinct', () {
      expect(local.appDataFolder, equals('com.helix/helix'));
      expect(remote.appDataFolder, equals('com.helix/helix_remote'));
      expect(local.appDataFolder, isNot(equals(remote.appDataFolder)));
    });

    test('verifies log namespaces and prefixes are distinct', () {
      expect(local.logNamespace, equals('helix_local'));
      expect(remote.logNamespace, equals('helix_remote'));
      expect(local.exportPrefix, equals('helix_local_export'));
      expect(remote.exportPrefix, equals('helix_remote_export'));
    });

    test('verifies secure storage prefixes are versioned and distinct', () {
      expect(local.secureStoragePrefix, equals('helix_local_v1_'));
      expect(remote.secureStoragePrefix, equals('helix_remote_v1_'));
      expect(
        local.secureStoragePrefix,
        isNot(equals(remote.secureStoragePrefix)),
      );
    });

    group('isPathInScopeForDestructiveOperation', () {
      // ── Positive cases ────────────────────────────────────────────────────

      test('allows valid Local app-data paths for Local descriptor', () {
        expect(
          isPathInScopeForDestructiveOperation(
            'C:/Users/User/AppData/Roaming/com.helix/helix/flutter_secure_storage.dat',
            local,
          ),
          isTrue,
        );
      });

      test('allows valid Local path with Windows backslashes', () {
        expect(
          isPathInScopeForDestructiveOperation(
            r'C:\Users\User\AppData\Roaming\com.helix\helix\flutter_secure_storage.dat',
            local,
          ),
          isTrue,
        );
      });

      test('allows valid Remote app-data paths for Remote descriptor', () {
        expect(
          isPathInScopeForDestructiveOperation(
            'C:/Users/User/AppData/Roaming/com.helix/helix_remote/flutter_secure_storage.dat',
            remote,
          ),
          isTrue,
        );
      });

      // ── Negative: cross-product paths ─────────────────────────────────────

      test('rejects Remote path for Local descriptor', () {
        expect(
          isPathInScopeForDestructiveOperation(
            'C:/Users/User/AppData/Roaming/com.helix/helix_remote/flutter_secure_storage.dat',
            local,
          ),
          isFalse,
        );
      });

      test('rejects Local path for Remote descriptor', () {
        expect(
          isPathInScopeForDestructiveOperation(
            'C:/Users/User/AppData/Roaming/com.helix/helix/flutter_secure_storage.dat',
            remote,
          ),
          isFalse,
        );
      });

      // ── Negative: Documents / user-space paths with matching filename ──────

      test(
        'rejects Documents path that contains Local namespace as filename substring',
        () {
          // Old string-contains check incorrectly allowed this because the filename
          // includes "helix_local" (the logNamespace).
          expect(
            isPathInScopeForDestructiveOperation(
              'C:/Users/User/Documents/helix_local_anomaly_log.txt',
              local,
            ),
            isFalse,
          );
        },
      );

      test('rejects Desktop path for Remote namespace', () {
        expect(
          isPathInScopeForDestructiveOperation(
            'C:/Users/User/Desktop/helix_remote_backup.dat',
            remote,
          ),
          isFalse,
        );
      });

      // ── Negative: sibling directories that share a prefix ─────────────────

      test('rejects sibling directory sharing the helix prefix', () {
        expect(
          isPathInScopeForDestructiveOperation(
            'C:/Users/User/AppData/Roaming/com.helix/helix_evil/data',
            local,
          ),
          isFalse,
        );
      });

      // ── Negative: path traversal with .. ──────────────────────────────────

      test('rejects path traversal that escapes the appDataFolder', () {
        expect(
          isPathInScopeForDestructiveOperation(
            'C:/Users/User/AppData/Roaming/com.helix/helix/../../../Users/User/Documents/evil.dat',
            local,
          ),
          isFalse,
        );
      });

      test('rejects relative path beginning with ..', () {
        expect(
          isPathInScopeForDestructiveOperation(
            '../../com.helix/helix/evil',
            local,
          ),
          isFalse,
        );
      });

      // ── Negative: mixed separators leading to wrong folder ────────────────

      test('rejects mixed-separator traversal to Remote folder', () {
        expect(
          isPathInScopeForDestructiveOperation(
            r'C:\Users\User\AppData\Roaming\com.helix\helix\..\helix_remote\data',
            local,
          ),
          isFalse,
        );
      });

      // ── Negative: system or unrelated paths ───────────────────────────────

      test('rejects Windows system path', () {
        expect(
          isPathInScopeForDestructiveOperation(
            'C:/Windows/System32/drivers/etc/hosts',
            local,
          ),
          isFalse,
        );
      });

      test('rejects Unix syslog path', () {
        expect(
          isPathInScopeForDestructiveOperation('/var/log/syslog', remote),
          isFalse,
        );
      });

      test('rejects filesystem root', () {
        expect(isPathInScopeForDestructiveOperation('/', local), isFalse);
        expect(isPathInScopeForDestructiveOperation('C:/', local), isFalse);
      });

      // ── Negative: Remote app-data path for Local descriptor ───────────────

      test('rejects Remote appDataFolder path when checking Local scope', () {
        expect(
          isPathInScopeForDestructiveOperation(
            'C:/Users/User/AppData/Roaming/com.helix/helix_remote',
            local,
          ),
          isFalse,
        );
      });
    });
  });
}
