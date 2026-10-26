import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/local_settings.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote/core/theme/orbit_app_theme.dart';
import 'package:helix_remote/features/conversation/presentation/conversation_screen.dart';
import 'package:helix_remote/features/conversation/presentation/conversation_settings_screen.dart';
import 'package:helix_remote/features/settings/presentation/appearance_page.dart';
import 'package:helix_remote/shared/wallpaper.dart';
import 'package:orbit_ui/orbit_ui.dart';

import 'support/a3b_fakes.dart' show FakeLocalSettings;
import 'support/chat_harness.dart';
import 'support/orbit_theme.dart';

/// A phone: the sheets are laid out for one.
void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(412, 866);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  group('which wallpaper a chat is drawn on', () {
    late FakeLocalSettings settings;
    late ProviderContainer container;
    setUp(() {
      settings = FakeLocalSettings();
      container = ProviderContainer(
        overrides: [localSettingsProvider.overrideWithValue(settings)],
      );
      addTearDown(container.dispose);
    });

    Future<HelixWallpaper> of(String chat) async {
      // A stream provider flows only while something listens to it.
      container
        ..listen(defaultWallpaperProvider, (_, _) {})
        ..listen(chatWallpaperChoiceProvider(chat), (_, _) {});
      await container.read(defaultWallpaperProvider.future);
      await container.read(chatWallpaperChoiceProvider(chat).future);
      return container.read(chatWallpaperProvider(chat));
    }

    test('the theme\'s own, until someone chooses', () async {
      expect(await of('direct:bob'), HelixWallpaper.theme);
    });

    test('the default applies to every chat', () async {
      await settings.set(AppSettings.wallpaper, HelixWallpaper.calm);
      expect(await of('direct:bob'), HelixWallpaper.calm);
      expect(await of('direct:cara'), HelixWallpaper.calm);
    });

    test(
      'a chat\'s own choice wins, and empty goes back to the default',
      () async {
        await settings.set(AppSettings.wallpaper, HelixWallpaper.calm);
        await settings.set(
          AppSettings.chatWallpaper('direct:bob'),
          HelixWallpaper.warm.name,
        );
        expect(await of('direct:bob'), HelixWallpaper.warm);
        expect(await of('direct:cara'), HelixWallpaper.calm);

        await settings.set(AppSettings.chatWallpaper('direct:bob'), '');
        await Future<void>.delayed(Duration.zero);
        expect(
          container.read(chatWallpaperProvider('direct:bob')),
          HelixWallpaper.calm,
        );
      },
    );

    test('a name this version does not know follows the default', () async {
      await settings.set(AppSettings.chatWallpaper('direct:bob'), 'sunset');
      expect(await of('direct:bob'), HelixWallpaper.theme);
      expect(wallpaperNamed('rose'), HelixWallpaper.rose);
      expect(wallpaperNamed(''), isNull);
    });
  });

  chatTest('a chat\'s settings keep its own wallpaper', (
    tester,
    gateway,
  ) async {
    phone(tester);
    final settings = FakeLocalSettings();
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await tester.pumpWidget(
      chatApp(
        gateway,
        ConversationSettingsScreen(conversationId: chat),
        settings: settings,
      ),
    );
    await settle(tester, rounds: 10);

    expect(find.text('Same as all chats'), findsOneWidget);
    await tester.tap(find.text('Wallpaper'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Fresh wallpaper'));
    await settle(tester);
    await tester.pumpAndSettle();

    expect(settings.read(AppSettings.chatWallpaper(chat)), 'fresh');
    expect(find.text('Fresh'), findsOneWidget, reason: 'the row says which');
  });

  chatTest('the conversation is drawn on the wallpaper in force', (
    tester,
    gateway,
  ) async {
    final settings = FakeLocalSettings();
    await settings.set(AppSettings.wallpaper, HelixWallpaper.calm);
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await tester.pumpWidget(
      chatApp(
        gateway,
        ConversationScreen(conversationId: chat),
        settings: settings,
      ),
    );
    await settle(tester, rounds: 10);

    Color background() => tester
        .widget<OrbitPatternBackground>(
          find
              .descendant(
                of: find.byType(ChatScreen),
                matching: find.byType(OrbitPatternBackground),
              )
              .first,
        )
        .color;
    expect(background(), orbitTestTokens.accentSoft);

    await settings.set(AppSettings.chatWallpaper(chat), 'rose');
    await settle(tester);
    expect(background(), orbitTestTokens.dangerSoft);
  });

  testWidgets('Appearance sets the wallpaper for every chat', (tester) async {
    phone(tester);
    final settings = FakeLocalSettings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localSettingsProvider.overrideWithValue(settings),
          orbitThemeLibraryProvider.overrideWithValue(orbitTestThemes),
        ],
        child: MaterialApp(
          theme: orbitTestTheme(),
          builder: orbitTestBuilder,
          home: const AppearancePage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Chat wallpaper'), findsOneWidget);
    await tester.tap(find.text('Chat wallpaper'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Plain wallpaper'));
    await tester.pumpAndSettle();

    expect(settings.read(AppSettings.wallpaper), HelixWallpaper.plain);
    expect(find.text('Plain wallpaper on'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
