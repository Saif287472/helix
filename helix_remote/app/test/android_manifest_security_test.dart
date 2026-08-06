import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('P8 HIGH-3 Android manifest disables backup and declares extraction rules', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:dataExtractionRules='));
    expect(manifest, contains('android:fullBackupContent='));
  });
}
