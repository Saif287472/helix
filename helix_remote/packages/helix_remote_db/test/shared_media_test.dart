import 'dart:typed_data';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The two queries behind the shared media, documents and links page.
void main() {
  late HelixDb db;
  late String chat;

  setUp(() async {
    db = memoryDb();
    chat = (await directChat(db, 'bob')).id;
  });

  AttachmentsCompanion item(String id, String kind, {String? name}) =>
      AttachmentsCompanion.insert(
        messageRowid: 0,
        position: 0,
        kind: kind,
        mediaId: id,
        mediaKey: Uint8List(32),
        digest: Uint8List(32),
        mime: kind == 'image' ? 'image/jpeg' : 'application/pdf',
        size: 1000,
        name: Value(name),
        transfer: AttachmentTransfer.remote,
      );

  test(
    'attachments of one chat, newest message first, no voice notes',
    () async {
      await db.messagesDao.insertMessage(
        textMessage(chat, 'm1', sentAt: at(1)),
        media: [item('a', 'image')],
      );
      await db.messagesDao.insertMessage(
        textMessage(chat, 'm2', sentAt: at(2)),
        media: [
          item('b', 'image'),
          item('c', 'file', name: 'plan.pdf'),
        ],
      );
      await db.messagesDao.insertMessage(
        textMessage(chat, 'm3', sentAt: at(3)),
        media: [item('v', 'voice_note')],
      );
      final other = (await directChat(db, 'carol')).id;
      await db.messagesDao.insertMessage(
        textMessage(other, 'x1', sentAt: at(4), sender: 'carol'),
        media: [item('z', 'image')],
      );

      final shared = await db.messagesDao.watchSharedAttachments(chat).first;
      expect([for (final s in shared) s.attachment.mediaId], ['b', 'c', 'a']);
      expect(shared.first.sentAt, at(2));
    },
  );

  test('messages with a link: newest first, deleted ones left out', () async {
    await db.messagesDao.insertMessage(
      textMessage(chat, 'm1', sentAt: at(1), body: 'see https://example.org/a'),
    );
    await db.messagesDao.insertMessage(
      textMessage(chat, 'm2', sentAt: at(2), body: 'no link here'),
    );
    final gone = await db.messagesDao.insertMessage(
      textMessage(chat, 'm3', sentAt: at(3), body: 'http://example.org/gone'),
    );
    await db.messagesDao.insertMessage(
      textMessage(chat, 'm4', sentAt: at(4), body: 'http://example.org/b'),
    );
    await db.messagesDao.deleteForEveryone(gone.localRowid, deletedAt: at(5));

    final rows = await db.messagesDao.watchMessagesWithLinks(chat).first;
    expect([for (final r in rows) r.messageId], ['m4', 'm1']);
  });
}
