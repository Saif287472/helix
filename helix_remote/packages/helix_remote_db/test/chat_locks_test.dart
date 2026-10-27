import 'dart:typed_data';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Schema 8: a locked chat is out of the list and out of everything that
/// reads across chats, and still readable inside itself.
void main() {
  late HelixDb db;
  late ConversationRow open;
  late ConversationRow secret;
  setUp(() async {
    db = memoryDb();
    open = await directChat(db, 'bob');
    secret = await directChat(db, 'cara');
  });

  Future<MessageRow> say(ConversationRow c, String id, String body, int s) =>
      db.messagesDao.insertMessage(
        textMessage(c.id, id, sentAt: at(s), body: body),
        media: const [],
      );

  Future<void> lock() => db.conversationsDao.setLocked(secret.id, at(100));

  test(
    'a locked chat leaves the list and the archive, and shows in Locked',
    () async {
      await lock();
      expect(
        [
          for (final c in await db.conversationsDao.watchList().first)
            c.conversation.id,
        ],
        [open.id],
      );
      await db.conversationsDao.setArchived(secret.id, true);
      expect(
        await db.conversationsDao.watchList(archived: true).first,
        isEmpty,
      );
      expect(
        [
          for (final c in await db.conversationsDao.watchLocked().first)
            c.conversation.id,
        ],
        [secret.id],
      );

      await db.conversationsDao.setLocked(secret.id, null);
      expect(await db.conversationsDao.watchLocked().first, isEmpty);
      expect(
        await db.conversationsDao.watchList(archived: true).first,
        hasLength(1),
      );
    },
  );

  test('its unread messages are not in the badge totals', () async {
    await say(open, 'a', 'one', 1);
    await say(secret, 'b', 'two', 2);
    expect((await db.conversationsDao.watchUnreadTotals().first).messages, 2);
    await lock();
    expect((await db.conversationsDao.watchUnreadTotals().first).messages, 1);
  });

  test(
    'a search of everything skips it; a search inside it does not',
    () async {
      await say(open, 'a', 'holiday plans', 1);
      await say(secret, 'b', 'holiday surprise', 2);
      expect(await db.messagesDao.search('holiday'), hasLength(2));
      await lock();
      expect(
        [for (final m in await db.messagesDao.search('holiday')) m.messageId],
        ['a'],
      );
      expect(
        [
          for (final m in await db.messagesDao.search(
            'holiday',
            conversationId: secret.id,
          ))
            m.messageId,
        ],
        ['b'],
      );
    },
  );

  test('its starred messages are not in the starred list', () async {
    final a = await say(open, 'a', 'one', 1);
    final b = await say(secret, 'b', 'two', 2);
    await db.messagesDao.setStarred(a.localRowid, at(10));
    await db.messagesDao.setStarred(b.localRowid, at(11));
    expect(await db.messagesDao.watchStarred().first, hasLength(2));
    await lock();
    expect(
      [for (final m in await db.messagesDao.watchStarred().first) m.messageId],
      ['a'],
    );
  });

  test('its GIFs are not in the GIF tray', () async {
    Future<void> gif(MessageRow m, int digest) => db
        .into(db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            messageRowid: m.localRowid,
            position: 0,
            kind: 'gif',
            mediaId: 'media-${m.localRowid}',
            mediaKey: Uint8List(32),
            digest: Uint8List.fromList(List.filled(32, digest)),
            mime: 'image/gif',
            size: 10,
            localPath: Value('/g/$digest.gif'),
            transfer: AttachmentTransfer.ready,
          ),
        );
    await gif(await say(open, 'a', 'one', 1), 1);
    await gif(await say(secret, 'b', 'two', 2), 2);
    expect(await db.messagesDao.recentGifs(), hasLength(2));
    await lock();
    expect(
      [for (final g in await db.messagesDao.recentGifs()) g.localPath],
      ['/g/1.gif'],
    );
  });
}
