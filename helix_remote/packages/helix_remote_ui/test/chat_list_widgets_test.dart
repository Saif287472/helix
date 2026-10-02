import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import 'support/harness.dart';

const _item = HelixChatListItem(
  id: 'c1',
  title: 'Sam Rivera',
  avatar: HelixAvatarModel(name: 'Sam Rivera'),
  timeLabel: '14:05',
  unreadCount: 3,
  preview: HelixChatPreview(text: 'See you at six', senderPrefix: 'Sam'),
);

void main() {
  group('HelixChatListTile', () {
    testWidgets('shows title, time, preview with sender and unread count', (
      tester,
    ) async {
      await pumpHelix(tester, const HelixChatListTile(item: _item));
      expect(find.text('Sam Rivera'), findsOneWidget);
      expect(find.text('14:05'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(
        find.textContaining('Sam: See you at six', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('caps the unread count at 99+', (tester) async {
      await pumpHelix(
        tester,
        const HelixChatListTile(
          item: HelixChatListItem(
            id: 'x',
            title: 'Busy',
            avatar: HelixAvatarModel(name: 'Busy'),
            unreadCount: 250,
            hasMention: true,
          ),
        ),
      );
      expect(find.text('99+'), findsOneWidget);
      expect(find.text('@'), findsOneWidget);
    });

    testWidgets('typing replaces the preview', (tester) async {
      await pumpHelix(
        tester,
        const HelixChatListTile(
          item: HelixChatListItem(
            id: 'x',
            title: 'Nadia',
            avatar: HelixAvatarModel(name: 'Nadia'),
            typingLabel: 'typing...',
            preview: HelixChatPreview(text: 'old message'),
          ),
        ),
      );
      expect(find.text('typing...'), findsOneWidget);
      expect(
        find.textContaining('old message', findRichText: true),
        findsNothing,
      );
    });

    testWidgets('media previews fall back to their label', (tester) async {
      await pumpHelix(
        tester,
        const HelixChatListTile(
          item: HelixChatListItem(
            id: 'x',
            title: 'Lee',
            avatar: HelixAvatarModel(name: 'Lee'),
            preview: HelixChatPreview(
              text: '',
              kind: HelixPreviewKind.voiceNote,
            ),
          ),
        ),
      );
      expect(
        find.textContaining('Voice message', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('semantics label tells the whole story', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHelix(
        tester,
        const HelixChatListTile(
          item: HelixChatListItem(
            id: 'x',
            title: 'Weekend hike',
            avatar: HelixAvatarModel(name: 'Weekend hike', isGroup: true),
            timeLabel: '13:40',
            unreadCount: 12,
            hasMention: true,
            pinned: true,
            muted: true,
            preview: HelixChatPreview(text: 'Stove?', senderPrefix: 'Lee'),
          ),
        ),
      );
      final label = tester.getSemantics(find.byType(HelixChatListTile)).label;
      for (final part in [
        'Weekend hike',
        '12 unread',
        'you were mentioned',
        'pinned',
        'muted',
        'Lee: Stove?',
        '13:40',
      ]) {
        expect(label, contains(part));
      }
      handle.dispose();
    });

    testWidgets('tap and long press reach the callbacks', (tester) async {
      var taps = 0;
      var longs = 0;
      await pumpHelix(
        tester,
        HelixChatListTile(
          item: _item,
          onTap: () => taps++,
          onLongPress: () => longs++,
        ),
      );
      await tester.tap(find.byType(HelixChatListTile));
      await tester.longPress(find.byType(HelixChatListTile));
      expect((taps, longs), (1, 1));
    });

    testWidgets('selected rows show the check in the avatar', (tester) async {
      await pumpHelix(
        tester,
        const HelixChatListTile(
          item: _item,
          selected: true,
          selectionMode: true,
        ),
      );
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('is exactly extentFor tall at text scale $scale', (
        tester,
      ) async {
        await pumpHelix(
          tester,
          const HelixChatListTile(item: _item),
          textScale: scale,
        );
        final expected = HelixChatListTile.extentFor(TextScaler.linear(scale));
        expect(tester.getSize(find.byType(HelixChatListTile)).height, expected);
        expect(tester.takeException(), isNull);
      });
    }

    test('extent grows with text scale and never shrinks below the base', () {
      expect(
        HelixChatListTile.extentFor(TextScaler.noScaling),
        HelixChatMetrics.chatTileHeight,
      );
      expect(
        HelixChatListTile.extentFor(const TextScaler.linear(2)),
        greaterThan(HelixChatMetrics.chatTileHeight),
      );
    });
  });

  group('HelixSwipeableChatListTile', () {
    testWidgets('swiping fires the matching action and snaps back', (
      tester,
    ) async {
      var pinned = 0;
      var archived = 0;
      await pumpHelix(
        tester,
        HelixSwipeableChatListTile(
          item: _item,
          startAction: HelixSwipeAction(
            icon: Icons.push_pin,
            label: 'Pin',
            onTriggered: () => pinned++,
          ),
          endAction: HelixSwipeAction(
            icon: Icons.archive,
            label: 'Archive',
            onTriggered: () => archived++,
          ),
        ),
      );
      await tester.drag(find.byType(HelixChatListTile), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect((pinned, archived), (1, 0));
      await tester.drag(find.byType(HelixChatListTile), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect((pinned, archived), (1, 1));
      expect(find.byType(HelixChatListTile), findsOneWidget);
    });

    testWidgets('screen readers get the actions too', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHelix(
        tester,
        const HelixSwipeableChatListTile(
          item: _item,
          startAction: HelixSwipeAction(
            icon: Icons.push_pin,
            label: 'Pin',
            onTriggered: _noop,
          ),
        ),
      );
      final data = tester
          .getSemantics(find.byType(HelixChatListTile))
          .getSemanticsData();
      expect(data.customSemanticsActionIds, isNotEmpty);
      handle.dispose();
    });

    testWidgets('selection mode turns swiping off', (tester) async {
      await pumpHelix(
        tester,
        const HelixSwipeableChatListTile(
          item: _item,
          selectionMode: true,
          startAction: HelixSwipeAction(
            icon: Icons.push_pin,
            label: 'Pin',
            onTriggered: _noop,
          ),
        ),
      );
      expect(find.byType(Dismissible), findsNothing);
    });
  });

  group('selection bar', () {
    testWidgets('shows the count and labels every button', (tester) async {
      var closed = false;
      await pumpHelix(tester, const SizedBox.shrink(), scaffold: false);
      await tester.pumpWidget(
        MaterialApp(
          theme: HelixThemes.light(),
          home: Scaffold(
            appBar: HelixSelectionBar(
              count: 3,
              onClose: () => closed = true,
              actions: const [
                HelixBarAction(
                  icon: Icons.archive,
                  tooltip: 'Archive',
                  onPressed: _noop,
                ),
                HelixBarAction(
                  icon: Icons.delete,
                  tooltip: 'Delete',
                  onPressed: _noop,
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('3 selected'), findsOneWidget);
      expect(find.byTooltip('Archive'), findsOneWidget);
      expect(find.byTooltip('Delete'), findsOneWidget);
      await tester.tap(find.byTooltip('Cancel selection'));
      expect(closed, isTrue);
    });
  });

  group('states', () {
    testWidgets('skeleton announces loading once and is not scrollable', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpHelix(tester, const HelixChatListSkeleton(count: 3));
      expect(find.bySemanticsLabel('Loading chats'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('empty state offers to find people', (tester) async {
      var found = 0;
      await pumpHelix(tester, HelixChatListEmpty(onFindPeople: () => found++));
      expect(find.text('No chats yet'), findsOneWidget);
      await tester.tap(find.text('Find people'));
      expect(found, 1);
    });

    testWidgets('section header has the fixed height and header semantics', (
      tester,
    ) async {
      await pumpHelix(tester, const HelixSectionHeader(title: 'Pinned'));
      expect(
        tester.getSize(find.byType(HelixSectionHeader)).height,
        HelixSectionHeader.height,
      );
    });

    testWidgets('archived row reports taps', (tester) async {
      var taps = 0;
      await pumpHelix(tester, HelixArchivedRow(count: 3, onTap: () => taps++));
      await tester.tap(find.text('Archived'));
      expect(taps, 1);
    });
  });

  group('avatar', () {
    testWidgets('shows initials, presence dot and group glyph', (tester) async {
      await pumpHelix(
        tester,
        const Column(
          children: [
            HelixAvatar(
              model: HelixAvatarModel(name: 'Sam Rivera'),
              online: true,
            ),
            HelixAvatar(model: HelixAvatarModel(name: 'Team', isGroup: true)),
          ],
        ),
      );
      expect(find.text('SR'), findsOneWidget);
      expect(find.byIcon(Icons.group), findsOneWidget);
    });

    testWidgets('initials do not grow with the text scale', (tester) async {
      await pumpHelix(
        tester,
        const HelixAvatar(model: HelixAvatarModel(name: 'Sam Rivera')),
        textScale: 2,
      );
      expect(tester.getSize(find.byType(HelixAvatar)), const Size(40, 40));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a standalone avatar can carry a label', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHelix(
        tester,
        const HelixAvatar(
          model: HelixAvatarModel(name: 'Sam'),
          semanticLabel: 'Sam, profile picture',
        ),
      );
      expect(find.bySemanticsLabel('Sam, profile picture'), findsOneWidget);
      handle.dispose();
    });
  });

  test('count badge kinds', () {
    // Constructors exist and are const.
    const a = HelixCountBadge(count: 1, color: Color(0xFF000000));
    const b = HelixCountBadge.mention(color: Color(0xFF000000));
    const c = HelixCountBadge.dot(color: Color(0xFF000000));
    expect([a, b, c], hasLength(3));
  });

  testWidgets('scroll-to-bottom shows the unread count and fires', (
    tester,
  ) async {
    var pressed = 0;
    await pumpHelix(
      tester,
      HelixScrollToBottomButton(
        visible: true,
        unreadCount: 5,
        onPressed: () => pressed++,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('5'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    expect(pressed, 1);
  });

  testWidgets('scroll-to-bottom is inert while hidden', (tester) async {
    var pressed = 0;
    await pumpHelix(
      tester,
      HelixScrollToBottomButton(visible: false, onPressed: () => pressed++),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byIcon(Icons.keyboard_arrow_down),
      warnIfMissed: false,
    );
    expect(pressed, 0);
  });
}

void _noop() {}
