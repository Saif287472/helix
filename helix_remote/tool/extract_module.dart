import 'dart:io';

// Extracts: one backend module, plus the few shared files any module needs
//           to be understood on its own.
// Output:   helix/docs/codebase/remote_module_<name>.txt
//
// Usage (from helix_remote/):
//   dart run tool/extract_module.dart groups
//   dart run tool/extract_module.dart --list
//
// The numbered extractors (extract_01..06) bundle a whole subsystem, which
// is what you want for onboarding or a cross-module review. This one exists
// for the far more common case: changing one feature. Pulling `messaging`
// used to mean generating a file that also contained every other module -
// `groups` alone was 2000 lines - so the bundle was mostly context you were
// never going to read.

/// Files included alongside every module, because a module's routes are not
/// readable without them: the error shape its handlers throw, the session
/// claims its auth checks read, and the repository interfaces it persists
/// through. Deliberately short - anything longer stops being shared context
/// and starts being the whole-subsystem bundle again.
const _sharedFiles = [
  'backend/lib/src/app_error.dart',
  'backend/lib/src/jwt.dart',
  'backend/lib/src/repositories.dart',
];

void main(List<String> args) async {
  final toolDir = File.fromUri(Platform.script).parent.path;
  final repoRoot = Directory(toolDir).parent.path;
  final helixRoot = Directory(repoRoot).parent.path;
  final docsDir = '$helixRoot/docs/codebase';
  final modulesDir = '$repoRoot/backend/lib/src/modules';

  final available = _availableModules(modulesDir);

  if (args.contains('--list') || args.contains('-l')) {
    stdout.writeln('Backend modules:');
    for (final m in available) {
      stdout.writeln('  $m');
    }
    return;
  }

  final positional = args.where((a) => !a.startsWith('-')).toList();
  if (positional.length != 1) {
    stderr.writeln('Usage: dart run tool/extract_module.dart <module>');
    stderr.writeln('       dart run tool/extract_module.dart --list');
    stderr.writeln('\nAvailable: ${available.join(', ')}');
    exit(2);
  }

  final name = positional.single;
  if (!available.contains(name)) {
    stderr.writeln('Unknown module: $name');
    stderr.writeln('Available: ${available.join(', ')}');
    exit(2);
  }

  // A module is either a folder of `part` files (groups, calls, auth) or a
  // single flat file (messaging, prekeys, ...). Both shapes resolve here so
  // callers don't have to know which one a given module currently is - that
  // changes as modules get split.
  final files = <String>[];
  final entry = File('$modulesDir/$name.dart');
  if (entry.existsSync()) files.add(entry.path);
  final dir = Directory('$modulesDir/$name');
  if (dir.existsSync()) files.addAll(_collect(dir.path));
  final doc = File('$modulesDir/$name.module.md');
  if (doc.existsSync()) files.insert(0, doc.path);
  final dirDoc = File('$modulesDir/$name/MODULE.md');
  if (dirDoc.existsSync()) files.insert(0, dirDoc.path);

  for (final shared in _sharedFiles) {
    final f = File('$repoRoot/$shared');
    if (f.existsSync()) files.add(f.path);
  }

  await _write(
    docsDir: docsDir,
    name: 'remote_module_$name',
    title: 'HELIX-REMOTE  ·  BACKEND MODULE: ${name.toUpperCase()}',
    subtitle:
        'module sources + shared context '
        '(${_sharedFiles.map((f) => f.split('/').last).join(' · ')})',
    repoRoot: repoRoot,
    files: files,
  );
}

/// Module names, from both shapes: `<name>.dart` and `<name>/`.
List<String> _availableModules(String modulesDir) {
  final dir = Directory(modulesDir);
  if (!dir.existsSync()) return [];
  final names = <String>{};
  for (final e in dir.listSync(followLinks: false)) {
    final base = e.path.replaceAll('\\', '/').split('/').last;
    if (e is File && base.endsWith('.dart')) {
      names.add(base.substring(0, base.length - '.dart'.length));
    } else if (e is Directory) {
      names.add(base);
    }
  }
  return names.toList()..sort();
}

// ---------------------------------------------------------------------------

List<String> _collect(
  String dirPath, {
  List<String> exts = const ['.dart', '.md'],
  List<String> exclude = const [],
}) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return [];
  final results = <String>[];
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final p = e.path.replaceAll('\\', '/');
    if (!exts.any(p.endsWith)) continue;
    if (exclude.any(p.contains)) continue;
    results.add(e.path);
  }
  results.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return results;
}

Future<void> _write({
  required String docsDir,
  required String name,
  required String title,
  required String subtitle,
  required String repoRoot,
  required List<String> files,
}) async {
  const sep =
      '================================================================================';
  final date = DateTime.now().toIso8601String().substring(0, 10);
  final root = repoRoot.replaceAll('\\', '/');
  final buf = StringBuffer();

  buf.writeln(sep);
  buf.writeln(title);
  buf.writeln(subtitle);
  buf.writeln('Generated: $date  ·  Files: ${files.length}');
  buf.writeln(sep);
  buf.writeln();
  buf.writeln('INDEX:');
  for (var i = 0; i < files.length; i++) {
    final rel = files[i].replaceAll('\\', '/').replaceFirst('$root/', '');
    buf.writeln('  [${_n(i)}] $rel');
  }

  for (var i = 0; i < files.length; i++) {
    final rel = files[i].replaceAll('\\', '/').replaceFirst('$root/', '');
    buf.writeln();
    buf.writeln(sep);
    buf.writeln('FILE [${_n(i)}]: $rel');
    buf.writeln(sep);
    final content = File(files[i]).readAsStringSync();
    buf.write(content);
    if (!content.endsWith('\n')) buf.writeln();
  }

  await Directory(docsDir).create(recursive: true);
  final out = File('$docsDir/$name.txt');
  await out.writeAsString(buf.toString());
  final kb = (buf.length / 1024).toStringAsFixed(1);
  stdout.writeln('✓  $name.txt  ($kb KB, ${files.length} files)');
  stdout.writeln('   → ${out.path}');
}

String _n(int i) => (i + 1).toString().padLeft(2, '0');
