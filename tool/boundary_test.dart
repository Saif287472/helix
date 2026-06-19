// Runs the architecture boundary checker and cycle detector as a test suite.
// P4-010: Forbidden import tests; P4-015: Circular dependency detection.

import 'dart:io';

import 'package:test/test.dart';

import 'check_boundaries.dart';
import 'dep_graph.dart' as graph;

void main() {
  late Directory root;

  setUpAll(() {
    root = _findRepoRoot();
  });

  test('no boundary violations exist', () async {
    final configFile = File(
      '${root.path}/docs/architecture/module_boundaries.json',
    );
    final violations = await checkBoundaries(root, configFile);

    if (violations.isNotEmpty) {
      final lines = violations.map(
        (v) =>
            '  ${v.source}:${v.line}: ${v.importUri}\n'
            '    -> ${v.target}\n'
            '    reason: ${v.reason}',
      );
      fail('Architecture boundary violations:\n${lines.join('\n')}');
    }
  });

  test('apps/helix_remote imports no packages/local/** files', () async {
    final configFile = File(
      '${root.path}/docs/architecture/module_boundaries.json',
    );
    final violations = await checkBoundaries(root, configFile);
    final remoteToLocal = violations.where(
      (v) =>
          v.source.startsWith('apps/helix_remote/') &&
          v.target.startsWith('packages/local/'),
    );
    expect(
      remoteToLocal,
      isEmpty,
      reason: 'Helix Remote must not import Local-classified packages',
    );
  });

  test('apps/helix_local imports no packages/remote/** files', () async {
    final configFile = File(
      '${root.path}/docs/architecture/module_boundaries.json',
    );
    final violations = await checkBoundaries(root, configFile);
    final localToRemote = violations.where(
      (v) =>
          v.source.startsWith('apps/helix_local/') &&
          v.target.startsWith('packages/remote/'),
    );
    expect(
      localToRemote,
      isEmpty,
      reason: 'Helix Local must not import Remote packages',
    );
  });

  test('packages/shared imports no product packages', () async {
    final configFile = File(
      '${root.path}/docs/architecture/module_boundaries.json',
    );
    final violations = await checkBoundaries(root, configFile);
    final sharedToProduct = violations.where(
      (v) =>
          v.source.startsWith('packages/shared/') &&
          (v.target.startsWith('packages/local/') ||
              v.target.startsWith('packages/remote/')),
    );
    expect(
      sharedToProduct,
      isEmpty,
      reason:
          'Shared packages must not import from either product package tree',
    );
  });

  test('workspace dependency graph has no cycles (P4-015)', () async {
    final cycles = await graph.detectCycles(root);
    expect(
      cycles,
      isEmpty,
      reason: 'Circular dependencies detected:\n${cycles.join('\n')}',
    );
  });

  test('all workspace packages are resolved and classified', () async {
    final packages = await loadWorkspacePackages(root);
    final packageNames = packages.map((package) => package.name).toSet();

    expect(packageNames, contains('helix_remote_calls'));
    expect(packageNames, contains('helix_remote_groups'));
    expect(packageNames, contains('helix_remote_backend'));
    expect(await checkWorkspacePackageClassifications(root), isEmpty);
  });

  test('unclassified workspace packages fail the boundary gate', () async {
    final temp = await Directory.systemTemp.createTemp('helix_boundary_test_');
    try {
      File('${temp.path}/pubspec.yaml').writeAsStringSync('''
name: temp_workspace
workspace:
  - packages/remote/unclassified
''');
      Directory(
        '${temp.path}/packages/remote/unclassified',
      ).createSync(recursive: true);
      File(
        '${temp.path}/packages/remote/unclassified/pubspec.yaml',
      ).writeAsStringSync('''
name: unclassified_remote_package
environment:
  sdk: ^3.12.0
''');
      File('${temp.path}/ownership-blast-radius.yaml').writeAsStringSync('''
packages: {}
''');

      final failures = await checkWorkspacePackageClassifications(temp);
      expect(failures, hasLength(1));
      expect(failures.single, contains('unclassified_remote_package'));
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
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
      throw StateError(
        'Could not find repo root from ${Directory.current.path}. '
        'Run this test from the repository root or any subdirectory.',
      );
    }
    dir = parent;
  }
}
