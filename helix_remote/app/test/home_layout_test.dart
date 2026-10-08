import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/chats/presentation/chats_tab.dart';
import 'package:helix_remote/features/home/presentation/home_screen.dart';

import 'support/chat_harness.dart';

/// The home shell and the chat list's wide layout: the new-chat button, the
/// chat opening beside the list on a wide window, and the tabs as a page view
/// only where there is something to swipe.
void main() {
  void size(WidgetTester tester, double width, [double height = 800]) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget home({Widget Function(BuildContext, String)? detail}) => HomeScreen(
    chatsTab: ChatsTab(detailBuilder: detail),
    callsTab: const Center(child: Text('calls here')),
    settingsTab: const Center(child: Text('settings here')),
  );

  chatTest('the new chat button opens the search', (tester, gateway) async {
    size(tester, 400);
    await tester.pumpWidget(chatApp(gateway, const ChatsTab()));
    await settle(tester);

    await tester.tap(find.byTooltip('New chat'));
    await settle(tester);

    expect(find.text('Search chats, messages and people'), findsOneWidget);
    // While searching the button steps aside (it animates out).
    await tester.pumpAndSettle();
    expect(find.byTooltip('New chat'), findsNothing);
  });

  chatTest('on a wide window the chat opens beside the list', (
    tester,
    gateway,
  ) async {
    size(tester, 1200);
    final bob = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    await tester.runAsync(() => gateway.incoming(bob, 'hi'));
    await tester.pumpWidget(
      chatApp(
        gateway,
        home(detail: (context, id) => Center(child: Text('open: $id'))),
      ),
    );
    await settle(tester);

    expect(find.text('Select a chat'), findsOneWidget);
    await tester.tap(find.text('Bob'));
    await settle(tester);

    expect(find.text('open: $bob'), findsOneWidget);
    expect(find.text('Select a chat'), findsNothing);
    // The list is still there, with the open chat marked.
    expect(find.text('Bob'), findsOneWidget);
  });

  chatTest('wide windows show the tabs one at a time, narrow ones page', (
    tester,
    gateway,
  ) async {
    size(tester, 1200);
    await tester.pumpWidget(chatApp(gateway, home()));
    await settle(tester);
    expect(find.byType(PageView), findsNothing);
    expect(find.byType(IndexedStack), findsWidgets);

    await tester.tap(find.text('Calls'));
    await settle(tester);
    expect(find.text('calls here'), findsOneWidget);

    // Narrowing keeps the tab the person was on.
    size(tester, 400);
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('calls here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  chatTest('narrow windows keep the swipeable pages', (tester, gateway) async {
    size(tester, 400);
    await tester.pumpWidget(chatApp(gateway, home()));
    await settle(tester);
    expect(find.byType(PageView), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await settle(tester);
    expect(find.text('settings here'), findsOneWidget);
  });
}
