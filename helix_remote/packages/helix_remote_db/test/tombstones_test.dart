import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'support.dart';

/// What this device deleted, for the backup importer (AUD-12q-1).
void main() {
  late HelixDb db;
  late TombstonesDao tombstones;
  late String chat;

  setUp(() async {
    db = memoryDb();
    addTearDown(db.close);
    tombstones = db.tombstonesDao;
    chat = (await directChat(db, 'bob')).id;
  });

  test('a message is recorded by its wire id and its author', () async {
    final bobs = await db.messagesDao.insertMessage(
      textMessage(chat, 'm1', sentAt: at(1)),
    );
    final mine = await db.messagesDao.insertMessage(
      textMessage(chat, 'm2', sentAt: at(2), sender: 'me', outgoing: true),
    );
    await tombstones.recordMessages([bobs.localRowid, mine.localRowid]);
    // Asking again, or for a row that is not there, records nothing new.
    await tombstones.recordMessages([bobs.localRowid, 999]);
    await tombstones.recordMessages(const []);

    expect(await tombstones.messageDeleted('m1', author: 'bob'), isTrue);
    expect(await tombstones.messageDeleted('m2', author: 'me'), isTrue);
    expect(
      await tombstones.messageDeleted('m1', author: 'carol'),
      isFalse,
      reason: 'another author\'s message with the same id is not this one',
    );
    expect(await tombstones.conversationDeleted(chat), isFalse);
    final rows = await db.select(db.deleteTombstones).get();
    expect(rows, hasLength(2));
  });

  test('a cleared or deleted chat is recorded once', () async {
    await tombstones.recordConversation(chat);
    await tombstones.recordConversation(chat);
    expect(await tombstones.conversationDeleted(chat), isTrue);
    expect(await tombstones.conversationDeleted('direct:carol'), isFalse);
    expect(
      await tombstones.messageDeleted(chat, author: ''),
      isFalse,
      reason: 'a chat is not a message',
    );
    expect(await db.select(db.deleteTombstones).get(), hasLength(1));
  });

  test('a set past one statement\'s parameters is recorded whole', () async {
    final rowids = <int>[];
    for (var i = 0; i < 1200; i++) {
      rowids.add(
        (await db.messagesDao.insertMessage(
          textMessage(chat, 'm$i', sentAt: at(i)),
        )).localRowid,
      );
    }
    await tombstones.recordMessages(rowids);
    expect(await db.select(db.deleteTombstones).get(), hasLength(1200));
    expect(await tombstones.messageDeleted('m1199', author: 'bob'), isTrue);
  });

  test('a sign-out forgets them', () async {
    await tombstones.recordConversation(chat);
    await db.wipeAll();
    expect(await db.select(db.deleteTombstones).get(), isEmpty);
  });
}
