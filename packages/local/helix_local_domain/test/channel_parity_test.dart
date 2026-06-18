// Verifies that every Dart channel constant matches the channel name registered
// in the corresponding native code (Kotlin / C++).  These tests will catch a
// Dart/native mismatch before it reaches a device.
//
// Canonical native registrations:
//   Android Kotlin  — apps/helix_local/android/.../MainActivity.kt
//   Windows C++     — apps/helix_local/windows/runner/mdns_plugin.cpp
//
// If a native channel name changes, update the constant in constants.dart AND
// the matching string in this test.
import 'package:test/test.dart';
import 'package:helix_local_domain/core/constants.dart';

void main() {
  group('Channel parity — Dart constants vs native registrations', () {
    test('foreground service channel matches Kotlin CHANNEL constant', () {
      expect(
        kMethodChannelName,
        equals('com.helix.local/foreground'),
        reason: 'Must match private const CHANNEL in MainActivity.kt',
      );
    });

    test('mDNS method channel matches Kotlin MDNS_CHANNEL and C++ plugin', () {
      expect(
        kMdnsMethodChannel,
        equals('com.helix.local/mdns'),
        reason: 'Must match MDNS_CHANNEL in MainActivity.kt and '
            '"com.helix.local/mdns" in mdns_plugin.cpp',
      );
    });

    test('mDNS event channel matches Kotlin MDNS_EVT_CHANNEL and C++ plugin', () {
      expect(
        kMdnsEventChannel,
        equals('com.helix.local/mdns/events'),
        reason: 'Must match MDNS_EVT_CHANNEL in MainActivity.kt and '
            '"com.helix.local/mdns/events" in mdns_plugin.cpp',
      );
    });

    test('Windows App User Model ID matches com.helix.local package', () {
      expect(
        kWindowsAppUserModelId,
        equals('com.helix.local'),
        reason: 'Must match com.helix.local (the Local product namespace)',
      );
    });

    test('all Local channels use com.helix.local namespace', () {
      for (final channel in [
        kMethodChannelName,
        kMdnsMethodChannel,
        kMdnsEventChannel,
      ]) {
        expect(
          channel,
          startsWith('com.helix.local/'),
          reason: '$channel must use the com.helix.local namespace',
        );
      }
    });

    test('no channel uses the legacy com.helix.app namespace', () {
      for (final channel in [
        kMethodChannelName,
        kMdnsMethodChannel,
        kMdnsEventChannel,
        kWindowsAppUserModelId,
      ]) {
        expect(
          channel,
          isNot(contains('com.helix.app')),
          reason: '$channel still contains the legacy com.helix.app namespace',
        );
      }
    });
  });
}
