import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The Review 3.4 rows: the chat list tile, the call log tile and the swipe.
/// How they look is checked against the prototype by the compare tool
/// (`kit-rows`).
void main() {
  late OrbitTokens orbit;
  setUpAll(() {
    orbit = OrbitTokens.fromThemeJson(
      jsonDecode(File('assets/themes/orbit.json').readAsStringSync())
          as Map<String, Object?>,
    );
  });

  Future<void> show(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: OrbitTheme.of(orbit),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: 412, child: child),
        ),
      ),
    ),
  );

  test("the fakes' colours are the prototype's", () {
    // The generator ports UI.colorIndexFor; the Dart model has its own copy.
    expect(
      OrbitFakes.chats.first.avatar.colorIndex,
      HelixAvatarModel.colorIndexFor('nadia'),
    );
    expect(
      OrbitFakes.chats[1].avatar.colorIndex,
      HelixAvatarModel.colorIndexFor('family'),
    );
  });

  testWidgets('a chat row is 72px and shows its count, @ and pin', (
    tester,
  ) async {
    var opened = 0;
    await show(
      tester,
      OrbitChatListTile(item: OrbitFakes.chats[1], onTap: () => opened++),
    );
    expect(tester.getSize(find.byType(OrbitChatListTile)).height, 72);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('@'), findsOneWidget);
    expect(find.text('Ammu:'), findsOneWidget);
    expect(find.byIcon(OrbitIcons.pushPin.fill), findsOneWidget);
    await tester.tap(find.byType(OrbitChatListTile));
    expect(opened, 1);
  });

  testWidgets('a draft, a typing label and an empty photo read right', (
    tester,
  ) async {
    await show(
      tester,
      Column(
        children: [
          for (final c in OrbitFakes.chats.where(
            (c) =>
                c.id == 'direct:tanvir' ||
                c.id == 'group:studio' ||
                c.id == 'group:design',
          ))
            OrbitChatListTile(item: c),
        ],
      ),
    );
    expect(find.text('Draft:'), findsOneWidget);
    expect(find.text('Sadia and Tanvir are typing...'), findsOneWidget);
    expect(find.text('Photo'), findsOneWidget);
  });

  testWidgets('a selected row ticks its avatar', (tester) async {
    await show(
      tester,
      OrbitChatListTile(item: OrbitFakes.chats.first, selected: true),
    );
    expect(find.byIcon(OrbitIcons.check.bold), findsOneWidget);
  });

  testWidgets('a missed call is red, folded calls are counted, and the '
      'call back button has a tooltip', (tester) async {
    var back = 0;
    final missed = OrbitFakes.calls.firstWhere(
      (c) => c.direction == HelixCallDirection.missed && c.count > 1,
    );
    await show(
      tester,
      OrbitCallLogTile(item: missed, onCallBack: () => back++),
    );
    expect(find.text('${missed.title} (${missed.count})'), findsOneWidget);
    final name = tester.widget<Text>(
      find.text('${missed.title} (${missed.count})'),
    );
    expect(name.style?.color, orbit.danger);
    await tester.tap(find.byTooltip('Voice call'));
    expect(back, 1);
  });

  testWidgets('a swipe past 30% runs its action and springs back', (
    tester,
  ) async {
    var archived = 0;
    var pinned = 0;
    await show(
      tester,
      OrbitSwipeRow(
        start: OrbitSwipeAction(
          icon: OrbitIcons.pushPin,
          label: 'Pin',
          onSwiped: () => pinned++,
        ),
        end: OrbitSwipeAction(
          icon: OrbitIcons.archive,
          label: 'Archive',
          onSwiped: () => archived++,
        ),
        child: OrbitChatListTile(item: OrbitFakes.chats.first),
      ),
    );
    await tester.drag(find.byType(OrbitChatListTile), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(archived, 1);
    await tester.drag(find.byType(OrbitChatListTile), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(pinned, 0, reason: '60px is under 30% of 412');
    expect(
      tester.getTopLeft(find.byType(OrbitChatListTile)),
      tester.getTopLeft(find.byType(OrbitSwipeRow)),
      reason: 'it springs back',
    );
  });
}
