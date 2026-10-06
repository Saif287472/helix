/// Keeps governance claims tied to concrete repository evidence.
///
/// §21 of the enterprise readiness audit records "governance documents
/// asserting controls that do not exist in code" as small debt at a *high*
/// interest rate: a document that is confidently wrong is worse than a missing
/// one, because reviewers trust it and skip the check it existed to prompt.
/// Three such documents were found in one pass — `LOG_REDACTION.md` required
/// redaction the client did not perform, `WORKSPACE_LOCKFILE_POLICY.md`
/// described a committed lockfile that was actively gitignored, and
/// `DEPENDENCY_RISK_REGISTER.md` misclassified a direct dependency as
/// transitive.
///
/// This gate is what stops that recurring. Add a row whenever a document makes
/// a durable implementation assertion.
///
/// Paths are relative to `helix_remote/`; `../` reaches repository-wide docs
/// that also govern Helix Remote.
library;

import 'dart:io';

/// A claim that must be evidenced somewhere in the repository.
///
/// [marker] is required to be present in [path] — or, when [absent] is true,
/// required to be *missing* from it. The absent form is what catches a
/// correction being reverted: re-asserting a withdrawn claim is a silent
/// regression that a "must contain" check cannot see.
class GovernanceControl {
  const GovernanceControl(
    this.name,
    this.path,
    this.marker, {
    this.absent = false,
    this.because,
  });

  final String name;
  final String path;
  final String marker;
  final bool absent;

  /// Why the claim matters, printed on failure so whoever trips this gate does
  /// not have to reconstruct the reasoning from the audit.
  final String? because;

  String? evaluate() {
    final file = File(path);
    if (!file.existsSync()) {
      return '$name: $path does not exist';
    }
    final contents = file.readAsStringSync();
    final present = contents.contains(marker);
    if (present == absent) {
      final requirement = absent
          ? '$path must NOT contain "$marker"'
          : '$path must contain "$marker"';
      final reason = because == null ? '' : '\n     ${because!}';
      return '$name: $requirement$reason';
    }
    return null;
  }
}

