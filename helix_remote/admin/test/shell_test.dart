import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/src/widgets/console_kit.dart';

import 'support/fake_admin_server.dart';
import 'support/harness.dart';

/// The shell's own behaviour: the places it shows for the server it is signed
/// in to, and the open-report count the Reports item wears.
void main() {
  late AdminHarness h;

  setUp(() {
    h = AdminHarness();
    h.server.accounts = [
      FakeAdminServer.account('acct-1', name: 'alice', last4: '1234'),
    ];
    h.server.reports = [
      FakeAdminServer.report('rep-1', subject: 'acct-1'),
      FakeAdminServer.report('rep-2', subject: 'acct-1'),
    ];
  });

  Finder badge(String text) =>
      find.descendant(of: find.byType(AppBar), matching: find.text(text));

  testWidgets('the Reports pill wears the open count', (tester) async {
    await h.startSignedIn(tester);
    expect(badge('2'), findsOneWidget);
  });

  testWidgets('a count the server has more of carries a plus', (tester) async {
    h.server.pageSize = 1;
    await h.startSignedIn(tester);
    expect(badge('1+'), findsOneWidget);
  });

  testWidgets('working the queue updates the count it came from', (
    tester,
  ) async {
    await h.startSignedIn(tester);
    await h.goTo(tester, 'Reports');
    await h.openReportSheet(tester, 'Spam');
    await tapText(tester, 'Resolve');

    expect(find.text('Report resolved.'), findsOneWidget);
    expect(badge('1'), findsOneWidget);
  });

  testWidgets('the phone dock wears it too', (tester) async {
    await h.startPhone(tester);

    expect(
      find.descendant(of: find.byType(ConsoleDock), matching: find.text('2')),
      findsOneWidget,
    );
  });

  testWidgets('Configuration is a screen of its own on the phone', (
    tester,
  ) async {
    await h.startPhone(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    // Inside Configuration there is no place switcher: the operator came here
    // to work on the server, and the screen is theirs until they leave it.
    expect(find.byType(ConsoleDock), findsNothing);
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    // Back returns to the place the gear was tapped from, switcher and all.
    expect(find.byType(ConsoleDock), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });
}
