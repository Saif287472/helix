import 'dart:io';

import 'package:helix_remote_architecture_rules/helix_remote_architecture_rules.dart';
import 'package:test/test.dart';

/// Import boundaries and purity of helix_remote_engine (ARCHITECTURE_V2_PLAN
/// §6.1, §8; ADR-027, ADR-029).
void main() {
  final files = scanDartSources(Directory.current.path);

  void expectClean(List<ArchitectureRule> rules) {
    final violations = checkAll(files, rules);
    expect(violations, isEmpty, reason: describeViolations(violations));
  }

  bool inLib(String path) => path.startsWith('lib/');

  test('scans the engine sources', () {
    expect(files.map((f) => f.path), contains('lib/helix_remote_engine.dart'));
    expect(files.where((f) => inLib(f.path)).length, greaterThan(25));
  });

  test('follows the v2 package graph', () {
    expectClean(v2PackageRules('helix_remote_engine'));
  });

  test(
    'is pure Dart: no Flutter, no dart:io, no sqlite3 or drift, no HTTP',
    () {
      expectClean([
        ForbiddenDirectiveRule(
          name: 'no-flutter',
          reason:
              'the engine runs in the app, the FCM isolate, the CLI and tests.',
          forbidden: (uri) =>
              uri == 'dart:ui' || uri.startsWith('package:flutter/'),
        ),
        ForbiddenDirectiveRule(
          name: 'no-io',
          reason:
              'files, sockets and processes belong to the host and to '
              'helix_remote_api; the engine gets them injected.',
          forbidden: (uri) => uri == 'dart:io',
          appliesTo: inLib,
        ),
        ForbiddenDirectiveRule(
          name: 'no-database-drivers',
          reason: 'only helix_remote_db touches drift and sqlite3 (plan §8).',
          forbidden: (uri) =>
              uri.startsWith('package:drift/') ||
              uri.startsWith('package:sqlite3/'),
        ),
        ForbiddenDirectiveRule(
          name: 'no-http',
          reason: 'only helix_remote_api talks HTTP or WebSocket (plan §8).',
          forbidden: (uri) =>
              uri.startsWith('package:http/') ||
              uri.startsWith('package:web_socket_channel/'),
          appliesTo: inLib,
        ),
      ]);
    },
  );

  test('uses no globals: the clock and randomness are injected', () {
    final offenders = <String>[];
    for (final file in files.where((f) => inLib(f.path))) {
      final lines = File(file.path).readAsLinesSync();
      for (final (index, line) in lines.indexed) {
        final code = line.split('//').first;
        if (code.contains('DateTime.now(') ||
            code.contains('Random.secure(') ||
            code.contains('SecureCryptoRandom(') ||
            code.contains('print(')) {
          offenders.add('${file.path}:${index + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'engine code reads the injected clock/CryptoRandom and never prints '
          '(it logs nothing; secrets must not leak)',
    );
  });

  test('the v1 packages are not used', () {
    expectClean([
      ForbiddenDirectiveRule(
        name: 'no-v1-api',
        reason: 'the engine speaks the v2 clients only.',
        forbidden: (uri) =>
            uri == 'package:helix_remote_api/api.dart' ||
            uri.startsWith('package:helix_remote_api/api/') ||
            uri == 'package:helix_remote_crypto/helix_remote_crypto.dart' ||
            uri.startsWith('package:helix_remote_domain/'),
      ),
    ]);
  });
}
