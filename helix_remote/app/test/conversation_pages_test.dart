import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/conversation/presentation/conversation_settings_screen.dart';
import 'package:helix_remote/features/conversation/presentation/forward_screen.dart';
import 'package:helix_remote/features/conversation/presentation/message_info_screen.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ReceiptKind;

import 'support/chat_harness.dart';
import 'support/orbit_theme.dart';

/// The conversation's pages on Orbit: forward, message info and chat
/// settings, over the test gateway.
void main() {
  /// [page] behind a button, so it can close back to something.
  Widget opener(Widget page) => Builder(
    builder: (context) => TextButton(
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => page)),
      child: const Text('open'),
    ),
  );

  group('forward', () {
    chatTest('lists the chats, sends to the picked one, and says so', (
      tester,
      gateway,
    ) async {
      final rowid = (await tester.runAsync(() async {
        final bob = await gateway.chatWith('bob', name: 'Bob');
        await gateway.chatWith('cara', name: 'Cara');
        return (await gateway.incoming(bob, 'see you at 6')).localRowid;
      }))!;
      await tester.pumpWidget(
        chatApp(
          gateway,
          opener(ForwardScreen(conversationId: 'direct:bob', rowids: [rowid])),
        ),
      );
      await tester.tap(find.text('open'));
      await settle(tester, rounds: 10);
      expect(find.text('Forward message'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Cara'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zz');
      await tester.pump();
      expect(find.text('No results'), findsOneWidget);
      expect(find.text('Nothing matches “zz”.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'car');
      await tester.pump();
      expect(find.text('Bob'), findsNothing);

      await tester.tap(find.text('Cara'));
      await tester.pump();
      await tester.tap(find.text('Send to 1 chat'));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(gateway.log, contains('forward:$rowid:direct:cara'));
      expect(find.text('Forwarded'), findsOneWidget);
      expect(find.text('Forward message'), findsNothing, reason: 'closed');
    });
  });

  group('message info', () {
    chatTest('shows the message, when it was sent, and each receipt', (
      tester,
      gateway,
    ) async {
      final rowid = (await tester.runAsync(() async {
        final bob = await gateway.chatWith('bob', name: 'Bob');
        final row = await gateway.outgoing(
          bob,
          'the colour pages are 14 to 22',
          at: testNow.subtract(const Duration(minutes: 20)),
        );
        await gateway.db.messagesDao.recordReceipt(
          row.localRowid,
          account: 'bob',
          kind: ReceiptKind.delivered,
          at: testNow.subtract(const Duration(minutes: 19)).toUtc(),
        );
        await gateway.db.messagesDao.recordReceipt(
          row.localRowid,
          account: 'bob',
          kind: ReceiptKind.read,
          at: testNow.subtract(const Duration(minutes: 10)).toUtc(),
        );
        return row.localRowid;
      }))!;
      await tester.pumpWidget(
        chatApp(gateway, MessageInfoScreen(rowid: rowid)),
      );
      await settle(tester, rounds: 10);
      expect(find.text('Message info'), findsOneWidget);
      // The message as its bubble draws it.
      expect(findMessageText('the colour pages are 14 to 22'), findsOneWidget);
      expect(find.text('Sent'), findsOneWidget);
      expect(find.text('Today, 14:10'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      // One line per person: read wins over delivered.
      expect(find.text('Read Today, 14:20'), findsOneWidget);
      expect(find.textContaining('Delivered'), findsNothing);
      expect(find.text('Recipients'), findsNothing, reason: 'a direct chat');
    });

    chatTest('a message that is gone says so', (tester, gateway) async {
      await tester.pumpWidget(
        chatApp(gateway, const MessageInfoScreen(rowid: 999)),
      );
      await settle(tester);
      expect(find.text('Message not found'), findsOneWidget);
      expect(find.text('It may have been deleted.'), findsOneWidget);
    });
  });

  group('chat settings', () {
    Future<void> open(WidgetTester tester, TestChatGateway gateway) async {
      await tester.runAsync(() async {
        final bob = await gateway.chatWith('bob', name: 'Bob');
        await gateway.incoming(bob, 'hi');
      });
      await tester.pumpWidget(
        chatApp(
          gateway,
          const ConversationSettingsScreen(conversationId: 'direct:bob'),
        ),
      );
      await settle(tester, rounds: 10);
    }

    chatTest('shows the chat and its rows', (tester, gateway) async {
      await open(tester, gateway);
      expect(find.text('Chat settings'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Contact info'), findsOneWidget);
      expect(find.text('Media, links and docs'), findsOneWidget);
      expect(find.text('Mute notifications'), findsOneWidget);
      expect(find.text('Disappearing messages'), findsOneWidget);
      expect(find.text('Clear chat'), findsOneWidget);
      expect(find.text('Block Bob'), findsOneWidget);
    });

    chatTest('muting offers durations, then Unmute', (tester, gateway) async {
      await open(tester, gateway);
      await tester.tap(find.text('Mute notifications'));
      await tester.pumpAndSettle();
      expect(find.text('8 hours'), findsOneWidget);
      expect(find.text('1 week'), findsOneWidget);
      expect(find.text('Always'), findsOneWidget);
      expect(find.text('Unmute'), findsNothing);
      await tester.tap(find.text('8 hours'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.text('Muted'), findsOneWidget);

      await tester.tap(find.text('Mute notifications'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unmute'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.text('Muted'), findsNothing);
    });

    chatTest('the timer sheet sets disappearing messages', (
      tester,
      gateway,
    ) async {
      await open(tester, gateway);
      await tester.tap(find.text('Disappearing messages'));
      await tester.pumpAndSettle();
      for (final label in [
        '5 minutes',
        '1 hour',
        '1 day',
        '1 week',
        '90 days',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      await tester.tap(find.text('1 day'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(gateway.log, contains('setDisappearing:direct:bob:86400'));
      expect(find.text('1 day'), findsOneWidget, reason: 'the row says so');
    });

    chatTest('clearing asks first, then says so', (tester, gateway) async {
      await open(tester, gateway);
      await tester.tap(find.text('Clear chat'));
      await tester.pumpAndSettle();
      expect(find.text('Clear this chat?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(gateway.log, isNot(contains('clearChat:direct:bob')));

      await tester.tap(find.text('Clear chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(gateway.log, contains('clearChat:direct:bob'));
      expect(find.text('Chat cleared'), findsOneWidget);
    });

    chatTest('blocking asks first; unblocking is one tap', (
      tester,
      gateway,
    ) async {
      await open(tester, gateway);
      // The page is a little longer since it offers a wallpaper.
      await tester.ensureVisible(find.text('Block Bob'));
      await tester.tap(find.text('Block Bob'));
      await tester.pumpAndSettle();
      expect(find.text('Block Bob?'), findsOneWidget);
      // ADR-030: the person is told.
      expect(find.textContaining('Orbit tells them'), findsOneWidget);
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(gateway.log, contains('block:bob'));
      expect(find.text('Unblock Bob'), findsOneWidget);

      await tester.tap(find.text('Unblock Bob'));
      await settle(tester);
      expect(gateway.log, contains('unblock:bob'));
      expect(find.text('Block Bob'), findsOneWidget);
    });
  });
}
