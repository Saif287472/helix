import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/conversation/presentation/conversation_screen.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import 'support/chat_harness.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    TestChatGateway gateway,
    String chat,
  ) async {
    await tester.pumpWidget(
      chatApp(gateway, ConversationScreen(conversationId: chat)),
    );
    await settle(tester, rounds: 10);
  }

  chatTest('shows the header, a date separator and the bubbles', (
    tester,
    gateway,
  ) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await tester.runAsync(() async {
      await gateway.incoming(chat, 'Hello Bob here');
      await gateway.outgoing(chat, 'Hi Bob');
    });
    await open(tester, gateway, chat);

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('online'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(
      find.textContaining('Hello Bob here', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('Hi Bob', findRichText: true), findsOneWidget);
    expect(find.byType(HelixMessageBubble), findsNWidgets(2));
  });

  chatTest('an empty conversation says it is encrypted', (
    tester,
    gateway,
  ) async {
    final chat = (await tester.runAsync(() => gateway.chatWith('bob')))!;
    await open(tester, gateway, chat);
    expect(find.textContaining('end-to-end encrypted'), findsOneWidget);
  });

  chatTest('sending clears the field and the message appears', (
    tester,
    gateway,
  ) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await open(tester, gateway, chat);

    await tester.enterText(find.byType(TextField), 'see you at 5');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
    await settle(tester, rounds: 10);

    expect(gateway.log, contains('sendText:$chat:see you at 5'));
    expect(
      find.textContaining('see you at 5', findRichText: true),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
  });

  chatTest('the unread divider is drawn once and messages are marked read', (
    tester,
    gateway,
  ) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await tester.runAsync(() async {
      await gateway.outgoing(chat, 'earlier');
      await gateway.incoming(chat, 'one');
      await gateway.incoming(chat, 'two');
    });
    await open(tester, gateway, chat);

    expect(find.text('2 unread messages'), findsOneWidget);
    await settle(tester, rounds: 10);
    expect(gateway.log, contains('markRead:$chat'));
  });

  chatTest('deleted, undecryptable and unsupported bubbles are notices', (
    tester,
    gateway,
  ) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await tester.runAsync(() async {
      final gone = await gateway.incoming(chat, 'secret');
      await gateway.db.messagesDao.deleteForEveryone(
        gone.localRowid,
        deletedAt: testNow,
      );
      for (final kind in ['undecryptable', 'unsupported']) {
        await gateway.db.messagesDao.insertMessage(
          MessagesCompanion.insert(
            messageId: kind,
            conversationId: chat,
            sender: 'bob',
            outgoing: false,
            sortKey: SortKey.of(testNow.toUtc(), kind),
            sentAt: testNow.toUtc(),
            receivedAt: testNow.toUtc(),
            kind: kind,
            status: MessageStatus.received,
          ),
        );
      }
    });
    await open(tester, gateway, chat);

    expect(find.text('This message was deleted'), findsOneWidget);
    expect(find.text("Couldn't decrypt this message"), findsOneWidget);
    expect(
      find.text('This message needs a newer version of Helix'),
      findsOneWidget,
    );
    expect(find.textContaining('secret'), findsNothing);
  });

  chatTest('long press offers reply, copy and delete; reply shows a banner', (
    tester,
    gateway,
  ) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await tester.runAsync(() => gateway.incoming(chat, 'what time?'));
    await open(tester, gateway, chat);

    await tester.longPress(
      find.textContaining('what time?', findRichText: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Delete for me'), findsOneWidget);
    // An incoming message cannot be edited or deleted for everyone.
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete for everyone'), findsNothing);

    await tester.tap(find.text('Reply'));
    await settle(tester);
    expect(find.text('Replying to Bob'), findsOneWidget);
  });

  chatTest('reacting records the reaction and shows it', (
    tester,
    gateway,
  ) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    final row = (await tester.runAsync(() => gateway.incoming(chat, 'nice')))!;
    await open(tester, gateway, chat);

    await tester.longPress(find.textContaining('nice', findRichText: true));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('React with 👍'));
    await settle(tester, rounds: 10);

    expect(gateway.log, contains('react:${row.localRowid}:👍'));
    expect(find.text('👍'), findsWidgets);
  });

  chatTest('a recent own message can be edited and deleted for everyone', (
    tester,
    gateway,
  ) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    final row = (await tester.runAsync(
      () => gateway.outgoing(
        chat,
        'typo here',
        at: testNow.subtract(const Duration(minutes: 2)),
      ),
    ))!;
    await open(tester, gateway, chat);

    await tester.longPress(
      find.textContaining('typo here', findRichText: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('Message info'), findsOneWidget);
    await tester.tap(find.text('Edit'));
    await settle(tester);
    expect(find.text('Edit message'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'fixed here');
    await tester.pump();
    await tester.tap(find.byTooltip('Save edit'));
    await settle(tester, rounds: 10);
    expect(gateway.log, contains('edit:${row.localRowid}:fixed here'));
    expect(
      find.textContaining('fixed here', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('Edited', findRichText: true), findsOneWidget);

    await tester.longPress(
      find.textContaining('fixed here', findRichText: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete for everyone'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete for everyone'));
    await settle(tester, rounds: 10);
    expect(gateway.log, contains('deleteForEveryone:${row.localRowid}'));
    expect(find.text('You deleted this message'), findsOneWidget);
  });

  chatTest('an old own message cannot be edited', (tester, gateway) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await tester.runAsync(
      () => gateway.outgoing(
        chat,
        'ancient',
        at: testNow.subtract(const Duration(hours: 3)),
      ),
    );
    await open(tester, gateway, chat);
    await tester.longPress(find.textContaining('ancient', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Delete for everyone'), findsOneWidget);
  });

  chatTest('a draft is saved when the conversation closes', (
    tester,
    gateway,
  ) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await open(tester, gateway, chat);
    await tester.enterText(find.byType(TextField), 'half written');
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    final row = await tester.runAsync(
      () => gateway.db.conversationsDao.byId(chat),
    );
    expect(row!.draft, 'half written');
  });

  chatTest('typing is announced, and stops when the text is cleared', (
    tester,
    gateway,
  ) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await open(tester, gateway, chat);
    await tester.enterText(find.byType(TextField), 'h');
    await tester.pump();
    await settle(tester);
    expect(gateway.log, contains('typing:true'));
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await settle(tester);
    expect(gateway.log, contains('typing:false'));
  });

  chatTest('searching inside the chat lists hits', (tester, gateway) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await tester.runAsync(() async {
      await gateway.incoming(chat, 'lunch at noon');
      await gateway.incoming(chat, 'something else');
    });
    await open(tester, gateway, chat);

    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'lunch');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester, rounds: 20);
    expect(find.byType(HelixMessageSearchTile), findsOneWidget);
  });

  chatTest('a group shows sender names and a blocked chat cannot be written', (
    tester,
    gateway,
  ) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await tester.runAsync(() async {
      await gateway.db.peopleDao.setBlocked('bob', true, now: testNow);
    });
    await open(tester, gateway, chat);
    expect(find.textContaining('You blocked this contact'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  chatTest('the microphone says so when recording is unavailable', (
    tester,
    gateway,
  ) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await open(tester, gateway, chat);
    final mic = find.bySemanticsLabel('Record voice message');
    await tester.longPress(mic);
    await settle(tester);
    expect(
      find.text('Voice messages are not available on this device.'),
      findsOneWidget,
    );
  });

  chatTest('lays out at 2x text and keeps 48 px targets', (
    tester,
    gateway,
  ) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await tester.runAsync(() async {
      await gateway.incoming(chat, 'hello');
      await gateway.outgoing(chat, 'hi back');
    });
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester, gateway, chat);
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });
}
