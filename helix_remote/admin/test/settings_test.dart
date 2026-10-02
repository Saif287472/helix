import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

import 'support/harness.dart';

void main() {
  late AdminHarness h;

  setUp(() => h = AdminHarness());

  Future<void> openSettings(WidgetTester tester) async {
    await h.startSignedIn(tester);
    await h.goTo(tester, 'Settings');
  }

  Future<void> openPasswordDialog(WidgetTester tester) async {
    await tester.tap(find.text('Change admin password'));
    await tester.pumpAndSettle();
  }

  Future<void> fillPasswords(
    WidgetTester tester, {
    String current = adminPassword,
    String next = 'a brand new long password',
    String? confirm,
  }) async {
    await enter(tester, 'Current password', current);
    await enter(tester, 'New password', next);
    await enter(tester, 'Repeat the new password', confirm ?? next);
  }

  testWidgets('shows the server name, address and when the session ends', (
    tester,
  ) async {
    await openSettings(tester);

    expect(find.text('Test Server'), findsWidgets);
    expect(find.text('https://helix.test'), findsOneWidget);
    expect(find.textContaining('admin sessions last 12 hours'), findsOneWidget);
  });

  group('server name', () {
    testWidgets('renames the server', (tester) async {
      await openSettings(tester);
      await tapText(tester, 'Rename');
      await tester.enterText(
        find.widgetWithText(TextField, 'Name people see for this server'),
        'Helix Home',
      );
      await tapText(tester, 'Save');

      expect(h.server.config.serverName, 'Helix Home');
      expect(find.text('Server name saved.'), findsOneWidget);
      expect(h.server.bodies['PATCH /v1/admin/config']!.single, {
        'server_name': 'Helix Home',
      });
    });

    testWidgets('an empty name is refused without asking the server', (
      tester,
    ) async {
      await openSettings(tester);
      await tapText(tester, 'Rename');
      await tester.enterText(
        find.widgetWithText(TextField, 'Name people see for this server'),
        '   ',
      );
      await tapText(tester, 'Save');

      expect(find.text('The server needs a name.'), findsOneWidget);
      expect(h.server.requests, isNot(contains('PATCH /v1/admin/config')));
    });

    testWidgets('a refusal is reported and the name stays', (tester) async {
      await openSettings(tester);
      h.server.fail('PATCH /v1/admin/config', ErrorCode.invalidField);
      await tapText(tester, 'Rename');
      await tester.enterText(
        find.widgetWithText(TextField, 'Name people see for this server'),
        'Bad',
      );
      await tapText(tester, 'Save');

      expect(
        find.text('The server did not accept that value.'),
        findsOneWidget,
      );
      expect(h.server.config.serverName, 'Test Server');
    });
  });

  group('changing the admin password', () {
    testWidgets('changes it, keeps this session and ends the others', (
      tester,
    ) async {
      await openSettings(tester);
      final oldToken = h.vault.stored!.session.token;
      h.server.validTokens.add('someone-elses-token');
      await openPasswordDialog(tester);
      await fillPasswords(tester);
      await tapText(tester, 'Change password');

      expect(
        find.text('Password changed. Other admin sessions were signed out.'),
        findsOneWidget,
      );
      expect(h.server.adminPassword, 'a brand new long password');
      expect(h.server.validTokens, isNot(contains('someone-elses-token')));
      // This console carries on with the new token, and saved it.
      expect(h.vault.stored!.session.token, isNot(oldToken));
      await h.goTo(tester, 'Accounts');
      expect(find.text('No accounts found'), findsOneWidget);
    });

    testWidgets('a wrong current password is shown and keeps the session', (
      tester,
    ) async {
      await openSettings(tester);
      await openPasswordDialog(tester);
      await fillPasswords(tester, current: 'not my password');
      await tapText(tester, 'Change password');

      expect(find.text('Wrong password.'), findsOneWidget);
      expect(find.text('Change admin password'), findsWidgets);
      // Still signed in: the console did not mistake the answer for an
      // expired token.
      expect(h.vault.stored, isNotNull);
      await tapText(tester, 'Cancel');
      await h.goTo(tester, 'Accounts');
      expect(find.text('No accounts found'), findsOneWidget);
      expect(h.server.adminPassword, adminPassword);
    });

    testWidgets('checks the new password before asking the server', (
      tester,
    ) async {
      await openSettings(tester);
      await openPasswordDialog(tester);
      await fillPasswords(tester, next: 'short', confirm: 'short');
      await tapText(tester, 'Change password');
      expect(find.textContaining('at least 12 characters'), findsWidgets);

      await fillPasswords(
        tester,
        next: 'a brand new long password',
        confirm: 'a different long password',
      );
      await tapText(tester, 'Change password');
      expect(find.text('The two passwords do not match.'), findsOneWidget);

      await fillPasswords(tester, current: '');
      await tapText(tester, 'Change password');
      expect(find.text('Enter your current password.'), findsOneWidget);

      expect(h.server.requests, isNot(contains('PUT /v1/admin/password')));
    });

    testWidgets('cancelling changes nothing', (tester) async {
      await openSettings(tester);
      await openPasswordDialog(tester);
      await tapText(tester, 'Cancel');

      expect(h.server.requests, isNot(contains('PUT /v1/admin/password')));
    });
  });

  group('app lock', () {
    testWidgets('turns on when the device has a screen lock', (tester) async {
      await openSettings(tester);
      await tester.tap(find.widgetWithText(SwitchListTile, 'App lock'));
      await tester.pumpAndSettle();

      expect(h.settings.appLockEnabled, isTrue);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'App lock'),
            )
            .value,
        isTrue,
      );
    });

    testWidgets('explains when the device has no screen lock', (tester) async {
      h.lock.supported = false;
      await openSettings(tester);
      await tester.tap(find.widgetWithText(SwitchListTile, 'App lock'));
      await tester.pumpAndSettle();

      expect(h.settings.appLockEnabled, isFalse);
      expect(find.textContaining('No screen lock is set up'), findsOneWidget);
    });
  });

  group('purge', () {
    testWidgets('asks first and reports the counts by kind', (tester) async {
      h.server.deadJobs = 3;
      await openSettings(tester);
      await tester.tap(find.text('Purge dead jobs'));
      await tester.pumpAndSettle();
      expect(find.text('Purge dead jobs?'), findsOneWidget);
      await tapText(tester, 'Purge');

      expect(find.text('Purge finished'), findsOneWidget);
      expect(find.text('Removed 3 dead jobs.'), findsOneWidget);
      expect(h.server.requests, contains('POST /v1/admin/purge'));
    });

    testWidgets('says plainly when there was nothing to purge', (tester) async {
      await openSettings(tester);
      await tester.tap(find.text('Purge dead jobs'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Purge');

      expect(find.text('There was nothing to purge.'), findsOneWidget);
    });

    testWidgets('cancelling purges nothing', (tester) async {
      await openSettings(tester);
      await tester.tap(find.text('Purge dead jobs'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Cancel');

      expect(h.server.requests, isNot(contains('POST /v1/admin/purge')));
    });

    testWidgets('a failure is reported, not a success', (tester) async {
      await openSettings(tester);
      h.server.fail('POST /v1/admin/purge', ErrorCode.internal);
      await tester.tap(find.text('Purge dead jobs'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Purge');

      expect(find.text('Purge finished'), findsNothing);
      expect(find.textContaining('server had a problem'), findsOneWidget);
    });
  });
}
