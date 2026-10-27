import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/conversation/presentation/conversation_screen.dart';
import 'package:helix_remote/features/conversation/presentation/message_info_screen.dart';

import 'support/chat_harness.dart';
import 'support/orbit_theme.dart';

/// An edited message keeps its earlier versions, shown on Message info.
void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(412, 866);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  chatTest('Message info lists what an edited message said before', (
    tester,
    gateway,
  ) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    final row = (await tester.runAsync(
      () => gateway.incoming(chat, 'meet at fiev'),
    ))!;
    await tester.runAsync(
      () => gateway.db.messagesDao.editMessage(
        row.localRowid,
        body: 'meet at five',
        editedAt: testNow,
      ),
    );
    phone(tester);
    await tester.pumpWidget(
      chatApp(gateway, MessageInfoScreen(rowid: row.localRowid)),
    );
    await settle(tester, rounds: 10);

    expect(
      find.textContaining(RegExp('edit history', caseSensitive: false)),
      findsOneWidget,
    );
    expect(find.textContaining('Now'), findsOneWidget);
    expect(find.text('meet at fiev'), findsOneWidget);
    // A message from someone else has no recipients to list.
    expect(find.text('Not delivered yet'), findsNothing);
  });

  chatTest('the menu of someone else\'s edited message has Message info', (
    tester,
    gateway,
  ) async {
    final chat = (await tester.runAsync(
      () => gateway.chatWith('bob', name: 'Bob'),
    ))!;
    final plain = (await tester.runAsync(
      () => gateway.incoming(chat, 'never changed'),
    ))!;
    final edited = (await tester.runAsync(
      () => gateway.incoming(chat, 'was changed'),
    ))!;
    await tester.runAsync(
      () => gateway.db.messagesDao.editMessage(
        edited.localRowid,
        body: 'was changed',
        editedAt: testNow,
      ),
    );
    expect(plain.localRowid, isNot(edited.localRowid));
    phone(tester);
    await tester.pumpWidget(
      chatApp(gateway, ConversationScreen(conversationId: chat)),
    );
    await settle(tester, rounds: 10);

    await tester.longPress(findMessageText('never changed'));
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Message info'), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.longPress(findMessageText('was changed'));
    await tester.pumpAndSettle();
    expect(find.text('Message info'), findsOneWidget);
  });
}
