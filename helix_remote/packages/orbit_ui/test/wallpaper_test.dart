import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The wallpapers a chat can be drawn on, and where they are chosen.
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
      MaterialApp(theme: OrbitTheme.of(orbit), home: home),
    );
    await tester.pump();
  }

  test('every wallpaper is a colour of the theme in use', () {
    final colours = {
      for (final w in HelixWallpaper.values) w: wallpaperLook(orbit, w).$2,
    };
    expect(colours[HelixWallpaper.theme], orbit.chatBg);
    expect(colours[HelixWallpaper.plain], orbit.chatBg);
    expect(colours[HelixWallpaper.calm], orbit.accentSoft);
    expect(colours[HelixWallpaper.warm], orbit.warningSoft);
    expect(colours[HelixWallpaper.fresh], orbit.successSoft);
    expect(colours[HelixWallpaper.rose], orbit.dangerSoft);
    expect(wallpaperLook(orbit, HelixWallpaper.theme).$1, orbit.chatPattern);
    for (final w in HelixWallpaper.values.skip(1)) {
      expect(wallpaperLook(orbit, w).$1.kind, 'none', reason: w.label);
    }
  });

  testWidgets('a chat is drawn on its wallpaper', (tester) async {
    await show(
      tester,
      Scaffold(
        body: ChatScreen(
          model: ChatModel(
            conversationId: 'direct:nadia',
            title: 'Nadia Rahman',
            avatar: OrbitFakes.nadia.avatar,
            wallpaper: HelixWallpaper.warm,
          ),
        ),
      ),
    );
    final background = tester.widget<OrbitPatternBackground>(
      find
          .descendant(
            of: find.byType(ChatScreen),
            matching: find.byType(OrbitPatternBackground),
          )
          .first,
    );
    expect(background.color, orbit.warningSoft);
  });

  group('a chat\'s settings', () {
    ChatSettingsModel model({HelixWallpaper? wallpaper}) => ChatSettingsModel(
      title: 'Nadia Rahman',
      avatar: OrbitFakes.nadia.avatar,
      wallpaper: wallpaper,
    );

    testWidgets('offer a wallpaper only where the app can keep it', (
      tester,
    ) async {
      await show(tester, ChatSettingsScreen(model: model()));
      expect(find.text('Wallpaper'), findsNothing);
    });

    testWidgets('pick one, or go back to the default', (tester) async {
      final picked = <HelixWallpaper?>[];
      Widget screen(HelixWallpaper? current) => ChatSettingsScreen(
        model: model(wallpaper: current),
        actions: ChatSettingsActions(onSetWallpaper: picked.add),
      );

      await show(tester, screen(null));
      expect(find.text('Same as all chats'), findsOneWidget);
      await tester.tap(find.text('Wallpaper'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Calm wallpaper'));
      await tester.pumpAndSettle();
      expect(picked, [HelixWallpaper.calm]);

      await show(tester, screen(HelixWallpaper.calm));
      expect(find.text('Calm'), findsOneWidget, reason: 'the row says which');
      await tester.tap(find.text('Wallpaper'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Calm wallpaper, selected'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Same as all chats wallpaper'));
      await tester.pumpAndSettle();
      expect(picked, [HelixWallpaper.calm, null]);
    });
  });

  testWidgets('Appearance picks the wallpaper for every chat', (tester) async {
    final picked = <HelixWallpaper>[];
    await show(
      tester,
      AppearanceScreen(
        model: AppearanceModel(
          current: orbit,
          themes: [ThemeChoice(tokens: orbit)],
          wallpaper: HelixWallpaper.plain,
        ),
        actions: AppearanceActions(onPickWallpaper: (w) async => picked.add(w)),
      ),
    );
    expect(find.text('Plain'), findsOneWidget);
    await tester.tap(find.text('Chat wallpaper'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Same as all chats wallpaper'),
      findsNothing,
      reason: 'there is no default above the default',
    );
    await tester.tap(find.bySemanticsLabel('Rose wallpaper'));
    await tester.pumpAndSettle();
    expect(picked, [HelixWallpaper.rose]);
    expect(find.text('Rose wallpaper on'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
