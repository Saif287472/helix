import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/services/screen_security.dart';

/// Regression suite for HIGH-2 in
/// docs/operations/ENTERPRISE_READINESS_AUDIT_2026-08-06.md — FLAG_SECURE was
/// never set anywhere, leaving message content screenshot-able, recordable,
/// and visible in the recents thumbnail.
void main() {
  final calls = <bool>[];

  setUp(() {
    calls.clear();
    ScreenSecurity.instance.resetForTest();
    ScreenSecurity.platformOverride = ({required bool secure}) async {
      calls.add(secure);
    };
  });

  tearDown(() => ScreenSecurity.platformOverride = null);

  testWidgets('a secure screen sets the flag while mounted', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _SecureScreen()));
    await tester.pumpAndSettle();

    expect(calls, equals([true]));
    expect(ScreenSecurity.instance.holderCount, equals(1));

    await tester.pumpWidget(const MaterialApp(home: Text('elsewhere')));
    await tester.pumpAndSettle();

    expect(calls, equals([true, false]));
    expect(ScreenSecurity.instance.holderCount, equals(0));
  });

  testWidgets('nested secure screens keep the flag until the last one goes', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: _SecureScreen()));
    await tester.pumpAndSettle();
    expect(calls, equals([true]));

    // A second secure screen on top must not re-apply...
    await ScreenSecurity.instance.acquire();
    expect(calls, equals([true]));
    expect(ScreenSecurity.instance.holderCount, equals(2));

    // ...and releasing it must not clear the flag while the first is still up.
    await ScreenSecurity.instance.release();
    expect(
      calls,
      equals([true]),
      reason: 'the flag must survive while a holder remains',
    );

    await tester.pumpWidget(const MaterialApp(home: Text('elsewhere')));
    await tester.pumpAndSettle();
    expect(calls, equals([true, false]));
  });

  testWidgets('a route transition never drops the flag mid-swap', (
    tester,
  ) async {
    // The new screen's initState runs before the old screen's dispose, so a
    // naive set/clear implementation would leave the flag off after replacing
    // one secure screen with another. Reference counting is what prevents it.
    await tester.pumpWidget(const MaterialApp(home: _SecureScreen()));
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      const MaterialApp(home: _SecureScreen(key: ValueKey('second'))),
    );
    await tester.pumpAndSettle();

    expect(
      calls.where((c) => c == false),
      isEmpty,
      reason: 'the flag must never be cleared while a secure screen is up',
    );
    expect(ScreenSecurity.instance.holderCount, equals(1));
  });

  test(
    'releasing more than acquired cannot drive the count negative',
    () async {
      await ScreenSecurity.instance.release();
      await ScreenSecurity.instance.release();
      expect(ScreenSecurity.instance.holderCount, equals(0));
      expect(calls, isEmpty);
    },
  );

  // The Windows half of HIGH-2. It cannot be exercised from a Dart test — the
  // handler lives in the C++ runner — so what is asserted here is that the
  // runner still carries it and is still compiled in. Both have to be true for
  // the desktop build to be protected, and both are one careless edit away
  // from silently reverting to the capturable build the audit found.
  test('the Windows runner registers capture protection', () {
    final channel = File(
      'windows/runner/screen_security.cpp',
    ).readAsStringSync();
    final cmake = File('windows/runner/CMakeLists.txt').readAsStringSync();
    final window = File('windows/runner/flutter_window.cpp').readAsStringSync();

    expect(channel, contains('com.helix.remote/screen_security'));
    expect(channel, contains('SetWindowDisplayAffinity'));
    expect(
      channel,
      contains('0x00000011'),
      reason: 'WDA_EXCLUDEFROMCAPTURE is the protection level that matters',
    );
    expect(
      channel,
      contains('0x00000001'),
      reason:
          'pre-2004 Windows 10 rejects WDA_EXCLUDEFROMCAPTURE outright, so '
          'the WDA_MONITOR fallback is what protects those machines',
    );
    expect(
      cmake,
      contains('screen_security.cpp'),
      reason: 'a handler that is not compiled in protects nothing',
    );
    expect(window, contains('RegisterScreenSecurityChannel'));
  });
}

class _SecureScreen extends StatefulWidget {
  const _SecureScreen({super.key});

  @override
  State<_SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<_SecureScreen>
    with SecureScreenStateMixin {
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('secret'));
}
