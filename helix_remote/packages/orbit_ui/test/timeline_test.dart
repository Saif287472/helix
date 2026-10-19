import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The Review 3.5 parts: the timeline and the composer. How they look is
/// checked against the prototype by the compare tool (`kit-timeline`).
void main() {
  final themes = <String, OrbitTokens>{};
  setUpAll(() {
    for (final id in ['orbit', 'field', 'terminal']) {
      themes[id] = OrbitTokens.fromThemeJson(
        jsonDecode(File('assets/themes/$id.json').readAsStringSync())
            as Map<String, Object?>,
      );
    }
  });

  Future<void> show(
    WidgetTester tester,
    Widget child, {
    String theme = 'orbit',
  }) => tester.pumpWidget(
    MaterialApp(
      theme: OrbitTheme.of(themes[theme]!),
      home: Scaffold(
        body: SingleChildScrollView(child: SizedBox(width: 380, child: child)),
      ),
    ),
  );

  test('runs follow the prototype: same side, same sender, 5 minutes', () {
    final items = OrbitFakes.conversations['direct:nadia']!;
    final positions = {
      for (final it in items.whereType<HelixMessageItem>())
        it.message.id: it.position,
    };
    // n4 and n5 are both yours at the same minute; n1 stands alone.
    expect(positions['n1'], HelixRunPosition.single);
    expect(positions['n4'], HelixRunPosition.first);
    expect(positions['n5'], HelixRunPosition.last);
  });

  testWidgets('every sample conversation draws without errors', (tester) async {
    for (final entry in OrbitFakes.conversations.entries) {
      await show(
        tester,
        OrbitTimeline(
          items: [...entry.value, const HelixTypingItem()],
          group: entry.key.startsWith('group:'),
        ),
      );
      expect(tester.takeException(), isNull, reason: entry.key);
    }
  });

  testWidgets('a group shows authors over their first bubble', (tester) async {
    await show(
      tester,
      OrbitTimeline(
        items: OrbitFakes.conversations['group:family']!,
        group: true,
      ),
    );
    expect(find.text('Ammu'), findsWidgets);
    expect(find.text('Abbu'), findsWidgets);
  });

  testWidgets('a failed message offers Retry', (tester) async {
    String? retried;
    await show(
      tester,
      OrbitTimeline(
        items: OrbitFakes.conversations['direct:rafiq']!,
        onRetry: (id) => retried = id,
      ),
    );
    expect(find.text('Not sent'), findsOneWidget);
    await tester.tap(find.text('RETRY'));
    expect(retried, 'r3');
  });

  testWidgets("Field's stripe and Terminal's brackets come from the theme", (
    tester,
  ) async {
    await show(tester, const OrbitDaySeparator('Today'), theme: 'terminal');
    expect(find.textContaining('[ TODAY ]'), findsOneWidget);
    await show(
      tester,
      OrbitTimeline(items: OrbitFakes.conversations['direct:nadia']!),
      theme: 'field',
    );
    expect(tester.takeException(), isNull);
  });

  group('composer', () {
    testWidgets('the mic becomes send once there is text', (tester) async {
      String? sent;
      await show(
        tester,
        OrbitComposer(actions: OrbitComposerActions(onSend: (s) => sent = s)),
      );
      expect(find.byTooltip('Record a voice message'), findsOneWidget);
      expect(find.byTooltip('Camera'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'See you there');
      await tester.pump();
      expect(find.byTooltip('Camera'), findsNothing);
      await tester.tap(find.byTooltip('Send'));
      expect(sent, 'See you there');
    });

    testWidgets('a reply banner can be cancelled', (tester) async {
      var cancelled = false;
      await show(
        tester,
        OrbitComposer(
          banner: const HelixComposerBannerModel(
            kind: HelixComposerBannerKind.reply,
            title: 'Replying to Nadia Rahman',
            text: 'Good morning',
          ),
          actions: OrbitComposerActions(onCancelBanner: () => cancelled = true),
        ),
      );
      await tester.tap(find.byTooltip('Cancel reply'));
      expect(cancelled, isTrue);
    });

    testWidgets('recording and the reasons a chat is closed', (tester) async {
      await show(
        tester,
        const Column(
          children: [
            OrbitComposer(recording: OrbitRecording.locked),
            OrbitComposer(recording: OrbitRecording.hold),
            OrbitComposer(
              disabled: 'You can no longer send messages to this group.',
            ),
          ],
        ),
      );
      expect(find.byTooltip('Delete recording'), findsOneWidget);
      expect(find.byTooltip('Send recording'), findsOneWidget);
      expect(find.text('Slide to cancel'), findsOneWidget);
      expect(
        find.text('You can no longer send messages to this group.'),
        findsOneWidget,
      );
    });
  });
}
