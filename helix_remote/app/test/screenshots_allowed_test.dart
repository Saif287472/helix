import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Screenshots and screen recording are allowed on every screen. Blocking
/// them (Android FLAG_SECURE, Windows display affinity) was removed on
/// 2026-09-30 at the product owner's request: people need to screenshot
/// chats. This keeps it from coming back unnoticed.
void main() {
  Iterable<File> sources(String dir, List<String> extensions) => Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => extensions.any(f.path.endsWith));

  test('Android never sets FLAG_SECURE', () {
    for (final file in sources('android/app/src', ['.kt', '.java'])) {
      expect(
        file.readAsStringSync(),
        isNot(contains('FLAG_SECURE')),
        reason: file.path,
      );
    }
  });

  test('Windows never hides the window from capture', () {
    for (final file in sources('windows/runner', ['.cpp', '.h'])) {
      expect(
        file.readAsStringSync(),
        isNot(contains('SetWindowDisplayAffinity')),
        reason: file.path,
      );
    }
  });

  test('the app has no screen-security channel', () {
    for (final file in sources('lib', ['.dart'])) {
      expect(
        file.readAsStringSync(),
        isNot(contains('screen_security')),
        reason: file.path,
      );
    }
  });
}
