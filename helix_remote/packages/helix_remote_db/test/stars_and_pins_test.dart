import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Schema 6: a starred message, a pinned message and a favourite chat.
void main() {
  late HelixDb db;
  late ConversationRow chat;
  late ConversationRow other;
  setUp(() async {
    db = memoryDb();
    chat = await directChat(db, 'bob');
    other = await directChat(db, 'cara');
  });

  Future<MessageRow> add(ConversationRow c, String id, int seconds) =>
      db.messagesDao.insertMessage(
        textMessage(c.id, id, sentAt: at(seconds), body: 'text $id'),
      );

  group('starred messages', () {
    test('start unstarred, and list newest star first across chats', () async {
      final a = await add(chat, 'a', 1);
      final b = await add(other, 'b', 2);
      final c = await add(chat, 'c', 3);
      expect(a.starredAt, isNull);
      expect(await db.messagesDao.watchStarred().first, isEmpty);

      await db.messagesDao.setStarred(a.localRowid, at(10));
      await db.messagesDao.setStarred(b.localRowid, at(20));
      await db.messagesDao.setStarred(c.localRowid, at(15));
      final starred = await db.messagesDao.watchStarred().first;
      expect([for (final m in starred) m.messageId], ['b', 'c', 'a']);

      await db.messagesDao.setStarred(c.localRowid, null);
      expect(
        [
          for (final m in await db.messagesDao.watchStarred().first)
            m.messageId,
        ],
        ['b', 'a'],
      );
    });

    test(
      'a message deleted for everyone loses its star and cannot get one',
      () async {
        final a = await add(chat, 'a', 1);
        await db.messagesDao.setStarred(a.localRowid, at(10));
        await db.messagesDao.deleteForEveryone(a.localRowid, deletedAt: at(20));
        expect((await db.messagesDao.byRowid(a.localRowid))!.starredAt, isNull);
        expect(await db.messagesDao.watchStarred().first, isEmpty);

        await db.messagesDao.setStarred(a.localRowid, at(30));
        expect((await db.messagesDao.byRowid(a.localRowid))!.starredAt, isNull);
      },
    );

    test('a message removed from this device leaves the list', () async {
      final a = await add(chat, 'a', 1);
      await db.messagesDao.setStarred(a.localRowid, at(10));
      await db.messagesDao.removeMessages([a.localRowid]);
      expect(await db.messagesDao.watchStarred().first, isEmpty);
    });
  });

  group('pinned messages', () {
    test('are listed per chat, newest pin first', () async {
      final a = await add(chat, 'a', 1);
      final b = await add(chat, 'b', 2);
      final c = await add(other, 'c', 3);
      await db.messagesDao.setPinned(a.localRowid, at(10));
      await db.messagesDao.setPinned(b.localRowid, at(20));
      await db.messagesDao.setPinned(c.localRowid, at(30));

      expect(
        [for (final m in await db.messagesDao.pinnedIn(chat.id)) m.messageId],
        ['b', 'a'],
      );
      expect(
        [
          for (final m in await db.messagesDao.watchPinned(other.id).first)
            m.messageId,
        ],
        ['c'],
      );

      await db.messagesDao.setPinned(b.localRowid, null);
      expect(
        [for (final m in await db.messagesDao.pinnedIn(chat.id)) m.messageId],
        ['a'],
      );
    });

    test('a message deleted for everyone is unpinned and stays so', () async {
      final a = await add(chat, 'a', 1);
      await db.messagesDao.setPinned(a.localRowid, at(10));
      await db.messagesDao.deleteForEveryone(a.localRowid, deletedAt: at(20));
      expect(await db.messagesDao.pinnedIn(chat.id), isEmpty);
      await db.messagesDao.setPinned(a.localRowid, at(30));
      expect(await db.messagesDao.pinnedIn(chat.id), isEmpty);
    });
  });

  test('a chat is made a favourite and unmade', () async {
    expect(chat.favouriteAt, isNull);
    await db.conversationsDao.setFavourite(chat.id, at(5));
    expect((await db.conversationsDao.byId(chat.id))!.favouriteAt, at(5));
    expect((await db.conversationsDao.byId(other.id))!.favouriteAt, isNull);
    await db.conversationsDao.setFavourite(chat.id, null);
    expect((await db.conversationsDao.byId(chat.id))!.favouriteAt, isNull);
  });
}
