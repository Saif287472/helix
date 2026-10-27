import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/conversation/presentation/conversation_screen.dart';
import 'package:helix_remote/features/conversation/presentation/starred_screen.dart';
import 'package:helix_remote_db/helix_remote_db.dart';

import 'support/chat_harness.dart';
import 'support/orbit_theme.dart';

/// Starred messages, pinned messages and favourite chats, in the app.
void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(412, 866);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> open(
    WidgetTester tester,
    TestChatGateway gateway,
    String chat,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      chatApp(gateway, ConversationScreen(conversationId: chat)),
    );
    await settle(tester, rounds: 10);
  }

  Future<String> chatWithBob(
    WidgetTester tester,
    TestChatGateway gateway,
  ) async =>
      (await tester.runAsync(() => gateway.chatWith('bob', name: 'Bob')))!;

  chatTest('the menu stars a message, and the bubble says so', (
    tester,
    gateway,
  ) async {
    final chat = await chatWithBob(tester, gateway);
    final row = (await tester.runAsync(
      () => gateway.incoming(chat, 'the door code is 4411'),
    ))!;
    await open(tester, gateway, chat);

    await tester.longPress(findMessageText('the door code is 4411'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Star'));
    await settle(tester);

    expect(
      (await tester.runAsync(
        () => gateway.db.messagesDao.byRowid(row.localRowid),
      ))!.starredAt,
      isNotNull,
    );
    expect(find.bySemanticsLabel(RegExp('door code.*starred')), findsOneWidget);

    await tester.longPress(findMessageText('the door code is 4411'));
    await tester.pumpAndSettle();
    expect(find.text('Unstar'), findsOneWidget);
    await tester.tap(find.text('Unstar'));
    await settle(tester);
    expect(
      (await tester.runAsync(
        () => gateway.db.messagesDao.byRowid(row.localRowid),
      ))!.starredAt,
      isNull,
    );
  });

  chatTest('the menu pins a message and the banner shows it, then unpins', (
    tester,
    gateway,
  ) async {
    final chat = await chatWithBob(tester, gateway);
    await tester.runAsync(() => gateway.incoming(chat, 'meet at five'));
    await open(tester, gateway, chat);
    expect(find.textContaining('Pinned message'), findsNothing);

    await tester.longPress(findMessageText('meet at five'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin'));
    await settle(tester, rounds: 10);

    expect(gateway.log, contains('pin:1:true'));
    expect(find.text('Pinned message'), findsOneWidget);
    expect(find.text('meet at five'), findsWidgets);

    // The banner says it too: the bubble is the one that starts "<text>,".
    await tester.longPress(
      find.bySemanticsLabel(RegExp('^meet at five, pinned')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unpin'));
    await settle(tester, rounds: 10);
    expect(gateway.log, contains('pin:1:false'));
    expect(find.textContaining('Pinned message'), findsNothing);
  });

  chatTest('a fourth pin is refused with a sentence, and nothing is sent', (
    tester,
    gateway,
  ) async {
    final chat = await chatWithBob(tester, gateway);
    await tester.runAsync(() async {
      for (final text in ['one', 'two', 'three', 'four']) {
        await gateway.incoming(chat, text);
      }
      final rows = await gateway.db.messagesDao.pageOlder(chat, limit: 10);
      for (final (i, row) in rows.messages.take(3).indexed) {
        await gateway.db.messagesDao.setPinned(
          row.localRowid,
          testNow.add(Duration(seconds: i)),
        );
      }
    });
    await open(tester, gateway, chat);
    expect(find.text('Pinned message 1 of 3'), findsOneWidget);

    await tester.longPress(findMessageText('four'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin'));
    await settle(tester, rounds: 10);

    expect(
      find.text('A chat keeps three pinned messages. Unpin one first.'),
      findsOneWidget,
    );
    expect(gateway.log.where((l) => l.startsWith('pin:')), isEmpty);
    await tester.pump(const Duration(seconds: 5));
  });

  chatTest('a message of your own can be starred and pinned too', (
    tester,
    gateway,
  ) async {
    final chat = await chatWithBob(tester, gateway);
    await tester.runAsync(() => gateway.outgoing(chat, 'oops'));
    await open(tester, gateway, chat);

    await tester.longPress(findMessageText('oops'));
    await tester.pumpAndSettle();
    expect(find.text('Star'), findsOneWidget);
    expect(find.text('Pin'), findsOneWidget);
    expect(find.text('Delete for me'), findsOneWidget);
  });

  group('the starred messages page', () {
    chatTest('lists them across chats, newest star first, and opens one', (
      tester,
      gateway,
    ) async {
      final bob = await chatWithBob(tester, gateway);
      final cara = (await tester.runAsync(
        () => gateway.chatWith('cara', name: 'Cara'),
      ))!;
      await tester.runAsync(() async {
        final a = await gateway.incoming(bob, 'the door code is 4411');
        final b = await gateway.incoming(
          cara,
          'bring the charger',
          sender: 'cara',
        );
        await gateway.incoming(cara, 'not this one', sender: 'cara');
        await gateway.db.messagesDao.setStarred(a.localRowid, testNow);
        await gateway.db.messagesDao.setStarred(
          b.localRowid,
          testNow.add(const Duration(minutes: 1)),
        );
      });
      phone(tester);
      await tester.pumpWidget(chatApp(gateway, const StarredScreen()));
      await settle(tester, rounds: 10);

      expect(find.text('Cara'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Bob: the door code is 4411'), findsOneWidget);
      expect(find.text('Cara: bring the charger'), findsOneWidget);
      expect(find.textContaining('not this one'), findsNothing);
      final order =
          tester.getTopLeft(find.text('Cara')).dy <
          tester.getTopLeft(find.text('Bob')).dy;
      expect(order, isTrue, reason: 'the newest star first');
    });

    chatTest('says so when nothing is starred', (tester, gateway) async {
      phone(tester);
      await tester.pumpWidget(chatApp(gateway, const StarredScreen()));
      await settle(tester, rounds: 10);
      expect(find.text('No starred messages'), findsOneWidget);
    });
  });
}
