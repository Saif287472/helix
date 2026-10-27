import 'dart:convert';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'support.dart';

/// An edited message keeps its earlier versions, newest first.
void main() {
  late HelixDb db;
  late ConversationRow chat;
  setUp(() async {
    db = memoryDb();
    chat = await directChat(db, 'bob');
  });

  Future<MessageRow> sent(String id, String body) => db.messagesDao
      .insertMessage(textMessage(chat.id, id, sentAt: at(1), body: body));

  Future<MessageRow> reload(MessageRow row) async =>
      (await db.messagesDao.byRowid(row.localRowid))!;

  test('a message never edited has no revisions', () async {
    final row = await sent('a', 'first');
    expect(revisionsOf(row), isEmpty);
  });

  test(
    'each edit keeps the text it replaced, newest first, with its time',
    () async {
      final row = await sent('a', 'first');
      await db.messagesDao.editMessage(
        row.localRowid,
        body: 'second',
        editedAt: at(60),
      );
      await db.messagesDao.editMessage(
        row.localRowid,
        body: 'third',
        editedAt: at(120),
      );

      final now = await reload(row);
      expect(now.body, 'third');
      final revisions = revisionsOf(now);
      expect([for (final r in revisions) r.body], ['second', 'first']);
      expect(revisions.first.at, at(60), reason: 'when "second" was written');
      expect(revisions.last.at, at(1), reason: 'the message\'s own time');
    },
  );

  test('an edit that changes nothing adds nothing', () async {
    final row = await sent('a', 'same');
    await db.messagesDao.editMessage(
      row.localRowid,
      body: 'same',
      editedAt: at(60),
    );
    expect(revisionsOf(await reload(row)), isEmpty);
  });

  test(
    'other payload fields survive, and only the newest ten are kept',
    () async {
      final row = await sent('a', 'v0');
      await db.messagesDao.updatePayload(
        row.localRowid,
        jsonEncode({'mentions': []}),
      );
      for (var i = 1; i <= 12; i++) {
        await db.messagesDao.editMessage(
          row.localRowid,
          body: 'v$i',
          editedAt: at(i * 10),
        );
      }
      final now = await reload(row);
      expect(jsonDecode(now.payload!)['mentions'], isEmpty);
      final revisions = revisionsOf(now);
      expect(revisions, hasLength(MessagesDao.maxRevisions));
      expect(revisions.first.body, 'v11');
      expect(revisions.last.body, 'v2', reason: 'v0 and v1 fell off');
    },
  );

  test('a payload handed in (a restore) is kept as it comes', () async {
    final row = await sent('a', 'first');
    final restored = jsonEncode({
      'revisions': [
        {'at': 5000, 'body': 'older'},
      ],
    });
    await db.messagesDao.editMessage(
      row.localRowid,
      body: 'second',
      payload: restored,
      editedAt: at(60),
    );
    expect([for (final r in revisionsOf(await reload(row))) r.body], ['older']);
  });

  test('delete for everyone takes the revisions with the text', () async {
    final row = await sent('a', 'secret');
    await db.messagesDao.editMessage(
      row.localRowid,
      body: 'fixed',
      editedAt: at(60),
    );
    await db.messagesDao.deleteForEveryone(row.localRowid, deletedAt: at(120));
    final gone = await reload(row);
    expect(gone.payload, isNull);
    expect(revisionsOf(gone), isEmpty);
  });

  test('a damaged payload reads as no revisions', () async {
    final row = await sent('a', 'x');
    await db.messagesDao.updatePayload(row.localRowid, '{not json');
    expect(revisionsOf(await reload(row)), isEmpty);
    // And an edit on top of it still works.
    await db.messagesDao.editMessage(
      row.localRowid,
      body: 'y',
      editedAt: at(60),
    );
    expect([for (final r in revisionsOf(await reload(row))) r.body], ['x']);
  });
}
