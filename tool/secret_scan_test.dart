import 'dart:io';

import 'package:test/test.dart';

import 'check_secrets.dart';

void main() {
  test('default source roots detect seeded canary secrets', () async {
    final temp = await Directory.systemTemp.createTemp('helix_secret_scan_');
    try {
      final canary = 'AKIA${List.filled(16, '0').join()}';
      for (final root in [
        '.github',
        'apps',
        'packages',
        'services',
        'contracts',
        'tool',
        'scripts',
        'docs',
      ]) {
        final dir = Directory('${temp.path}/$root')
          ..createSync(recursive: true);
        File('${dir.path}/canary.txt').writeAsStringSync(canary);
      }
      for (final file in [
        'pubspec.yaml',
        'pubspec.lock',
        'analysis_options.yaml',
        '.env.example',
      ]) {
        File('${temp.path}/$file').writeAsStringSync(canary);
      }

      final findings = await scanForSecrets(temp, defaultSecretScanRoots);
      final findingPaths = findings.map((finding) => finding.path).toSet();

      expect(findings, hasLength(defaultSecretScanRoots.length));
      for (final root in defaultSecretScanRoots) {
        final expected =
            {
              'pubspec.yaml',
              'pubspec.lock',
              'analysis_options.yaml',
              '.env.example',
            }.contains(root)
            ? root
            : '$root/canary.txt';
        expect(findingPaths, contains(expected));
      }
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
}
