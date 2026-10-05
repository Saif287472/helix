import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chat_harness.dart' show settle;
import 'journey_harness.dart';

/// The whole `HelixRemoteApp`, as `main()` builds it (lifecycle host, call
/// host, phone-book sync, app lock, link listener, text scale around the
/// router), over the in-memory fakes: it starts on sign-in, signs in, shows
/// the chat list, takes a person to a conversation and a message, and the
/// three tabs are all there.
void main() {
  journeyTest('the whole app starts, signs in and sends a message', (
    tester,
  ) async {
    final app = await Journey.start(
      tester,
      wholeApp: true,
      known: [knownPerson('mum', 'Mum', number: '+8801711000001')],
      seed: (chat) async {
        await chat.chatWith('mum', name: 'Mum');
        await chat.incoming('direct:mum', 'dinner at eight?');
      },
    );

    expect(find.text('Sign in'), findsWidgets);
    await app.signIn(tester);

    // The three tabs, the chat with its last message.
    expect(find.text('Chats'), findsWidgets);
    expect(find.text('Calls'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Mum'), findsOneWidget);
    expect(find.text('dinner at eight?'), findsOneWidget);

    await tapAndSettle(tester, find.text('Mum'));
    await tester.enterText(find.byType(TextField), 'yes, see you there');
    await tester.pump();
    await tapAndSettle(tester, find.byTooltip('Send'));
    expect(app.chat.log, contains('sendText:direct:mum:yes, see you there'));

    // Back to the list: the new last message is the preview.
    app.router.go('/home');
    await settle(tester, rounds: 10);
    expect(find.text('You: yes, see you there'), findsOneWidget);
  });
}
