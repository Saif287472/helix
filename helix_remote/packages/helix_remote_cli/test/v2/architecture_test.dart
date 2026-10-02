import 'dart:io';

import 'package:helix_remote_architecture_rules/helix_remote_architecture_rules.dart';
import 'package:test/test.dart';

/// The v2 CLI (`lib/v2.dart`, `lib/src/v2/`, `bin/helix_v2.dart`) is built
/// on the engine and must not reach for v1 code, which stays only until the
/// cutover. The v1 CLI files are not checked here.
void main() {
  final files = scanDartSources(Directory.current.path);

  bool isV2(String path) =>
      path == 'lib/v2.dart' ||
      path.startsWith('lib/src/v2/') ||
      path == 'bin/helix_v2.dart' ||
      path.startsWith('test/v2/');

  test('scans the v2 sources', () {
    expect(files.where((f) => isV2(f.path)).length, greaterThan(5));
  });

  test('v2 code uses no v1 packages and no v1 CLI files', () {
    final violations = checkAll(files, [
      ForbiddenDirectiveRule(
        name: 'no-v1',
        reason: 'v1 is retired at cutover (ADR-029).',
        forbidden: (uri) =>
            anyPackage(v1RetiredPackages)(uri) ||
            uri == 'package:helix_remote_api/api.dart' ||
            uri.startsWith('package:helix_remote_api/api/') ||
            uri == 'package:helix_remote_crypto/helix_remote_crypto.dart' ||
            uri.startsWith('package:helix_remote_domain/') ||
            uri == 'package:helix_remote_cli/helix_remote_cli.dart' ||
            uri.startsWith('package:helix_remote_cli/src/cli_'),
        appliesTo: isV2,
      ),
      ForbiddenDirectiveRule(
        name: 'no-flutter',
        reason: 'the CLI is a plain Dart program.',
        forbidden: (uri) =>
            uri == 'dart:ui' || uri.startsWith('package:flutter/'),
        appliesTo: isV2,
      ),
      ForbiddenDirectiveRule(
        name: 'no-drivers',
        reason: 'the database is reached through helix_remote_db only.',
        forbidden: (uri) =>
            uri.startsWith('package:drift/') ||
            uri.startsWith('package:sqlite3/') ||
            uri.startsWith('package:http/'),
        appliesTo: (path) => isV2(path) && path.startsWith('lib/'),
      ),
    ]);
    expect(violations, isEmpty, reason: describeViolations(violations));
  });
}
