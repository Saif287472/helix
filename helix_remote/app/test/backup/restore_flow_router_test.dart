import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/post_sign_in.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/router/app_router.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import '../support/a3b_fakes.dart';

/// The restore step wired into the real router: signing in on a new device
/// shows "restore or skip" once, before the home tabs, and never otherwise.
void main() {
  late StreamController<AppAuthState> auth;
  late FakeBackupGateway backup;
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester) async {
    useTallWindow(tester, height: 1600);
    auth = StreamController<AppAuthState>.broadcast();
    backup = FakeBackupGateway();
    container = newContainer([
      ...a3bOverrides(
        backup: backup,
        devices: FakeDevicesGateway(),
        settingsGateway: FakeSettingsGateway(),
      ),
      authStateProvider.overrideWith((ref) async* {
        yield AppAuthState.signedOut;
        yield* auth.stream;
      }),
    ]);
    addTearDown(container.dispose);
    addTearDown(() => unawaited(auth.close()));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            theme: HelixThemes.light(),
            routerConfig: ref.watch(appRouterProvider),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('sign-in goes to the home tabs when the engine signs in', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Sign in'), findsWidgets);

    auth.add(AppAuthState.ready);
    await settle(tester);
    // The router follows the session: no navigation was needed.
    expect(find.text('Chats'), findsWidgets);
    expect(find.text('Restore your chats'), findsNothing);
  });

  testWidgets('a password sign-in shows the restore step before the tabs', (
    tester,
  ) async {
    await pump(tester);
    // Sign-in asks for the step, then the engine reports the session.
    container.read(postSignInProvider.notifier).offerRestore();
    auth.add(AppAuthState.ready);
    await settle(tester);

    expect(find.text('Restore your chats'), findsOneWidget);
    expect(find.text('Skip for now'), findsOneWidget);

    await tester.tap(find.text('Skip for now'));
    await settle(tester);
    expect(find.text('Restore your chats'), findsNothing);
    expect(container.read(postSignInProvider), PostSignInStep.none);
    expect(find.text('Chats'), findsWidgets);
  });

  testWidgets('restoring then continuing lands on the tabs', (tester) async {
    await pump(tester);
    container.read(postSignInProvider.notifier).offerRestore();
    auth.add(AppAuthState.ready);
    await settle(tester);

    await tester.tap(find.text('Restore from my backup'));
    await settle(tester);
    expect(backup.calls, contains('restoreHistory'));
    expect(find.text('Restored 120 messages.'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await settle(tester);
    expect(find.text('Restore your chats'), findsNothing);
    expect(find.text('Chats'), findsWidgets);
  });

  testWidgets('the step is shown once: signing out and in again without a '
      'request goes straight to the tabs', (tester) async {
    await pump(tester);
    auth.add(AppAuthState.ready);
    await settle(tester);
    expect(find.text('Restore your chats'), findsNothing);

    auth.add(AppAuthState.signedOut);
    await settle(tester);
    expect(find.text('Sign in'), findsWidgets);
    auth.add(AppAuthState.ready);
    await settle(tester);
    expect(find.text('Restore your chats'), findsNothing);
  });

  testWidgets('linking this device is reachable while signed out', (
    tester,
  ) async {
    await pump(tester);
    container.read(appRouterProvider).go(RoutePaths.linkThisDevice);
    await settle(tester);
    expect(find.text('Link this device'), findsOneWidget);
    // Dispose the page's timers before the test ends.
    container.read(appRouterProvider).go('/sign-in');
    await settle(tester);
  });
}
