import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/src/app.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

import 'support/fake_admin_server.dart';
import 'support/harness.dart';

void main() {
  late AdminHarness h;

  setUp(() {
    h = AdminHarness();
    h.server.accounts = [
      FakeAdminServer.account('acct-1', name: 'alice', last4: '1234'),
      FakeAdminServer.account(
        'acct-2',
        name: 'bob',
        last4: '5678',
        status: AccountStatus.suspended,
        devices: 2,
      ),
      FakeAdminServer.account('acct-3', devices: 0),
    ];
    h.server.devices['acct-1'] = [
      FakeAdminServer.device('dev-1', name: 'Alice Pixel'),
      FakeAdminServer.device(
        'dev-2',
        name: 'Old laptop',
        platform: DevicePlatform.windows,
        active: false,
      ),
    ];
    h.server.reports = [FakeAdminServer.report('rep-1', subject: 'acct-1')];
  });

  Future<void> openAccounts(WidgetTester tester) async {
    await h.startSignedIn(tester);
    await h.goTo(tester, 'Users & Devices');
  }

  Future<void> openAlice(WidgetTester tester) async {
    await openAccounts(tester);
    await tester.tap(find.text('alice'));
    await tester.pumpAndSettle();
  }

  group('the list', () {
    testWidgets('shows names, the last four digits and status', (tester) async {
      await openAccounts(tester);

      expect(find.text('alice'), findsOneWidget);
      expect(find.textContaining('1 device · Joined'), findsOneWidget);
      expect(find.text('SUSPENDED'), findsOneWidget);
      expect(find.textContaining('2 devices · Joined'), findsOneWidget);
      // No name and no number: placeholders, never invented values.
      expect(find.text('No Helix name'), findsOneWidget);
      expect(find.textContaining('No phone number'), findsOneWidget);
    });

    testWidgets('never shows anything that looks like a full phone number', (
      tester,
    ) async {
      await openAccounts(tester);

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n');
      expect(RegExp(r'\d{7,}').hasMatch(texts), isFalse);
    });

    testWidgets('searching asks the server by name or last four digits', (
      tester,
    ) async {
      await openAccounts(tester);

      await tester.enterText(find.byType(TextField), 'bo');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('bob'), findsOneWidget);
      expect(find.text('alice'), findsNothing);

      await tester.enterText(find.byType(TextField), '1234');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('bob'), findsNothing);
    });

    testWidgets('the status chips filter the list', (tester) async {
      await openAccounts(tester);
      await tester.tap(find.widgetWithText(ConsoleChip, 'Suspended'));
      await tester.pumpAndSettle();

      expect(find.text('bob'), findsOneWidget);
      expect(find.text('alice'), findsNothing);
      await tester.tap(find.widgetWithText(ConsoleChip, 'All users'));
      await tester.pumpAndSettle();
      expect(find.text('alice'), findsOneWidget);
    });

    testWidgets('an empty result says so and suggests another search', (
      tester,
    ) async {
      await openAccounts(tester);
      await tester.enterText(find.byType(TextField), 'nobody');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text('No accounts found'), findsOneWidget);
      expect(find.text('Try another search or filter.'), findsOneWidget);
    });

    testWidgets('loads more pages until the last one', (tester) async {
      h.server.pageSize = 2;
      await openAccounts(tester);
      expect(find.text('bob'), findsOneWidget);
      expect(find.text('No Helix name'), findsNothing);

      await tapText(tester, 'Load more');
      expect(find.text('No Helix name'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('a failed first load shows the error, and retry works', (
      tester,
    ) async {
      h.server.fail('GET /v1/admin/accounts', ErrorCode.unavailable);
      await openAccounts(tester);

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(
        find.textContaining('The server is unavailable right now.'),
        findsOneWidget,
      );
      expect(find.text('alice'), findsNothing);

      await tapText(tester, 'Try again');
      expect(find.text('alice'), findsOneWidget);
    });

    testWidgets('a failed "load more" keeps what is shown', (tester) async {
      h.server.pageSize = 2;
      await openAccounts(tester);
      h.server.fail('GET /v1/admin/accounts', ErrorCode.internal);
      await tapText(tester, 'Load more');

      expect(find.text('alice'), findsOneWidget);
      expect(find.textContaining('server had a problem'), findsOneWidget);
      await tapText(tester, 'Try again');
      expect(find.text('No Helix name'), findsOneWidget);
    });
  });

  group('one account', () {
    testWidgets('shows its details and devices', (tester) async {
      await openAlice(tester);

      expect(find.text('•••• 1234'), findsWidgets);
      expect(find.text('acct-1'), findsOneWidget);
      expect(find.text('OPEN REPORTS'), findsOneWidget);
      expect(find.text('Alice Pixel'), findsOneWidget);
      expect(find.text('Old laptop'), findsOneWidget);
      expect(find.text('REVOKED'), findsOneWidget);
    });

    testWidgets('suspending asks for a reason and then shows the new state', (
      tester,
    ) async {
      await openAlice(tester);
      await tapText(tester, 'Suspend');
      expect(find.text('Suspend this account?'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Reason (optional, kept in the audit log)',
        ),
        'spam wave',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Suspend'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Account suspended.'), findsOneWidget);
      expect(find.text('Resume account'), findsOneWidget);
      expect(
        h.server.bodies['PUT /v1/admin/accounts/acct-1/suspension']!.single,
        {'reason': 'spam wave'},
      );
    });

    testWidgets('a reason is optional', (tester) async {
      await openAlice(tester);
      await tapText(tester, 'Suspend');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Suspend'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Resume account'), findsOneWidget);
    });

    testWidgets('resuming a suspended account', (tester) async {
      await openAccounts(tester);
      await tester.tap(find.text('bob'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Resume account');

      expect(find.text('Account resumed.'), findsOneWidget);
      expect(find.text('Suspend'), findsOneWidget);
      expect(h.server.accounts[1].status, AccountStatus.active);
    });

    testWidgets('a failed suspend does not claim success', (tester) async {
      await openAlice(tester);
      h.server.fail(
        'PUT /v1/admin/accounts/{}/suspension',
        ErrorCode.internal,
        status: 500,
      );
      await tapText(tester, 'Suspend');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Suspend'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Account suspended.'), findsNothing);
      expect(find.textContaining('server had a problem'), findsOneWidget);
      expect(find.text('Resume account'), findsNothing);
    });

    testWidgets('banning confirms, removes the account and reloads the '
        'list', (tester) async {
      await openAlice(tester);
      await tapText(tester, 'Ban');
      expect(find.text('Ban this person?'), findsOneWidget);
      await tapText(tester, 'Ban and delete');

      expect(find.text('Account banned and deleted.'), findsOneWidget);
      expect(h.server.requests, contains('POST /v1/admin/accounts/acct-1/ban'));
      // Back on the list, which no longer has her.
      expect(find.text('alice'), findsNothing);
      expect(find.text('bob'), findsOneWidget);
    });

    testWidgets('cancelling the ban sends nothing', (tester) async {
      await openAlice(tester);
      await tapText(tester, 'Ban');
      await tapText(tester, 'Cancel');

      expect(
        h.server.requests,
        isNot(contains('POST /v1/admin/accounts/acct-1/ban')),
      );
    });

    testWidgets('deleting needs the word DELETE typed', (tester) async {
      await openAlice(tester);
      await tapText(tester, 'Delete');
      expect(find.text('Delete this account?'), findsOneWidget);

      FilledButton confirm() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Delete account'),
      );
      expect(confirm().onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextField, 'Type DELETE to confirm'),
        'delete me',
      );
      await tester.pump();
      expect(confirm().onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextField, 'Type DELETE to confirm'),
        'DELETE',
      );
      await tester.pump();
      expect(confirm().onPressed, isNotNull);
      await tapText(tester, 'Delete account');

      expect(find.text('Account deleted.'), findsOneWidget);
      expect(h.server.requests, contains('DELETE /v1/admin/accounts/acct-1'));
      expect(find.text('alice'), findsNothing);
    });

    testWidgets('revoking a device asks first and shows it revoked', (
      tester,
    ) async {
      await openAlice(tester);
      await tapText(tester, 'Revoke');
      expect(find.text('Revoke Alice Pixel?'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Revoke'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Device revoked.'), findsOneWidget);
      expect(
        h.server.requests,
        contains('DELETE /v1/admin/accounts/acct-1/devices/dev-1'),
      );
      expect(find.text('REVOKED'), findsNWidgets(2));
    });

    testWidgets('a recovery code is shown once and can be copied', (
      tester,
    ) async {
      final copied = recordClipboard(tester);
      await openAlice(tester);
      await tapText(tester, 'Recovery code');
      expect(find.text('Create a recovery code?'), findsOneWidget);
      expect(find.textContaining('HLX-REC'), findsNothing);
      await tapText(tester, 'Create code');

      expect(find.text('Recovery code'), findsWidgets);
      expect(find.byKey(const Key('shown-once-code')), findsOneWidget);
      expect(find.textContaining('shown only now'), findsOneWidget);

      await tapText(tester, 'Copy code');
      expect(copied, ['HLX-REC-SECRET-CODE-acct-1']);

      await tapText(tester, 'Done');
      // Gone from the screen, and no screen in the console holds it.
      expect(find.textContaining('HLX-REC'), findsNothing);
      await h.openOps(tester, 'Audit');
      expect(find.textContaining('HLX-REC'), findsNothing);
      expect(find.text('account.recovery_code'), findsOneWidget);
    });

    testWidgets('a failed recovery code shows the problem', (tester) async {
      await openAlice(tester);
      h.server.fail(
        'POST /v1/admin/accounts/{}/recovery-codes',
        ErrorCode.notFound,
      );
      await tapText(tester, 'Recovery code');
      await tapText(tester, 'Create code');

      expect(find.text('That item no longer exists.'), findsOneWidget);
      expect(find.byKey(const Key('shown-once-code')), findsNothing);
    });

    testWidgets('an account that is gone shows an error with retry', (
      tester,
    ) async {
      await openAccounts(tester);
      h.server.fail('GET /v1/admin/accounts/{}', ErrorCode.notFound);
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      expect(find.text('That item no longer exists.'), findsOneWidget);
      await tapText(tester, 'Try again');
      expect(find.text('DEVICES'), findsOneWidget);
    });
  });

  group('on a phone', () {
    Future<void> openPhone(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      h.saveSession();
      await tester.pumpWidget(HelixAdminApp(services: h.services()));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Users'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an account opens as its own page', (tester) async {
      await openPhone(tester);
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();

      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Alice Pixel'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Users & Devices'), findsOneWidget);
    });

    testWidgets('banning from the page returns to a list without her', (
      tester,
    ) async {
      await openPhone(tester);
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).last, const Offset(0, -900));
      await tester.pumpAndSettle();
      await tapText(tester, 'Ban');
      await tapText(tester, 'Ban and delete');

      expect(find.text('Users & Devices'), findsOneWidget);
      expect(find.text('alice'), findsNothing);
      expect(find.text('bob'), findsOneWidget);
    });
  });
}
