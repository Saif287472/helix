import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

import 'support/harness.dart';

void main() {
  late AdminHarness h;

  setUp(() => h = AdminHarness());

  Future<void> openSettings(WidgetTester tester) async {
    await h.startSignedIn(tester);
    await h.openOps(tester, 'Config');
  }

  Future<void> openPasswordDialog(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(OutlinedButton, 'Change password'));
    await tester.pumpAndSettle();
  }

  /// The switch in the row titled [title].
  Finder toggle(String title) => find.descendant(
    of: find.ancestor(
      of: find.text(title),
      matching: find.byType(MergeSemantics),
    ),
    matching: find.byType(Switch),
  );

  bool on(WidgetTester tester, String title) =>
      tester.widget<Switch>(toggle(title)).value;

  Future<void> flip(WidgetTester tester, String title) async {
    await tester.ensureVisible(toggle(title));
    await tester.tap(toggle(title));
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
    expect(find.text('node-1'), findsOneWidget);
    expect(find.text('2.0.0-test'), findsOneWidget);
    expect(find.text('10 MiB'), findsOneWidget);
    expect(find.text('Invite code'), findsOneWidget);
  });

  group('server name', () {
    testWidgets('renames the server', (tester) async {
      await openSettings(tester);
      await tapText(tester, 'Edit name');
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
      await tapText(tester, 'Edit name');
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
      await tapText(tester, 'Edit name');
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
      await h.goTo(tester, 'Users & Devices');
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
      await h.goTo(tester, 'Users & Devices');
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
      await flip(tester, 'Device biometric / PIN lock');

      expect(h.settings.appLockEnabled, isTrue);
      expect(on(tester, 'Device biometric / PIN lock'), isTrue);
    });

    testWidgets('explains when the device has no screen lock', (tester) async {
      h.lock.supported = false;
      await openSettings(tester);
      await flip(tester, 'Device biometric / PIN lock');

      expect(h.settings.appLockEnabled, isFalse);
      expect(find.textContaining('No screen lock is set up'), findsOneWidget);
    });
  });

  group('purge', () {
    testWidgets('asks first and reports the counts by kind', (tester) async {
      h.server.deadJobs = 3;
      await openSettings(tester);
      await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Purge'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Purge'));
      await tester.pumpAndSettle();
      expect(find.text('Purge dead jobs?'), findsOneWidget);
      await tapText(tester, 'Purge');

      expect(find.text('Purge finished'), findsOneWidget);
      expect(find.text('Removed 3 dead jobs.'), findsOneWidget);
      expect(h.server.requests, contains('POST /v1/admin/purge'));
    });

    testWidgets('says plainly when there was nothing to purge', (tester) async {
      await openSettings(tester);
      await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Purge'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Purge'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Purge');

      expect(find.text('There was nothing to purge.'), findsOneWidget);
    });

    testWidgets('cancelling purges nothing', (tester) async {
      await openSettings(tester);
      await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Purge'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Purge'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Cancel');

      expect(h.server.requests, isNot(contains('POST /v1/admin/purge')));
    });

    testWidgets('a failure is reported, not a success', (tester) async {
      await openSettings(tester);
      h.server.fail('POST /v1/admin/purge', ErrorCode.internal);
      await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Purge'));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Purge'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Purge');

      expect(find.text('Purge finished'), findsNothing);
      expect(find.textContaining('server had a problem'), findsOneWidget);
    });
  });

  group('maintenance mode', () {
    testWidgets('asks first, then turns it on', (tester) async {
      await openSettings(tester);
      expect(on(tester, 'Server maintenance mode'), isFalse);

      await flip(tester, 'Server maintenance mode');
      expect(find.text('Turn on maintenance mode?'), findsOneWidget);
      await tapText(tester, 'Turn on');

      expect(h.server.config.maintenance, isTrue);
      expect(on(tester, 'Server maintenance mode'), isTrue);
      expect(find.text('Maintenance mode is on.'), findsOneWidget);
      expect(h.server.bodies['PATCH /v1/admin/config']!.single, {
        'maintenance': true,
      });
    });

    testWidgets('cancelling changes nothing', (tester) async {
      await openSettings(tester);
      await flip(tester, 'Server maintenance mode');
      await tapText(tester, 'Cancel');

      expect(h.server.requests, isNot(contains('PATCH /v1/admin/config')));
      expect(on(tester, 'Server maintenance mode'), isFalse);
    });

    testWidgets('turning it off needs no confirmation', (tester) async {
      await openSettings(tester);
      await flip(tester, 'Server maintenance mode');
      await tapText(tester, 'Turn on');

      await flip(tester, 'Server maintenance mode');

      expect(h.server.config.maintenance, isFalse);
      expect(find.text('Maintenance mode is off.'), findsOneWidget);
    });

    testWidgets('a refusal leaves the switch where the server has it', (
      tester,
    ) async {
      await openSettings(tester);
      h.server.fail('PATCH /v1/admin/config', ErrorCode.forbidden);
      await flip(tester, 'Server maintenance mode');
      await tapText(tester, 'Turn on');

      expect(find.text('The server refused this action.'), findsOneWidget);
      expect(on(tester, 'Server maintenance mode'), isFalse);
    });
  });

  testWidgets('the worldwide network switch changes federation', (
    tester,
  ) async {
    await openSettings(tester);
    await flip(tester, 'Worldwide Network Mode');

    expect(h.server.config.federationEnabled, isTrue);
    expect(on(tester, 'Worldwide Network Mode'), isTrue);
    expect(h.server.bodies['PATCH /v1/admin/config']!.single, {
      'federation_enabled': true,
    });
  });

  group('feature flags', () {
    testWidgets('lists the allow-listed flags with plain names', (
      tester,
    ) async {
      await openSettings(tester);

      expect(on(tester, 'Accept crash reports from apps'), isFalse);
      expect(on(tester, 'Minimal analytics'), isTrue);
      expect(on(tester, 'Group calls'), isFalse);
    });

    testWidgets('switching one sends only that flag', (tester) async {
      await openSettings(tester);
      await flip(tester, 'Group calls');

      expect(h.server.flags['group_calls'], isTrue);
      expect(on(tester, 'Group calls'), isTrue);
      expect(
        h.server.requests,
        contains('PUT /v1/admin/feature-flags/group_calls'),
      );
      expect(h.server.flags['minimal_analytics'], isTrue);
    });

    testWidgets('a refused change says why and keeps the old value', (
      tester,
    ) async {
      await openSettings(tester);
      h.server.fail('PUT /v1/admin/feature-flags/{}', ErrorCode.notFound);
      await flip(tester, 'Group calls');

      expect(find.text('That item no longer exists.'), findsOneWidget);
      expect(on(tester, 'Group calls'), isFalse);
    });
  });
}
