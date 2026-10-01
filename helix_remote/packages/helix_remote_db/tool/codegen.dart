// Regenerates everything drift generates for this package, formatted the way
// the repository's format gate expects:
//
//   dart run tool/codegen.dart           regenerate
//   dart run tool/codegen.dart --check   regenerate, and fail if anything
//                                        changed (CI and scripts/verify.*)
//
// Generated files are committed (ADR-027). They are the `*.g.dart` parts,
// the schema dumps in drift_schemas/ and the schema helpers in
// test/drift/helix/generated/ (plus lib/src/database.steps.dart once a second
// schema version exists). The migration test itself is written once by
// `make-migrations` and then maintained by hand, so it is not compared.
import 'dart:io';

Future<void> main(List<String> args) async {
  final check = args.contains('--check');
  final root = File.fromUri(Platform.script).parent.parent;
  Directory.current = root;

  final before = _snapshot();
  // Delete the code outputs first: build_runner's cache would otherwise keep
  // a hand-edited generated file as long as its inputs are unchanged. The
  // schema dumps are history (older versions cannot be regenerated) and are
  // never deleted.
  for (final file in _generatedFiles()) {
    if (!_relative(file.path).startsWith('drift_schemas/')) file.deleteSync();
  }
  await _run(['run', 'build_runner', 'build']);
  await _run(['run', 'drift_dev', 'make-migrations']);
  // make-migrations writes the test helpers only once two versions exist;
  // generate them from schema 1 onwards so the migration test always runs.
  await _run([
    'run',
    'drift_dev',
    'schema',
    'generate',
    'drift_schemas/helix/',
    'test/drift/helix/generated/',
  ]);
  final generated = _generatedFiles().map((f) => f.path).toList();
  if (generated.any((p) => p.endsWith('.dart'))) {
    await _run(['format', ...generated.where((p) => p.endsWith('.dart'))]);
  }
  final after = _snapshot();

  final changed = <String>{
    for (final path in {...before.keys, ...after.keys})
      if (before[path] != after[path]) path,
  }.toList()..sort();

  if (changed.isEmpty) {
    stdout.writeln('drift generated code is up to date.');
    return;
  }
  stdout.writeln(
    '${check ? 'Stale' : 'Regenerated'} drift output '
    '(${changed.length} file(s)):',
  );
  for (final path in changed) {
    stdout.writeln('  $path');
  }
  if (check) {
    stdout.writeln(
      'Run `dart run tool/codegen.dart` in packages/helix_remote_db and '
      'commit the result.',
    );
    exitCode = 1;
  }
}

Iterable<File> _generatedFiles() sync* {
  bool isGenerated(String path) =>
      (path.startsWith('lib/') &&
          (path.endsWith('.g.dart') || path.endsWith('.steps.dart'))) ||
      path.startsWith('drift_schemas/') ||
      (path.startsWith('test/drift/') && path.contains('/generated/'));

  for (final dir in ['lib', 'drift_schemas', 'test/drift']) {
    final directory = Directory(dir);
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (isGenerated(_relative(entity.path))) yield entity;
    }
  }
}

/// Generated file contents by relative path, line endings normalised (a
/// Windows checkout may have CRLF).
Map<String, String> _snapshot() => {
  for (final file in _generatedFiles())
    _relative(file.path): file.readAsStringSync().replaceAll('\r\n', '\n'),
};

String _relative(String path) {
  final normalized = path.replaceAll(r'\', '/');
  return normalized.startsWith('./') ? normalized.substring(2) : normalized;
}

Future<void> _run(List<String> args) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    args,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) {
    stderr.writeln('dart ${args.join(' ')} failed (exit $code)');
    exit(code);
  }
}
