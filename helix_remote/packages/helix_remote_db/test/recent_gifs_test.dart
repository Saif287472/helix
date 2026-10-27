import 'dart:typed_data';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The GIFs a person already has on the phone, for the GIF tray.
void main() {
  late HelixDb db;
  late ConversationRow chat;
  late ConversationRow other;
  setUp(() async {
    db = memoryDb();
    chat = await directChat(db, 'bob');
    other = await directChat(db, 'cara');
  });

  Future<MessageRow> message(ConversationRow c, String id, int at0) => db
      .messagesDao
      .insertMessage(textMessage(c.id, id, sentAt: at(at0)), media: const []);

  Future<void> attach(
    MessageRow m, {
    required String kind,
    String? localPath,
    int digest = 1,
  }) async {
    await db
        .into(db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            messageRowid: m.localRowid,
            position: 0,
            kind: kind,
            mediaId: 'media-${m.localRowid}',
            mediaKey: Uint8List(32),
            digest: Uint8List.fromList(List.filled(32, digest)),
            mime: kind == 'gif' ? 'image/gif' : 'image/jpeg',
            size: 10,
            localPath: Value(localPath),
            transfer: AttachmentTransfer.ready,
          ),
        );
  }

  test(
    'lists GIFs that are on the device, newest first, across chats',
    () async {
      final a = await message(chat, 'a', 1);
      final b = await message(other, 'b', 2);
      final c = await message(chat, 'c', 3);
      await attach(a, kind: 'gif', localPath: '/g/a.gif', digest: 1);
      await attach(b, kind: 'gif', localPath: '/g/b.gif', digest: 2);
      await attach(c, kind: 'image', localPath: '/g/c.jpg', digest: 3);
      expect(
        [for (final g in await db.messagesDao.recentGifs()) g.localPath],
        ['/g/b.gif', '/g/a.gif'],
        reason: 'a photo is not a GIF',
      );
    },
  );

  test(
    'leaves out a GIF not downloaded, and one deleted for everyone',
    () async {
      final a = await message(chat, 'a', 1);
      final b = await message(chat, 'b', 2);
      final c = await message(chat, 'c', 3);
      await attach(a, kind: 'gif', localPath: null, digest: 1);
      await attach(b, kind: 'gif', localPath: '/g/b.gif', digest: 2);
      await attach(c, kind: 'gif', localPath: '/g/c.gif', digest: 3);
      await db.messagesDao.deleteForEveryone(c.localRowid, deletedAt: at(10));
      expect(
        [for (final g in await db.messagesDao.recentGifs()) g.localPath],
        ['/g/b.gif'],
      );
    },
  );

  test('the same GIF in two chats is one', () async {
    final a = await message(chat, 'a', 1);
    final b = await message(other, 'b', 2);
    await attach(a, kind: 'gif', localPath: '/g/old.gif', digest: 7);
    await attach(b, kind: 'gif', localPath: '/g/new.gif', digest: 7);
    expect(
      [for (final g in await db.messagesDao.recentGifs()) g.localPath],
      ['/g/new.gif'],
    );
  });

  test('is capped', () async {
    for (var i = 0; i < 5; i++) {
      final m = await message(chat, 'm$i', i + 1);
      await attach(m, kind: 'gif', localPath: '/g/$i.gif', digest: i + 1);
    }
    expect(await db.messagesDao.recentGifs(limit: 3), hasLength(3));
  });
}
