import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/check_secrets.dart';

void main() {
  test('placeholder examples pass', () async {
    final root = await _project({
      '.env.example': 'API_KEY=your-placeholder-value\n',
    });
    addTearDown(() => root.delete(recursive: true));

    final findings = await scanForSecrets(root, ['.env.example']);

    expect(findings, isEmpty);
  });

  test('private key blocks fail', () async {
    final root = await _project({
      'lib/key.dart': 'const key = """${'-----BEGIN'} PRIVATE KEY-----""";\n',
    });
    addTearDown(() => root.delete(recursive: true));

    final findings = await scanForSecrets(root, ['lib']);

    expect(findings, hasLength(1));
    expect(findings.single.patternName, 'private key block');
  });

  test('generic assigned secrets fail', () async {
    final root = await _project({
      'scripts/deploy.ps1':
          r'$env:'
          'CLIENT_'
          'SECRET='
          '"super-secret-real-value"',
    });
    addTearDown(() => root.delete(recursive: true));

    final findings = await scanForSecrets(root, ['scripts']);

    expect(findings, hasLength(1));
    expect(findings.single.patternName, 'generic assigned secret');
  });
}

Future<Directory> _project(Map<String, String> files) async {
  final root = await Directory.systemTemp.createTemp('secret_scan_test_');
  for (final entry in files.entries) {
    final file = File('${root.path}/${entry.key}');
    await file.parent.create(recursive: true);
    await file.writeAsString(entry.value);
  }
  return root;
}
