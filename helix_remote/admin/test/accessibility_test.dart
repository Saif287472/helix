import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/src/app.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

import 'support/fake_admin_server.dart';
import 'support/harness.dart';

/// The shipped screens, checked against Flutter's accessibility guidelines:
/// 48 px tap targets, labelled controls (AGENTS.md product rules).
void main() {
  late AdminHarness h;

  setUp(() {
    h = AdminHarness();
    h.server.accounts = [
      FakeAdminServer.account('acct-1', name: 'alice', last4: '1234'),
    ];
    h.server.devices['acct-1'] = [FakeAdminServer.device('d1')];
    h.server.reports = [FakeAdminServer.report('rep-1', subject: 'acct-1')];
    h.server.invites = [
      AdminInvite(
        inviteId: 'invite-000001',
        issuer: 'admin',
        status: InviteStatus.open,
        createdAt: DateTime.utc(2026, 10, 1),
        expiresAt: DateTime.utc(2026, 10, 8),
      ),
    ];
    h.server.logLines = ['{"level":"info","event":"x"}'];
    h.server.audit.add(
      AuditEntry(id: 'a1', action: 'config.update', at: DateTime.utc(2026, 10)),
    );
  });

  Future<void> check(WidgetTester tester) async {
    final handle = tester.ensureSemantics();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  }

  testWidgets('sign-in', (tester) async {
    h.configured();
    await h.pumpApp(tester);
    await enter(tester, 'Server address', 'helix.test');
    await tapText(tester, 'Continue');
    await check(tester);
  });

  testWidgets('first-run setup', (tester) async {
    await h.pumpApp(tester);
    await enter(tester, 'Server address', 'helix.test');
    await tapText(tester, 'Continue');
    await check(tester);
  });

  for (final place in const [
    'Overview',
    'Users & Devices',
    'Invites',
    'Reports',
    'Configuration',
  ]) {
    testWidgets(place, (tester) async {
      await h.startSignedIn(tester);
      if (place != 'Overview') await h.goTo(tester, place);
      await check(tester);
    });
  }

  testWidgets('Configuration > the live log sheet', (tester) async {
    await h.startSignedIn(tester);
    await h.openLogSheet(tester);
    await check(tester);
  });

  testWidgets('Configuration > the audit trail page', (tester) async {
    await h.startSignedIn(tester);
    await h.openAudit(tester);
    await check(tester);
  });

  testWidgets('an account sheet', (tester) async {
    await h.startSignedIn(tester);
    await h.goTo(tester, 'Users & Devices');
    await tester.tap(find.text('alice'));
    await tester.pumpAndSettle();
    await check(tester);
  });

  testWidgets('a report sheet', (tester) async {
    await h.startSignedIn(tester);
    await h.goTo(tester, 'Reports');
    await h.openReportSheet(tester, 'Spam');
    await check(tester);
  });

  /// Starts the console on a phone: the dock layout, not the header pills.
  Future<void> phone(WidgetTester tester) => h.startPhone(tester);

  testWidgets('the phone layout has a dock with the operating places', (
    tester,
  ) async {
    await phone(tester);

    expect(find.byType(ConsoleDock), findsOneWidget);
    // Only the open place is named; the others are an icon each.
    expect(
      find.descendant(
        of: find.byType(ConsoleDock),
        matching: find.text('Overview'),
      ),
      findsOneWidget,
    );
    for (final icon in const [
      Icons.people_outline,
      Icons.local_activity_outlined,
      Icons.shield_outlined,
    ]) {
      expect(
        find.descendant(
          of: find.byType(ConsoleDock),
          matching: find.byIcon(icon),
        ),
        findsOneWidget,
      );
    }
    // Configuration is not in the dock: the gear in the header opens it.
    expect(
      find.descendant(
        of: find.byType(ConsoleDock),
        matching: find.byIcon(Icons.settings_outlined),
      ),
      findsNothing,
    );
    await check(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(ConsoleDock),
        matching: find.byIcon(Icons.people_outline),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('alice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the phone gear opens Configuration, and Configuration opens '
      'the log', (tester) async {
    await phone(tester);
    await h.openConfigWithGear(tester);

    expect(find.text('Configuration'), findsWidgets);
    // The Logs & Activity tile is below the fold on a phone; bringing its
    // audit row in builds the whole tile.
    await tester.dragUntilVisible(
      find.text('Audit trail'),
      find.byType(ListView).first,
      const Offset(0, -150),
    );
    await tester.pumpAndSettle();
    expect(find.text('Live log'), findsOneWidget);
    expect(find.text('Audit trail'), findsOneWidget);
    await check(tester);

    await h.tapRowAction(tester, 'Show log');
    expect(find.text('Live Server Console'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow phone shows the dock, then Configuration, with room', (
    tester,
  ) async {
    await h.startPhone(tester, size: const Size(320, 640));
    expect(tester.takeException(), isNull);

    await h.openConfigWithGear(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a phone-sized sign-in has no overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(HelixAdminApp(services: h.services()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
