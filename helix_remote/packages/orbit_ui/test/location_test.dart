import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// A location in a bubble, live or not, and the sheet that shares one.
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

  HelixMessageItem place(
    String id,
    HelixLocationContent content, {
    bool outgoing = false,
  }) => HelixMessageItem(
    HelixMessage(
      id: id,
      outgoing: outgoing,
      content: content,
      timeLabel: '14:05',
    ),
  );

  testWidgets('a live share says until when, and a touch opens it', (
    tester,
  ) async {
    final opened = <String>[];
    await showChat(tester, [
      place(
        'l1',
        const HelixLocationContent(
          label: 'Live location',
          live: HelixLiveShare(active: true, statusLabel: 'Live until 14:30'),
          openable: true,
        ),
      ),
    ], actions: ChatActions(onOpenLocation: opened.add));
    expect(find.text('Live until 14:30'), findsOneWidget);
    expect(find.text('Stop sharing'), findsNothing);
    await tester.tap(find.text('Live location'));
    expect(opened, ['l1']);
  });

  testWidgets('your own running share offers Stop sharing', (tester) async {
    final stopped = <String>[];
    await showChat(tester, [
      place(
        'l2',
        const HelixLocationContent(
          label: 'Live location',
          live: HelixLiveShare(
            active: true,
            statusLabel: 'Live until 15:00',
            mine: true,
          ),
          openable: true,
        ),
        outgoing: true,
      ),
    ], actions: ChatActions(onStopLive: stopped.add));
    await tester.tap(find.text('Stop sharing'));
    expect(stopped, ['l2']);
  });

  testWidgets('an ended share cannot be opened or stopped', (tester) async {
    final opened = <String>[];
    final stopped = <String>[];
    await showChat(
      tester,
      [
        place(
          'l3',
          const HelixLocationContent(
            label: 'Live location',
            live: HelixLiveShare(
              active: false,
              statusLabel: 'Live location ended',
              mine: true,
            ),
            openable: true,
          ),
          outgoing: true,
        ),
      ],
      actions: ChatActions(onOpenLocation: opened.add, onStopLive: stopped.add),
    );
    expect(find.text('Live location ended'), findsOneWidget);
    expect(find.text('Stop sharing'), findsNothing);
    await tester.tap(find.text('Live location'));
    expect(opened, isEmpty);
  });

  testWidgets('the attach sheet offers Location, once or live', (tester) async {
    final asked = <Duration?>[];
    await showChat(
      tester,
      const [],
      actions: ChatActions(
        onShareLocation: (live) {
          asked.add(live);
          return live == null ? 'Allow location access to share it.' : null;
        },
      ),
    );
    await tester.tap(find.byTooltip('Attach'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Location'));
    await tester.pumpAndSettle();
    expect(find.text('Share live for 15 minutes'), findsOneWidget);
    expect(find.text('Share live for 1 hour'), findsOneWidget);
    expect(find.text('Share live for 8 hours'), findsOneWidget);

    await tester.tap(find.text('Share live for 1 hour'));
    await tester.pumpAndSettle();
    expect(asked, [const Duration(hours: 1)]);

    await tester.tap(find.byTooltip('Attach'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Location'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send current location'));
    await tester.pumpAndSettle();
    expect(asked.last, isNull);
    expect(find.text('Allow location access to share it.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
