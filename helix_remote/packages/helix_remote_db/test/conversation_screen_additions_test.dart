import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The two small queries the conversation screen needs on top of the paged
/// message queries: the reactions of the visible window, and "clear chat".
void main() {
  late HelixDb db;
  late String chat;

  setUp(() async {
    db = memoryDb();
    chat = (await directChat(db, 'bob')).id;
  });

  group('watchReactionsSince', () {
    test(
      'reads the reactions of the window only, and follows changes',
      () async {
        final old = await db.messagesDao.insertMessage(
          textMessage(chat, 'm1', sentAt: at(1)),
        );
        final newer = await db.messagesDao.insertMessage(
          textMessage(chat, 'm2', sentAt: at(2)),
        );
        await db.messagesDao.setReaction(
          old.localRowid,
          reactor: 'bob',
          emoji: '👍',
          at: at(3),
        );
        await db.messagesDao.setReaction(
          newer.localRowid,
          reactor: 'bob',
          emoji: '❤️',
          at: at(4),
        );

        final stream = db.messagesDao.watchReactionsSince(chat, newer.sortKey);
        final seen = <List<String>>[];
        final sub = stream.listen(
          (rows) => seen.add([for (final r in rows) r.emoji]),
        );
        addTearDown(sub.cancel);
        await pumpEventQueue();
        expect(seen.last, ['❤️']);

        await db.messagesDao.setReaction(
          newer.localRowid,
          reactor: 'carol',
          emoji: '😂',
          at: at(5),
        );
        await pumpEventQueue();
        expect(seen.last, ['❤️', '😂']);
      },
    );

    test('ignores other conversations', () async {
      final other = (await directChat(db, 'carol')).id;
      final theirs = await db.messagesDao.insertMessage(
        textMessage(other, 'x1', sentAt: at(1), sender: 'carol'),
      );
      await db.messagesDao.setReaction(
        theirs.localRowid,
        reactor: 'carol',
        emoji: '🙏',
        at: at(2),
      );
      final rows = await db.messagesDao
          .watchReactionsSince(chat, SortKey.of(at(0), 'a'))
          .first;
      expect(rows, isEmpty);
    });
  });

  group('clearConversation', () {
    test(
      'removes the messages, keeps the chat and resets its summary',
      () async {
        await db.messagesDao.insertMessage(
          textMessage(chat, 'm1', sentAt: at(1)),
        );
        await db.messagesDao.insertMessage(
          textMessage(chat, 'm2', sentAt: at(2)),
        );
        final other = (await directChat(db, 'carol')).id;
        await db.messagesDao.insertMessage(
          textMessage(other, 'x1', sentAt: at(3), sender: 'carol'),
        );

        expect(await db.messagesDao.clearConversation(chat), 2);

        final cleared = (await db.conversationsDao.byId(chat))!;
        expect(cleared.lastMessagePreview, isNull);
        expect(cleared.unreadCount, 0);
        expect((await db.messagesDao.pageOlder(chat)).messages, isEmpty);
        // The other chat is untouched.
        expect((await db.conversationsDao.byId(other))!.unreadCount, 1);
      },
    );
  });
}
