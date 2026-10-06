import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Watch queries: the chat list, a conversation page and unread totals.
void main() {
  late HelixDb db;

  setUp(() => db = memoryDb());

  test('the chat list orders pinned chats first, then by activity', () async {
    final bob = (await directChat(db, 'bob')).id;
    final carol = (await directChat(db, 'carol')).id;
    final dave = (await directChat(db, 'dave')).id;
    final list = collect(db.conversationsDao.watchList());

    await db.messagesDao.insertMessage(textMessage(bob, 'b1', sentAt: at(1)));
    await db.messagesDao.insertMessage(
      textMessage(carol, 'c1', sentAt: at(2), sender: 'carol'),
    );
    await eventually(
      () =>
          list.isNotEmpty &&
          list.last.first.conversation.id == carol &&
          list.last[1].conversation.id == bob,
    );
    // dave has no messages and was created at t0, before both.
    expect(list.last.map((i) => i.conversation.id), [carol, bob, dave]);
    expect(list.last.first.lastMessage!.messageId, 'c1');
    expect(list.last.last.lastMessage, isNull);

    await db.conversationsDao.setPinned(dave, at(3));
    await eventually(() => list.last.first.conversation.id == dave);
    expect(list.last.map((i) => i.conversation.id), [dave, carol, bob]);

    await db.conversationsDao.setArchived(carol, true);
    await eventually(() => list.last.length == 2);
    expect(list.last.map((i) => i.conversation.id), [dave, bob]);
    final archived = await db.conversationsDao.watchList(archived: true).first;
    expect(archived.single.conversation.id, carol);
  });

  test('a conversation page emits on inserts, edits and deletes', () async {
    final chat = (await directChat(db, 'bob')).id;
    final page = collect(db.messagesDao.watchLatest(chat, limit: 3));
    await eventually(() => page.isNotEmpty);
    expect(page.last, isEmpty);

    for (var i = 1; i <= 4; i++) {
      await db.messagesDao.insertMessage(
        textMessage(chat, 'm$i', sentAt: at(i)),
      );
    }
    await eventually(
      () => page.last.map((m) => m.messageId).join(',') == 'm2,m3,m4',
    );

    final m4 = page.last.last;
    await db.messagesDao.editMessage(
      m4.localRowid,
      body: 'edited',
      editedAt: at(5),
    );
    await eventually(() => page.last.last.body == 'edited');

    await db.messagesDao.removeMessages([m4.localRowid]);
    await eventually(
      () => page.last.map((m) => m.messageId).join(',') == 'm1,m2,m3',
    );

    // A window the user scrolled back to stays live too.
    final m2 = (await db.messagesDao.find('m2', sender: 'bob'))!;
    final window = collect(db.messagesDao.watchFrom(chat, m2.sortKey));
    await eventually(() => window.isNotEmpty);
    expect(window.last.map((m) => m.messageId), ['m2', 'm3']);
  });

  test('unread totals follow writes and reads across chats', () async {
    final bob = (await directChat(db, 'bob')).id;
    final carol = (await directChat(db, 'carol')).id;
    final totals = collect(db.conversationsDao.watchUnreadTotals());
    await eventually(() => totals.isNotEmpty);
    expect(totals.last, UnreadTotals.zero);

    await db.messagesDao.insertMessage(textMessage(bob, 'b1', sentAt: at(1)));
    final b2 = await db.messagesDao.insertMessage(
      textMessage(bob, 'b2', sentAt: at(2), mentionsMe: true),
    );
    await db.messagesDao.insertMessage(
      textMessage(carol, 'c1', sentAt: at(3), sender: 'carol'),
    );
    const expected = UnreadTotals(messages: 3, conversations: 2, mentions: 1);
    await eventually(() => totals.last == expected);

    await db.messagesDao.markReadUpTo(bob, b2.sortKey);
    const afterRead = UnreadTotals(messages: 1, conversations: 1, mentions: 0);
    await eventually(() => totals.last == afterRead);

    await db.conversationsDao.setArchived(carol, true);
    await eventually(() => totals.last == UnreadTotals.zero);
  });

  test('typed settings read defaults, round-trip and emit', () async {
    const receipts = Setting<bool>('privacy.read_receipts', true);
    const ringtone = Setting<String?>('calls.ringtone', null);
    const size = Setting.enumeration(
      'chats.text_size',
      _TextSize.values,
      _TextSize.normal,
    );
    final settings = db.settingsDao;

    expect(await settings.get(receipts), isTrue);
    expect(await settings.get(ringtone), isNull);
    final watched = collect(settings.watch(receipts));
    await eventually(() => watched.isNotEmpty);

    await settings.set(receipts, false);
    await settings.set(ringtone, 'chime');
    await settings.set(size, _TextSize.large);
    expect(await settings.get(receipts), isFalse);
    expect(await settings.get(ringtone), 'chime');
    expect(await settings.get(size), _TextSize.large);
    await eventually(() => watched.last == false);

    // A value of the wrong shape or an unknown enum name reads as default.
    await db.customStatement(
      "UPDATE settings SET value = '\"huge\"' WHERE key = 'chats.text_size'",
    );
    expect(await settings.get(size), _TextSize.normal);
    expect(receipts.decode('not json'), isTrue);

    await settings.reset(receipts);
    expect(await settings.get(receipts), isTrue);
    await eventually(() => watched.last == true);
    expect(watched, [true, false, true]);
  });
}

enum _TextSize { small, normal, large }
