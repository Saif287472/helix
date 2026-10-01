import 'dart:typed_data';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ReceiptKind;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late HelixDb db;
  late MessagesDao messages;
  late String chat;

  setUp(() async {
    db = memoryDb();
    messages = db.messagesDao;
    chat = (await directChat(db, 'bob')).id;
  });

  Future<ConversationRow> conversation() async =>
      (await db.conversationsDao.byId(chat))!;

  group('conversation summary', () {
    test('a message write updates the summary', () async {
      final row = await messages.insertMessage(
        textMessage(chat, 'm1', sentAt: at(1), body: 'hello  there\nbob'),
      );
      final c = await conversation();
      expect(c.lastMessageRowid, row.localRowid);
      expect(c.lastMessageSortKey, row.sortKey);
      expect(c.lastMessageAt, at(1));
      expect(c.lastMessagePreview, 'hello there bob');
      expect(c.unreadCount, 1);
      expect(c.mentionCount, 0);
    });

    test(
      'counts unread incoming messages and mentions, not outgoing ones',
      () async {
        await messages.insertMessage(
          textMessage(chat, 'm1', sentAt: at(1), mentionsMe: true),
        );
        await messages.insertMessage(textMessage(chat, 'm2', sentAt: at(2)));
        await messages.insertMessage(
          textMessage(chat, 'm3', sentAt: at(3), sender: 'me', outgoing: true),
        );
        final c = await conversation();
        expect(c.unreadCount, 2);
        expect(c.mentionCount, 1);
        expect(c.lastMessagePreview, 'message m3');
      },
    );

    test('an older late message does not replace the last message', () async {
      await messages.insertMessage(textMessage(chat, 'm2', sentAt: at(2)));
      await messages.insertMessage(textMessage(chat, 'm1', sentAt: at(1)));
      final c = await conversation();
      expect(c.lastMessagePreview, 'message m2');
      expect(c.unreadCount, 2);
    });

    test('is written in the same transaction as the message', () async {
      // A transaction that fails after the write leaves neither behind.
      await expectLater(
        db.transaction(() async {
          await messages.insertMessage(textMessage(chat, 'm1', sentAt: at(1)));
          throw StateError('apply failed');
        }),
        throwsStateError,
      );
      var c = await conversation();
      expect((await messages.pageOlder(chat)).messages, isEmpty);
      expect(c.lastMessageRowid, isNull);
      expect(c.unreadCount, 0);

      // A failing write (duplicate id from the same sender) changes nothing.
      await messages.insertMessage(textMessage(chat, 'm1', sentAt: at(1)));
      await expectLater(
        messages.insertMessage(textMessage(chat, 'm1', sentAt: at(5))),
        throwsA(anything),
      );
      c = await conversation();
      expect(c.unreadCount, 1);
      expect(c.lastMessageAt, at(1));

      // Watchers never see a message without its summary.
      final list = collect(db.conversationsDao.watchList());
      for (var i = 2; i < 12; i++) {
        await messages.insertMessage(textMessage(chat, 'm$i', sentAt: at(i)));
      }
      await eventually(
        () =>
            list.isNotEmpty &&
            list.last.single.conversation.lastMessagePreview == 'message m11',
      );
      for (final emission in list) {
        final item = emission.single;
        expect(item.lastMessage?.sortKey, item.conversation.lastMessageSortKey);
        final unread = (await messages.pageOlder(chat, limit: 100)).messages
            .where((m) => m.sortKey.compareTo(item.lastMessage!.sortKey) <= 0)
            .length;
        expect(item.conversation.unreadCount, unread);
      }
    });

    test('mark read returns the newly read messages and recounts', () async {
      final m1 = await messages.insertMessage(
        textMessage(chat, 'm1', sentAt: at(1), mentionsMe: true),
      );
      final m2 = await messages.insertMessage(
        textMessage(chat, 'm2', sentAt: at(2)),
      );
      await messages.insertMessage(textMessage(chat, 'm3', sentAt: at(3)));

      final read = await messages.markReadUpTo(chat, m2.sortKey);
      expect(read.map((m) => m.messageId), ['m1', 'm2']);
      expect(read.every((m) => m.status == MessageStatus.read), isTrue);
      var c = await conversation();
      expect(c.unreadCount, 1);
      expect(c.mentionCount, 0);
      expect(c.lastReadSortKey, m2.sortKey);

      expect(await messages.markReadUpTo(chat, m1.sortKey), isEmpty);
      c = await conversation();
      expect(c.lastReadSortKey, m2.sortKey, reason: 'never moves back');
    });

    test('edit and delete for everyone refresh the preview', () async {
      final m1 = await messages.insertMessage(
        textMessage(chat, 'm1', sentAt: at(1), body: 'typo'),
      );
      await messages.editMessage(m1.localRowid, body: 'fixed', editedAt: at(2));
      expect((await conversation()).lastMessagePreview, 'fixed');
      expect((await messages.byRowid(m1.localRowid))!.editedAt, at(2));

      await messages.setReaction(
        m1.localRowid,
        reactor: 'me',
        emoji: '👍',
        at: at(3),
      );
      final removed = await messages.deleteForEveryone(
        m1.localRowid,
        deletedAt: at(4),
      );
      expect(removed, isEmpty);
      final row = (await messages.byRowid(m1.localRowid))!;
      expect(row.body, isNull);
      expect(row.deletedAt, at(4));
      expect(await messages.reactionsFor([m1.localRowid]), isEmpty);
      expect((await conversation()).lastMessagePreview, '');
    });

    test('removing messages and expiry refresh the summary', () async {
      await messages.insertMessage(textMessage(chat, 'm1', sentAt: at(1)));
      final m2 = await messages.insertMessage(
        textMessage(chat, 'm2', sentAt: at(2), expireSeconds: 60),
      );
      await messages.markDisplayed(m2.localRowid, at(10));
      expect((await messages.byRowid(m2.localRowid))!.expiresAt, at(70));
      await messages.markDisplayed(m2.localRowid, at(20));
      expect(
        (await messages.byRowid(m2.localRowid))!.expiresAt,
        at(70),
        reason: 'the timer starts once',
      );

      expect(await messages.removeExpired(at(69)), 0);
      expect(await messages.removeExpired(at(70)), 1);
      final c = await conversation();
      expect(c.lastMessagePreview, 'message m1');
      expect(c.unreadCount, 1);

      await messages.removeMessages([c.lastMessageRowid!]);
      final empty = await conversation();
      expect(empty.lastMessageRowid, isNull);
      expect(empty.lastMessagePreview, isNull);
      expect(empty.unreadCount, 0);
    });

    test('the preview is one line of at most 100 code points', () async {
      final long = '😀' * 150;
      await messages.insertMessage(
        textMessage(chat, 'm1', sentAt: at(1), body: long),
      );
      final preview = (await conversation()).lastMessagePreview!;
      expect(preview.runes.length, MessagesDao.previewLength);
      expect(preview, '😀' * 100);
    });
  });

  group('keyset paging', () {
    setUp(() async {
      // Inserted out of order; two messages share a timestamp.
      for (final i in [5, 1, 9, 3, 7, 2, 8, 4, 6, 10]) {
        await messages.insertMessage(textMessage(chat, 'm$i', sentAt: at(i)));
      }
      await messages.insertMessage(textMessage(chat, 'm5b', sentAt: at(5)));
      final other = (await directChat(db, 'carol')).id;
      await messages.insertMessage(
        textMessage(other, 'x1', sentAt: at(6), sender: 'carol'),
      );
    });

    List<String> ids(MessagePage page) =>
        page.messages.map((m) => m.messageId).toList();

    test('pages older from the newest, oldest first in each page', () async {
      final p1 = await messages.pageOlder(chat, limit: 4);
      expect(ids(p1), ['m7', 'm8', 'm9', 'm10']);
      expect(p1.hasMore, isTrue);
      final p2 = await messages.pageOlder(
        chat,
        before: p1.oldestSortKey,
        limit: 4,
      );
      expect(ids(p2), ['m4', 'm5', 'm5b', 'm6']);
      final p3 = await messages.pageOlder(
        chat,
        before: p2.oldestSortKey,
        limit: 4,
      );
      expect(ids(p3), ['m1', 'm2', 'm3']);
      expect(p3.hasMore, isFalse);
    });

    test('pages newer from an anchor without gaps or repeats', () async {
      final start = (await messages.find('m2', sender: 'bob'))!;
      final seen = <String>[];
      var after = start.sortKey;
      while (true) {
        final page = await messages.pageNewer(chat, after: after, limit: 3);
        seen.addAll(ids(page));
        if (!page.hasMore) break;
        after = page.newestSortKey!;
      }
      expect(seen, ['m3', 'm4', 'm5', 'm5b', 'm6', 'm7', 'm8', 'm9', 'm10']);
    });

    test('the sort key orders by author time, then message id', () {
      final a = SortKey.of(at(1), '0192-b');
      final b = SortKey.of(at(1), '0192-c');
      final c = SortKey.of(at(2), '0192-a');
      expect([c, b, a]..sort(), [a, b, c]);
      expect(SortKey.of(DateTime.utc(1960), 'x'), startsWith('000000000000'));
    });
  });

  test('reactions replace per reactor; receipts keep the first time', () async {
    final m = await messages.insertMessage(
      textMessage(chat, 'm1', sentAt: at(1), sender: 'me', outgoing: true),
    );
    await messages.setReaction(
      m.localRowid,
      reactor: 'bob',
      emoji: '👍',
      at: at(2),
    );
    await messages.setReaction(
      m.localRowid,
      reactor: 'bob',
      emoji: '❤️',
      at: at(3),
    );
    expect((await messages.reactionsFor([m.localRowid])).single.emoji, '❤️');
    await messages.removeReaction(m.localRowid, reactor: 'bob');
    expect(await messages.reactionsFor([m.localRowid]), isEmpty);

    await messages.recordReceipt(
      m.localRowid,
      account: 'bob',
      kind: ReceiptKind.delivered,
      at: at(4),
    );
    await messages.recordReceipt(
      m.localRowid,
      account: 'bob',
      kind: ReceiptKind.read,
      at: at(5),
    );
    await messages.recordReceipt(
      m.localRowid,
      account: 'bob',
      kind: ReceiptKind.delivered,
      at: at(6),
    );
    final receipt = (await messages.receiptsFor(m.localRowid)).single;
    expect(receipt.deliveredAt, at(4));
    expect(receipt.readAt, at(5));
    expect(receipt.viewedAt, isNull);
  });

  test('outgoing status only moves forward', () async {
    final m = await messages.insertMessage(
      textMessage(chat, 'm1', sentAt: at(1), sender: 'me', outgoing: true),
    );
    expect(
      await messages.advanceStatus(m.localRowid, MessageStatus.sent),
      MessageStatus.sent,
    );
    expect(
      await messages.advanceStatus(m.localRowid, MessageStatus.read),
      MessageStatus.read,
    );
    expect(
      await messages.advanceStatus(m.localRowid, MessageStatus.delivered),
      MessageStatus.read,
    );
    expect(
      await messages.advanceStatus(m.localRowid, MessageStatus.failed),
      MessageStatus.read,
    );
    expect(
      MessageStatus.pending.advance(MessageStatus.failed),
      MessageStatus.failed,
    );
    expect(
      MessageStatus.failed.advance(MessageStatus.pending),
      MessageStatus.pending,
    );
  });

  test(
    'media rows are stored in album order and removed with the message',
    () async {
      AttachmentsCompanion item(String id) => AttachmentsCompanion.insert(
        messageRowid: 0,
        position: 0,
        kind: 'image',
        mediaId: id,
        mediaKey: Uint8List(32),
        digest: Uint8List(32),
        mime: 'image/jpeg',
        size: 1000,
        transfer: AttachmentTransfer.remote,
      );
      final m = await messages.insertMessage(
        textMessage(chat, 'm1', sentAt: at(1), body: 'album caption'),
        media: [item('a'), item('b')],
      );
      final media = await messages.attachmentsFor([m.localRowid]);
      expect(media.map((a) => (a.mediaId, a.position)), [('a', 0), ('b', 1)]);

      await messages.updateAttachment(
        media.first.id,
        transfer: AttachmentTransfer.ready,
        localPath: 'media/a.jpg',
      );
      expect(
        (await messages.attachmentsFor([m.localRowid])).first.transfer,
        AttachmentTransfer.ready,
      );

      final removed = await messages.deleteForEveryone(
        m.localRowid,
        deletedAt: at(2),
      );
      expect(removed.map((a) => a.localPath), ['media/a.jpg', null]);
      expect(await messages.attachmentsFor([m.localRowid]), isEmpty);
    },
  );

  test('deleting a conversation cascades to its messages', () async {
    final m = await messages.insertMessage(
      textMessage(chat, 'm1', sentAt: at(1)),
    );
    await messages.setReaction(
      m.localRowid,
      reactor: 'me',
      emoji: '👍',
      at: at(2),
    );
    await db.conversationsDao.deleteConversation(chat);
    expect(await messages.byRowid(m.localRowid), isNull);
    expect(await messages.reactionsFor([m.localRowid]), isEmpty);
  });
}
