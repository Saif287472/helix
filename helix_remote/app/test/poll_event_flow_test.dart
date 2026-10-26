import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/conversation/application/message_mapper.dart';
import 'package:helix_remote/features/conversation/presentation/conversation_screen.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:orbit_ui/orbit_ui.dart';

import 'support/chat_harness.dart';

MessageRow _row(String kind, Map<String, Object?> payload) {
  final at = DateTime.utc(2026, 10, 3, 9);
  return MessageRow(
    localRowid: 1,
    messageId: 'm1',
    conversationId: 'direct:bob',
    sender: 'bob',
    outgoing: false,
    sortKey: SortKey.of(at, 'm1'),
    sentAt: at,
    receivedAt: at,
    kind: kind,
    payload: jsonEncode(payload),
    forwarded: false,
    mentionsMe: false,
    status: MessageStatus.received,
  );
}

void main() {
  final now = DateTime(2026, 10, 3, 14, 30);

  group('what a poll and an event row draw', () {
    final options = [
      {'id': 'a', 'text': 'Star Kabab'},
      {'id': 'b', 'text': 'Order in'},
    ];

    test('a poll counts every voter once and finds your answer', () {
      final content =
          contentOf(
                _row('poll', {
                  'question': 'Lunch?',
                  'options': options,
                  'multiple': true,
                  'votes': {
                    'bob': ['a'],
                    'cara': ['a', 'b'],
                    'me': ['b'],
                    'dan': <String>[],
                  },
                }),
                selfId: 'me',
                now: now,
              )
              as HelixPollContent;
      expect(content.question, 'Lunch?');
      expect(content.multiple, isTrue);
      expect(content.voters, 3, reason: 'an empty vote is not a voter');
      expect([for (final o in content.options) o.votes], [2, 2]);
      expect([for (final o in content.options) o.mine], [false, true]);
      expect(content.closed, isFalse);
    });

    test('a poll past its closing time is closed', () {
      final past = DateTime(2026, 10, 3, 14).millisecondsSinceEpoch;
      final content =
          contentOf(
                _row('poll', {
                  'question': 'Lunch?',
                  'options': options,
                  'closes_at': past,
                }),
                selfId: 'me',
                now: now,
              )
              as HelixPollContent;
      expect(content.closed, isTrue);
    });

    test('a poll with a broken payload still draws', () {
      final content =
          contentOf(
                _row('poll', {'options': 'nope', 'votes': 3}),
                selfId: 'me',
                now: now,
              )
              as HelixPollContent;
      expect(content.options, isEmpty);
      expect(content.voters, 0);
    });

    test('an event counts the answers and finds yours', () {
      final starts = DateTime(2026, 10, 30, 18, 30);
      final content =
          contentOf(
                _row('event', {
                  'title': 'Picnic',
                  'starts_at': starts.millisecondsSinceEpoch,
                  'time_zone': 'UTC+06:00',
                  'location_text': ' Ramna Park ',
                  'rsvps': {
                    'bob': {'state': 'going'},
                    'cara': {'state': 'going'},
                    'me': {'state': 'maybe'},
                    'dan': {'state': 'nonsense'},
                  },
                }),
                selfId: 'me',
                now: now,
              )
              as HelixEventContent;
      expect(content.title, 'Picnic');
      expect(content.place, 'Ramna Park');
      expect(content.whenLabel, '30 Oct, 18:30');
      expect([content.going, content.maybe, content.declined], [2, 1, 0]);
      expect(content.mine, HelixRsvp.maybe);
    });
  });

  group('in a conversation', () {
    Future<String> chatWithCard(
      WidgetTester tester,
      TestChatGateway gateway,
      String kind,
      Map<String, Object?> payload,
    ) async {
      final chat = (await tester.runAsync(
        () => gateway.chatWith('bob', name: 'Bob'),
      ))!;
      await tester.runAsync(
        () => gateway.db.messagesDao.insertMessage(
          MessagesCompanion.insert(
            messageId: 'card',
            conversationId: chat,
            sender: 'bob',
            outgoing: false,
            sortKey: SortKey.of(testNow.toUtc(), 'card'),
            sentAt: testNow.toUtc(),
            receivedAt: testNow.toUtc(),
            kind: kind,
            payload: Value(jsonEncode(payload)),
            status: MessageStatus.received,
          ),
        ),
      );
      await tester.pumpWidget(
        chatApp(gateway, ConversationScreen(conversationId: chat)),
      );
      await settle(tester, rounds: 10);
      return chat;
    }

    chatTest('tapping a poll answer votes, and the count follows', (
      tester,
      gateway,
    ) async {
      await chatWithCard(tester, gateway, 'poll', {
        'question': 'Lunch?',
        'options': [
          {'id': 'a', 'text': 'Star Kabab'},
          {'id': 'b', 'text': 'Order in'},
        ],
      });
      expect(find.text('No votes yet'), findsOneWidget);

      await tester.tap(find.text('Star Kabab'));
      await settle(tester);
      expect(gateway.log, contains('vote:1:a'));
      expect(find.text('1 vote'), findsOneWidget);

      await tester.tap(find.text('Star Kabab'));
      await settle(tester);
      expect(gateway.log, contains('vote:1:'), reason: 'taken back');
      expect(find.text('No votes yet'), findsOneWidget);
    });

    chatTest('tapping Going answers an event', (tester, gateway) async {
      await chatWithCard(tester, gateway, 'event', {
        'title': 'Picnic',
        'starts_at': DateTime(2026, 10, 30, 18, 30).millisecondsSinceEpoch,
        'time_zone': 'UTC+00:00',
      });
      expect(find.text('No answers yet'), findsOneWidget);

      await tester.tap(find.text('Going'));
      await settle(tester);
      expect(gateway.log, contains('rsvp:1:going'));
      expect(find.text('1 going'), findsOneWidget);
    });

    chatTest('a poll written on the page is sent and appears', (
      tester,
      gateway,
    ) async {
      final chat = (await tester.runAsync(
        () => gateway.chatWith('bob', name: 'Bob'),
      ))!;
      await tester.pumpWidget(
        chatApp(gateway, ConversationScreen(conversationId: chat)),
      );
      await settle(tester, rounds: 10);

      await tester.tap(find.byTooltip('Attach'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Poll'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Lunch?');
      await tester.enterText(find.byType(TextField).at(1), 'Pizza');
      await tester.enterText(find.byType(TextField).at(2), 'Burgers');
      await tester.pump();
      final send = find.widgetWithText(OrbitButton, 'Send poll');
      await tester.ensureVisible(send);
      await tester.tap(send);
      // The page closes once the send has answered, which takes real time.
      for (
        var i = 0;
        i < 40 && find.text('New poll').evaluate().isNotEmpty;
        i++
      ) {
        await settle(tester, rounds: 1);
      }
      await tester.pumpAndSettle();

      expect(
        gateway.log,
        contains('sendPoll:$chat:Lunch?:Pizza|Burgers:false'),
      );
      expect(find.text('Lunch?'), findsOneWidget);
      expect(find.text('Burgers'), findsOneWidget);
    });
  });
}
