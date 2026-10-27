import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Starred messages, pinned messages and favourite chats.
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

  HelixMessageItem message(
    String id,
    String text, {
    bool starred = false,
    bool pinned = false,
    bool outgoing = false,
  }) => HelixMessageItem(
    HelixMessage(
      id: id,
      outgoing: outgoing,
      content: HelixTextContent(text),
      timeLabel: '14:05',
      starred: starred,
      pinned: pinned,
    ),
  );

  ChatScreen chat(
    List<HelixMessageItem> items, {
    List<ChatPinnedMessage> pinned = const [],
    ChatActions actions = const ChatActions(),
    ChatStart start = const ChatStart(),
  }) => ChatScreen(
    model: ChatModel(
      conversationId: 'direct:nadia',
      title: 'Nadia Rahman',
      avatar: OrbitFakes.nadia.avatar,
      items: items,
      pinned: pinned,
    ),
    actions: actions,
    start: start,
  );

  group('a bubble', () {
    testWidgets('tells a screen reader it is starred or pinned', (
      tester,
    ) async {
      await show(
        tester,
        chat([
          message('a', 'plain'),
          message('b', 'kept', starred: true),
          message('c', 'fixed', pinned: true),
        ]),
      );
      expect(find.bySemanticsLabel(RegExp('kept.*starred')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('fixed.*pinned')), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('plain.*(starred|pinned)')),
        findsNothing,
      );
    });
  });

  group('the message menu', () {
    testWidgets('offers Star and Pin only where the app can keep them', (
      tester,
    ) async {
      await show(
        tester,
        chat([message('a', 'hello')], start: const ChatStart(actionsFor: 'a')),
      );
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Star'), findsNothing);
      expect(find.text('Pin'), findsNothing);
    });

    testWidgets('Star keeps the message', (tester) async {
      final calls = <(String, bool)>[];
      await show(
        tester,
        chat(
          [message('a', 'hello')],
          actions: ChatActions(
            onStar: (id, {required starred}) => calls.add((id, starred)),
          ),
          start: const ChatStart(actionsFor: 'a'),
        ),
      );
      await tester.tap(find.text('Star'));
      await tester.pump();
      expect(calls, [('a', true)]);
    });

    testWidgets('Pin pins it for the chat', (tester) async {
      final calls = <(String, bool)>[];
      await show(
        tester,
        chat(
          [message('a', 'hello')],
          actions: ChatActions(
            onPin: (id, {required pinned}) {
              calls.add((id, pinned));
              return null;
            },
          ),
          start: const ChatStart(actionsFor: 'a'),
        ),
      );
      await tester.tap(find.text('Pin'));
      await tester.pump();
      expect(calls, [('a', true)]);
    });

    testWidgets('a starred, pinned message offers to undo both', (
      tester,
    ) async {
      final starCalls = <(String, bool)>[];
      final pinCalls = <(String, bool)>[];
      await show(
        tester,
        chat(
          [message('a', 'hello', starred: true, pinned: true)],
          actions: ChatActions(
            onStar: (id, {required starred}) => starCalls.add((id, starred)),
            onPin: (id, {required pinned}) {
              pinCalls.add((id, pinned));
              return null;
            },
          ),
          start: const ChatStart(actionsFor: 'a'),
        ),
      );
      expect(find.text('Star'), findsNothing);
      expect(find.text('Pin'), findsNothing);
      await tester.tap(find.text('Unstar'));
      await tester.pump();
      expect(starCalls, [('a', false)]);
      expect(pinCalls, isEmpty);
    });

    testWidgets('a refusal to pin is shown', (tester) async {
      await show(
        tester,
        chat(
          [message('a', 'hello')],
          actions: ChatActions(
            onPin: (id, {required pinned}) =>
                'A chat keeps three pinned messages. Unpin one first.',
          ),
          start: const ChatStart(actionsFor: 'a'),
        ),
      );
      await tester.tap(find.text('Pin'));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('keeps three pinned'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('the pinned banner', () {
    const pins = [
      ChatPinnedMessage(id: 'b', text: 'meet at five', author: 'Nadia'),
      ChatPinnedMessage(id: 'a', text: 'bring tea'),
    ];

    testWidgets('shows one pinned message, and none when there are none', (
      tester,
    ) async {
      await show(tester, chat([message('a', 'hello')]));
      expect(find.textContaining('Pinned message'), findsNothing);

      await show(tester, chat([message('a', 'hello')], pinned: [pins.first]));
      expect(find.text('Pinned message'), findsOneWidget);
      expect(find.text('Nadia: meet at five'), findsOneWidget);
    });

    testWidgets('a tap jumps to it and moves on to the next', (tester) async {
      final jumped = <String>[];
      await show(
        tester,
        chat(
          [message('a', 'bring tea'), message('b', 'meet at five')],
          pinned: pins,
          actions: ChatActions(onJumpTo: jumped.add),
        ),
      );
      expect(find.text('Pinned message 1 of 2'), findsOneWidget);
      await tester.tap(find.text('Nadia: meet at five'));
      await tester.pump();
      expect(jumped, ['b']);
      expect(find.text('Pinned message 2 of 2'), findsOneWidget);
      expect(find.text('bring tea'), findsOneWidget);

      await tester.tap(find.text('Pinned message 2 of 2'));
      await tester.pump();
      expect(jumped, ['b', 'a']);
      expect(find.text('Pinned message 1 of 2'), findsOneWidget);
    });
  });

  group('favourite chats', () {
    HelixChatListItem item(String id, String name, {bool favourite = false}) =>
        HelixChatListItem(
          id: id,
          title: name,
          avatar: HelixAvatarModel(name: name),
          favourite: favourite,
        );

    HomeScreen home(
      List<HelixChatListItem> chats, {
      HomeActions actions = const HomeActions(),
      HomeStart start = const HomeStart(),
    }) => HomeScreen(
      model: HomeModel(
        me: const HelixAvatarModel(name: 'Me'),
        chats: ChatsTabModel(chats: chats),
      ),
      actions: actions,
      start: start,
    );

    testWidgets('the Favourites filter keeps only them', (tester) async {
      await show(
        tester,
        home([
          item('a', 'Anika', favourite: true),
          item('b', 'Bilal'),
        ], start: const HomeStart(filter: ChatFilter.favourites)),
      );
      expect(find.text('Anika'), findsOneWidget);
      expect(find.text('Bilal'), findsNothing);
      expect(find.text('Favourites'), findsOneWidget);
    });

    testWidgets('with none, it says how to add one', (tester) async {
      await show(
        tester,
        home([
          item('a', 'Anika'),
        ], start: const HomeStart(filter: ChatFilter.favourites)),
      );
      expect(find.text('No favourite chats'), findsOneWidget);
    });

    testWidgets('selected chats can be added to the favourites', (
      tester,
    ) async {
      final calls = <(Set<String>, bool)>[];
      await show(
        tester,
        home(
          [item('a', 'Anika'), item('b', 'Bilal', favourite: true)],
          actions: HomeActions(
            onSetFavourite: (ids, {required favourite}) async =>
                calls.add((ids, favourite)),
          ),
          start: const HomeStart(selected: {'a'}),
        ),
      );
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to favourites'));
      await tester.pumpAndSettle();
      expect(calls.single.$1, {'a'});
      expect(calls.single.$2, isTrue);
    });

    testWidgets('chats that are all favourites can be removed from them', (
      tester,
    ) async {
      final calls = <(Set<String>, bool)>[];
      await show(
        tester,
        home(
          [item('a', 'Anika'), item('b', 'Bilal', favourite: true)],
          actions: HomeActions(
            onSetFavourite: (ids, {required favourite}) async =>
                calls.add((ids, favourite)),
          ),
          start: const HomeStart(selected: {'b'}),
        ),
      );
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from favourites'));
      await tester.pumpAndSettle();
      expect(calls.single.$1, {'b'});
      expect(calls.single.$2, isFalse);
    });

    testWidgets('the menu has no Favourite until the app can keep one', (
      tester,
    ) async {
      await show(
        tester,
        home([item('a', 'Anika')], start: const HomeStart(selected: {'a'})),
      );
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      expect(find.text('Add to favourites'), findsNothing);
      expect(find.text('Pin'), findsOneWidget);
    });
  });

  group('the starred messages page', () {
    const items = [
      StarredItem(
        chatId: 'direct:nadia',
        messageId: 'm1',
        title: 'Nadia Rahman',
        avatar: HelixAvatarModel(name: 'Nadia Rahman'),
        who: 'Nadia',
        text: 'the door code is 4411',
        timeLabel: 'Mon',
      ),
      StarredItem(
        chatId: 'group:family',
        messageId: 'm2',
        title: 'Family',
        avatar: HelixAvatarModel(name: 'Family', isGroup: true),
        who: 'You',
        text: 'Photo',
        timeLabel: '12/10',
      ),
    ];

    testWidgets('lists them, and a row opens its chat at the message', (
      tester,
    ) async {
      final opened = <(String, String)>[];
      await show(
        tester,
        StarredMessagesScreen(
          model: const StarredModel(items: items),
          actions: StarredActions(onOpen: (c, m) => opened.add((c, m))),
        ),
      );
      expect(find.text('Nadia: the door code is 4411'), findsOneWidget);
      expect(find.text('You: Photo'), findsOneWidget);
      await tester.tap(find.text('Family'));
      expect(opened, [('group:family', 'm2')]);
    });

    testWidgets('says so when there are none, or when loading fails', (
      tester,
    ) async {
      await show(tester, const StarredMessagesScreen(model: StarredModel()));
      expect(find.text('No starred messages'), findsOneWidget);

      var retried = false;
      await show(
        tester,
        StarredMessagesScreen(
          model: const StarredModel(status: ListStatus.failed),
          actions: StarredActions(onRetry: () => retried = true),
        ),
      );
      await tester.tap(find.text('Try again'));
      expect(retried, isTrue);
    });
  });

  testWidgets('You has a row for starred messages that opens its topic', (
    tester,
  ) async {
    YouTopic? opened;
    await show(
      tester,
      YouScreen(
        model: const YouModel(
          name: 'Me',
          avatar: HelixAvatarModel(name: 'Me'),
        ),
        actions: YouActions(openTopic: (t) => opened = t),
      ),
    );
    await tester.scrollUntilVisible(
      find.text('Starred messages'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Starred messages'));
    expect(opened, YouTopic.starred);
  });
}
