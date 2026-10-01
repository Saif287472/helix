import 'dart:io';

import 'package:helix_remote_architecture_rules/helix_remote_architecture_rules.dart';
import 'package:test/test.dart';

/// Import boundaries for the v2 server (ADR-026, ADR-029). Later phases add
/// rules here as the platform and modules land (plan §8).
void main() {
  final files = scanDartSources(Directory.current.path);

  void expectClean(List<ArchitectureRule> rules) {
    final violations = checkAll(files, rules);
    expect(violations, isEmpty, reason: describeViolations(violations));
  }

  test('scans the server sources', () {
    expect(files.map((f) => f.path), contains('lib/helix_remote_server.dart'));
  });

  test('depends only on the packages declared for the server', () {
    expectClean(v2PackageRules('helix_remote_server'));
  });

  test('modules reach each other only through api.dart', () {
    expectClean([ModuleBoundaryRule(packageName: 'helix_remote_server')]);
  });

  test('uses PostgreSQL, never SQLite', () {
    expectClean([
      ForbiddenDirectiveRule(
        name: 'no-sqlite',
        reason: 'the v2 server stores everything in PostgreSQL (ADR-025).',
        forbidden: anyPackage({'sqlite3', 'drift', 'sqlite3_flutter_libs'}),
      ),
    ]);
  });

  test('is pure Dart', () {
    expectClean([
      ForbiddenDirectiveRule(
        name: 'no-flutter',
        reason: 'the server must not depend on Flutter.',
        forbidden: (uri) =>
            uri.startsWith('package:flutter/') || uri.startsWith('dart:ui'),
      ),
    ]);
  });
}
