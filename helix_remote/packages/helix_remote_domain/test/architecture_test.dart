import 'dart:io';

import 'package:helix_remote_architecture_rules/helix_remote_architecture_rules.dart';
import 'package:test/test.dart';

void main() {
  final files = scanDartSources(Directory.current.path);

  void expectClean(List<ArchitectureRule> rules) {
    final violations = checkAll(files, rules);
    expect(violations, isEmpty, reason: describeViolations(violations));
  }

  test('follows the v2 package graph: it depends on no Helix package', () {
    expect(files, isNotEmpty);
    expectClean(v2PackageRules('helix_remote_domain'));
  });

  test('is pure, portable Dart: no Flutter, no dart:io in lib', () {
    expectClean([
      ForbiddenDirectiveRule(
        name: 'pure-domain',
        reason:
            'value types shared by the server and every client must not '
            'touch the platform.',
        forbidden: (uri) =>
            uri == 'dart:io' ||
            uri == 'dart:ui' ||
            uri.startsWith('package:flutter/'),
        appliesTo: (path) => path.startsWith('lib/'),
      ),
    ]);
  });
}
