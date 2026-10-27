import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The colour of your own bubbles in a chat.
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
    await tester.pumpWidget(
      MaterialApp(
        theme: OrbitTheme.of(orbit),
        home: Scaffold(body: home),
      ),
    );
    await tester.pump();
  }

  HelixMessageItem message(String id, String text, {required bool outgoing}) =>
      HelixMessageItem(
        HelixMessage(
          id: id,
          outgoing: outgoing,
          content: HelixTextContent(text),
          timeLabel: '14:05',
        ),
      );

  /// The fills of the bubbles drawn, by their frames (a bubble paints its
  /// own fill rather than using a decoration).
  List<Color?> fills(WidgetTester tester) => [
    for (final c in tester.widgetList<CustomPaint>(find.byType(CustomPaint)))
      if (c.painter.runtimeType.toString() == '_BubbleFrame')
        (c.painter! as dynamic).fill as Color?,
  ];

  Widget chat(HelixBubbleTint tint) => ChatScreen(
    model: ChatModel(
      conversationId: 'direct:nadia',
      title: 'Nadia Rahman',
      avatar: OrbitFakes.nadia.avatar,
      bubbleTint: tint,
      items: [
        message('a', 'Hello there', outgoing: true),
        message('b', 'Hi back', outgoing: false),
      ],
    ),
  );

  testWidgets('by default your bubble is the theme\'s own', (tester) async {
    await show(tester, chat(HelixBubbleTint.theme));
    expect(fills(tester), unorderedEquals([orbit.out, orbit.inBubble]));
  });

  testWidgets('a tint recolours your bubble and not theirs', (tester) async {
    final expected = {
      HelixBubbleTint.calm: orbit.accentSoft,
      HelixBubbleTint.fresh: orbit.successSoft,
      HelixBubbleTint.warm: orbit.warningSoft,
      HelixBubbleTint.rose: orbit.dangerSoft,
    };
    for (final entry in expected.entries) {
      await show(tester, const SizedBox());
      await show(tester, chat(entry.key));
      expect(
        fills(tester),
        unorderedEquals([entry.value, orbit.inBubble]),
        reason: entry.key.label,
      );
    }
  });

  group('a chat\'s settings', () {
    ChatSettingsModel model(HelixBubbleTint tint) => ChatSettingsModel(
      title: 'Nadia Rahman',
      avatar: OrbitFakes.nadia.avatar,
      bubbleTint: tint,
    );

    testWidgets('offer a colour only where the app can keep it', (
      tester,
    ) async {
      await show(
        tester,
        ChatSettingsScreen(model: model(HelixBubbleTint.theme)),
      );
      expect(find.text('Bubble colour'), findsNothing);
    });

    testWidgets('pick one, and the row says which is in use', (tester) async {
      final picked = <HelixBubbleTint>[];
      await show(
        tester,
        ChatSettingsScreen(
          model: model(HelixBubbleTint.rose),
          actions: ChatSettingsActions(onSetBubbleTint: picked.add),
        ),
      );
      expect(find.text('Rose'), findsOneWidget);
      await tester.tap(find.text('Bubble colour'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Calm'));
      await tester.pumpAndSettle();
      expect(picked, [HelixBubbleTint.calm]);
    });
  });
}
