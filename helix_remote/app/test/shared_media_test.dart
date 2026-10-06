import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/conversation/presentation/shared_media_screen.dart';
import 'package:helix_remote_db/helix_remote_db.dart';

import 'support/chat_harness.dart';

/// The media, documents and links of one conversation, from the engine's
/// shared-media queries.
void main() {
  AttachmentsCompanion item(String id, String kind, {String? name}) =>
      AttachmentsCompanion.insert(
        messageRowid: 0,
        position: 0,
        kind: kind,
        mediaId: id,
        mediaKey: Uint8List(32),
        digest: Uint8List(32),
        mime: kind == 'image' ? 'image/jpeg' : 'application/pdf',
        size: 482000,
        name: Value(name),
        transfer: AttachmentTransfer.remote,
      );

  Future<void> open(WidgetTester tester, TestChatGateway gateway) async {
    await tester.pumpWidget(
      chatApp(gateway, const SharedMediaScreen(conversationId: 'direct:bob')),
    );
    await settle(tester, rounds: 10);
  }

  chatTest('an empty chat says so on every tab', (tester, gateway) async {
    await tester.runAsync(() => gateway.chatWith('bob', name: 'Bob'));
    await open(tester, gateway);
    expect(find.text('No media yet'), findsOneWidget);
    await tester.tap(find.text('Docs'));
    await settle(tester);
    expect(find.text('No documents yet'), findsOneWidget);
    await tester.tap(find.text('Links'));
    await settle(tester);
    expect(find.text('No links yet'), findsOneWidget);
  });

  chatTest('photos in a grid, documents and links in lists', (
    tester,
    gateway,
  ) async {
    await tester.runAsync(() async {
      final chat = await gateway.chatWith('bob', name: 'Bob');
      await gateway.db.messagesDao.insertMessage(
        MessagesCompanion.insert(
          messageId: 'p1',
          conversationId: chat,
          sender: 'bob',
          outgoing: false,
          sortKey: SortKey.of(testNow, 'p1'),
          sentAt: testNow,
          receivedAt: testNow,
          kind: 'media',
          status: MessageStatus.received,
        ),
        media: [
          item('a', 'image'),
          item('b', 'file', name: 'plan.pdf'),
        ],
      );
      await gateway.incoming(
        chat,
        'read https://www.example.org/a, ok',
        at: testNow,
      );
    });
    await open(tester, gateway);

    expect(find.bySemanticsLabel('Photo, 14:30'), findsOneWidget);
    await tester.tap(find.text('Docs'));
    await settle(tester);
    expect(find.text('plan.pdf'), findsOneWidget);
    expect(find.text('482 KB, PDF, 14:30'), findsOneWidget);
    await tester.tap(find.text('Links'));
    await settle(tester);
    // Trailing punctuation belongs to the sentence, not the link.
    expect(find.text('https://www.example.org/a'), findsOneWidget);
    expect(find.text('example.org, 14:30'), findsOneWidget);
    expect(find.byTooltip('Show in chat'), findsOneWidget);
  });
}
