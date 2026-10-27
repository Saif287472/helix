import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Locked chats: the menu entries, the screen behind the unlock, the switch
/// on a chat's settings.
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

  HelixChatListItem item(String id, String name) => HelixChatListItem(
    id: id,
    title: name,
    avatar: HelixAvatarModel(name: name),
  );

  Widget home(
    List<HelixChatListItem> chats, {
    HomeActions actions = const HomeActions(),
    int locked = 0,
    HomeStart start = const HomeStart(),
  }) => HomeScreen(
    model: HomeModel(
      me: const HelixAvatarModel(name: 'Me'),
      chats: ChatsTabModel(chats: chats, lockedCount: locked),
    ),
    actions: actions,
    start: start,
  );

  group('the Chats tab', () {
    testWidgets('selected chats are locked from the menu, with a note', (
      tester,
    ) async {
      final calls = <(Set<String>, bool)>[];
      await show(
        tester,
        home(
          [item('a', 'Anika')],
          actions: HomeActions(
            onSetLocked: (ids, {required locked}) async {
              calls.add((ids, locked));
              return null;
            },
          ),
          start: const HomeStart(selected: {'a'}),
        ),
      );
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lock chat'));
      await tester.pumpAndSettle();
      expect(calls.single.$1, {'a'});
      expect(calls.single.$2, isTrue);
      expect(find.textContaining('Find it in Locked chats'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('there is no Lock chat until the app can keep one', (
      tester,
    ) async {
      await show(
        tester,
        home([item('a', 'Anika')], start: const HomeStart(selected: {'a'})),
      );
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      expect(find.text('Lock chat'), findsNothing);
    });

    testWidgets('the menu has no Locked chats while none are locked', (
      tester,
    ) async {
      await show(
        tester,
        home([item('a', 'Anika')], actions: HomeActions(onOpenLocked: () {})),
      );
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      expect(find.text('New group'), findsOneWidget);
      expect(find.text('Locked chats'), findsNothing);
    });

    testWidgets('the menu opens Locked chats when some are locked', (
      tester,
    ) async {
      var opened = 0;
      await show(
        tester,
        home(
          [item('a', 'Anika')],
          locked: 2,
          actions: HomeActions(onOpenLocked: () => opened++),
        ),
      );
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Locked chats'));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });
  });

  group('the Locked chats screen', () {
    testWidgets('shows nothing of the chats until unlocked', (tester) async {
      var asked = 0;
      await show(
        tester,
        LockedChatsScreen(
          model: LockedChatsModel(chats: [item('a', 'Anika')]),
          actions: LockedChatsActions(onUnlock: () => asked++),
        ),
      );
      expect(find.text('Anika'), findsNothing);
      await tester.tap(find.text('Unlock'));
      expect(asked, 1);
    });

    testWidgets('lists them once unlocked, and opens one', (tester) async {
      final opened = <String>[];
      await show(
        tester,
        LockedChatsScreen(
          model: LockedChatsModel(
            chats: [item('a', 'Anika'), item('b', 'Bilal')],
            unlocked: true,
          ),
          actions: LockedChatsActions(onOpenChat: opened.add),
        ),
      );
      expect(find.text('Bilal'), findsOneWidget);
      await tester.tap(find.text('Anika'));
      expect(opened, ['a']);
    });

    testWidgets('says so when none are locked', (tester) async {
      await show(
        tester,
        const LockedChatsScreen(model: LockedChatsModel(unlocked: true)),
      );
      expect(find.text('No locked chats'), findsOneWidget);
    });

    testWidgets('a long press selects, and Remove lock takes it off', (
      tester,
    ) async {
      final removed = <Set<String>>[];
      await show(
        tester,
        LockedChatsScreen(
          model: LockedChatsModel(chats: [item('a', 'Anika')], unlocked: true),
          actions: LockedChatsActions(
            onRemoveLock: (ids) async => removed.add(ids),
          ),
        ),
      );
      await tester.longPress(find.text('Anika'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Remove lock'));
      await tester.pumpAndSettle();
      expect(removed.single, {'a'});
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('a chat\'s settings', () {
    ChatSettingsModel model({bool locked = false}) => ChatSettingsModel(
      title: 'Nadia Rahman',
      avatar: OrbitFakes.nadia.avatar,
      locked: locked,
    );

    testWidgets('offer Lock chat only where the app can keep it', (
      tester,
    ) async {
      await show(tester, ChatSettingsScreen(model: model()));
      expect(find.text('Lock chat'), findsNothing);
    });

    testWidgets('the switch locks and unlocks', (tester) async {
      final set = <bool>[];
      await show(
        tester,
        ChatSettingsScreen(
          model: model(),
          actions: ChatSettingsActions(
            onSetLocked: (v) {
              set.add(v);
              return null;
            },
          ),
        ),
      );
      await tester.ensureVisible(find.text('Lock chat'));
      await tester.tap(find.text('Lock chat'));
      await tester.pump();
      expect(set, [true]);
    });
  });

  testWidgets('the cover asks for the unlock', (tester) async {
    var asked = 0;
    await show(
      tester,
      Center(child: OrbitLockedCover(onUnlock: () => asked++)),
    );
    expect(find.text('Locked'), findsOneWidget);
    await tester.tap(find.text('Unlock'));
    expect(asked, 1);
  });
}
