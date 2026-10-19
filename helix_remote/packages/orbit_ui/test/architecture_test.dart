import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_architecture_rules/helix_remote_architecture_rules.dart';

/// orbit_ui is a leaf: screens take a model and actions and never reach the
/// engine, the database, the API or the app (orbit/flutter/AGENTS.md, "The
/// one rule that makes Part B safe").
void main() {
  final files = scanDartSources(Directory.current.path);

  test('follows the v2 package graph: it depends on no Helix package', () {
    expect(files, isNotEmpty);
    final violations = checkAll(files, v2PackageRules('orbit_ui'));
    expect(violations, isEmpty, reason: describeViolations(violations));
  });
}
