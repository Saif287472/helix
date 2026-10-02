import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

import 'support/fake_admin_server.dart';
import 'support/harness.dart';

AdminInvite invite(
  String id, {
  InviteStatus status = InviteStatus.open,
  String? redeemedBy,
}) => AdminInvite(
  inviteId: id,
  issuer: 'admin',
  status: status,
  createdAt: DateTime.utc(2026, 10, 1, 9),
  expiresAt: DateTime.utc(2026, 10, 8, 9),
  redeemedBy: redeemedBy,
);

void main() {
  late AdminHarness h;

  setUp(() => h = AdminHarness());

  group('invites', () {
    setUp(() {
      h.server.invites = [
        invite('open-invite-1'),
        invite(
          'used-invite-2',
          status: InviteStatus.used,
          redeemedBy: 'acct-9',
        ),
        invite('gone-invite-3', status: InviteStatus.cancelled),
      ];
    });

    Future<void> openInvites(WidgetTester tester) async {
      await h.startSignedIn(tester);
      await h.goTo(tester, 'Invites');
    }

    testWidgets('lists invites with their state, never a code', (tester) async {
      await openInvites(tester);

      expect(find.text('Invite open-inv'), findsOneWidget);
      expect(find.text('Used'), findsOneWidget);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.textContaining('used by acct-9'), findsOneWidget);
      expect(find.textContaining('HLX-INV'), findsNothing);
      // Only an open invite can be cancelled.
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    });

    testWidgets('creating an invite shows the code once', (tester) async {
      final copied = recordClipboard(tester);
      await openInvites(tester);
      await tapText(tester, 'Create invite');

      expect(find.byKey(const Key('shown-once-code')), findsOneWidget);
      expect(find.text('HLX-INV-SECRET-CODE'), findsOneWidget);
      await tapText(tester, 'Copy code');
      expect(copied, ['HLX-INV-SECRET-CODE']);
      await tapText(tester, 'Done');

      // The list shows the new invite, still without its code.
      expect(find.textContaining('HLX-INV'), findsNothing);
      expect(find.textContaining('Invite invite-4'), findsOneWidget);
      expect(h.server.requests, contains('POST /v1/admin/invites'));
    });

    testWidgets('a failure to create says so and shows no code', (
      tester,
    ) async {
      await openInvites(tester);
      h.server.fail('POST /v1/admin/invites', ErrorCode.rateLimited);
      await tapText(tester, 'Create invite');

      expect(find.textContaining('Too many requests'), findsOneWidget);
      expect(find.byKey(const Key('shown-once-code')), findsNothing);
    });

    testWidgets('cancelling asks first and then marks it cancelled', (
      tester,
    ) async {
      await openInvites(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this invite?'), findsOneWidget);
      await tapText(tester, 'Cancel invite');

      expect(find.text('Invite cancelled.'), findsOneWidget);
      expect(
        h.server.requests,
        contains('DELETE /v1/admin/invites/open-invite-1'),
      );
      expect(find.widgetWithText(TextButton, 'Cancel'), findsNothing);
    });

    testWidgets('declining the cancel sends nothing', (tester) async {
      await openInvites(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Cancel');

      expect(h.server.requests.where((r) => r.startsWith('DELETE')), isEmpty);
    });

    testWidgets('a load failure is an error, not an empty list', (
      tester,
    ) async {
      h.server.fail('GET /v1/admin/invites', ErrorCode.internal);
      await openInvites(tester);

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('No invites yet'), findsNothing);
    });

    testWidgets('no invites yet', (tester) async {
      h.server.invites = [];
      await openInvites(tester);

      expect(find.text('No invites yet'), findsOneWidget);
    });

    testWidgets('Helix Global (phone sign-up) has no Invites place', (
      tester,
    ) async {
      h.server.config = const AdminConfig(
        serverName: 'Helix Global',
        version: '2.0.0-test',
        registration: RegistrationMode.phone,
        maintenance: false,
        federationEnabled: false,
        maxAttachmentBytes: 1024,
        nodeId: 'n',
      );
      await h.startSignedIn(tester);

      expect(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.text('Invites'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.text('Accounts'),
        ),
        findsOneWidget,
      );
    });
  });

  group('reports', () {
    setUp(() {
      h.server.accounts = [
        FakeAdminServer.account('acct-1', name: 'alice', last4: '1234'),
      ];
      h.server.reports = [
        FakeAdminServer.report('rep-1', note: 'sends me spam every day'),
        FakeAdminServer.report(
          'rep-2',
          category: ReportCategory.abuse,
          status: ReportStatus.resolved,
        ),
        FakeAdminServer.report(
          'rep-3',
          category: ReportCategory.impersonation,
          status: ReportStatus.dismissed,
        ),
      ];
    });

    Future<void> openReports(WidgetTester tester) async {
      await h.startSignedIn(tester);
      await h.goTo(tester, 'Reports');
    }

    testWidgets('shows the open reports first', (tester) async {
      await openReports(tester);

      expect(find.text('Spam'), findsOneWidget);
      expect(find.text('sends me spam every day'), findsOneWidget);
      expect(find.text('Abuse'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Resolve'), findsOneWidget);
    });

    testWidgets('filters by outcome', (tester) async {
      await openReports(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Resolved'));
      await tester.pumpAndSettle();
      expect(find.text('Abuse'), findsOneWidget);
      expect(find.text('Spam'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.pumpAndSettle();
      expect(find.text('Spam'), findsOneWidget);
      expect(find.text('Impersonation'), findsOneWidget);
      // Only an open report offers actions.
      expect(find.widgetWithText(FilledButton, 'Resolve'), findsOneWidget);
    });

    testWidgets('resolving removes it from the open queue', (tester) async {
      await openReports(tester);
      await tapText(tester, 'Resolve');

      expect(find.text('Report resolved.'), findsOneWidget);
      expect(find.text('No open reports'), findsOneWidget);
      expect(h.server.bodies['PUT /v1/admin/reports/rep-1']!.single, {
        'status': 'resolved',
      });
    });

    testWidgets('dismissing sends dismissed', (tester) async {
      await openReports(tester);
      await tapText(tester, 'Dismiss');

      expect(find.text('Report dismissed.'), findsOneWidget);
      expect(h.server.bodies['PUT /v1/admin/reports/rep-1']!.single, {
        'status': 'dismissed',
      });
    });

    testWidgets('a refused resolve leaves the report open and says why', (
      tester,
    ) async {
      await openReports(tester);
      h.server.fail('PUT /v1/admin/reports/{}', ErrorCode.notFound);
      await tapText(tester, 'Resolve');

      expect(find.text('Report resolved.'), findsNothing);
      expect(find.text('That item no longer exists.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Resolve'), findsOneWidget);
    });

    testWidgets('a report can open the reported account', (tester) async {
      await openReports(tester);
      await tapText(tester, 'Open account');

      expect(find.text('•••• 1234'), findsOneWidget);
      expect(find.text('Devices'), findsOneWidget);
    });

    testWidgets('a load failure is an error, not "no reports"', (tester) async {
      h.server.fail('GET /v1/admin/reports', ErrorCode.internal);
      await openReports(tester);

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('No open reports'), findsNothing);
    });

    testWidgets('an empty queue says nothing is waiting', (tester) async {
      h.server.reports = [];
      await openReports(tester);

      expect(find.text('No open reports'), findsOneWidget);
      expect(find.text('Nothing is waiting for you.'), findsOneWidget);
    });
  });

  group('audit log', () {
    setUp(() {
      for (var i = 1; i <= 5; i++) {
        h.server.audit.add(
          AuditEntry(
            id: 'a$i',
            action: 'action.$i',
            at: DateTime.utc(2026, 10, 1, i),
            target: i.isEven ? 'target-number-$i' : null,
            details: i == 5 ? {'enabled': 'true'} : const {},
          ),
        );
      }
    });

    Future<void> openAudit(WidgetTester tester) async {
      await h.startSignedIn(tester);
      await h.goTo(tester, 'Audit log');
    }

    testWidgets('shows newest first with targets and details', (tester) async {
      await openAudit(tester);

      expect(find.text('action.5'), findsOneWidget);
      expect(find.textContaining('enabled: true'), findsOneWidget);
      expect(find.textContaining('target target-n'), findsWidgets);
      final first = tester.getTopLeft(find.text('action.5')).dy;
      final last = tester.getTopLeft(find.text('action.1')).dy;
      expect(first, lessThan(last));
    });

    testWidgets('pages with Load more', (tester) async {
      h.server.pageSize = 2;
      await openAudit(tester);
      expect(find.text('action.5'), findsOneWidget);
      expect(find.text('action.3'), findsNothing);

      await tapText(tester, 'Load more');
      expect(find.text('action.3'), findsOneWidget);
      await tapText(tester, 'Load more');
      expect(find.text('action.1'), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('an action in the console appears in the log', (tester) async {
      h.server.accounts = [
        FakeAdminServer.account('acct-1', name: 'alice', last4: '1234'),
      ];
      await h.startSignedIn(tester);
      await h.goTo(tester, 'Accounts');
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Suspend');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Suspend'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await h.goTo(tester, 'Audit log');

      expect(find.text('account.suspend'), findsOneWidget);
    });

    testWidgets('an empty log says so', (tester) async {
      h.server.audit.clear();
      await openAudit(tester);

      expect(find.text('Nothing recorded yet'), findsOneWidget);
    });

    testWidgets('a failure shows an error with retry', (tester) async {
      h.server.fail('GET /v1/admin/audit', ErrorCode.unavailable);
      await openAudit(tester);

      expect(find.text('Something went wrong'), findsOneWidget);
      await tapText(tester, 'Retry');
      expect(find.text('action.5'), findsOneWidget);
    });
  });
}
