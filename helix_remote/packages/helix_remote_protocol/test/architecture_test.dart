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
    expect(files, isNotEmpty);
    expectClean(v2PackageRules('helix_remote_protocol'));
  });

  test('is pure, portable Dart: no Flutter, no dart:io in lib', () {
    expectClean([
      ForbiddenDirectiveRule(
        name: 'pure-protocol',
        reason:
            'the protocol is shared by server, app, admin and CLI; it must not '
            'touch the platform (ADR-028).',
        forbidden: (uri) =>
            uri == 'dart:io' ||
            uri == 'dart:ui' ||
            uri.startsWith('package:flutter/'),
        appliesTo: (path) => path.startsWith('lib/'),
      ),
    ]);
  });
}
