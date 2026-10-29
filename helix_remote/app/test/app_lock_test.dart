import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/security/app_lock.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'support/orbit_theme.dart';

/// H1: the app lock engages on a cold start, and "Lock again" means something.
void main() {
  test('locking empties the in-memory picture cache', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    AppLock.resetForTest();
    AppLock.attach(read: () => (true, 60), callActive: () => false);
    final cache = PaintingBinding.instance.imageCache;
    cache.putIfAbsent('a picture', () => _FakeStream(), onError: (_, _) {});
    expect(cache.statusForKey('a picture').untracked, isFalse);

    AppLock.lockIfEnabled();
    expect(AppLock.locked.value, isTrue);
    expect(cache.statusForKey('a picture').untracked, isTrue);
    AppLock.resetForTest();
  });

  late StreamController<AppAuthState> auth;
  late List<String> prompts;

  setUp(() {
    AppLock.resetForTest();
    prompts = [];
    // The prompt is refused, so a lock that engaged stays on screen.
    AppLock.authenticator = (reason) async {
      prompts.add(reason);
      return false;
    };
    auth = StreamController<AppAuthState>.broadcast();
  });

  tearDown(() async {
    AppLock.resetForTest();
    await auth.close();
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required SessionRestore restore,
    required bool lockOn,
    int relockAfter = 60,
    AppAuthState? initial,
    bool settingFails = false,
  }) async {
    final container = ProviderContainer(
      overrides: [
        sessionRestoreProvider.overrideWith(() => _Restore(restore)),
        authStateProvider.overrideWith((ref) async* {
          if (initial != null) yield initial;
          yield* auth.stream;
        }),
        appLockSettingProvider.overrideWith((ref) async* {
          if (settingFails) throw StateError('unreadable');
          yield AppLockSetting(
            enabled: lockOn,
            relockAfterSeconds: relockAfter,
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: orbitTestTheme(),
          builder: orbitTestBuilder,
          home: const AppLockGate(child: Scaffold(body: Text('secret chats'))),
        ),
      ),
    );
    return container;
  }

  final locked = find.text('Orbit is locked');

  testWidgets('a remembered session locks on start, before content shows', (
    tester,
  ) async {
    await pump(
      tester,
      restore: SessionRestore.restored,
      lockOn: true,
      initial: AppAuthState.ready,
    );
    // The very first frame after the session is ready: covered, not locked
    // yet, and the content is hidden from semantics.
    expect(
      tester
          .widget<ExcludeSemantics>(find.byType(ExcludeSemantics).first)
          .excluding,
      isTrue,
    );
    await tester.pump();
    await tester.pump();
    expect(locked, findsOneWidget);
    expect(AppLock.locked.value, isTrue);
    expect(prompts, isNotEmpty);
  });

  testWidgets('the lock setting off leaves the app open', (tester) async {
    await pump(
      tester,
      restore: SessionRestore.restored,
      lockOn: false,
      initial: AppAuthState.ready,
    );
    await tester.pump();
    await tester.pump();
    expect(locked, findsNothing);
    expect(AppLock.locked.value, isFalse);
    expect(AppLock.coldStartDone.value, isTrue);
  });

  testWidgets('a sign-in made in this process does not lock', (tester) async {
    final container = await pump(
      tester,
      restore: SessionRestore.none,
      lockOn: true,
      initial: AppAuthState.signedOut,
    );
    await tester.pump();
    auth.add(AppAuthState.ready);
    await tester.pump();
    await tester.pump();
    expect(locked, findsNothing);
    expect(container.read(sessionRestoreProvider), SessionRestore.none);
  });

  testWidgets('a saved server that turns out signed out does not lock a later '
      'sign-in', (tester) async {
    await pump(
      tester,
      restore: SessionRestore.restored,
      lockOn: true,
      initial: AppAuthState.signedOut,
    );
    await tester.pump();
    await tester.pump();
    auth.add(AppAuthState.ready);
    await tester.pump();
    await tester.pump();
    expect(locked, findsNothing);
  });

  testWidgets('it waits for the restore: nothing is decided before it', (
    tester,
  ) async {
    await pump(
      tester,
      restore: SessionRestore.pending,
      lockOn: true,
      initial: AppAuthState.ready,
    );
    await tester.pump();
    expect(AppLock.coldStartDone.value, isFalse);
    expect(locked, findsNothing);
  });

  testWidgets('cold start happens once: unlocking does not lock again', (
    tester,
  ) async {
    await pump(
      tester,
      restore: SessionRestore.restored,
      lockOn: true,
      initial: AppAuthState.ready,
    );
    await tester.pump();
    await tester.pump();
    expect(locked, findsOneWidget);
    AppLock.authenticator = (_) async => true;
    await tester.tap(find.text('Unlock'));
    await tester.pump();
    await tester.pump();
    expect(locked, findsNothing);
    auth.add(AppAuthState.ready);
    await tester.pump();
    expect(locked, findsNothing);
  });

  testWidgets('a setting that cannot be read locks rather than opens', (
    tester,
  ) async {
    await pump(
      tester,
      restore: SessionRestore.restored,
      lockOn: false,
      initial: AppAuthState.ready,
      settingFails: true,
    );
    await tester.pump();
    await tester.pump();
    expect(locked, findsOneWidget);
  });

  group('Lock again', () {
    Future<void> settled(WidgetTester tester, int relock) async {
      await pump(
        tester,
        restore: SessionRestore.none,
        lockOn: true,
        relockAfter: relock,
        initial: AppAuthState.signedOut,
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a short absence does not lock', (tester) async {
      await settled(tester, 60);
      var now = DateTime(2026, 1, 1, 12);
      AppLock.clock = () => now;
      AppLock.onBackgrounded();
      expect(AppLock.locked.value, isFalse);
      now = now.add(const Duration(seconds: 30));
      AppLock.onResumed();
      expect(AppLock.locked.value, isFalse);
    });

    testWidgets('an absence of the chosen time locks', (tester) async {
      await settled(tester, 60);
      var now = DateTime(2026, 1, 1, 12);
      AppLock.clock = () => now;
      AppLock.onBackgrounded();
      now = now.add(const Duration(seconds: 61));
      AppLock.onResumed();
      expect(AppLock.locked.value, isTrue);
    });

    testWidgets('"Immediately" locks as the app goes to the background', (
      tester,
    ) async {
      await settled(tester, 0);
      AppLock.onBackgrounded();
      expect(AppLock.locked.value, isTrue);
    });

    testWidgets('a clock set backwards locks', (tester) async {
      await settled(tester, 300);
      var now = DateTime(2026, 1, 1, 12);
      AppLock.clock = () => now;
      AppLock.onBackgrounded();
      now = now.subtract(const Duration(hours: 1));
      AppLock.onResumed();
      expect(AppLock.locked.value, isTrue);
    });

    /// A call hides the relock, it does not cancel it: hanging up after a
    /// long call leaves the app locked (AUD-14b-2).
    testWidgets('a relock that came due during a call applies at hang-up', (
      tester,
    ) async {
      await settled(tester, 60);
      var now = DateTime(2026, 1, 1, 12);
      AppLock.clock = () => now;
      AppLock.onBackgrounded();
      AppLock.callInProgress.value = true; // a call, phone on the table
      now = now.add(const Duration(minutes: 10));
      AppLock.onResumed(); // the call screen comes back
      await tester.pump();
      expect(locked, findsNothing, reason: 'the call UI is not covered');

      AppLock.callInProgress.value = false; // hung up
      AppLock.onCallEnded();
      await tester.pump();
      expect(locked, findsOneWidget);
    });

    testWidgets('a short absence during a call owes nothing', (tester) async {
      await settled(tester, 60);
      var now = DateTime(2026, 1, 1, 12);
      AppLock.clock = () => now;
      AppLock.onBackgrounded();
      AppLock.callInProgress.value = true;
      now = now.add(const Duration(seconds: 5));
      AppLock.onResumed();
      AppLock.callInProgress.value = false;
      AppLock.onCallEnded();
      await tester.pump();
      expect(locked, findsNothing);
    });
  });

  /// The lock follows the phone's own screen lock. When that is gone,
  /// "try again" is a dead end that reads like lost data (AUD-14b-3).
  group('a phone without a screen lock', () {
    Future<void> lockedApp(WidgetTester tester) async {
      await pump(
        tester,
        restore: SessionRestore.restored,
        lockOn: true,
        initial: AppAuthState.ready,
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();
      // The prompt opens by itself, fails, and the screen asks why.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('the screen names the missing screen lock', (tester) async {
      AppLock.deviceSupportsLock = () async => false;
      await lockedApp(tester);
      expect(locked, findsOneWidget);
      expect(
        find.textContaining(
          Platform.isWindows
              ? 'no longer has a sign-in PIN'
              : 'no longer has one',
        ),
        findsOneWidget,
      );
      expect(find.text('Not unlocked. Try again.'), findsNothing);
      expect(AppLock.locked.value, isTrue, reason: 'it never fails open');
    });

    testWidgets('a real mismatch still says try again', (tester) async {
      AppLock.deviceSupportsLock = () async => true;
      await lockedApp(tester);
      expect(find.text('Not unlocked. Try again.'), findsOneWidget);
      expect(find.textContaining('no longer has'), findsNothing);
    });
  });
}

final class _Restore extends SessionRestoreNotifier {
  _Restore(this._value);

  final SessionRestore _value;

  @override
  SessionRestore build() => _value;
}

/// A picture that never finishes, which is all the cache needs to hold it.
final class _FakeStream extends ImageStreamCompleter {}
