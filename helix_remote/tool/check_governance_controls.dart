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
    'production hardening ADR',
    'docs/adr/022-production-hardening-boundaries.md',
    'SQLite deployment',
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

  // --- Certificate pinning -------------------------------------------------
  GovernanceControl(
    'Android TLS pin config',
    'app/android/app/src/main/res/xml/helix_remote_network_security.xml',
    'hr.agiletechbd.com',
  ),

  // --- HIGH-2: screen capture protection, both platforms -------------------
  GovernanceControl(
    'Android screen capture protection',
    'app/android/app/src/main/kotlin/com/helix/remote/MainActivity.kt',
    'com.helix.remote/screen_security',
    because:
        'HIGH-2 — FLAG_SECURE keeps message content out of screenshots, '
        'recordings, and the recents thumbnail.',
  ),
  GovernanceControl(
    'Windows screen capture protection',
    'app/windows/runner/screen_security.cpp',
    'SetWindowDisplayAffinity',
    because:
        'HIGH-2 was closed on Android first and left the Windows desktop '
        'build capturable. The runner must keep serving the same channel.',
  ),
  GovernanceControl(
    'Windows capture handler is compiled in',
    'app/windows/runner/CMakeLists.txt',
    'screen_security.cpp',
    because: 'a handler that is not in the build protects nothing.',
  ),

  // --- HIGH-1: log redaction ----------------------------------------------
  GovernanceControl(
    'client log redaction',
    'app/lib/services/app_logger.dart',
    'redactLogLine',
    because:
        'HIGH-1 — LOG_REDACTION.md mandates redaction of tokens, keys, '
        'and payloads, and the log is exported through the share sheet. '
        'Redaction must stay at the write boundary, where call sites cannot '
        'bypass it.',
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

  // --- Localization --------------------------------------------------------
  GovernanceControl(
    'localization delegate',
    'app/lib/l10n/helix_localizations.dart',
    "'bn'",
  ),
];

void main() {
  final missing = <String>[];
  for (final control in controls) {
    final failure = control.evaluate();
    if (failure != null) missing.add(failure);
  }

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
