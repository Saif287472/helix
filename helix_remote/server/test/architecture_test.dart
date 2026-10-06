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
    // test/client/ drives the server through the v2 client packages: the
    // API clients (Phase C3a) and the engine with the packages it sits on
    // (Phase C3b), plus the v2 CLI built on it. The server itself never depends on them, so only those
    // test files may import them, and nothing else beyond the server's own
    // packages.
    bool clientTest(SourceFile f) => f.path.startsWith('test/client/');
    final server = files.where((f) => !clientTest(f)).toList();
    final clientTests = files.where(clientTest).toList();
    final violations = [
      ...checkAll(server, v2PackageRules('helix_remote_server')),
      ...checkAll(clientTests, [
        InternalDependencyRule(
          selfPackage: 'helix_remote_server',
          allowed: {
            'helix_remote_protocol',
            'helix_remote_api',
            'helix_remote_cli',
            'helix_remote_crypto',
            'helix_remote_db',
            'helix_remote_engine',
          },
        ),
      ]),
    ];
    expect(violations, isEmpty, reason: describeViolations(violations));
    expect(clientTests, isNotEmpty);
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
        name: 'push-isolation',
        reason: 'use PushProvider; Google auth stays in platform/push.',
        forbidden: anyPackage({'googleapis_auth'}),
        appliesTo: (path) =>
            path.startsWith('lib/') &&
            !path.startsWith('lib/src/platform/push/'),
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

  test('sessions are minted only in identity/application/sessions.dart', () {
    final offenders = <String>[];
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>()) {
      final path = file.path.replaceAll(r'\', '/');
      if (!path.endsWith('.dart')) continue;
      if (path.endsWith('identity/application/sessions.dart') ||
          path.endsWith('identity/domain/jwt.dart')) {
        continue;
      }
      if (file.readAsStringSync().contains('AccessClaims(')) {
        offenders.add(path);
      }
    }
    expect(offenders, isEmpty, reason: 'AGENTS.md: one session mint point');
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
