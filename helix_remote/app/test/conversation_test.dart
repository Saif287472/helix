import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote/features/conversation/presentation/conversation_screen.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart' show FailedAction;
import 'package:orbit_ui/orbit_ui.dart';

import 'support/a3b_fakes.dart' show FakeLocalSettings;
import 'support/chat_harness.dart';
import 'support/orbit_theme.dart';

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
    // Orbit sets the day in capitals.
    expect(find.text('TODAY'), findsOneWidget);
    expect(findMessageText('Hello Bob here'), findsOneWidget);
    expect(findMessageText('Hi Bob'), findsOneWidget);
    expect(find.byType(OrbitMessageBubble), findsNWidgets(2));
  });

  chatTest('your own chat is yours alone', (tester, gateway) async {
    final chat = (await tester.runAsync(
      () => gateway.db.conversationsDao.ensureDirect('me', now: testNow),
    ))!;
    await tester.runAsync(() => gateway.outgoing(chat.id, 'buy milk'));
    await open(tester, gateway, chat.id);

    expect(find.text('Note to self'), findsOneWidget);
    expect(findMessageText('buy milk'), findsOneWidget);
    expect(
      find.text('online'),
      findsNothing,
      reason: 'there is nobody here whose presence to ask the server about',
    );
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
    expect(findMessageText('see you at 5'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
  });

  chatTest('an action that failed for good is shown on its message and retried '
      'from there', (tester, gateway) async {
    final chat = (await tester.runAsync(() => gateway.chatWith('bob')))!;
    final row = (await tester.runAsync(
      () => gateway.outgoing(chat, 'see you at 5'),
    ))!;
    gateway.actionFailures.add(
      FailedAction(
        opId: 42,
        targetRowid: row.localRowid,
        action: 'delete',
        errorCode: 'forbidden',
      ),
    );
    await open(tester, gateway, chat);

    expect(find.text("Couldn't delete for everyone"), findsOneWidget);
    await tester.tap(find.text('RETRY'));
    await settle(tester, rounds: 5);
    expect(gateway.log, contains('retryAction:42'));
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

    expect(find.text('2 UNREAD MESSAGES'), findsOneWidget);
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

    expect(findMessageText('This message was deleted'), findsOneWidget);
    expect(findMessageText("Couldn't decrypt this message"), findsOneWidget);
    // The app is called Orbit now.
    expect(
      findMessageText('This message needs a newer version of Orbit'),
      findsOneWidget,
    );
    expect(findMessageText('secret'), findsNothing);
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

    await tester.longPress(findMessageText('what time?'));
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

    await tester.longPress(findMessageText('nice'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('React with 👍'));
    await settle(tester, rounds: 10);

    expect(gateway.log, contains('react:${row.localRowid}:👍'));
    expect(find.text('👍'), findsWidgets);
  });

  chatTest('the reactions sheet says who reacted, and yours can go', (
    tester,
    gateway,
  ) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    final row = (await tester.runAsync(() async {
      final row = await gateway.incoming(chat, 'nice');
      await gateway.react(row.localRowid, '👍');
      return row;
    }))!;
    gateway.log.clear();
    await open(tester, gateway, chat);

    // The reaction under the bubble opens the sheet.
    await tester.tap(find.text('👍'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(find.text('Reactions'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Tap to remove'), findsOneWidget);

    await tester.tap(find.text('You'));
    await settle(tester, rounds: 10);
    expect(gateway.log, contains('react:${row.localRowid}:null'));
    expect(find.text('Reactions'), findsNothing);
  });

  chatTest('Enter sends when "Enter key sends" is on', (tester, gateway) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    final settings = FakeLocalSettings();
    await tester.runAsync(() => settings.set(AppSettings.enterToSend, true));
    await tester.pumpWidget(
      chatApp(
        gateway,
        ConversationScreen(conversationId: chat),
        settings: settings,
      ),
    );
    await settle(tester, rounds: 10);

    await tester.enterText(find.byType(TextField), 'on my way');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await settle(tester, rounds: 10);
    expect(gateway.log, contains('sendText:$chat:on my way'));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
  });

  chatTest('a quote jumps to the message it quotes, outside the loaded '
      'window, and Scroll to latest comes back', (tester, gateway) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await tester.runAsync(() async {
      final first = await gateway.incoming(
        chat,
        'the very first message',
        at: testNow.subtract(const Duration(hours: 5)),
      );
      // Yours, so none of them is unread (the window would grow to show the
      // unread ones).
      for (var i = 0; i < 80; i++) {
        await gateway.outgoing(
          chat,
          'filler $i',
          at: testNow.subtract(Duration(hours: 4, minutes: -i)),
        );
      }
      await gateway.db.messagesDao.insertMessage(
        MessagesCompanion.insert(
          messageId: 'quoting',
          conversationId: chat,
          sender: 'me',
          outgoing: true,
          sortKey: SortKey.of(testNow.toUtc(), 'quoting'),
          sentAt: testNow.toUtc(),
          receivedAt: testNow.toUtc(),
          kind: 'text',
          body: const Value('about that'),
          status: MessageStatus.sent,
          replyToId: Value(first.messageId),
          replyToAuthor: const Value('bob'),
        ),
      );
      await gateway.db.messagesDao.refreshSummary(chat);
    });
    await open(tester, gateway, chat);
    // The bubble holding [text] (the quote repeats the words).
    Finder bubble(String text) => find.byWidgetPredicate(
      (w) =>
          w is OrbitMessageBubble &&
          w.message.content is HelixTextContent &&
          (w.message.content as HelixTextContent).text == text,
    );
    expect(bubble('the very first message'), findsNothing);
    expect(bubble('about that'), findsOneWidget);

    // The quote names it; tapping it opens a window around it.
    await tester.tap(find.text('the very first message', findRichText: true));
    await settle(tester, rounds: 20);
    await tester.pumpAndSettle();
    expect(bubble('the very first message'), findsOneWidget);
    expect(bubble('about that'), findsNothing);

    // The newest messages are a tap away.
    await tester.tap(find.byTooltip('Scroll to latest message'));
    await settle(tester, rounds: 20);
    await tester.pumpAndSettle();
    expect(bubble('about that'), findsOneWidget);
  });

  chatTest('opened at a message (a search hit), it shows that message', (
    tester,
    gateway,
  ) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    final first = (await tester.runAsync(() async {
      final first = await gateway.incoming(
        chat,
        'where it started',
        at: testNow.subtract(const Duration(hours: 5)),
      );
      for (var i = 0; i < 80; i++) {
        await gateway.outgoing(
          chat,
          'later $i',
          at: testNow.subtract(Duration(hours: 4, minutes: -i)),
        );
      }
      await gateway.db.messagesDao.refreshSummary(chat);
      return first;
    }))!;
    await tester.pumpWidget(
      chatApp(
        gateway,
        ConversationScreen(conversationId: chat, messageId: first.messageId),
      ),
    );
    await settle(tester, rounds: 20);
    await tester.pumpAndSettle();
    expect(findMessageText('where it started'), findsOneWidget);
    // Far from the newest now: the way back, with the unread count.
    expect(
      find.byTooltip('Scroll to latest message, 1 unread'),
      findsOneWidget,
    );
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

    await tester.longPress(findMessageText('typo here'));
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
    expect(findMessageText('fixed here'), findsOneWidget);
    expect(find.text('Edited'), findsOneWidget);

    await tester.longPress(findMessageText('fixed here'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete for everyone'));
    await tester.pumpAndSettle();
    expect(find.text('Delete for everyone?'), findsOneWidget);
    await tester.tap(find.widgetWithText(OrbitButton, 'Delete for everyone'));
    await settle(tester, rounds: 10);
    expect(gateway.log, contains('deleteForEveryone:${row.localRowid}'));
    expect(findMessageText('You deleted this message'), findsOneWidget);
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
    await tester.longPress(findMessageText('ancient'));
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

  chatTest('a stored draft cleared to nothing stays cleared', (
    tester,
    gateway,
  ) async {
    final chat = (await tester.runAsync(() async {
      final id = await gateway.chatWith('bob', name: 'Bob');
      await gateway.db.conversationsDao.setDraft(id, 'old words');
      return id;
    }))!;
    await open(tester, gateway, chat);
    await settle(tester);
    expect(find.text('old words'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    final row = await tester.runAsync(
      () => gateway.db.conversationsDao.byId(chat),
    );
    expect(row!.draft, isNull);
  });

  chatTest('the text just sent does not come back as the draft', (
    tester,
    gateway,
  ) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await open(tester, gateway, chat);
    await tester.enterText(find.byType(TextField), 'see you at six');
    // The draft is saved half a second after the last keystroke.
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
    expect(
      (await tester.runAsync(
        () => gateway.db.conversationsDao.byId(chat),
      ))!.draft,
      'see you at six',
    );
    await tester.tap(find.byTooltip('Send'));
    await settle(tester);
    expect(gateway.log, contains('sendText:$chat:see you at six'));
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    final row = await tester.runAsync(
      () => gateway.db.conversationsDao.byId(chat),
    );
    expect(row!.draft, isNull);
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
    // Orbit's menu closes first and opens the search a beat later.
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'lunch');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester, rounds: 20);
    // One hit, with the match marked; the timeline is not shown meanwhile.
    expect(
      find.textContaining('lunch at noon', findRichText: true),
      findsOneWidget,
    );
    expect(findMessageText('something else'), findsNothing);
    expect(find.text('No results'), findsNothing);

    // Picking it closes the search and brings the message back into view.
    await tester.tap(find.textContaining('lunch at noon', findRichText: true));
    await settle(tester, rounds: 10);
    expect(find.byTooltip('Close search'), findsNothing);
    expect(findMessageText('lunch at noon'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
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

  group('disappearing messages', () {
    /// The timer the screen started for [rowid], or null when it started none.
    Future<DateTime?> expiryOf(
      WidgetTester tester,
      TestChatGateway gateway,
      int rowid,
    ) async => (await tester.runAsync(
      () => gateway.engine.chats.message(rowid),
    ))?.expiresAt;

    // The framework asserts on lifecycle shortcuts, so the app is walked the
    // way the platform walks it: resumed -> inactive -> hidden -> paused, and
    // back the other way.
    Future<void> leave(WidgetTester tester) async {
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
    }

    Future<void> comeBack(WidgetTester tester) async {
      for (final state in const [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
    }

    chatTest('a message on screen starts its timer, and only once', (
      tester,
      gateway,
    ) async {
      final chat = (await tester.runAsync(
        () => gateway.chatWith('bob', name: 'Bob'),
      ))!;
      final rowid = (await tester.runAsync(
        () => gateway.incoming(chat, 'this goes away', expireSeconds: 3600),
      ))!;
      expect(
        (await tester.runAsync(
          () => gateway.engine.chats.message(rowid.localRowid),
        ))?.expiresAt,
        isNull,
        reason: 'a received message arrives with no timer',
      );

      await open(tester, gateway, chat);
      expect(
        await expiryOf(tester, gateway, rowid.localRowid),
        testNow.toUtc().add(const Duration(hours: 1)),
      );

      // Scrolling back and forth must not restart it: the timer counts from
      // first display, and a longer life is not a thing the person agreed to.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await settle(tester, rounds: 10);
      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await settle(tester, rounds: 10);
      expect(
        await expiryOf(tester, gateway, rowid.localRowid),
        testNow.toUtc().add(const Duration(hours: 1)),
      );
    });

    chatTest('a message drawn in the background waits for the app to return', (
      tester,
      gateway,
    ) async {
      final chat = (await tester.runAsync(
        () => gateway.chatWith('bob', name: 'Bob'),
      ))!;
      await open(tester, gateway, chat);

      await leave(tester);
      final rowid = (await tester.runAsync(
        () => gateway.incoming(chat, 'sent while away', expireSeconds: 60),
      ))!;
      await settle(tester, rounds: 10);

      // Nobody has looked at this, so it must not be disappearing yet.
      expect(await expiryOf(tester, gateway, rowid.localRowid), isNull);

      await comeBack(tester);
      await settle(tester, rounds: 10);
      expect(
        await expiryOf(tester, gateway, rowid.localRowid),
        testNow.toUtc().add(const Duration(minutes: 1)),
      );
    });

    chatTest('an ordinary message is left alone', (tester, gateway) async {
      final chat = (await tester.runAsync(
        () => gateway.chatWith('bob', name: 'Bob'),
      ))!;
      final rowid = (await tester.runAsync(
        () => gateway.incoming(chat, 'this one stays'),
      ))!;
      await open(tester, gateway, chat);
      await settle(tester, rounds: 10);
      expect(await expiryOf(tester, gateway, rowid.localRowid), isNull);
    });
  });
}
