import 'dart:io';

import 'package:helix_remote_architecture_rules/helix_remote_architecture_rules.dart';
import 'package:test/test.dart';

void main() {
  final files = scanDartSources(Directory.current.path);

  void expectClean(List<ArchitectureRule> rules) {
    final violations = checkAll(files, rules);
    expect(violations, isEmpty, reason: describeViolations(violations));
  }

  bool isV2(String path) =>
      path == 'lib/v2.dart' ||
      path.startsWith('lib/src/v2/') ||
      path.startsWith('test/v2/');

  test('follows the v2 package graph', () {
    expect(files.where((f) => isV2(f.path)), isNotEmpty);
    expectClean(v2PackageRules('helix_remote_crypto'));
  });

  test('v2 is pure Dart: no Flutter, no dart:io, no platform storage', () {
    expectClean([
      ForbiddenDirectiveRule(
        name: 'pure-crypto-v2',
        reason:
            'v2 crypto is shared by the app, the background isolate and the '
            'CLI; storage belongs to helix_remote_db (ARCHITECTURE_V2_PLAN.md '
            '§6.1).',
        forbidden: (uri) =>
            uri == 'dart:io' ||
            uri == 'dart:ui' ||
            uri.startsWith('package:flutter/') ||
            uri.startsWith('package:flutter_secure_storage/') ||
            uri.startsWith('package:cryptography_flutter/'),
        appliesTo: (path) =>
            path == 'lib/v2.dart' || path.startsWith('lib/src/v2/'),
      ),
    ]);
  });

  test('v2 does not use the v1 crypto API', () {
    expectClean([
      ForbiddenDirectiveRule(
        name: 'no-v1-crypto',
        reason:
            'v1 crypto files were deleted at Phase X; v2 code uses only '
            'src/v2/.',
        forbidden: (uri) =>
            (uri.startsWith('package:helix_remote_crypto/') &&
                uri != 'package:helix_remote_crypto/v2.dart' &&
                !uri.startsWith('package:helix_remote_crypto/src/v2/')) ||
            (!uri.startsWith('package:') &&
                !uri.startsWith('dart:') &&
                (uri.contains('..') ||
                    (uri.contains('/') && !uri.startsWith('src/v2/')))),
        appliesTo: isV2,
      ),
    ]);
  });
}
