import 'dart:io';

import 'package:helix_local_domain/core/constants.dart';

Future<void> main() async {
  final root = Directory.current;
  final failures = <String>[];

  void requireFile(String path) {
    if (!File(_join(root.path, path)).existsSync()) {
      failures.add('Missing required release/security file: $path');
    }
  }

  void requireContains(String path, String needle) {
    final file = File(_join(root.path, path));
    if (!file.existsSync()) {
      failures.add('Missing file for content check: $path');
      return;
    }
    final text = file.readAsStringSync();
    if (!text.contains(needle)) {
      failures.add('$path does not contain required text: $needle');
    }
  }

  void requireNotContains(String path, String needle) {
    final file = File(_join(root.path, path));
    if (!file.existsSync()) {
      failures.add('Missing file for content check: $path');
      return;
    }
    final text = file.readAsStringSync();
    if (text.contains(needle)) {
      failures.add('$path contains forbidden text: $needle');
    }
  }

  if ((kCapAll & kCapForwardSecrecy) != 0) {
    failures.add(
      'kCapForwardSecrecy must not be advertised in kCapAll until reviewed.',
    );
  }

  requireNotContains(
    'apps/helix_local/android/app/build.gradle.kts',
    'signingConfigs.getByName("debug")',
  );
  requireNotContains(
    'apps/helix_remote/android/app/build.gradle.kts',
    'signingConfigs.getByName("debug")',
  );
  requireContains(
    'apps/helix_local/android/app/build.gradle.kts',
    'Debug signing is forbidden for Helix Local release.',
  );
  requireContains(
    'apps/helix_remote/android/app/build.gradle.kts',
    'Debug signing is forbidden for Helix Remote release.',
  );
  requireContains(
    'apps/helix_local/android/app/build.gradle.kts',
    'HELIX_LOCAL_STORE_PASSWORD',
  );
  requireContains(
    'apps/helix_local/android/app/build.gradle.kts',
    'HELIX_LOCAL_KEY_ALIAS',
  );
  requireContains(
    'apps/helix_local/android/app/build.gradle.kts',
    'HELIX_LOCAL_KEY_PASSWORD',
  );
  requireContains(
    'apps/helix_local/android/app/build.gradle.kts',
    'helix_local.keystore',
  );
  requireContains(
    'apps/helix_remote/android/app/build.gradle.kts',
    'HELIX_REMOTE_STORE_PASSWORD',
  );
  requireContains(
    'apps/helix_remote/android/app/build.gradle.kts',
    'HELIX_REMOTE_KEY_ALIAS',
  );
  requireContains(
    'apps/helix_remote/android/app/build.gradle.kts',
    'HELIX_REMOTE_KEY_PASSWORD',
  );
  requireContains(
    'apps/helix_remote/android/app/build.gradle.kts',
    'helix_remote.keystore',
  );

  requireContains(
    'apps/helix_local/android/app/src/main/AndroidManifest.xml',
    'android:foregroundServiceType="connectedDevice|microphone"',
  );
  requireContains(
    'apps/helix_local/android/app/src/main/AndroidManifest.xml',
    'android:exported="false"',
  );

  requireContains(
    'apps/helix_local/windows/CMakeLists.txt',
    'set(BINARY_NAME "helix_local")',
  );
  requireContains('apps/helix_local/windows/runner/main.cpp', 'Helix Local');
  requireContains(
    'apps/helix_local/windows/runner/Runner.rc',
    'ProductName", "Helix Local"',
  );

  requireContains('.github/workflows/verify.yml', './scripts/verify.ps1');
  requireContains('.github/workflows/verify.yml', './scripts/verify.sh');
  requireContains('scripts/verify.ps1', 'check_release_hardening.dart');
  requireContains('scripts/verify.sh', 'check_release_hardening.dart');
  requireContains(
    'scripts/verify.ps1',
    'generate_local_sbom.dart --check-only',
  );
  requireContains('scripts/verify.sh', 'generate_local_sbom.dart --check-only');
  requireContains('scripts/verify.ps1', 'phase20_release_governance_test.dart');
  requireContains('scripts/verify.sh', 'phase20_release_governance_test.dart');

  requireFile('docs/security/AUTHENTICATED_KEY_AGREEMENT_REVIEW.md');
  requireFile('docs/security/EXTERNAL_SECURITY_REVIEW_GATE.md');
  requireFile('docs/release/LOCAL_RELEASE_CHECKLIST.md');
  requireFile('docs/release/LOCAL_PRIVACY_VERIFICATION_CHECKLIST.md');
  requireFile('docs/release/LOCAL_RELEASE_ROLLBACK_PLAN.md');
  requireFile('docs/release/LOCAL_SBOM_DEPENDENCY_AUDIT.md');
  requireFile('docs/release/REMOTE_RELEASE_CHECKLIST.md');
  requireFile('docs/release/REMOTE_RELEASE_ROLLBACK_PLAN.md');
  requireFile('docs/release/REMOTE_RELEASE_NOTES_TEMPLATE.md');
  requireFile('docs/release/CROSS_PRODUCT_ACCEPTANCE_CHECKLIST.md');
  requireFile('docs/governance/LONG_TERM_GOVERNANCE.md');
  requireFile('docs/governance/PHASE_20_COMPLETION_EVIDENCE.md');
  requireFile('scripts/local_release_gate.ps1');
  requireFile('scripts/remote_release_gate.ps1');

  if (failures.isNotEmpty) {
    stderr.writeln('Release hardening check failed:');
    for (final failure in failures) {
      stderr.writeln('- $failure');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln('Release hardening check passed.');
}

String _join(String a, String b) {
  if (a.endsWith(Platform.pathSeparator)) return '$a$b';
  return '$a${Platform.pathSeparator}$b';
}
