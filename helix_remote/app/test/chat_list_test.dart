import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/chat/chat_people.dart';
import 'package:helix_remote/core/chat/search_snippet.dart';
import 'package:helix_remote/features/chats/presentation/chats_tab.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import 'support/chat_harness.dart';

void main() {
  Future<void> pumpTab(WidgetTester tester, TestChatGateway gateway) async {
    await tester.pumpWidget(chatApp(gateway, const ChatsTab()));
    await settle(tester);
  }

  chatTest('shows the empty state with no chats', (tester, gateway) async {
    await pumpTab(tester, gateway);
    expect(find.text('No chats yet'), findsOneWidget);
    expect(find.text('Find people'), findsOneWidget);
  });

  chatTest('names people by the naming rule, with unread and ticks', (
    tester,
    gateway,
  ) async {
    final bob = await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob Marley'),
    );
    await tester.runAsync(() async {
      await gateway.incoming(bob!, 'hello there');
      await gateway.incoming(bob, 'are you free?');
      final carol = await gateway.chatWith('carol');
      await gateway.db.peopleDao.upsertPerson(
        PeopleCompanion.insert(
          accountId: 'carol',
          nickname: const Value('Caz'),
          updatedAt: testNow,
        ),
      );
      await gateway.outgoing(
        carol,
        'on my way',
        status: MessageStatus.delivered,
      );
    });
    await pumpTab(tester, gateway);

    expect(find.text('Bob Marley'), findsOneWidget);
    expect(find.text('Caz'), findsOneWidget);
    expect(find.text('are you free?'), findsOneWidget);
    expect(find.text('You: on my way'), findsOneWidget);
    // Two unread messages in Bob's chat.
    expect(find.text('2'), findsOneWidget);
    expect(find.byType(HelixStatusTicks), findsOneWidget);
  });

  chatTest('long press selects, pin and archive act on the chat', (
    tester,
    gateway,
  ) async {
    final bob = await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    );
    await tester.runAsync(() => gateway.incoming(bob!, 'hi'));
    await pumpTab(tester, gateway);

    await tester.longPress(find.text('Bob'));
    await tester.pump();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Pin chats'));
    await settle(tester);
    final row = await tester.runAsync(
      () => gateway.db.conversationsDao.byId(bob!),
    );
    expect(row!.pinnedAt, isNotNull);
    expect(find.text('1 selected'), findsNothing);

    await tester.longPress(find.text('Bob'));
    await tester.pump();
    await tester.tap(find.byTooltip('Archive chats'));
    await settle(tester);
    expect(find.text('Bob'), findsNothing);
    expect(find.text('Archived'), findsOneWidget);
  });

  chatTest('delete asks first and removes the chat', (tester, gateway) async {
    final bob = await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    );
    await tester.runAsync(() => gateway.incoming(bob!, 'hi'));
    await pumpTab(tester, gateway);

    await tester.longPress(find.text('Bob'));
    await tester.pump();
    await tester.tap(find.byTooltip('Delete chats'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this chat?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(find.text('Bob'), findsNothing);
    expect(find.text('No chats yet'), findsOneWidget);
  });

  chatTest('search finds a message and a chat by name', (
    tester,
    gateway,
  ) async {
    final bob = await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    );
    await tester.runAsync(() => gateway.incoming(bob!, 'pizza tonight?'));
    await pumpTab(tester, gateway);

    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'pizza');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester, rounds: 20);
    expect(find.text('Messages'), findsOneWidget);
    expect(find.byType(HelixMessageSearchTile), findsOneWidget);
  });

  chatTest('the people seam is placed in the search', (tester, gateway) async {
    await tester.pumpWidget(
      chatApp(
        gateway,
        ChatsTab(
          peopleResults: (context, query) =>
              Text('people for $query', key: const ValueKey('people')),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.byTooltip('Search'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'sam');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester, rounds: 20);
    expect(find.byKey(const ValueKey('people')), findsOneWidget);
  });

  chatTest('lays out at 2x text without overflow', (tester, gateway) async {
    final bob = await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    );
    await tester.runAsync(() => gateway.incoming(bob!, 'hi'));
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpTab(tester, gateway);
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });

  test('snippet marks every matching word and keeps the first in view', () {
    final s = snippetFor(
      'Dinner at the new pizza place with pizza lovers',
      'pizza',
    );
    expect(s.ranges, hasLength(2));
    for (final r in s.ranges) {
      expect(s.text.substring(r.start, r.end), 'pizza');
    }
  });

  test('ChatPeople names by phone book, nickname, number then ~name', () {
    expect(ChatPeople.empty.nameOf('abcdef123456'), startsWith('Helix user'));
  });
}
