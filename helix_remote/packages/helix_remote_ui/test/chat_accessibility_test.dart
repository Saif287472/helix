// Accessibility and layout rules for the v2 chat components: the gallery
// sections are the realistic content (every state of every component), so the
// guidelines run against them rather than against components in isolation.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import 'support/harness.dart';

const _sections = <String, Widget>{
  'chat list': HelixGalleryChatList(),
  'conversation': HelixGalleryConversation(),
  'composer': HelixGalleryComposer(),
  'general': HelixGalleryGeneral(),
};

Widget _scroll(Widget child) => SingleChildScrollView(child: child);

void main() {
  group('guidelines at text scale 1', () {
    for (final entry in _sections.entries) {
      testWidgets('${entry.key}: tap targets are at least 48 px', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await pumpHelix(tester, _scroll(entry.value), height: 4000);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        handle.dispose();
      });

      testWidgets('${entry.key}: every tappable has a label', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpHelix(tester, _scroll(entry.value), height: 4000);
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });

      testWidgets('${entry.key}: text contrast', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpHelix(tester, _scroll(entry.value), height: 4000);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  });

  group('text scaling up to 2x never overflows', () {
    for (final scale in [1.0, 1.5, 2.0]) {
      for (final entry in _sections.entries) {
        testWidgets('${entry.key} at ${scale}x', (tester) async {
          await pumpHelix(
            tester,
            _scroll(entry.value),
            height: 6000,
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('a narrow phone at 2x', (tester) async {
      await pumpHelix(
        tester,
        _scroll(const HelixGalleryConversation()),
        width: 320,
        height: 8000,
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('RTL', () {
    for (final entry in _sections.entries) {
      testWidgets('${entry.key} lays out right to left', (tester) async {
        await pumpHelix(
          tester,
          _scroll(entry.value),
          height: 6000,
          direction: TextDirection.rtl,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('chat tile: the avatar sits at the start (right) edge', (
      tester,
    ) async {
      await pumpHelix(
        tester,
        HelixChatListTile(item: HelixGallerySamples.chats.first),
        direction: TextDirection.rtl,
      );
      final avatar = tester.getRect(find.byType(HelixAvatar));
      final tile = tester.getRect(find.byType(HelixChatListTile));
      expect(avatar.right, greaterThan(tile.right - 24));
    });

    testWidgets('Arabic and Bengali chat titles and previews render', (
      tester,
    ) async {
      await pumpHelix(
        tester,
        const Column(
          children: [
            HelixChatListTile(
              item: HelixChatListItem(
                id: 'a',
                title: 'نادية',
                avatar: HelixAvatarModel(name: 'نادية'),
                preview: HelixChatPreview(text: 'مرحبا، هل نلتقي غدا؟'),
              ),
            ),
            HelixChatListTile(
              item: HelixChatListItem(
                id: 'b',
                title: 'রহিম',
                avatar: HelixAvatarModel(name: 'রহিম'),
                preview: HelixChatPreview(text: 'আজ দেখা হবে তো?'),
              ),
            ),
          ],
        ),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('every action control is named', () {
    testWidgets(
      'icon buttons in the composer, banner, bars and sheets have tooltips',
      (tester) async {
        final controller = TextEditingController(text: 'x');
        addTearDown(controller.dispose);
        await pumpHelix(
          tester,
          SingleChildScrollView(
            child: Column(
              children: [
                HelixComposer(
                  controller: controller,
                  onSend: () {},
                  banner: const HelixComposerBannerModel(
                    kind: HelixComposerBannerKind.reply,
                    title: 'Replying',
                  ),
                ),
                HelixScrollToBottomButton(visible: true, onPressed: () {}),
                HelixSearchField(controller: controller),
              ],
            ),
          ),
          height: 1000,
        );
        final buttons = find.byWidgetPredicate((w) => w is IconButton);
        expect(buttons, findsWidgets);
        for (final element in buttons.evaluate()) {
          final button = element.widget as IconButton;
          expect(button.tooltip, isNotNull, reason: '${button.icon}');
          expect(button.tooltip, isNotEmpty);
        }
      },
    );
  });

  group('high contrast theme', () {
    testWidgets('conversation text stays legible', (tester) async {
      final handle = tester.ensureSemantics();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 5000);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: HelixThemes.highContrastLight(),
          home: Scaffold(body: _scroll(const HelixGalleryConversation())),
        ),
      );
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  });
}
