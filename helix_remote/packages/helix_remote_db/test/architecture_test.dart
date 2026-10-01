import 'dart:io';

import 'package:helix_remote_architecture_rules/helix_remote_architecture_rules.dart';
import 'package:test/test.dart';

void main() {
  final files = scanDartSources(Directory.current.path);

  void expectClean(List<ArchitectureRule> rules) {
    final violations = checkAll(files, rules);
    expect(violations, isEmpty, reason: describeViolations(violations));
  }

  test('follows the v2 package graph', () {
    expect(files.map((f) => f.path), contains('lib/helix_remote_db.dart'));
    expectClean(v2PackageRules('helix_remote_db'));
  });

  test('is pure Dart: no Flutter, so background isolates and the CLI can '
      'open it', () {
    expectClean([
      ForbiddenDirectiveRule(
        name: 'no-flutter',
        reason:
            'helix_remote_db runs in the FCM background isolate and the CLI '
            '(ADR-027).',
        forbidden: (uri) =>
            uri == 'dart:ui' ||
            uri.startsWith('package:flutter/') ||
            uri.startsWith('package:sqlite3_flutter_libs/'),
      ),
    ]);
  });

  test(
    'only opening.dart and database.dart touch sqlite3 and drift backends',
    () {
      expectClean([
        ForbiddenDirectiveRule(
          name: 'backend-isolation',
          reason:
              'open the database through HelixDb.open (SQLCipher key checks); '
              'DAOs use drift queries only.',
          forbidden: (uri) =>
              uri.startsWith('package:sqlite3/') ||
              uri == 'package:drift/native.dart',
          appliesTo: (path) =>
              path.startsWith('lib/') &&
              path != 'lib/src/opening.dart' &&
              path != 'lib/src/database.dart',
        ),
      ]);
    },
  );
}
