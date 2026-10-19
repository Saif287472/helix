import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/chats/presentation/chats_tab.dart';

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

  Widget home({Widget Function(BuildContext, String)? detail}) =>
      ChatsTab(detailBuilder: detail);

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
}
