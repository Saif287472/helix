import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

import 'support/fake_admin_server.dart';
import 'support/harness.dart';

void main() {
  late AdminHarness h;

  setUp(() => h = AdminHarness());

  group('first-run setup', () {
    testWidgets('a server without an admin password offers setup', (
      tester,
    ) async {
      await h.pumpApp(tester);
      await enter(tester, 'Server address', 'helix.test');
      await tapText(tester, 'Continue');

      expect(find.textContaining('First-time setup'), findsOneWidget);
      expect(find.text('Set password and sign in'), findsOneWidget);
      expect(find.text('New admin password'), findsOneWidget);
      expect(find.text('Repeat the password'), findsOneWidget);
    });

    testWidgets('refuses a short password and a mismatch before asking the '
        'server', (tester) async {
      await h.pumpApp(tester);
      await enter(tester, 'Server address', 'helix.test');
      await tapText(tester, 'Continue');

      await enter(tester, 'New admin password', 'short');
      await enter(tester, 'Repeat the password', 'short');
      await tapText(tester, 'Set password and sign in');
      expect(find.textContaining('at least 12 characters'), findsWidgets);

      await enter(tester, 'New admin password', adminPassword);
      await enter(tester, 'Repeat the password', '$adminPassword!');
      await tapText(tester, 'Set password and sign in');
      expect(find.text('The two passwords do not match.'), findsOneWidget);

      expect(h.server.requests, isNot(contains('POST /v1/admin/setup')));
      expect(h.server.adminPassword, isNull);
    });

    testWidgets('sets the password, signs in and opens the dashboard', (
      tester,
    ) async {
      await h.pumpApp(tester);
      await enter(tester, 'Server address', 'helix.test');
      await tapText(tester, 'Continue');
      await enter(tester, 'New admin password', adminPassword);
      await enter(tester, 'Repeat the password', adminPassword);
      await tapText(tester, 'Set password and sign in');

      expect(h.server.adminPassword, adminPassword);
      expect(find.text('Overview'), findsWidgets);
      expect(find.text('Test Server'), findsWidgets);
      // The session is saved for next time, with the server it belongs to.
      expect(h.vault.stored?.serverUrl, 'https://helix.test');
      expect(h.settings.serverUrl, 'https://helix.test');
    });

    testWidgets('someone else finishing setup first turns it into sign-in', (
      tester,
    ) async {
      await h.pumpApp(tester);
      await enter(tester, 'Server address', 'helix.test');
      await tapText(tester, 'Continue');
      h.server.adminPassword = 'someone else got here first';

      await enter(tester, 'New admin password', adminPassword);
      await enter(tester, 'Repeat the password', adminPassword);
      await tapText(tester, 'Set password and sign in');

      expect(
        find.textContaining('already has an admin password'),
        findsOneWidget,
      );
      expect(find.text('Sign in'), findsOneWidget);
    });
  });

  group('sign-in', () {
    testWidgets('signs in with the admin password', (tester) async {
      h.configured();
      await h.pumpApp(tester);
      await enter(tester, 'Server address', 'https://helix.test/');
      await tapText(tester, 'Continue');
      expect(find.textContaining('First-time setup'), findsNothing);

      await enter(tester, 'Admin password', adminPassword);
      await tapText(tester, 'Sign in');

      expect(find.text('Overview'), findsWidgets);
      expect(h.vault.stored, isNotNull);
    });

    testWidgets('the saved server is checked at once', (tester) async {
      h.configured();
      h.settings.serverUrl = 'https://helix.test';
      await h.pumpApp(tester);

      expect(find.widgetWithText(TextField, 'Admin password'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('a wrong password says so and keeps the form', (tester) async {
      h.configured();
      await h.pumpApp(tester);
      await enter(tester, 'Server address', 'helix.test');
      await tapText(tester, 'Continue');
      await enter(tester, 'Admin password', 'not the password');
      await tapText(tester, 'Sign in');

      expect(find.text('Wrong password.'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(h.vault.stored, isNull);
    });

    testWidgets('the lockout is explained with how long to wait', (
      tester,
    ) async {
      h.configured();
      h.server.failedSignIns = 5;
      await h.pumpApp(tester);
      await enter(tester, 'Server address', 'helix.test');
      await tapText(tester, 'Continue');
      await enter(tester, 'Admin password', adminPassword);
      await tapText(tester, 'Sign in');

      expect(
        find.text(
          'Sign-in is locked after too many wrong passwords. Try again in '
          '15 minutes.',
        ),
        findsOneWidget,
      );
      expect(h.vault.stored, isNull);
    });

    testWidgets('a rate limit shows the Retry-After wait', (tester) async {
      h.configured();
      await h.pumpApp(tester);
      await enter(tester, 'Server address', 'helix.test');
      await tapText(tester, 'Continue');
      h.server.fail(
        'POST /v1/admin/sessions',
        ErrorCode.rateLimited,
        retryAfter: const Duration(seconds: 42),
      );
      await enter(tester, 'Admin password', adminPassword);
      await tapText(tester, 'Sign in');

      expect(
        find.text('Too many requests. Try again in 42 seconds.'),
        findsOneWidget,
      );
    });

    testWidgets('an unreachable server is reported', (tester) async {
      h.server.unreachable = true;
      await h.pumpApp(tester);
      await enter(tester, 'Server address', 'helix.test');
      await tapText(tester, 'Continue');

      expect(find.textContaining('Could not reach the server'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('a plain http address is refused before anything is sent', (
      tester,
    ) async {
      await h.pumpApp(tester);
      await enter(tester, 'Server address', 'http://helix.example.com');
      await tapText(tester, 'Continue');

      expect(find.textContaining('Use https://'), findsOneWidget);
      expect(h.server.requests, isEmpty);
    });

    testWidgets('editing the address forgets what was checked', (tester) async {
      h.configured();
      await h.pumpApp(tester);
      await enter(tester, 'Server address', 'helix.test');
      await tapText(tester, 'Continue');
      expect(find.text('Sign in'), findsOneWidget);

      await enter(tester, 'Server address', 'helix.tes');
      expect(find.text('Continue'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Admin password'), findsNothing);
    });

    testWidgets('the password can be shown and hidden', (tester) async {
      h.configured();
      await h.pumpApp(tester);
      await enter(tester, 'Server address', 'helix.test');
      await tapText(tester, 'Continue');

      EditableText field() => tester.widget<EditableText>(
        find.descendant(
          of: find.widgetWithText(TextField, 'Admin password'),
          matching: find.byType(EditableText),
        ),
      );
      expect(field().obscureText, isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(field().obscureText, isFalse);
    });
  });

  group('the saved session', () {
    testWidgets('opens the console without asking for the password', (
      tester,
    ) async {
      await h.startSignedIn(tester);

      expect(find.text('Overview'), findsWidgets);
      expect(h.server.requests, contains('GET /v1/admin/config'));
      expect(h.server.requests, isNot(contains('POST /v1/admin/sessions')));
    });

    testWidgets('an expired saved session goes to sign-in with a reason', (
      tester,
    ) async {
      h.saveSession();
      h.clock.advance(const Duration(days: 7, hours: 1));
      await h.pumpApp(tester);

      expect(find.textContaining('session expired'), findsOneWidget);
      expect(h.vault.stored, isNull);
    });

    testWidgets('a token the server no longer accepts is dropped', (
      tester,
    ) async {
      h.saveSession();
      h.server.expireAllTokens();
      await h.pumpApp(tester);

      expect(
        find.text('Your admin session has ended. Sign in again.'),
        findsOneWidget,
      );
      expect(h.vault.stored, isNull);
    });

    testWidgets('an unreachable server keeps the saved session for later', (
      tester,
    ) async {
      h.saveSession();
      h.server.unreachable = true;
      await h.pumpApp(tester);

      expect(find.textContaining('Could not reach the server'), findsWidgets);
      expect(h.vault.stored, isNotNull);
    });
  });

  group('while signed in', () {
    testWidgets('the session ends at its expiry', (tester) async {
      await h.startSignedIn(tester);
      expect(find.text('Overview'), findsWidgets);

      h.clock.advance(const Duration(days: 7, minutes: 1));
      await tester.pump(const Duration(days: 7, minutes: 1));
      await tester.pumpAndSettle();

      expect(find.textContaining('session expired'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Server address'), findsOneWidget);
      expect(h.vault.stored, isNull);
    });

    testWidgets('a rejected token on any screen returns to sign-in', (
      tester,
    ) async {
      await h.startSignedIn(tester);
      h.server.expireAllTokens();
      await h.goTo(tester, 'Users & Devices');

      expect(
        find.text('Your admin session has ended. Sign in again.'),
        findsOneWidget,
      );
      expect(h.vault.stored, isNull);
    });

    testWidgets('an open account sheet does not stay over the sign-in form', (
      tester,
    ) async {
      h.server.accounts = [
        FakeAdminServer.account('acct-1', name: 'alice', last4: '1234'),
      ];
      h.server.devices['acct-1'] = [FakeAdminServer.device('d1')];
      await h.startSignedIn(tester);
      await h.goTo(tester, 'Users & Devices');
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();
      expect(find.text('DEVICES'), findsOneWidget);

      // The next call from inside the sheet is the one the server turns down.
      h.server.expireAllTokens();
      await tapText(tester, 'Recovery code');
      await tapText(tester, 'Create code');
      await tester.pumpAndSettle();

      expect(find.text('DEVICES'), findsNothing);
      expect(find.widgetWithText(TextField, 'Server address'), findsOneWidget);
    });

    Future<void> signOut(WidgetTester tester) async {
      await h.goTo(tester, 'Configuration');
      final button = find.widgetWithText(FilledButton, 'Sign out');
      // The sign-out card is below the fold, so it has to be scrolled to.
      await tester.dragUntilVisible(
        button,
        find.byType(ListView).first,
        const Offset(0, -200),
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Sign out'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('signing out ends the session on the server, forgets the '
        'token and asks for the password again', (tester) async {
      await h.startSignedIn(tester);
      await signOut(tester);

      expect(h.server.requests, contains('DELETE /v1/admin/sessions'));
      expect(h.server.validTokens, isEmpty, reason: 'every copy is cut off');
      expect(find.widgetWithText(TextField, 'Server address'), findsOneWidget);
      expect(h.vault.stored, isNull);
    });

    testWidgets('signing out without the server still signs out here, and '
        'says so', (tester) async {
      await h.startSignedIn(tester);
      h.server.unreachable = true;
      await signOut(tester);

      expect(find.widgetWithText(TextField, 'Server address'), findsOneWidget);
      expect(h.vault.stored, isNull);
      expect(
        find.textContaining('Signed out on this device only'),
        findsOneWidget,
      );
    });
  });

  group('app lock', () {
    testWidgets('asks for the device lock before opening the session', (
      tester,
    ) async {
      h.saveSession();
      h.settings.appLockEnabled = true;
      await h.pumpApp(tester);

      expect(h.lock.prompts, 1);
      expect(find.text('Overview'), findsWidgets);
    });

    testWidgets('stays locked when the unlock fails, and can retry', (
      tester,
    ) async {
      h.saveSession();
      h.settings.appLockEnabled = true;
      h.lock.allow = false;
      await h.pumpApp(tester);

      expect(find.text('Helix Admin is locked'), findsOneWidget);
      expect(find.text('The device was not unlocked.'), findsOneWidget);
      expect(h.server.requests, isEmpty);

      h.lock.allow = true;
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('Overview'), findsWidgets);
    });

    Future<void> away(WidgetTester tester, Duration duration) async {
      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      h.clock.advance(duration);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    }

    testWidgets('a minute in the background locks the console again', (
      tester,
    ) async {
      h.saveSession();
      h.settings.appLockEnabled = true;
      await h.pumpApp(tester);
      expect(h.lock.prompts, 1);

      await away(tester, const Duration(seconds: 30));
      expect(find.text('Overview'), findsWidgets, reason: 'a short trip');
      expect(h.lock.prompts, 1);

      h.lock.allow = false;
      await away(tester, const Duration(minutes: 1));
      expect(find.text('Helix Admin is locked'), findsOneWidget);
      expect(find.text('Overview'), findsNothing);
      expect(h.lock.prompts, 2);

      h.lock.allow = true;
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('Overview'), findsWidgets);
      expect(h.vault.stored, isNotNull, reason: 'the same saved session');
    });

    testWidgets('the unlock prompt itself is not time away', (tester) async {
      h.saveSession();
      h.settings.appLockEnabled = true;
      h.lock.whilePrompting = () {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        h.clock.advance(const Duration(minutes: 5));
      };
      await h.pumpApp(tester);
      h.lock.whilePrompting = null;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Overview'), findsWidgets);
      expect(h.lock.prompts, 1);
    });

    testWidgets('without App lock, time away changes nothing', (tester) async {
      await h.startSignedIn(tester);
      await away(tester, const Duration(hours: 1));
      expect(find.text('Overview'), findsWidgets);
      expect(h.lock.prompts, 0);
    });
  });
}
