import 'dart:io';

// Runs all 5 helix_remote extractors in sequence.
// Usage (from helix_remote/): dart run tool/extract_all.dart

void main() async {
  final toolDir = File.fromUri(Platform.script).parent.path;
  final repoRoot = Directory(toolDir).parent.path;

  final scripts = [
    'extract_01_backend_infrastructure.dart',
    'extract_02_backend_modules.dart',
    'extract_03_app.dart',
    'extract_04_packages_crypto_sync.dart',
    'extract_05_packages_rest.dart',
    'extract_06_admin_and_cli.dart',
  ];

  for (final script in scripts) {
    stdout.writeln('\n── $script ──');
    final result = await Process.run('dart', [
      'run',
      'tool/$script',
    ], workingDirectory: repoRoot);
    stdout.write(result.stdout);
    if ((result.stderr as String).isNotEmpty) stderr.write(result.stderr);
    if (result.exitCode != 0) {
      stderr.writeln('FAILED: $script (exit ${result.exitCode})');
      exit(result.exitCode);
    }
  }

  stdout.writeln('\nDone. All extracts written to helix/docs/codebase/');
}
