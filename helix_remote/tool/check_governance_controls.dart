import 'dart:io';

/// Keeps high-value governance claims tied to concrete repository evidence.
/// Add a row here when a document makes a durable implementation assertion.
void main() {
  const checks = <(String, String, String)>[
    (
      'iOS support decision',
      'docs/adr/023-ios-support-decision.md',
      'does not currently ship an iOS target',
    ),
    (
      'production hardening ADR',
      'docs/adr/022-production-hardening-boundaries.md',
      'SQLite deployment',
    ),
    ('release obfuscation', 'scripts/remote_release_gate.ps1', '--obfuscate'),
    (
      'Android backup refusal',
      'app/android/app/src/main/AndroidManifest.xml',
      'android:allowBackup="false"',
    ),
    (
      'Android TLS pin config',
      'app/android/app/src/main/res/xml/helix_remote_network_security.xml',
      'hr.agiletechbd.com',
    ),
    ('localization delegate', 'app/lib/l10n/helix_localizations.dart', "'bn'"),
  ];
  final missing = <String>[];
  for (final (name, path, marker) in checks) {
    final file = File(path);
    if (!file.existsSync() || !file.readAsStringSync().contains(marker)) {
      missing.add('$name: $path must contain $marker');
    }
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
    'Governance control verification passed (${checks.length} controls).',
  );
}
