import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('Phase 20 release pipelines and governance', () {
    test(
      'Local and Remote release signing fail closed and use scoped inputs',
      () {
        final localGradle = _read(
          'apps/helix_local/android/app/build.gradle.kts',
        );
        final remoteGradle = _read(
          'apps/helix_remote/android/app/build.gradle.kts',
        );

        expect(localGradle, contains('helix_local.keystore'));
        expect(localGradle, contains('HELIX_LOCAL_STORE_PASSWORD'));
        expect(localGradle, contains('HELIX_LOCAL_KEY_ALIAS'));
        expect(localGradle, contains('HELIX_LOCAL_KEY_PASSWORD'));
        expect(localGradle, contains('Debug signing is forbidden'));
        expect(
          localGradle,
          isNot(contains('signingConfigs.getByName("debug")')),
        );

        expect(remoteGradle, contains('helix_remote.keystore'));
        expect(remoteGradle, contains('HELIX_REMOTE_STORE_PASSWORD'));
        expect(remoteGradle, contains('HELIX_REMOTE_KEY_ALIAS'));
        expect(remoteGradle, contains('HELIX_REMOTE_KEY_PASSWORD'));
        expect(remoteGradle, contains('Debug signing is forbidden'));
        expect(
          remoteGradle,
          isNot(contains('signingConfigs.getByName("debug")')),
        );
      },
    );

    test('independent verification and release gate scripts exist', () {
      final verifyPs = _read('scripts/verify.ps1');
      final verifySh = _read('scripts/verify.sh');
      final localGate = _read('scripts/local_release_gate.ps1');
      final remoteGate = _read('scripts/remote_release_gate.ps1');

      expect(verifyPs, contains('apps/helix_local'));
      expect(verifyPs, contains('apps/helix_remote'));
      expect(verifyPs, contains('services/helix_remote_backend'));
      expect(verifyPs, contains('phase20_release_governance_test.dart'));
      expect(verifySh, contains('apps/helix_local'));
      expect(verifySh, contains('apps/helix_remote'));
      expect(verifySh, contains('services/helix_remote_backend'));
      expect(verifySh, contains('phase20_release_governance_test.dart'));

      expect(localGate, contains('HELIX_LOCAL_STORE_PASSWORD'));
      expect(localGate, contains('helix_local.keystore'));
      expect(remoteGate, contains('HELIX_REMOTE_STORE_PASSWORD'));
      expect(remoteGate, contains('helix_remote.keystore'));
      expect(remoteGate, contains('HELIX_REMOTE_STAGING_BASE_URL'));
    });

    test('CI separates product and Remote backend checks', () {
      final ci = _read('.github/workflows/ci.yml');
      final verify = _read('.github/workflows/verify.yml');

      for (final required in [
        'local-flutter',
        'remote-flutter',
        'remote-backend',
        'Remote API compatibility',
        'Release hardening',
      ]) {
        expect(ci, contains(required));
      }
      expect(verify, contains('./scripts/verify.ps1'));
      expect(verify, contains('./scripts/verify.sh'));
    });

    test('release and governance documents cover final gates', () {
      final requiredFiles = [
        'docs/release/LOCAL_RELEASE_CHECKLIST.md',
        'docs/release/LOCAL_RELEASE_ROLLBACK_PLAN.md',
        'docs/release/REMOTE_RELEASE_CHECKLIST.md',
        'docs/release/REMOTE_RELEASE_ROLLBACK_PLAN.md',
        'docs/release/REMOTE_RELEASE_NOTES_TEMPLATE.md',
        'docs/release/CROSS_PRODUCT_ACCEPTANCE_CHECKLIST.md',
        'docs/governance/LONG_TERM_GOVERNANCE.md',
        'docs/governance/PHASE_20_COMPLETION_EVIDENCE.md',
        'docs/operations/REMOTE_OPERABILITY_AND_DR.md',
      ];

      for (final path in requiredFiles) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }

      final governance = _read('docs/governance/LONG_TERM_GOVERNANCE.md');
      for (final phrase in [
        'Quarterly architecture review',
        'Quarterly dependency review',
        'Annual threat-model review',
        'Security-claim review before every major release',
        'An ADR is required',
        'Deprecation Policy',
        'Execution Ledger',
      ]) {
        expect(governance, contains(phrase));
      }

      final remoteChecklist = _read('docs/release/REMOTE_RELEASE_CHECKLIST.md');
      expect(remoteChecklist, contains('Staging is blocked until real'));
      expect(remoteChecklist, contains('Debug signing is forbidden'));
      expect(remoteChecklist, contains('SQLCipher-capable'));
    });

    test('cross-product app identifiers and storage scopes remain isolated', () {
      final localGradle = _read(
        'apps/helix_local/android/app/build.gradle.kts',
      );
      final remoteGradle = _read(
        'apps/helix_remote/android/app/build.gradle.kts',
      );
      final localStorageTest = _read(
        'packages/local/helix_local_storage/test/storage_path_inventory_test.dart',
      );
      final remoteRoot = _read(
        'apps/helix_remote/lib/app/composition_root.dart',
      );

      expect(localGradle, contains('applicationId = "com.helix.local"'));
      expect(remoteGradle, contains('applicationId = "com.helix.remote"'));
      expect(localStorageTest, contains("equals('helix_local.db')"));
      expect(localStorageTest, contains("equals('helix_remote.db')"));
      expect(localStorageTest, contains("equals('helix_local_v1_')"));
      expect(localStorageTest, contains("equals('helix_remote_v1_')"));
      expect(remoteRoot, contains("packageId: 'com.helix.remote'"));
      expect(remoteRoot, contains("secureStoragePrefix: 'helix_remote_v1_'"));
    });

    test(
      'Remote source has no Local LAN discovery or panic-wipe dependency',
      () {
        final remoteText = _concatFiles('apps/helix_remote/lib');
        for (final forbidden in [
          'helix_local_',
          'LocalPanicWipeOrchestrator',
          'NsdManager',
          'multicast',
          'mDNS',
          'kUdpDiscoveryPort',
          'Udp',
          'UDP broadcast',
        ]) {
          expect(remoteText, isNot(contains(forbidden)), reason: forbidden);
        }
      },
    );

    test('Local app source has no Remote backend dependency', () {
      final localText = _concatFiles('apps/helix_local/lib');
      for (final forbidden in [
        'helix_remote_',
        'HELIX_REMOTE',
        '/api/v1/',
        'turn-credentials',
        'RemoteCompositionRoot',
        'com.helix.remote/',
      ]) {
        expect(localText, isNot(contains(forbidden)), reason: forbidden);
      }
    });

    test(
      'ownership map includes current products, packages, service, and tools',
      () {
        final ownership = _read('ownership-blast-radius.yaml');
        final required = [
          'apps/helix_local:',
          'apps/helix_remote:',
          'packages/local/helix_local_domain:',
          'packages/local/helix_local_protocol:',
          'packages/local/helix_local_crypto:',
          'packages/local/helix_local_transport:',
          'packages/local/helix_local_discovery:',
          'packages/local/helix_local_storage:',
          'packages/local/helix_local_platform:',
          'packages/local/helix_local_groups:',
          'packages/local/helix_local_messaging:',
          'packages/local/helix_local_calls:',
          'packages/local/helix_local_transfer:',
          'packages/remote/helix_remote_domain:',
          'packages/remote/helix_remote_crypto:',
          'packages/remote/helix_remote_api:',
          'packages/remote/helix_remote_storage:',
          'packages/remote/helix_remote_sync:',
          'packages/remote/helix_remote_calls:',
          'packages/remote/helix_remote_groups:',
          'services/helix_remote_backend:',
          'tool:',
        ];

        for (final entry in required) {
          expect(ownership, contains(entry), reason: entry);
        }
      },
    );

    test('execution ledger keeps external blockers unclaimed', () {
      final phase9To11 = _read('docs/architecture/PHASE_9_11_CLOSURE.md');
      final phase12To20 = _read('docs/architecture/PHASE_12_20_CLOSURE.md');
      final security = _read('docs/security/REMOTE_SECURITY_AND_COMPLIANCE.md');

      expect(phase9To11, contains('P10-027 | Staging deployment'));
      expect(phase9To11, contains('**BLOCKED**'));
      expect(security, contains('Independent cryptographic review: BLOCKED'));
      expect(phase12To20, contains('| P18-015 | Penetration test |'));
      expect(phase12To20, contains('| P18-016 | Independent crypto review |'));
      expect(
        phase12To20,
        contains('| P18-017 | Mobile application security review |'),
      );
      expect(phase12To20, contains('| P18-018 | Backend security review |'));
      expect(phase12To20, contains('| P18-019 | Secrets and access review |'));
      expect(
        phase12To20,
        contains('| P20-014 | Staging E2E tests | **OUT OF STUDENT SCOPE**'),
      );
      expect(
        phase12To20,
        contains('| P20-016 | Production deployment/rollback |'),
      );
    });
  });
}

String _read(String path) => File(path).readAsStringSync();

String _concatFiles(String directoryPath) {
  final buffer = StringBuffer();
  for (final entity in Directory(directoryPath).listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    buffer.writeln(entity.readAsStringSync());
  }
  return buffer.toString();
}
