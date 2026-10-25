import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Phase 4 batch 3: the conversation screen. How it looks is checked against
/// the prototype by the compare tool (the `chat-*` and `group-*` keys).
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
    ChatModel model, {
    ChatActions actions = const ChatActions(),
    ChatStart start = const ChatStart(),
  }) async {
    tester.view.physicalSize = const Size(412, 866);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: OrbitTheme.of(orbit),
        home: Scaffold(
          body: ChatScreen(model: model, actions: actions, start: start),
        ),
      ),
    );
    await tester.pump();
  }

  ChatModel nadia({
    String? disabled,
    List<PendingMemberItem> pending = const [],
    bool group = false,
  }) => ChatModel(
    conversationId: 'direct:nadia',
    title: 'Nadia Rahman',
    avatar: OrbitFakes.nadia.avatar,
    subtitle: 'online',
    isGroup: group,
    showCallButtons: !group,
    items: OrbitFakes.conversations['direct:nadia']!,
    composerDisabledReason: disabled,
    pendingMembers: pending,
  );

  testWidgets("a group author's picture opens their profile", (tester) async {
    String? opened;
    await show(
      tester,
      ChatModel(
        conversationId: 'group:family',
        title: 'Family',
        avatar: OrbitFakes.nadia.avatar,
        subtitle: '4 members',
        isGroup: true,
        showCallButtons: false,
        items: OrbitFakes.conversations['group:family']!,
      ),
      actions: ChatActions(onOpenAuthor: (author) => opened = author),
    );
    final abbu = find.byWidgetPredicate(
      (w) => w is OrbitAvatar && w.size == 30 && w.avatar.name == 'Abbu',
    );
    expect(abbu, findsWidgets);
    await tester.tap(abbu.last);
    expect(opened, 'abbu');
  });

  testWidgets('the header shows the name and status and places calls', (
    tester,
  ) async {
    bool? placed;
    await show(
      tester,
      nadia(),
      actions: ChatActions(
        onCall: ({required bool video}) {
          placed = video;
          return null;
        },
      ),
    );
    expect(find.text('Nadia Rahman'), findsOneWidget);
    expect(find.text('online'), findsOneWidget);
    await tester.tap(find.byTooltip('Video call'));
    expect(placed, isTrue);
    await tester.tap(find.byTooltip('Voice call'));
    expect(placed, isFalse);
  });

  testWidgets('long-press opens the actions; your sent text can be edited', (
    tester,
  ) async {
    String? edited;
    await show(
      tester,
      nadia(),
      actions: ChatActions(onEdit: (id) => edited = id),
      start: const ChatStart(actionsFor: 'n5'),
    );
    await tester.pump();
    for (final label in [
      'Reply',
      'Copy',
      'Forward',
      'Edit',
      'Message info',
      'Select',
      'Delete for me',
      'Delete for everyone',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.tap(find.text('Edit'));
    await tester.pump();
    expect(edited, 'n5');
    expect(find.text('Message info'), findsNothing);
  });

  testWidgets('a long message keeps its reactions and actions on screen', (
    tester,
  ) async {
    final long = HelixMessageItem(
      HelixMessage(
        id: 'long',
        outgoing: true,
        content: HelixTextContent('A line that goes on and on. ' * 200),
        timeLabel: '21:10',
        authorId: 'me',
        authorColorIndex: 5,
        sentAtMs: 370000,
        status: HelixDeliveryStatus.read,
      ),
    );
    await show(
      tester,
      ChatModel(
        conversationId: 'direct:nadia',
        title: 'Nadia Rahman',
        avatar: OrbitFakes.nadia.avatar,
        subtitle: 'online',
        isGroup: false,
        showCallButtons: true,
        items: [long],
      ),
      start: const ChatStart(actionsFor: 'long'),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final screen = tester.getRect(find.byType(ChatScreen));
    for (final shown in [
      find.bySemanticsLabel('React with 👍'),
      find.text('Reply'),
      find.text('Delete for everyone'),
    ]) {
      expect(screen.contains(tester.getCenter(shown)), isTrue);
    }
  });

  testWidgets("their message has no Edit, Message info or delete for all", (
    tester,
  ) async {
    await show(tester, nadia(), start: const ChatStart(actionsFor: 'n6'));
    await tester.pump();
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Message info'), findsNothing);
    expect(find.text('Delete for everyone'), findsNothing);
  });

  testWidgets('selection swaps the header and hides the composer', (
    tester,
  ) async {
    Set<String>? forwarded;
    await show(
      tester,
      nadia(),
      actions: ChatActions(onForward: (ids) => forwarded = ids),
      start: const ChatStart(selected: {'n3', 'n5'}),
    );
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.byType(OrbitComposer), findsNothing);
    // Forward takes the selection with it, as the prototype's bar does.
    await tester.tap(find.byTooltip('Forward'));
    await tester.pump();
    expect(forwarded, {'n3', 'n5'});
    expect(find.text('2 selected'), findsNothing);
    expect(find.byType(OrbitComposer), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await show(tester, nadia(), start: const ChatStart(selected: {'n3'}));
    expect(find.text('1 selected'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel selection'));
    await tester.pump();
    expect(find.text('1 selected'), findsNothing);
    expect(find.byType(OrbitComposer), findsOneWidget);
  });

  testWidgets('in-chat search lists matches and says when there are none', (
    tester,
  ) async {
    await show(tester, nadia(), start: const ChatStart(searching: true));
    expect(find.text('Search this chat'), findsWidgets);
    await tester.enterText(find.byType(EditableText), 'zzzz');
    await tester.pump();
    expect(find.text('No results'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'the');
    await tester.pump();
    expect(find.text('No results'), findsNothing);
    expect(find.text('You'), findsWidgets);
  });

  testWidgets('a blocked chat says why instead of offering the composer', (
    tester,
  ) async {
    const why = 'You blocked this contact. Open chat settings to unblock.';
    await show(tester, nadia(disabled: why));
    expect(find.textContaining('You blocked this contact'), findsOneWidget);
    expect(find.byTooltip('Send'), findsNothing);
  });

  testWidgets('a pending member can be confirmed, and removed by an admin', (
    tester,
  ) async {
    String? confirmed;
    String? removed;
    const p = PendingMemberItem(
      account: 'karim',
      title: 'Confirm Karim Uncle?',
      explanation: 'Karim Uncle was added by the server roster.',
      canRemove: true,
    );
    await show(
      tester,
      nadia(group: true, pending: const [p]),
      actions: ChatActions(
        onConfirmMember: (a) {
          confirmed = a;
          return null;
        },
        onRemoveMember: (a) {
          removed = a;
          return null;
        },
      ),
    );
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    expect(confirmed, 'karim');
    // Remove asks first.
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Karim Uncle?'), findsOneWidget);
    expect(removed, isNull);
    await tester.tap(find.text('Remove').last);
    await tester.pumpAndSettle();
    expect(removed, 'karim');
    expect(find.textContaining('Only an admin'), findsNothing);
  });

  testWidgets('loading and failure keep the header and drop the composer', (
    tester,
  ) async {
    await show(
      tester,
      const ChatModel(
        conversationId: 'direct:nadia',
        title: 'Nadia Rahman',
        avatar: HelixAvatarModel(name: 'Nadia Rahman'),
        loadState: ChatLoadState.openFailed,
      ),
    );
    expect(find.text('Nadia Rahman'), findsOneWidget);
    expect(find.text('This conversation could not be opened.'), findsOneWidget);
    expect(find.byType(OrbitComposer), findsNothing);
  });

  group('the bottom of a chat on a three-button phone', () {
    Future<void> showWith(
      WidgetTester tester, {
      required double navBar,
      bool emoji = false,
    }) async {
      // Android draws its navigation buttons over the bottom of the window, so
      // the composer keeps the field clear of them; with the emoji panel open
      // the panel is the bottom strip and takes the inset instead.
      tester.view.physicalSize = const Size(412, 866);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: OrbitTheme.of(orbit),
          home: MediaQuery(
            data: MediaQueryData(viewPadding: EdgeInsets.only(bottom: navBar)),
            child: Scaffold(
              body: ChatScreen(
                model: nadia(),
                start: ChatStart(emoji: emoji),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('the field rises above the bar', (tester) async {
      await showWith(tester, navBar: 0);
      final plain = tester.getSize(find.byType(OrbitComposer)).height;
      await showWith(tester, navBar: 48);
      expect(tester.getSize(find.byType(OrbitComposer)).height, plain + 48);
      final screenBottom = tester.getBottomLeft(find.byType(Scaffold)).dy;
      expect(
        tester.getBottomLeft(find.byType(TextField)).dy,
        lessThanOrEqualTo(screenBottom - 48),
      );
    });

    testWidgets('an open emoji panel takes the bar, not the composer', (
      tester,
    ) async {
      await showWith(tester, navBar: 0, emoji: true);
      final composer = tester.getSize(find.byType(OrbitComposer)).height;
      final grid = tester.getSize(find.byType(GridView)).height;
      await showWith(tester, navBar: 48, emoji: true);
      expect(tester.getSize(find.byType(OrbitComposer)).height, composer);
      expect(tester.getSize(find.byType(GridView)).height, grid + 48);
    });
  });

  group('the app\'s hooks', () {
    HelixMessageItem text(String id, String body, {bool out = false}) =>
        HelixMessageItem(
          HelixMessage(
            id: id,
            outgoing: out,
            content: HelixTextContent(body),
            timeLabel: '14:05',
          ),
        );

    ChatModel chat(List<HelixTimelineItem> items, {bool enter = false}) =>
        ChatModel(
          conversationId: 'direct:nadia',
          title: 'Nadia Rahman',
          avatar: OrbitFakes.nadia.avatar,
          items: items,
          enterSends: enter,
        );

    testWidgets('the app can decide the menu, and deleting asks first', (
      tester,
    ) async {
      Set<String>? deleted;
      await show(
        tester,
        nadia(),
        actions: ChatActions(
          messageMenu: (id) => const ChatMessageMenu(
            actions: {ChatMessageAction.reply, ChatMessageAction.deleteForMe},
            allowReactions: false,
          ),
          onDeleteForMe: (ids) => deleted = ids,
        ),
        start: const ChatStart(actionsFor: 'n6'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Select'), findsNothing);
      expect(find.bySemanticsLabel('React with 👍'), findsNothing);
      await tester.tap(find.text('Delete for me'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this message?'), findsOneWidget);
      expect(deleted, isNull);
      await tester.tap(find.text('Delete for me'));
      await tester.pumpAndSettle();
      expect(deleted, {'n6'});
    });

    testWidgets('a link, a quote and a reaction answer taps', (tester) async {
      String? link;
      String? quoted;
      String? reactions;
      await show(
        tester,
        chat([
          text('a', 'https://example.org/plan'),
          const HelixMessageItem(
            HelixMessage(
              id: 'b',
              outgoing: true,
              content: HelixTextContent('about that'),
              timeLabel: '14:06',
              reply: HelixReplyQuote(authorName: 'Nadia', text: 'the plan'),
              reactions: [HelixReaction(emoji: '👍', count: 1)],
            ),
          ),
        ]),
        actions: ChatActions(
          onOpenLink: (url) => link = url,
          onQuote: (id) => quoted = id,
          reactionsOf: (id) async {
            reactions = id;
            return const [];
          },
        ),
      );
      // Just inside the first bubble: the start of the link.
      final first = tester.getTopLeft(
        find.byWidgetPredicate(
          (w) => w is OrbitMessageBubble && w.message.id == 'a',
        ),
      );
      await tester.tapAt(first + const Offset(30, 22));
      expect(link, 'https://example.org/plan');
      await tester.tap(find.text('the plan', findRichText: true));
      expect(quoted, 'b');
      await tester.tap(find.text('👍'));
      await tester.pumpAndSettle();
      expect(reactions, 'b');
      expect(find.text('No reactions yet.'), findsOneWidget);
    });

    testWidgets('swiping their message towards the middle replies', (
      tester,
    ) async {
      String? replied;
      await show(
        tester,
        chat([text('a', 'are you coming?')]),
        actions: ChatActions(onReply: (id) => replied = id),
      );
      await tester.dragFrom(
        tester.getTopLeft(find.byType(OrbitMessageBubble)) +
            const Offset(30, 22),
        const Offset(70, 0),
      );
      await tester.pumpAndSettle();
      expect(replied, 'a');
    });

    testWidgets('the mic records while held; a tap says to hold it', (
      tester,
    ) async {
      final calls = <String>[];
      await show(
        tester,
        chat(const []),
        actions: ChatActions(
          onVoiceStart: () => calls.add('start'),
          onVoiceSlide: (cancel, lock) {},
          onVoiceLock: () => calls.add('lock'),
          onVoiceEnd: ({required send}) => calls.add('end:$send'),
        ),
      );
      final mic = find.byTooltip('Record a voice message');
      await tester.tap(mic);
      await tester.pump();
      expect(
        find.text('Hold the microphone to record a voice message.'),
        findsOneWidget,
      );
      expect(calls, isEmpty);

      var hold = await tester.startGesture(tester.getCenter(mic));
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, ['start']);
      await hold.up();
      expect(calls, ['start', 'end:true']);

      hold = await tester.startGesture(tester.getCenter(mic));
      await tester.pump(const Duration(milliseconds: 300));
      await hold.moveBy(const Offset(0, -90));
      await hold.up();
      expect(calls, ['start', 'end:true', 'start', 'lock']);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Enter sends when the setting says so', (tester) async {
      final sent = <String>[];
      await show(
        tester,
        chat(const [], enter: true),
        actions: ChatActions(
          onSend: (t) {
            sent.add(t);
            return true;
          },
        ),
      );
      await tester.enterText(find.byType(TextField), 'on my way');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(sent, ['on my way']);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
    });
  });
}
