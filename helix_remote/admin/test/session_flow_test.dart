import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';
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
      h.clock.advance(const Duration(hours: 13));
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
    testWidgets('the session ends after 12 hours', (tester) async {
      await h.startSignedIn(tester);
      expect(find.text('Overview'), findsWidgets);

      h.clock.advance(const Duration(hours: 12, minutes: 1));
      await tester.pump(const Duration(hours: 12, minutes: 1));
      await tester.pumpAndSettle();

      expect(find.textContaining('expired after 12 hours'), findsOneWidget);
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

    testWidgets('an open account page does not stay over the sign-in form', (
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

      h.server.expireAllTokens();
      await tester.tap(find.widgetWithText(ConsoleChip, 'Active'));
      await tester.pumpAndSettle();

      expect(find.text('DEVICES'), findsNothing);
      expect(find.widgetWithText(TextField, 'Server address'), findsOneWidget);
    });

    testWidgets('signing out forgets the token and asks for the password '
        'again', (tester) async {
      await h.startSignedIn(tester);
      await h.openOps(tester, 'Config');
      final signOut = find.widgetWithText(FilledButton, 'Sign out');
      await tester.ensureVisible(signOut);
      await tester.tap(signOut);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Sign out'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'Server address'), findsOneWidget);
      expect(h.vault.stored, isNull);
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
  });
}
