import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory root;

  setUpAll(() {
    root = _findRepoRoot();
  });

  test(
    'backend architecture marks Go and production stores as target-state',
    () {
      final adr = _read(
        root,
        'docs/adr/019-dart-shelf-backend-authoritative.md',
      );
      final architecture = _read(
        root,
        'docs/architecture/remote_backend_architecture.md',
      );

      expect(adr, contains('Dart/Shelf'));
      expect(adr, contains('Go/Chi'));
      expect(adr, contains('target-state'));
      expect(architecture, contains('Superseded'));
      expect(architecture, contains('Dart/Shelf modular'));
      expect(architecture, contains('target-state ideas'));
    },
  );

  test('privacy claims do not assert implemented SQLCipher or full E2EE', () {
    final claims = _read(root, 'docs/product/PRIVACY_CLAIM_MATRIX.md');

    expect(claims, isNot(contains('Persistent SQLCipher databases')));
    expect(claims, contains('not SQLCipher-encrypted'));
    expect(claims, contains('Blocked for strong claim'));
  });
}

Directory _findRepoRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}/pubspec.yaml').existsSync() &&
        File('${dir.path}/AGENTS.md').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not find repo root from ${Directory.current}');
    }
    dir = parent;
  }
}

String _read(Directory root, String path) =>
    File('${root.path}/$path').readAsStringSync();
