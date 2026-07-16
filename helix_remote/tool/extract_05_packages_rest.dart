import 'dart:io';

// Extracts: domain · api · storage · calls · groups packages + contracts
// Output:   helix/docs/codebase/remote_5_packages_rest.txt

void main() async {
  final toolDir = File.fromUri(Platform.script).parent.path;
  final repoRoot = Directory(toolDir).parent.path;
  final helixRoot = Directory(repoRoot).parent.path;
  final docsDir = '$helixRoot/docs/codebase';

  final files = <String>[];

  // Packages: domain, api, storage, calls, groups
  for (final pkg in [
    'helix_remote_domain',
    'helix_remote_api',
    'helix_remote_storage',
    'helix_remote_calls',
    'helix_remote_groups',
  ]) {
    _addFile(files, repoRoot, 'packages/$pkg/pubspec.yaml');
    files.addAll(_collect('$repoRoot/packages/$pkg/lib', exts: ['.dart']));
  }

  // Contracts (JSON + YAML — the API surface definitions)
  files.addAll(_collect('$repoRoot/contracts', exts: ['.json', '.yaml']));

  await _write(
    docsDir: docsDir,
    name: 'remote_5_packages_rest',
    title:
        'HELIX-REMOTE  ·  PACKAGES: DOMAIN · API · STORAGE · CALLS · GROUPS  +  CONTRACTS',
    subtitle:
        'helix_remote_{domain, api, storage, calls, groups} · contracts/remote-rest-openapi · contracts/remote-realtime',
    repoRoot: repoRoot,
    files: files,
  );
}

// ---------------------------------------------------------------------------

void _addFile(List<String> out, String root, String rel) {
  final f = File('$root/$rel');
  if (f.existsSync()) out.add(f.path);
}

List<String> _collect(
  String dirPath, {
  List<String> exts = const ['.dart', '.yaml', '.json'],
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
