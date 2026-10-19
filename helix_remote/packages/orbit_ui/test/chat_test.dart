import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
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

  testWidgets('the header shows the name and status and places calls', (
    tester,
  ) async {
    bool? placed;
    await show(
      tester,
      nadia(),
      actions: ChatActions(onCall: ({required bool video}) => placed = video),
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
    await tester.tap(find.byTooltip('Forward'));
    expect(forwarded, {'n3', 'n5'});
    await tester.tap(find.byTooltip('Cancel selection'));
    await tester.pump();
    expect(find.text('2 selected'), findsNothing);
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
        onConfirmMember: (a) => confirmed = a,
        onRemoveMember: (a) => removed = a,
      ),
    );
    await tester.tap(find.text('Confirm'));
    await tester.tap(find.text('Remove'));
    expect(confirmed, 'karim');
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
}
