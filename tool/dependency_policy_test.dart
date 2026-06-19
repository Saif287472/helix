import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  late Directory root;

  setUpAll(() {
    root = _findRepoRoot();
  });

  test('direct pubspec dependencies do not use any', () async {
    final pubspecs = await _pubspecs(root).toList();
    final offenders = <String>[];

    for (final pubspec in pubspecs) {
      final lines = pubspec.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(r'^\s+[A-Za-z0-9_]+:\s+any\s*$').hasMatch(lines[i])) {
          offenders.add('${_relativePath(root, pubspec)}:${i + 1}');
        }
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('workspace lockfile risk markers are documented', () {
    final lockfile = File('${root.path}/pubspec.lock');
    final riskRegister = File(
      '${root.path}/docs/dependencies/DEPENDENCY_RISK_REGISTER.md',
    ).readAsStringSync();
    final yaml = loadYaml(lockfile.readAsStringSync()) as YamlMap;
    final packages = yaml['packages'] as YamlMap;
    final undocumented = <String>[];

    for (final entry in packages.entries) {
      final packageName = entry.key as String;
      final package = entry.value as YamlMap;
      final version = package['version'] as String?;
      if (version == null) continue;
      final isRisk = version.contains('+eol') || version.contains('-');
      if (isRisk && !riskRegister.contains('`$packageName`')) {
        undocumented.add('$packageName $version');
      }
    }

    expect(undocumented, isEmpty, reason: undocumented.join('\n'));
  });

  test('workspace package names are unique', () async {
    final rootPubspec =
        loadYaml(File('${root.path}/pubspec.yaml').readAsStringSync())
            as YamlMap;
    final workspace = (rootPubspec['workspace'] as YamlList).cast<String>();
    final names = <String>{};
    final duplicates = <String>[];

    for (final path in workspace) {
      final pubspec = File('${root.path}/$path/pubspec.yaml');
      final yaml = loadYaml(pubspec.readAsStringSync()) as YamlMap;
      final name = yaml['name'] as String;
      if (!names.add(name)) duplicates.add(name);
    }

    expect(duplicates, isEmpty, reason: duplicates.join('\n'));
  });
}

Stream<File> _pubspecs(Directory root) async* {
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    final relative = _relativePath(root, entity);
    final segments = relative.split('/');
    if (segments.any({'.dart_tool', '.git', 'build'}.contains)) continue;
    if (entity is File && entity.path.endsWith('pubspec.yaml')) {
      yield entity;
    }
  }
}

Directory _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        File('${dir.path}/AGENTS.md').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not find repo root from ${Directory.current}');
    }
    dir = parent;
  }
}

String _relativePath(Directory root, FileSystemEntity entity) {
  var rootPath = root.absolute.path.replaceAll('\\', '/');
  final entityPath = entity.absolute.path.replaceAll('\\', '/');
  if (!rootPath.endsWith('/')) rootPath = '$rootPath/';
  return entityPath.startsWith(rootPath)
      ? entityPath.substring(rootPath.length)
      : entityPath;
}
