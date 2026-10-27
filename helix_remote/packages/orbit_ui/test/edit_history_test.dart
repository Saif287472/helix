import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// "Edit history" on Message info, and who can open it.
final _history = RegExp('edit history', caseSensitive: false);

void main() {
  late OrbitTokens orbit;
  setUpAll(() {
    orbit = OrbitTokens.fromThemeJson(
      jsonDecode(File('assets/themes/orbit.json').readAsStringSync())
          as Map<String, Object?>,
    );
  });

  Future<void> show(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(412, 866);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        theme: OrbitTheme.of(orbit),
        home: Scaffold(body: home),
      ),
    );
    await tester.pump();
  }

  testWidgets('lists every version, the current one first', (tester) async {
    await show(
      tester,
      const MessageInfoScreen(
        model: MessageInfoModel(
          sentLabel: 'Today, 14:05',
          edits: [
            MessageEditItem(
              text: 'meet at five',
              whenLabel: 'Today, 14:07',
              current: true,
            ),
            MessageEditItem(text: 'meet at fiev', whenLabel: 'Today, 14:05'),
          ],
        ),
      ),
    );
    expect(find.textContaining(_history), findsOneWidget);
    expect(find.text('meet at five'), findsOneWidget);
    expect(find.text('Now · Today, 14:07'), findsOneWidget);
    expect(find.text('meet at fiev'), findsOneWidget);
    expect(find.text('Today, 14:05'), findsWidgets);
  });

  testWidgets(
    'a message never edited has no history, and no empty recipients',
    (tester) async {
      await show(
        tester,
        const MessageInfoScreen(
          model: MessageInfoModel(sentLabel: 'Today, 14:05'),
        ),
      );
      expect(find.textContaining(_history), findsNothing);
      expect(find.text('Recipients'), findsNothing);
    },
  );

  testWidgets('the menu offers Message info for an edited message of someone '
      'else, and not for an unedited one', (tester) async {
    HelixMessageItem item(String id, {required bool edited}) =>
        HelixMessageItem(
          HelixMessage(
            id: id,
            outgoing: false,
            content: const HelixTextContent('hello'),
            timeLabel: '14:05',
            edited: edited,
          ),
        );
    ChatScreen chat(HelixMessageItem m) => ChatScreen(
      model: ChatModel(
        conversationId: 'direct:nadia',
        title: 'Nadia Rahman',
        avatar: OrbitFakes.nadia.avatar,
        items: [m],
      ),
      start: const ChatStart(actionsFor: 'a'),
    );
    await show(tester, chat(item('a', edited: true)));
    expect(find.text('Message info'), findsOneWidget);
    await show(tester, chat(item('a', edited: false)));
    expect(find.text('Message info'), findsNothing);
  });
}
