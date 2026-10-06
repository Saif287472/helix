import 'dart:typed_data';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'support.dart';

/// DAO methods added for the engine (Phase C3b): wipe, ordered outbox
/// claims, the queue change mark, payload updates, the next expiry and the
/// people list.
void main() {
  group('wipeAll', () {
    test('empties every table, the FTS index included, and the database is '
        'usable afterwards', () async {
      final db = memoryDb();
      final chat = await directChat(db, 'bob');
      await db.messagesDao.insertMessage(
        textMessage(chat.id, 'm1', sentAt: at(1), body: 'findable words'),
      );
      await db.outboxDao.enqueue(
        kind: 'send_content',
        idempotencyKey: 'k',
        payload: '{}',
        conversationId: chat.id,
        now: t0,
      );
      await db.settingsDao.set(const Setting<int>('x', 0), 5, now: t0);
      await db.peopleDao.upsertPerson(
        PeopleCompanion.insert(accountId: 'bob', updatedAt: t0),
      );
      await db.inboxDao.advanceCursor(processedSeq: 9, now: t0);
      expect(await db.messagesDao.search('findable'), hasLength(1));

      await db.wipeAll();

      expect(await db.messagesDao.search('findable'), isEmpty);
      expect(await db.conversationsDao.byId(chat.id), isNull);
      expect(await db.outboxDao.byId(1), isNull);
      expect(await db.peopleDao.byAccount('bob'), isNull);
      expect(await db.inboxDao.cursor(), isNull);
      expect(await db.settingsDao.get(const Setting<int>('x', 0)), 0);
      // Still a working database.
      final again = await directChat(db, 'carol');
      await db.messagesDao.insertMessage(
        textMessage(again.id, 'm2', sentAt: at(2), body: 'second life'),
      );
      expect(await db.messagesDao.search('second'), hasLength(1));
    });

    test('empties the group, call-log and transfer tables too', () async {
      final db = memoryDb();
      final chat = await directChat(db, 'bob');
      final message = await db.messagesDao.insertMessage(
        textMessage(chat.id, 'm1', sentAt: at(1)),
        media: [
          AttachmentsCompanion.insert(
            messageRowid: 0,
            position: 0,
            kind: 'image',
            mediaId: 'media-1',
            mediaKey: Uint8List(32),
            digest: Uint8List(32),
            mime: 'image/jpeg',
            size: 10,
            transfer: AttachmentTransfer.remote,
          ),
        ],
      );
      final attachment = (await db.messagesDao.attachmentsFor([
        message.localRowid,
      ])).single;
      await db.groupsDao.upsert(
        GroupsCompanion.insert(
          id: 'g1',
          title: 'Team',
          role: 'owner',
          createdAt: t0,
        ),
      );
      await db.groupsDao.replaceRoster('g1', [
        const GroupMemberRow(
          groupId: 'g1',
          accountId: 'alice',
          qualifiedId: 'alice',
          role: 'owner',
          isSelf: true,
          devicesJson: '["a1"]',
        ),
      ], epoch: 1);
      await db.groupsDao.addBan('g1', 'mallory', now: t0);
      await db.callsDao.start(
        CallLogCompanion.insert(
          callId: 'c1',
          peerAccountId: 'bob',
          kind: 'direct',
          direction: 'incoming',
          state: 'ended',
          startedAt: t0,
        ),
      );
      await db.transfersDao.enqueueDownload(
        attachmentRowid: attachment.id,
        mediaId: 'media-1',
        mediaKey: Uint8List(32),
        size: 10,
        now: t0,
      );
      await db.transfersDao.addChunk(
        transferId: 't1',
        sequence: 0,
        payload: Uint8List(4),
        total: 2,
        isFinal: false,
        now: t0,
      );

      await db.wipeAll();

      expect(await db.groupsDao.byId('g1'), isNull);
      expect(await db.groupsDao.members('g1'), isEmpty);
      expect(await db.groupsDao.bans('g1'), isEmpty);
      expect(await db.callsDao.recent(), isEmpty);
      expect(await db.transfersDao.pending(), isEmpty);
      expect(await db.transfersDao.chunks('t1'), isEmpty);
    });
  });

  group('outbox claims in order', () {
    Future<void> enqueue(HelixDb db, String key, String? chat) =>
        db.outboxDao.enqueue(
          kind: 'k',
          idempotencyKey: key,
          payload: '{}',
          conversationId: chat,
          now: t0,
        );

    test('one op per conversation at a time, oldest first; chats without '
        'one never wait', () async {
      final db = memoryDb();
      final a = await directChat(db, 'a');
      final b = await directChat(db, 'b');
      await enqueue(db, 'a1', a.id);
      await enqueue(db, 'a2', a.id);
      await enqueue(db, 'b1', b.id);
      await enqueue(db, 'n1', null);
      await enqueue(db, 'n2', null);

      final first = await db.outboxDao.claimDueOrdered(
        at(1),
        leaseUntil: at(60),
      );
      expect(first.map((o) => o.idempotencyKey), ['a1', 'b1', 'n1', 'n2']);
      // a2 waits while a1 is queued, in flight or backing off.
      expect(
        await db.outboxDao.claimDueOrdered(at(2), leaseUntil: at(61)),
        isEmpty,
      );
      await db.outboxDao.reschedule(
        first.first.id,
        nextAttemptAt: at(100),
        errorCode: 'unavailable',
      );
      expect(
        await db.outboxDao.claimDueOrdered(at(3), leaseUntil: at(62)),
        isEmpty,
        reason: 'a1 is backing off, a2 must not overtake it',
      );
      await db.outboxDao.complete(first.first.id);
      final next = await db.outboxDao.claimDueOrdered(
        at(4),
        leaseUntil: at(63),
      );
      expect(next.map((o) => o.idempotencyKey), ['a2']);
    });

    test('a failed op does not hold up its chat, and a crashed worker\'s '
        'lease runs out', () async {
      final db = memoryDb();
      final a = await directChat(db, 'a');
      await enqueue(db, 'a1', a.id);
      await enqueue(db, 'a2', a.id);
      final claimed = await db.outboxDao.claimDueOrdered(
        at(1),
        leaseUntil: at(10),
      );
      expect(claimed.map((o) => o.idempotencyKey), ['a1']);
      // The worker dies. Before the lease ends nothing is claimable...
      expect(
        await db.outboxDao.claimDueOrdered(at(5), leaseUntil: at(20)),
        isEmpty,
      );
      // ...afterwards a1 is claimed again.
      final again = await db.outboxDao.claimDueOrdered(
        at(11),
        leaseUntil: at(30),
      );
      expect(again.map((o) => o.idempotencyKey), ['a1']);
      await db.outboxDao.fail(again.single.id, errorCode: 'forbidden');
      final after = await db.outboxDao.claimDueOrdered(
        at(12),
        leaseUntil: at(40),
      );
      expect(after.map((o) => o.idempotencyKey), ['a2']);
    });

    test('the queue mark changes when the count does not', () async {
      final db = memoryDb();
      final a = await directChat(db, 'a');
      await enqueue(db, 'a1', a.id);
      final marks = <String>[];
      final sub = db.outboxDao.watchQueueMark().listen(marks.add);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      // One op completes as another is enqueued: the count stays 1.
      await db.transaction(() async {
        await db.outboxDao.complete(1);
        await enqueue(db, 'a2', a.id);
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();
      expect(marks, hasLength(2));
      expect(marks.toSet(), hasLength(2));
    });
  });

  group('messages', () {
    test('updatePayload does not mark the message edited', () async {
      final db = memoryDb();
      final chat = await directChat(db, 'bob');
      final row = await db.messagesDao.insertMessage(
        textMessage(chat.id, 'm1', sentAt: at(1), body: 'poll'),
      );
      await db.messagesDao.updatePayload(row.localRowid, '{"votes":{}}');
      final after = (await db.messagesDao.byRowid(row.localRowid))!;
      expect(after.payload, '{"votes":{}}');
      expect(after.editedAt, isNull);
      expect(after.body, 'poll');
    });

    test('nextExpiryAt is the soonest deadline', () async {
      final db = memoryDb();
      final chat = await directChat(db, 'bob');
      expect(await db.messagesDao.nextExpiryAt(), isNull);
      final one = await db.messagesDao.insertMessage(
        textMessage(chat.id, 'm1', sentAt: at(1), expireSeconds: 100),
      );
      final two = await db.messagesDao.insertMessage(
        textMessage(chat.id, 'm2', sentAt: at(2), expireSeconds: 10),
      );
      expect(
        await db.messagesDao.nextExpiryAt(),
        isNull,
        reason: 'timers start at first display',
      );
      await db.messagesDao.markDisplayed(one.localRowid, at(50));
      await db.messagesDao.markDisplayed(two.localRowid, at(60));
      expect(await db.messagesDao.nextExpiryAt(), at(70));
    });
  });

  test('the people list is in display order', () async {
    final db = memoryDb();
    Future<void> person(
      String id, {
      String? phonebook,
      String? nickname,
      String? phone,
      String? helix,
    }) => db.peopleDao.upsertPerson(
      PeopleCompanion.insert(
        accountId: id,
        phonebookName: Value(phonebook),
        nickname: Value(nickname),
        phoneNumber: Value(phone),
        helixName: Value(helix),
        updatedAt: t0,
      ),
    );
    await person('1', helix: 'zed');
    await person('2', phonebook: 'Mum');
    await person('3', nickname: 'Bro');
    await person('4', phone: '+88017');
    expect((await db.peopleDao.all()).map((p) => p.accountId), [
      '4', // +88017
      '3', // Bro
      '2', // Mum
      '1', // zed
    ]);
    final seen = await db.peopleDao.watchAll().first;
    expect(seen, hasLength(4));
  });
}
