import 'package:flutter/material.dart' show Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/engine/local_settings.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:helix_remote/features/conversation/presentation/conversation_screen.dart';
import 'package:helix_remote/features/conversation/presentation/conversation_settings_screen.dart';
import 'package:helix_remote/shared/wallpaper.dart';
import 'package:orbit_ui/orbit_ui.dart';

import 'support/a3b_fakes.dart' show FakeLocalSettings;
import 'support/chat_harness.dart';

/// The colour of your own bubbles in a chat: kept per chat, drawn in it.
void main() {
  test(
    'the theme\'s own until a chat chooses, and a stranger name is that',
    () async {
      final settings = FakeLocalSettings();
      final container = ProviderContainer(
        overrides: [localSettingsProvider.overrideWithValue(settings)],
      );
      addTearDown(container.dispose);
      Future<HelixBubbleTint> of(String chat) async {
        container.listen(chatBubbleTintProvider(chat), (_, _) {});
        return container.read(chatBubbleTintProvider(chat).future);
      }

      expect(await of('direct:cara'), HelixBubbleTint.theme);
      await settings.set(AppSettings.chatBubbleTint('direct:bob'), 'rose');
      expect(await of('direct:bob'), HelixBubbleTint.rose);
      expect(bubbleTintNamed('sunset'), HelixBubbleTint.theme);
    },
  );

  chatTest('a chat\'s settings keep its own bubble colour', (
    tester,
    gateway,
  ) async {
    tester.view.physicalSize = const Size(412, 866);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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

    await tester.tap(find.text('Bubble colour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fresh'));
    await settle(tester);
    await tester.pumpAndSettle();
    expect(settings.read(AppSettings.chatBubbleTint(chat)), 'fresh');

    // Back to the theme's own is stored as empty.
    await tester.tap(find.text('Bubble colour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Theme'));
    await settle(tester);
    expect(settings.read(AppSettings.chatBubbleTint(chat)), '');
  });

  chatTest('the conversation draws your messages in the chosen colour', (
    tester,
    gateway,
  ) async {
    final settings = FakeLocalSettings();
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await settings.set(AppSettings.chatBubbleTint(chat), 'warm');
    await tester.pumpWidget(
      chatApp(
        gateway,
        ConversationScreen(conversationId: chat),
        settings: settings,
      ),
    );
    await settle(tester, rounds: 10);
    final screen = tester.widget<ChatScreen>(find.byType(ChatScreen));
    expect(screen.model.bubbleTint, HelixBubbleTint.warm);

    await settings.set(AppSettings.chatBubbleTint(chat), '');
    await settle(tester);
    expect(
      tester.widget<ChatScreen>(find.byType(ChatScreen)).model.bubbleTint,
      HelixBubbleTint.theme,
    );
  });
}
