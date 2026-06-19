import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('critical risk areas have scenario coverage rows', () {
    final root = _findRepoRoot();
    final plan = File(
      '${root.path}/docs/quality/RISK_BASED_COVERAGE.md',
    ).readAsStringSync();

    for (final area in [
      'Remote auth and identity',
      'Remote crypto',
      'Remote storage',
      'Remote sync/outbox',
      'Local wipe/storage',
      'Privacy/deletion',
    ]) {
      expect(plan, contains('| $area |'), reason: area);
    }
    expect(plan, contains('Branch coverage'));
    expect(plan, contains('build/coverage/'));
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
      throw StateError('Could not find repo root from ${Directory.current}');
    }
    dir = parent;
  }
}
