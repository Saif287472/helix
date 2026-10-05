import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/core/chat/message_semantics.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/router/app_router.dart';
import 'package:helix_remote/features/conversation/presentation/conversation_screen.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote/features/groups/presentation/group_info_screen.dart';
import 'package:helix_remote/shared/widgets/pending_members_prompt.dart';
import 'package:helix_remote/shared/widgets/unconfirmed_member_host.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import '../chat_logic_test.dart' show row;
import '../support/chat_harness.dart' as chat;
import '../support/group_support.dart';
import '../support/harness.dart';

/// Members the server's roster added without an announcement: the notice in
/// the chat, the "Confirm NAME?" prompt in the group info and the
/// conversation, and the app-wide banner.
void main() {
  const bobWaiting = PendingMemberInfo(
    account: 'bob',
    reason: PendingReason.unattributed,
  );
  const carolByLink = PendingMemberInfo(
    account: 'carol',
    reason: PendingReason.linkJoin,
  );

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('the notice row', () {
    MessageRow noticeRow(String payload) =>
        row(1, kind: 'system', payload: payload, sender: 'ada');

    test('an unattributed member reads as added by the server roster', () {
      final text = systemNoticeText(
        noticeRow(
          '{"kind":"member_unconfirmed","members":["bob"],'
          '"reason":"unattributed"}',
        ),
        selfId: 'self',
        people: testNames,
      );
      expect(text, startsWith('Bob was added by the server roster.'));
      expect(text, contains('No admin announced it.'));
      expect(text, contains('until you confirm'));
    });

    test('a link joiner is explained as joining with the link', () {
      final text = systemNoticeText(
        noticeRow(
          '{"kind":"member_unconfirmed","members":["carol"],'
          '"reason":"link_join"}',
        ),
        selfId: 'self',
        people: testNames,
      );
      expect(text, startsWith('~carol was added by the server roster.'));
      expect(text, contains('They joined with the group link.'));
    });

    test('an unknown reason (a newer engine) reads as unattributed', () {
      final text = systemNoticeText(
        noticeRow(
          '{"kind":"member_unconfirmed","members":["bob"],"reason":"x"}',
        ),
        selfId: 'self',
        people: testNames,
      );
      expect(text, contains('No admin announced it.'));
    });

    test('a notice with no member still reads, never raw JSON', () {
      final text = systemNoticeText(
        noticeRow('{"kind":"member_unconfirmed"}'),
        selfId: 'self',
        people: testNames,
      );
      expect(text, startsWith('Someone was added by the server roster.'));
      expect(text, isNot(contains('{')));
    });
  });

  group('group info', () {
    Future<FakeGroupsPort> pump(
      WidgetTester tester, {
      GroupMemberRole role = GroupMemberRole.owner,
      List<PendingMemberInfo> pending = const [],
    }) async {
      tall(tester);
      final port = FakeGroupsPort(group: testGroup(role: role))
        ..pending = pending;
      await tester.pumpWidget(
        harness(
          home: const GroupInfoScreen(groupId: 'g1'),
          overrides: groupOverrides(port: port, names: testNames),
        ),
      );
      await tester.pumpAndSettle();
      return port;
    }

    testWidgets('shows nothing when nobody is waiting', (tester) async {
      await pump(tester);
      expect(find.byType(PendingMembersPrompt), findsOneWidget);
      expect(find.textContaining('Confirm '), findsNothing);
      expect(find.text('Not confirmed'), findsNothing);
    });

    testWidgets('asks "Confirm Bob?" and explains why, in plain English', (
      tester,
    ) async {
      await pump(tester, pending: [bobWaiting]);

      expect(find.text('Confirm Bob?'), findsOneWidget);
      expect(
        find.textContaining(
          'Bob was added by the server roster, but no admin of this group '
          'announced it.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('stays unreadable to them'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Confirm'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Remove'), findsOneWidget);
      // The roster row says so too.
      expect(find.textContaining('Not confirmed'), findsOneWidget);
    });

    testWidgets('a member who joined by the link is explained as such', (
      tester,
    ) async {
      await pump(tester, pending: [carolByLink]);
      expect(find.text('Confirm ~carol?'), findsOneWidget);
      expect(
        find.textContaining('joined this group through its invite link'),
        findsOneWidget,
      );
    });

    testWidgets('Confirm calls confirmMember and the prompt goes away', (
      tester,
    ) async {
      final port = await pump(tester, pending: [bobWaiting]);

      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(port.calls, contains('confirm bob'));
      expect(find.text('Confirm Bob?'), findsNothing);
      expect(find.textContaining('Bob was confirmed'), findsOneWidget);
      expect(find.text('Not confirmed'), findsNothing);
    });

    testWidgets('Remove asks first, then removes the member', (tester) async {
      final port = await pump(tester, pending: [bobWaiting]);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Bob?'), findsOneWidget);
      // Backing out removes nobody.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(port.calls, isNot(contains('remove bob')));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(port.calls, contains('remove bob'));
    });

    testWidgets('an admin may remove an ordinary member, not another admin', (
      tester,
    ) async {
      // Self is an admin; Ada is the owner (the fixture), Bob a member.
      await pump(
        tester,
        role: GroupMemberRole.admin,
        pending: [
          bobWaiting,
          const PendingMemberInfo(
            account: 'ada',
            reason: PendingReason.unattributed,
          ),
        ],
      );
      final bobCard = find.byKey(const ValueKey('pending-bob'));
      final adaCard = find.byKey(const ValueKey('pending-ada'));
      expect(
        find.descendant(
          of: bobCard,
          matching: find.widgetWithText(OutlinedButton, 'Remove'),
        ),
        findsOneWidget,
      );
      // The owner cannot be removed by an admin: Confirm only, with the hint.
      expect(
        find.descendant(
          of: adaCard,
          matching: find.widgetWithText(OutlinedButton, 'Remove'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: adaCard,
          matching: find.textContaining('Only an admin can remove'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a plain member only sees the warning and Confirm', (
      tester,
    ) async {
      final port = await pump(
        tester,
        role: GroupMemberRole.member,
        pending: [bobWaiting],
      );

      expect(find.text('Confirm Bob?'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Remove'), findsNothing);
      expect(find.textContaining('Only an admin can remove'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Confirm'), findsOneWidget);
      expect(port.calls, isNot(contains('remove bob')));
    });

    testWidgets('a refusal is a sentence, not an exception', (tester) async {
      final port = await pump(tester, pending: [bobWaiting]);
      port.failWith = StateError('server said no');

      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Confirm Bob?'), findsOneWidget);
    });

    testWidgets('a member who is no longer waiting is said, not an error', (
      tester,
    ) async {
      final port = await pump(tester, pending: [bobWaiting]);
      // Confirmed on another device in the meantime: the engine says false.
      port.pending = const [];

      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('no longer waiting for confirmation'),
        findsOneWidget,
      );
    });

    testWidgets('the engine event shows a snackbar here', (tester) async {
      final port = await pump(tester);
      port.signal(
        const GroupMemberUnconfirmedArrived(
          'g1',
          'bob',
          PendingReason.unattributed,
          groupTitle: 'Book club',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('added by the server roster'), findsOneWidget);
    });

    testWidgets('prompts fit at 2x text with no overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester, pending: [bobWaiting, carolByLink]);
      expect(find.text('Confirm Bob?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the buttons are at least 48 px tall', (tester) async {
      await pump(tester, pending: [bobWaiting]);
      for (final label in ['Confirm', 'Remove']) {
        final size = tester.getSize(
          find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate(
              (w) => w is FilledButton || w is OutlinedButton,
            ),
          ),
        );
        expect(size.height, greaterThanOrEqualTo(48), reason: label);
        expect(size.width, greaterThanOrEqualTo(48), reason: label);
      }
    });
  });

  group('the app-wide banner', () {
    testWidgets('names the person and the group and opens the group info', (
      tester,
    ) async {
      tall(tester);
      final port = FakeGroupsPort(group: testGroup());
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(body: Text('home')),
          ),
          GoRoute(
            path: '/home/groups/:id',
            builder: (context, state) =>
                Scaffold(body: Text('info:${state.pathParameters['id']}')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...groupOverrides(port: port, names: testNames),
            appRouterProvider.overrideWithValue(router),
            authStateProvider.overrideWith(
              (ref) => Stream.value(AppAuthState.ready),
            ),
          ],
          child: MaterialApp.router(
            theme: HelixThemes.light(),
            routerConfig: router,
            builder: (context, child) => UnconfirmedMemberHost(child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      port.announceUnconfirmed(
        const GroupMemberUnconfirmedArrived(
          'g1',
          'bob',
          PendingReason.unattributed,
          groupTitle: 'Book club',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text(
          'Bob was added to "Book club" by the server roster. Review it.',
        ),
        findsOneWidget,
      );
      // Pressed through the widget: the snackbar floats in an overlay the
      // test's hit testing does not reach.
      tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('info:g1'), findsOneWidget);
    });
  });

  group('the group conversation', () {
    chat.chatTest('shows the prompt above the messages, and confirming works', (
      tester,
      gateway,
    ) async {
      await tester.runAsync(
        () => gateway.db.conversationsDao.ensureGroup(
          'group:g1',
          title: 'Book club',
          now: chat.testNow,
        ),
      );
      final port = FakeGroupsPort(
        group: testGroup(role: GroupMemberRole.member),
      )..pending = [bobWaiting];
      await tester.pumpWidget(
        chat.chatApp(
          gateway,
          const ConversationScreen(conversationId: 'group:g1'),
          overrides: [...groupOverrides(port: port, names: testNames)],
        ),
      );
      await chat.settle(tester, rounds: 10);

      expect(find.text('Confirm Bob?'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Remove'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await chat.settle(tester, rounds: 6);
      expect(port.calls, contains('confirm bob'));
      expect(find.text('Confirm Bob?'), findsNothing);
    });

    chat.chatTest('a direct chat has no prompt', (tester, gateway) async {
      final id = (await tester.runAsync(
        () => gateway.chatWith('bob', name: 'Bob'),
      ))!;
      final port = FakeGroupsPort(group: testGroup())..pending = [bobWaiting];
      await tester.pumpWidget(
        chat.chatApp(
          gateway,
          ConversationScreen(conversationId: id),
          overrides: groupOverrides(port: port, names: testNames),
        ),
      );
      await chat.settle(tester, rounds: 8);
      expect(find.byType(PendingMembersPrompt), findsNothing);
    });
  });
}
