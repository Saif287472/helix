import 'dart:io';

// Runs all 2 helix_local extractors in sequence.
// Usage (from helix_local/): dart run tool/extract_all.dart

void main() async {
  final toolDir = File.fromUri(Platform.script).parent.path;
  final repoRoot = Directory(toolDir).parent.path;

  final scripts = [
    'extract_01_app.dart',
    'extract_02_packages.dart',
  ];

  for (final script in scripts) {
    stdout.writeln('\n── $script ──');
    final result = await Process.run(
      'dart',
      ['run', 'tool/$script'],
      workingDirectory: repoRoot,
    );
    stdout.write(result.stdout);
    if ((result.stderr as String).isNotEmpty) stderr.write(result.stderr);
    if (result.exitCode != 0) {
      stderr.writeln('FAILED: $script (exit ${result.exitCode})');
      exit(result.exitCode);
    }
  }

  stdout.writeln('\nDone. All extracts written to helix/docs/codebase/');
}