const controls = <GovernanceControl>[
  // --- Platform and product decisions -------------------------------------
  GovernanceControl(
    'iOS support decision',
    'docs/adr/023-ios-support-decision.md',
    'does not currently ship an iOS target',
  ),
  GovernanceControl(
    'server architecture decision',
    'docs/adr/025-postgres-stateless-server.md',
    'PostgreSQL',
    because:
        'ADR-025 replaced the SQLite server (ADR-022 is historical); the '
        'handoff and the verify scripts assume Postgres.',
  ),
  GovernanceControl(
    'release obfuscation',
    'scripts/remote_release_gate.ps1',
    '--obfuscate',
  ),

  // --- HIGH-3: backup refusal ---------------------------------------------
  GovernanceControl(
    'Android backup refusal',
    'app/android/app/src/main/AndroidManifest.xml',
    'android:allowBackup="false"',
    because:
        'HIGH-3 — the app-private directory holds the SQLCipher database '
        'and the diagnostic log; the platform default is allowBackup=true.',
  ),

  // --- Transport security --------------------------------------------------
  GovernanceControl(
    'Android release config forbids cleartext traffic',
    'app/android/app/src/main/res/xml/helix_remote_network_security.xml',
    'base-config cleartextTrafficPermitted="false"',
  ),
  GovernanceControl(
    'Android release config carries no pin that Dart would ignore',
    'app/android/app/src/main/res/xml/helix_remote_network_security.xml',
    '<pin-set',
    absent: true,
    because:
        'network_security_config only governs the platform HTTP stack. The '
        'app\'s traffic is Dart\'s, so a pin here protects nothing and only '
        'looks like protection. Pinning lives in tls_pinning.dart.',
  ),
  GovernanceControl(
    'TLS pinning is off unless a build defines pins',
    'app/lib/core/platform/tls_pinning.dart',
    'enforce: !debug && pins.isNotEmpty',
    because:
        'no pin is built in (a stale one locks every release build out of '
        'Helix Global); HELIX_GLOBAL_PINS turns pinning on at build time.',
  ),

  // --- Screenshots are allowed (product rule, 2026-09-30) ------------------
  GovernanceControl(
    'no screen-capture blocking on Android',
    'app/android/app/src/main/kotlin/com/helix/remote/MainActivity.kt',
    'FLAG_SECURE',
    absent: true,
    because:
        'people need to screenshot chats; capture blocking was removed on '
        '2026-09-30 and must not come back (AGENTS.md, product rules).',
  ),
  GovernanceControl(
    'no screen-capture blocking on Windows (handler is not built)',
    'app/windows/runner/CMakeLists.txt',
    'screen_security.cpp',
    absent: true,
    because:
        'the Windows display-affinity handler was removed with Android\'s.',
  ),
  GovernanceControl(
    'no screen-capture blocking on Windows (no display affinity)',
    'app/windows/runner/flutter_window.cpp',
    'SetWindowDisplayAffinity',
    absent: true,
    because: 'screenshots are allowed everywhere.',
  ),
  GovernanceControl(
    'a test keeps screenshots allowed',
    'app/test/product_rules_test.dart',
    'screenshots are allowed everywhere',
  ),

  // --- LOW-1: release shrinking ----------------------------------------------
  GovernanceControl(
    'release builds are minified',
    'app/android/app/build.gradle.kts',
    'isMinifyEnabled = true',
    because:
        'LOW-1 — shipping without R8 leaves debug metadata in the artifact. '
        'The v1 regression test for it was deleted with v1.',
  ),
  GovernanceControl(
    'release builds shrink resources',
    'app/android/app/build.gradle.kts',
    'isShrinkResources = true',
  ),

  // --- Logs and crash reports: no secrets, no content -----------------------
  GovernanceControl(
    'server logs are redacted at the write boundary',
    'server/lib/src/platform/observability/log.dart',
    'redactFields',
    because:
        'AGENTS.md: never log passwords, tokens, keys, message content, '
        'codes or full phone numbers. Redaction must stay where every call '
        'site goes through it.',
  ),
  GovernanceControl(
    'a test proves the log redaction',
    'server/test/platform/infra_test.dart',
    'redact',
  ),
  GovernanceControl(
    'the request id reaches the request log line',
    'server/lib/src/platform/http/pipeline.dart',
    "'request_id': requestId",
    because:
        'a request that cannot be found in the log by its id cannot be '
        'correlated with a client report.',
  ),

  // --- HIGH-4 / MED-9: dependency governance -------------------------------
  GovernanceControl(
    'lockfile policy describes the real workspace layout',
    '../docs/dependencies/WORKSPACE_LOCKFILE_POLICY.md',
    'enforce-lockfile',
    because:
        'HIGH-4 — the policy asserted a committed lockfile while the '
        'workspace gitignored it.',
  ),
  GovernanceControl(
    'file_picker is recorded as a direct dependency',
    '../docs/dependencies/DEPENDENCY_RISK_REGISTER.md',
    'not directly declared by Helix',
    absent: true,
    because:
        'MED-9 — file_picker IS directly declared in app/pubspec.yaml. '
        'The claim came from reading direct-vs-transitive off a workspace '
        'root lockfile, which classifies from the root package. Do not '
        'reinstate it.',
  ),
  GovernanceControl(
    'file_picker prerelease exception is recorded',
    'docs/adr/024-file-picker-prerelease-exception.md',
    'file_picker',
  ),
  GovernanceControl(
    'file_picker is still declared where the register says it is',
    'app/pubspec.yaml',
    'file_picker:',
    because: 'if this moves, the risk register entry needs to move with it.',
  ),
  GovernanceControl(
    'stale drift generated code fails CI',
    '../.github/workflows/ci.yml',
    'dart run tool/codegen.dart --check',
    because:
        'the risk register accepts drift_dev and build_runner on the '
        'condition that committed generated code can never silently diverge '
        'from the schema (ADR-027).',
  ),
  GovernanceControl(
    'the local database keeps the SQLCipher at-rest tests',
    'packages/helix_remote_db/test/encryption_test.dart',
    'P2-01 encrypted database rejects a wrong key',
    because:
        'the register carries the P2-01 wrong-key and no-plaintext tests '
        'over to helix_remote_db; the at-rest promise depends on them.',
  ),

  // --- MED-4: crash reporting ----------------------------------------------
  GovernanceControl(
    'crash reporter is wired to the zone handlers',
    'app/lib/main.dart',
    'CrashReporter.report',
    because:
        'MED-4 — the consent and event types existed for a while with no '
        'caller, so no crash was ever reported. The wiring is the control, '
        'not the types.',
  ),
  GovernanceControl(
    'crash reporting stays opt-in',
    'app/lib/core/engine/crash_reporter.dart',
    'if (!opted) return;',
    because:
        'reporting must require the person\'s opt-in AND the server\'s '
        'crash_reporting_upload flag. Weakening either half turns a '
        'privacy-first product into one that phones home by default.',
  ),
  GovernanceControl(
    'a crash report carries the exception type only',
    'app/lib/core/engine/crash_reporter.dart',
    'error.runtimeType.toString()',
    because:
        'no message text, stack trace, account or server address leaves '
        'the device.',
  ),
  GovernanceControl(
    'the crash sink is self-hosted',
    'server/lib/src/modules/ops/module.dart',
    'Routes.crashReport',
    because:
        'MED-4 asked for a self-hosted sink specifically. A vendor SDK '
        'in the client would satisfy the letter and not the intent.',
  ),
];

/// Every `.dart` path the regression matrix names must exist, so the matrix
/// cannot come to describe tests that were renamed or deleted. Paths in the
/// matrix are relative to `helix_remote/`.
List<String> regressionMatrixFailures() {
  const matrix = 'docs/security/REGRESSION_TEST_MATRIX.md';
  final file = File(matrix);
  if (!file.existsSync()) return ['$matrix does not exist'];
  final paths = RegExp(
    r'`([A-Za-z0-9_./-]+\.dart)`',
  ).allMatches(file.readAsStringSync()).map((m) => m.group(1)!).toSet();
  return [
    if (paths.isEmpty) '$matrix names no test files',
    for (final path in paths)
      if (!File(path).existsSync()) '$matrix names $path, which does not exist',
  ];
}

void main() {
  final missing = <String>[];
  for (final control in controls) {
    final failure = control.evaluate();
    if (failure != null) missing.add(failure);
  }
  missing.addAll(regressionMatrixFailures());

  if (missing.isNotEmpty) {
    stderr.writeln('Governance control verification failed:');
    for (final failure in missing) {
      stderr.writeln(' - $failure');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Governance control verification passed (${controls.length} controls).',
  );
}
