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

  test('only the db layer touches the Postgres driver', () {
    expectClean([
      ForbiddenDirectiveRule(
        name: 'driver-isolation',
        reason:
            'use the Db/Tx interfaces (ADR-025); the driver stays in platform/db.',
        forbidden: anyPackage({'postgres'}),
        appliesTo: (path) =>
            path.startsWith('lib/') && !path.startsWith('lib/src/platform/db/'),
      ),
      ForbiddenDirectiveRule(
        name: 'storage-isolation',
        reason: 'use ObjectStorage; S3 signing stays in platform/blobs.',
        forbidden: anyPackage({'aws_signature_v4', 'aws_common'}),
        appliesTo: (path) =>
            path.startsWith('lib/') &&
            !path.startsWith('lib/src/platform/blobs/'),
      ),
      ForbiddenDirectiveRule(
        name: 'modules-use-the-platform',
        reason:
            'modules get infrastructure from ModuleContext, not from shelf_io or dart:io servers.',
        forbidden: (uri) => uri == 'package:shelf/shelf_io.dart',
        appliesTo: (path) => path.startsWith('lib/src/modules/'),
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
