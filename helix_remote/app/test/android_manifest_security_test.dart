import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P8 HIGH-3 Android manifest disables backup and declares extraction rules', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:dataExtractionRules='));
    expect(manifest, contains('android:fullBackupContent='));
  });

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
}
