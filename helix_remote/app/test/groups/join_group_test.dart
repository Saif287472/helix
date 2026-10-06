import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/links/deep_link.dart';
import 'package:helix_remote/core/router/app_router.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote/features/groups/groups_routes.dart';
import 'package:helix_remote/features/groups/presentation/join_group_screen.dart';
import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode;
import 'package:go_router/go_router.dart';

import '../support/group_support.dart';
import '../support/harness.dart';

/// Joining a group from a link: a preview first, an explicit button second,
/// and every way the link can fail said plainly.
void main() {
  const link = 'https://example.org/open#HLX-GRP-dG9rZW4.a2V5';

  Future<FakeGroupsPort> pump(
    WidgetTester tester, {
    String? initial = link,
    FakeGroupsPort? port,
  }) async {
    port ??= FakeGroupsPort();
    await tester.pumpWidget(
      harness(
        home: JoinGroupScreen(initialLink: initial),
        routes: [stubRoute('/home/groups/:id', 'group page')],
        overrides: groupOverrides(port: port, names: testNames),
      ),
    );
    await tester.pumpAndSettle();
    return port;
  }

  testWidgets('a shared link shows the group before anything is joined', (
    tester,
  ) async {
    final port = await pump(tester);

    expect(find.text('Book club'), findsOneWidget);
    expect(find.text('3 members'), findsOneWidget);
    expect(find.text('We read on Sundays'), findsOneWidget);
    expect(find.text('Join group'), findsOneWidget);
    // Opening a link never joins by itself.
    expect(port.calls, ['preview']);
  });

  testWidgets('Join joins, and Open group goes to the group', (tester) async {
    final port = await pump(tester);

    await tester.tap(find.text('Join group'));
    await tester.pumpAndSettle();
    expect(port.calls, ['preview', 'join']);
    expect(find.text('You joined "Book club"'), findsOneWidget);

    await tester.tap(find.text('Open group'));
    await tester.pumpAndSettle();
    expect(find.text('group page'), findsOneWidget);
  });

  testWidgets('an approval link asks, and says an admin must approve', (
    tester,
  ) async {
    final port = FakeGroupsPort()
      ..preview = const InvitePreviewInfo(
        groupId: 'g1',
        memberCount: 12,
        requiresApproval: true,
        name: 'Careful club',
      )
      ..joinOutcome = JoinOutcome.pending;
    await pump(tester, port: port);

    expect(
      find.text('An admin has to approve you before you are in.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Ask to join'));
    await tester.pumpAndSettle();

    expect(find.text('Request sent'), findsOneWidget);
    expect(find.textContaining('has to approve you'), findsOneWidget);
  });

  testWidgets('a group you are already in offers to open it', (tester) async {
    final port = FakeGroupsPort(group: testGroup());
    await pump(tester, port: port);

    expect(find.text('You are already in this group.'), findsOneWidget);
    expect(find.text('Join group'), findsNothing);
    await tester.tap(find.text('Open group'));
    await tester.pumpAndSettle();
    expect(find.text('group page'), findsOneWidget);
  });

  testWidgets('a link whose key did not open the preview still lets you ask', (
    tester,
  ) async {
    final port = FakeGroupsPort()
      ..preview = const InvitePreviewInfo(
        groupId: 'g1',
        memberCount: 4,
        requiresApproval: false,
        name: '',
      );
    await pump(tester, port: port);

    expect(find.text('Group'), findsOneWidget);
    expect(find.textContaining('may be cut off'), findsOneWidget);
    expect(find.text('Join group'), findsOneWidget);
  });

  testWidgets('a dead link says so, with a way to try another', (tester) async {
    final port = FakeGroupsPort()
      ..failWith = const ApiException(status: 404, code: ErrorCode.notFound);
    await pump(tester, port: port);

    expect(find.textContaining('no longer valid'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Group link'), findsOneWidget);
  });

  testWidgets('a banned person is refused plainly', (tester) async {
    final port = await pump(tester);
    port.failWith = const ApiException(status: 403, code: ErrorCode.forbidden);

    await tester.tap(find.text('Join group'));
    await tester.pumpAndSettle();

    expect(find.text('You cannot join this group.'), findsOneWidget);
  });

  testWidgets('a full group says so', (tester) async {
    final port = await pump(tester);
    port.failWith = const ApiException(status: 409, code: ErrorCode.groupFull);

    await tester.tap(find.text('Join group'));
    await tester.pumpAndSettle();

    expect(find.textContaining('This group is full'), findsOneWidget);
  });

  testWidgets('a malformed link never reaches the server as text', (
    tester,
  ) async {
    final port = FakeGroupsPort()
      ..failWith = const GroupException(GroupFailure.badLink);
    await pump(tester, port: port);

    expect(find.textContaining('not a Helix group link'), findsOneWidget);
    expect(find.textContaining('HLX-GRP'), findsNothing);
  });

  testWidgets('with no link the person pastes one', (tester) async {
    final port = await pump(tester, initial: null);
    expect(find.text('Group link'), findsOneWidget);

    await tester.enterText(find.byType(TextField), link);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(port.calls, ['preview']);
    expect(find.text('Book club'), findsOneWidget);
  });

  testWidgets('holds at 2x text and meets the guidelines', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester);

    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });

  group('the link forms', () {
    test(
      'https /open#HLX-GRP and helix://open are group links, code intact',
      () {
        const code = 'HLX-GRP-dG9rZW4.a2V5';
        final web = HelixDeepLink.tryParse('https://srv.example/open#$code');
        final app = HelixDeepLink.tryParse('helix://open?code=$code');

        expect(web?.kind, HelixDeepLinkKind.groupLink);
        expect(web?.code, code);
        expect(app?.kind, HelixDeepLinkKind.groupLink);
        expect(app?.code, code);
        // A group link is not a sign-in code.
        expect(web?.setupCode, isNull);
      },
    );

    test('the group token keeps its case', () {
      final link = HelixDeepLink.tryParse(
        'https://srv.example/open#HLX-GRP-AbC.dEf',
      );
      expect(link?.code, 'HLX-GRP-AbC.dEf');
    });

    testWidgets('routing a group link opens the join screen with the code', (
      tester,
    ) async {
      late GoRouter router;
      await tester.pumpWidget(
        harness(
          home: Builder(
            builder: (context) {
              router = GoRouter.of(context);
              return const Scaffold(body: Text('home'));
            },
          ),
          routes: [stubRoute(GroupRoutes.join, 'join')],
        ),
      );
      await tester.pumpAndSettle();

      routeDeepLink(
        router,
        HelixDeepLink.tryParse('https://srv.example/open#HLX-GRP-AbC.dEf')!,
      );
      await tester.pumpAndSettle();

      expect(find.text('join HLX-GRP-AbC.dEf'), findsOneWidget);
    });
  });
}
