import 'dart:io';

import 'package:helix_remote_architecture_rules/helix_remote_architecture_rules.dart';
import 'package:test/test.dart';

/// Import boundaries for helix_remote_api (ARCHITECTURE_V2_PLAN.md §6.1, §8).
/// The whole package is checked, v1 files included: the v1 API depends only
/// on helix_remote_domain, which the v2 graph allows.
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

  test('scans the v2 sources', () {
    expect(files.map((f) => f.path), contains('lib/v2.dart'));
    expect(files.where((f) => isV2(f.path)).length, greaterThan(15));
  });

  test('follows the v2 package graph', () {
    expectClean(v2PackageRules('helix_remote_api'));
  });

  test('v2 code does not use the v1 API or the domain models', () {
    expectClean([
      ForbiddenDirectiveRule(
        name: 'v2-isolation',
        reason:
            'v2 clients speak helix_remote_protocol DTOs only; the v1 API is '
            'retired at Phase A1.',
        forbidden: (uri) =>
            uri.startsWith('package:helix_remote_api/api') ||
            uri.startsWith('package:helix_remote_domain/'),
        appliesTo: isV2,
      ),
    ]);
  });

  test('is pure Dart: no Flutter', () {
    expectClean([
      ForbiddenDirectiveRule(
        name: 'no-flutter',
        reason: 'the engine, the CLI and the FCM isolate use this package.',
        forbidden: (uri) =>
            uri == 'dart:ui' || uri.startsWith('package:flutter/'),
      ),
    ]);
  });

  test('dart:io is confined to the socket adapter, so the web admin '
      'console can compile the clients', () {
    expectClean([
      ForbiddenDirectiveRule(
        name: 'io-isolation',
        reason:
            'only lib/src/v2/realtime/io_socket.dart (behind a conditional '
            'import) may use dart:io.',
        forbidden: (uri) => uri == 'dart:io',
        appliesTo: (path) =>
            path.startsWith('lib/src/v2/') &&
            path != 'lib/src/v2/realtime/io_socket.dart',
      ),
    ]);
  });

  test('only the transport and the facades touch package:http', () {
    expectClean([
      ForbiddenDirectiveRule(
        name: 'http-isolation',
        reason: 'clients go through HelixTransport (auth, retries, errors).',
        forbidden: (uri) => uri.startsWith('package:http/'),
        appliesTo: (path) =>
            path.startsWith('lib/src/v2/') &&
            path != 'lib/src/v2/transport/transport.dart' &&
            path != 'lib/src/v2/helix_api.dart',
      ),
    ]);
  });
}
