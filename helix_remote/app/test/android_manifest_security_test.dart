import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'P8 HIGH-3 Android manifest disables backup and declares extraction rules',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:dataExtractionRules='));
      expect(manifest, contains('android:fullBackupContent='));
    },
  );

  test('release manifest pins the Helix Global certificate key', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final networkConfig = File(
      'android/app/src/main/res/xml/helix_remote_network_security.xml',
    ).readAsStringSync();

    expect(manifest, contains('networkSecurityConfig'));
    expect(networkConfig, contains('hr.agiletechbd.com'));
    expect(networkConfig, contains('pin-set'));
    expect(networkConfig, contains('SHA-256'));
  });

  test('LOW-4 no foreground-service permission is requested unused', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    // Comments are stripped first. The manifest explains the removal in prose
    // that necessarily names the very elements being searched for, so a raw
    // substring search reads the explanation as a declaration.
    final declarations = manifest.replaceAll(
      RegExp(r'<!--.*?-->', dotAll: true),
      '',
    );

    // Asserted as a pair: the permissions are only defensible alongside a
    // service element that actually needs them. Whichever is added first
    // without the other is the state this test exists to reject.
    final declaresService = declarations.contains('<service');
    for (final permission in const [
      'android.permission.FOREGROUND_SERVICE',
      'android.permission.FOREGROUND_SERVICE_CAMERA',
      'android.permission.FOREGROUND_SERVICE_MICROPHONE',
    ]) {
      expect(
        declarations.contains('<uses-permission android:name="$permission"'),
        equals(declaresService),
        reason: declaresService
            ? '$permission is needed once a foreground service exists'
            : '$permission is requested but no service element is declared; '
                  'Play Console requires a justification per foreground '
                  'service type',
      );
    }
  });
}
