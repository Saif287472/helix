import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Polls and events in a bubble, and the two pages that write them.
void main() {
  late OrbitTokens orbit;
  setUpAll(() {
    orbit = OrbitTokens.fromThemeJson(
      jsonDecode(File('assets/themes/orbit.json').readAsStringSync())
          as Map<String, Object?>,
    );
  });

  Future<void> showChat(
    WidgetTester tester,
    List<HelixMessageItem> items, {
    ChatActions actions = const ChatActions(),
  }) async {
    tester.view.physicalSize = const Size(412, 866);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: OrbitTheme.of(orbit),
        home: Scaffold(
          body: ChatScreen(
            model: ChatModel(
              conversationId: 'direct:nadia',
              title: 'Nadia Rahman',
              avatar: OrbitFakes.nadia.avatar,
              items: items,
            ),
            actions: actions,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  HelixMessageItem message(String id, HelixMessageContent content) =>
      HelixMessageItem(
        HelixMessage(
          id: id,
          outgoing: false,
          content: content,
          timeLabel: '14:05',
        ),
      );

  HelixPollContent poll({
    bool multiple = false,
    bool closed = false,
    List<String> mine = const [],
  }) => HelixPollContent(
    question: 'Friday lunch?',
    multiple: multiple,
    closed: closed,
    voters: 4,
    options: [
      HelixPollOption(
        id: 'a',
        text: 'Star Kabab',
        votes: 3,
        mine: mine.contains('a'),
      ),
      HelixPollOption(
        id: 'b',
        text: 'Order in',
        votes: 1,
        mine: mine.contains('b'),
      ),
    ],
  );

  group('a poll', () {
    testWidgets('shows the question, the answers and the counts', (
      tester,
    ) async {
      await showChat(tester, [
        message('p', poll(mine: ['b'])),
      ]);
      expect(find.text('Friday lunch?'), findsOneWidget);
      expect(find.text('Star Kabab'), findsOneWidget);
      expect(find.text('Order in'), findsOneWidget);
      expect(find.text('Select one'), findsOneWidget);
      expect(find.text('4 votes'), findsOneWidget);
    });

    testWidgets('a tap votes, and a tap on yours takes it back', (
      tester,
    ) async {
      final votes = <(String, List<String>)>[];
      ChatActions actions() =>
          ChatActions(onVote: (id, ids) => votes.add((id, ids)));
      await showChat(tester, [message('p', poll())], actions: actions());
      await tester.tap(find.text('Star Kabab'));
      expect(votes.single.$1, 'p');
      expect(votes.single.$2, ['a']);

      votes.clear();
      await showChat(tester, [
        message('p', poll(mine: ['a'])),
      ], actions: actions());
      await tester.tap(find.text('Star Kabab'));
      expect(votes.single.$1, 'p');
      expect(votes.single.$2, isEmpty);
    });

    testWidgets('a single-choice vote replaces yours', (tester) async {
      final votes = <List<String>>[];
      await showChat(tester, [
        message('p', poll(mine: ['a'])),
      ], actions: ChatActions(onVote: (_, ids) => votes.add(ids)));
      await tester.tap(find.text('Order in'));
      expect(votes.single, ['b']);
    });

    testWidgets('a multiple-choice vote adds to yours', (tester) async {
      final votes = <List<String>>[];
      await showChat(tester, [
        message('p', poll(multiple: true, mine: ['a'])),
      ], actions: ChatActions(onVote: (_, ids) => votes.add(ids)));
      expect(find.text('Select one or more'), findsOneWidget);
      await tester.tap(find.text('Order in'));
      expect(votes.single, ['a', 'b']);
    });

    testWidgets('a closed poll takes no vote', (tester) async {
      var voted = false;
      await showChat(tester, [
        message('p', poll(closed: true)),
      ], actions: ChatActions(onVote: (_, _) => voted = true));
      expect(find.text('Poll closed'), findsOneWidget);
      await tester.tap(find.text('Star Kabab'));
      expect(voted, isFalse);
    });
  });

  group('an event', () {
    const event = HelixEventContent(
      title: 'Picnic',
      whenLabel: 'Fri 30 Oct, 18:30',
      place: 'Ramna Park',
      going: 2,
      maybe: 1,
      mine: HelixRsvp.maybe,
    );

    testWidgets('shows what, when, where and who is coming', (tester) async {
      await showChat(tester, [message('e', event)]);
      expect(find.text('Picnic'), findsOneWidget);
      expect(find.text('Fri 30 Oct, 18:30'), findsOneWidget);
      expect(find.text('Ramna Park'), findsOneWidget);
      expect(find.text('2 going · 1 maybe'), findsOneWidget);
    });

    testWidgets('each button answers', (tester) async {
      final answers = <(String, HelixRsvp)>[];
      await showChat(tester, [
        message('e', event),
      ], actions: ChatActions(onRsvp: (id, a) => answers.add((id, a))));
      await tester.tap(find.text('Going'));
      await tester.tap(find.text('Can’t go'));
      expect(answers, [('e', HelixRsvp.going), ('e', HelixRsvp.declined)]);
    });
  });

  group('the attach sheet', () {
    testWidgets('offers Poll and Event only where they can be sent', (
      tester,
    ) async {
      await showChat(tester, [message('t', const HelixTextContent('hi'))]);
      await tester.tap(find.byTooltip('Attach'));
      await tester.pumpAndSettle();
      expect(find.text('Poll'), findsNothing);
      expect(find.text('Event'), findsNothing);
    });

    testWidgets('Poll opens the page, and Send hands over the draft', (
      tester,
    ) async {
      HelixPollDraft? sent;
      await showChat(
        tester,
        [message('t', const HelixTextContent('hi'))],
        actions: ChatActions(
          onPickFiles: (_) {},
          onCreatePoll: (d) {
            sent = d;
            return null;
          },
        ),
      );
      await tester.tap(find.byTooltip('Attach'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Poll'));
      await tester.pumpAndSettle();
      expect(find.text('New poll'), findsOneWidget);

      // Nothing to send until there is a question and two different answers.
      final send = find.widgetWithText(OrbitButton, 'Send poll');
      expect(tester.widget<OrbitButton>(send).onPressed, isNull);
      await tester.enterText(find.byType(TextField).at(0), ' Lunch? ');
      await tester.enterText(find.byType(TextField).at(1), 'Pizza');
      await tester.enterText(find.byType(TextField).at(2), 'pizza');
      await tester.pump();
      expect(
        tester.widget<OrbitButton>(send).onPressed,
        isNull,
        reason: 'the same answer twice',
      );
      await tester.enterText(find.byType(TextField).at(2), 'Burgers');
      await tester.pump();
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();

      expect(sent?.question, 'Lunch?');
      expect(sent?.options, ['Pizza', 'Burgers']);
      expect(sent?.multiple, isFalse);
      expect(find.text('New poll'), findsNothing, reason: 'the page closes');
    });
  });

  group('the new-event page', () {
    Future<void> open(
      WidgetTester tester,
      Future<String?> Function(HelixEventDraft) onSend,
    ) async {
      tester.view.physicalSize = const Size(412, 866);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: OrbitTheme.of(orbit),
          home: OrbitNewEventPage(
            now: DateTime(2026, 10, 26, 9),
            onSend: onSend,
          ),
        ),
      );
    }

    testWidgets('starts at 18:00 tomorrow and sends what was typed', (
      tester,
    ) async {
      HelixEventDraft? sent;
      await open(tester, (d) async {
        sent = d;
        return null;
      });
      expect(find.text('Tue 27 Oct 2026'), findsOneWidget);
      expect(find.text('18:00'), findsOneWidget);
      final send = find.widgetWithText(OrbitButton, 'Send event');
      expect(tester.widget<OrbitButton>(send).onPressed, isNull);

      await tester.enterText(find.byType(TextField).at(0), 'Picnic');
      await tester.enterText(find.byType(TextField).at(1), 'Ramna Park');
      await tester.pump();
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pump();

      expect(sent?.title, 'Picnic');
      expect(sent?.place, 'Ramna Park');
      expect(sent?.startsAt, DateTime(2026, 10, 27, 18));
    });

    testWidgets('a refusal is shown and the page stays', (tester) async {
      await open(tester, (_) async => 'Could not send.');
      await tester.enterText(find.byType(TextField).at(0), 'Picnic');
      await tester.pump();
      final send = find.widgetWithText(OrbitButton, 'Send event');
      await tester.ensureVisible(send);
      await tester.tap(send);
      await tester.pumpAndSettle();
      expect(find.text('Could not send.'), findsOneWidget);
      expect(find.text('New event'), findsOneWidget);
    });
  });
}
