import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The person's own lists on the Chats tab.
void main() {
  late OrbitTokens orbit;
  setUpAll(() {
    orbit = OrbitTokens.fromThemeJson(
      jsonDecode(File('assets/themes/orbit.json').readAsStringSync())
          as Map<String, Object?>,
    );
  });

  Future<void> show(
    WidgetTester tester,
    List<HelixChatListItem> chats, {
    List<HelixChatList> lists = const [],
    HomeActions actions = const HomeActions(),
    HomeStart start = const HomeStart(),
  }) async {
    tester.view.physicalSize = const Size(412, 866);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: OrbitTheme.of(orbit),
        home: Scaffold(
          body: HomeScreen(
            model: HomeModel(
              me: const HelixAvatarModel(name: 'Me'),
              chats: ChatsTabModel(chats: chats, lists: lists),
            ),
            actions: actions,
            start: start,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  HelixChatListItem item(String id, String name, {List<String>? on}) =>
      HelixChatListItem(
        id: id,
        title: name,
        avatar: HelixAvatarModel(name: name),
        lists: on ?? const [],
      );

  /// The chips slide sideways: bring one into view before touching it.
  Future<void> reveal(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pump();
  }

  const work = HelixChatList(id: 'w', name: 'Work');
  const family = HelixChatList(id: 'f', name: 'Family');

  testWidgets('a list chip keeps only the chats on it', (tester) async {
    await show(
      tester,
      [
        item('a', 'Anika', on: ['w']),
        item('b', 'Bilal', on: ['f']),
        item('c', 'Cara'),
      ],
      lists: [work, family],
    );
    expect(find.text('Anika'), findsOneWidget);
    expect(find.text('Bilal'), findsOneWidget);

    await reveal(tester, 'Work');
    await tester.tap(find.text('Work'));
    await tester.pump();
    expect(find.text('Anika'), findsOneWidget);
    expect(find.text('Bilal'), findsNothing);
    expect(find.text('Cara'), findsNothing);

    await reveal(tester, 'All');
    await tester.tap(find.text('All'));
    await tester.pump();
    expect(find.text('Cara'), findsOneWidget);
  });

  testWidgets('an empty list says how to fill it', (tester) async {
    await show(tester, [item('a', 'Anika')], lists: [work]);
    await reveal(tester, 'Work');
    await tester.tap(find.text('Work'));
    await tester.pump();
    expect(find.text('Nothing on this list'), findsOneWidget);
  });

  testWidgets('New list asks for a name and reports a refusal', (tester) async {
    final made = <(String, Set<String>)>[];
    await show(
      tester,
      [item('a', 'Anika')],
      actions: HomeActions(
        onCreateList: (name, ids) {
          made.add((name, ids));
          return name == 'Work' ? 'A list with that name exists.' : null;
        },
        onSetOnList: (ids, listId, {required member}) async {},
      ),
    );
    await reveal(tester, 'New list');
    await tester.tap(find.text('New list'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Gym');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(made.first.$1, 'Gym');
    expect(made.first.$2, isEmpty);

    await reveal(tester, 'New list');
    await tester.tap(find.text('New list'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Work');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('A list with that name exists.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('selected chats are put on a list from the menu', (tester) async {
    final calls = <(Set<String>, String, bool)>[];
    await show(
      tester,
      [
        item('a', 'Anika'),
        item('b', 'Bilal', on: ['w']),
      ],
      lists: [work, family],
      actions: HomeActions(
        onCreateList: (name, ids) => null,
        onSetOnList: (ids, listId, {required member}) async =>
            calls.add((ids, listId, member)),
      ),
      start: const HomeStart(selected: {'a'}),
    );
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to list'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Family').last);
    await tester.pumpAndSettle();
    expect(calls.single.$1, {'a'});
    expect(calls.single.$2, 'f');
    expect(calls.single.$3, isTrue);
  });

  testWidgets('chats already on the list are taken off it', (tester) async {
    final calls = <(Set<String>, String, bool)>[];
    await show(
      tester,
      [
        item('b', 'Bilal', on: ['w']),
      ],
      lists: [work],
      actions: HomeActions(
        onCreateList: (name, ids) => null,
        onSetOnList: (ids, listId, {required member}) async =>
            calls.add((ids, listId, member)),
      ),
      start: const HomeStart(selected: {'b'}),
    );
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to list'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Work').last);
    await tester.pumpAndSettle();
    expect(calls.single.$1, {'b'});
    expect(calls.single.$2, 'w');
    expect(calls.single.$3, isFalse);
  });

  testWidgets('a long press on a list renames or deletes it', (tester) async {
    final renamed = <(String, String)>[];
    final deleted = <String>[];
    await show(
      tester,
      [
        item('a', 'Anika', on: ['w']),
      ],
      lists: [work],
      actions: HomeActions(
        onRenameList: (id, name) {
          renamed.add((id, name));
          return null;
        },
        onDeleteList: (id) async => deleted.add(id),
      ),
    );
    await reveal(tester, 'Work');
    await tester.longPress(find.text('Work'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Office');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(renamed.single, ('w', 'Office'));

    await reveal(tester, 'Work');
    await tester.longPress(find.text('Work'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete list'));
    await tester.pumpAndSettle();
    expect(deleted.single, 'w');
  });

  testWidgets('without the actions there is no New list and no menu entry', (
    tester,
  ) async {
    await show(tester, [
      item('a', 'Anika'),
    ], start: const HomeStart(selected: {'a'}));
    expect(find.text('New list'), findsNothing);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Add to list'), findsNothing);
  });
}
