import 'dart:typed_data';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The DAO methods the media transfer queue (Phase C4-M) added: held outbox
/// ops, lease renewal and release, rescheduling, thumbnail jobs, and the
/// attachment queries behind progress, view-once and the file sweep.
void main() {
  late HelixDb db;

  Uint8List bytes(int fill, [int length = 32]) =>
      Uint8List.fromList(List.filled(length, fill));

  Future<(MessageRow, List<AttachmentRow>)> mediaMessage(
    String id, {
    int items = 1,
    bool outgoing = false,
    MessageStatus? status,
    ViewOnceState? viewOnce,
  }) async {
    final chat = await directChat(db, 'bob');
    final message = await db.messagesDao.insertMessage(
      MessagesCompanion.insert(
        messageId: id,
        conversationId: chat.id,
        sender: outgoing ? 'me' : 'bob',
        outgoing: outgoing,
        sortKey: SortKey.of(at(items), id),
        sentAt: at(items),
        receivedAt: at(items),
        kind: 'media',
        status:
            status ??
            (outgoing ? MessageStatus.pending : MessageStatus.received),
        viewOnceState: viewOnce == null
            ? const Value.absent()
            : Value(viewOnce),
      ),
      media: [
        for (var i = 0; i < items; i++)
          AttachmentsCompanion.insert(
            messageRowid: 0,
            position: 0,
            kind: 'image',
            mediaId: '',
            mediaKey: bytes(7),
            digest: bytes(0),
            mime: 'image/jpeg',
            size: 1000,
            localPath: Value('media/$id-$i.jpg'),
            thumbnailPath: Value('media/$id-$i.thumb'),
            transfer: AttachmentTransfer.uploading,
          ),
      ],
    );
    return (message, await db.messagesDao.attachmentsFor([message.localRowid]));
  }

  setUp(() => db = memoryDb());

  group('held outbox ops', () {
    Future<OutboxOpRow> held(String key, String chat) =>
        db.outboxDao.enqueueHeld(
          kind: 'send_content',
          idempotencyKey: key,
          payload: '{"held":"media"}',
          conversationId: chat,
          now: at(0),
        );

    test('keep their place but are never due', () async {
      final chat = await directChat(db, 'bob');
      final op = await held('m1', chat.id);
      expect(OutboxDao.isHeld(op), isTrue);
      expect(op.state, OutboxState.pending);
      expect((await db.outboxDao.heldOps()).map((o) => o.id), [op.id]);
      expect(
        await db.outboxDao.claimDue(at(1000), leaseUntil: at(2000)),
        isEmpty,
      );
    });

    test('hold back later ops of the same chat, not of others', () async {
      final a = await directChat(db, 'a');
      final b = await directChat(db, 'b');
      await held('m1', a.id);
      Future<void> text(String key, String chat) => db.outboxDao.enqueue(
        kind: 'send_content',
        idempotencyKey: key,
        payload: '{}',
        conversationId: chat,
        now: at(1),
      );
      await text('t-a', a.id);
      await text('t-b', b.id);
      final claimed = await db.outboxDao.claimDueOrdered(
        at(10),
        leaseUntil: at(70),
      );
      expect(claimed.map((o) => o.idempotencyKey), ['t-b']);
    });

    test('release makes it due with its real payload, once', () async {
      final chat = await directChat(db, 'bob');
      final op = await held('m1', chat.id);
      expect(
        await db.outboxDao.release(op.id, payload: '{"real":1}', now: at(5)),
        isTrue,
      );
      final after = (await db.outboxDao.byId(op.id))!;
      expect(after.payload, '{"real":1}');
      expect(OutboxDao.isHeld(after), isFalse);
      expect(after.nextAttemptAt, at(5));
      // A second release (a duplicate completion) changes nothing.
      expect(
        await db.outboxDao.release(op.id, payload: '{"real":2}', now: at(6)),
        isFalse,
      );
      expect((await db.outboxDao.byId(op.id))!.payload, '{"real":1}');
      final claimed = await db.outboxDao.claimDueOrdered(
        at(6),
        leaseUntil: at(70),
      );
      expect(claimed.single.id, op.id);
    });

    test('a failed op can be put on hold again', () async {
      final chat = await directChat(db, 'bob');
      final op = await held('m1', chat.id);
      await db.outboxDao.fail(op.id, errorCode: 'quota_exceeded');
      expect((await db.outboxDao.heldOps()), isEmpty);
      await db.outboxDao.hold(op.id, payload: '{"held":"media"}');
      final after = (await db.outboxDao.byId(op.id))!;
      expect(OutboxDao.isHeld(after), isTrue);
      expect(after.lastError, isNull);
      expect(after.attempts, 0);
    });

    test('the queue mark moves when one is released', () async {
      final chat = await directChat(db, 'bob');
      final op = await held('m1', chat.id);
      final marks = collect(db.outboxDao.watchQueueMark());
      await eventually(() => marks.isNotEmpty);
      await db.outboxDao.release(op.id, payload: '{}', now: at(5));
      await eventually(() => marks.length >= 2);
      expect(marks.last, isNot(marks.first));
    });
  });

  group('transfer jobs', () {
    late int attachment;

    setUp(() async {
      final (_, rows) = await mediaMessage('m1');
      attachment = rows.single.id;
    });

    Future<int> upload() => db.transfersDao.enqueueUpload(
      attachmentRowid: attachment,
      localPath: 'media/m1-0.jpg',
      size: 1000,
      mediaKey: bytes(7),
      now: t0,
    );

    test('claim can be limited to some kinds', () async {
      final id = await upload();
      expect(
        await db.transfersDao.claim(
          at(1),
          lease: const Duration(seconds: 60),
          kinds: {'download', 'thumbnail'},
        ),
        isNull,
      );
      final job = await db.transfersDao.claim(
        at(1),
        lease: const Duration(seconds: 60),
        kinds: {'upload'},
      );
      expect(job!.id, id);
    });

    test('renewLease extends a held lease and refuses a lost one', () async {
      final id = await upload();
      expect(
        await db.transfersDao.renewLease(id, until: at(100)),
        isFalse,
        reason: 'not claimed yet',
      );
      await db.transfersDao.claim(at(1), lease: const Duration(seconds: 10));
      expect(await db.transfersDao.renewLease(id, until: at(100)), isTrue);
      expect((await db.transfersDao.byId(id))!.leaseUntil, at(100));
      // Nobody can claim it while the renewed lease lasts.
      expect(
        await db.transfersDao.claim(at(50), lease: const Duration(seconds: 10)),
        isNull,
      );
      await db.transfersDao.remove(id);
      expect(await db.transfersDao.renewLease(id, until: at(200)), isFalse);
    });

    test('release hands a job back with its progress and no attempt', () async {
      final id = await upload();
      await db.transfersDao.claim(at(1), lease: const Duration(seconds: 60));
      await db.transfersDao.setProgress(id, offset: 4096, mediaId: 'obj');
      await db.transfersDao.release(id, at: at(2));
      final job = (await db.transfersDao.byId(id))!;
      expect(job.state, TransferState.pending);
      expect(job.leaseUntil, isNull);
      expect((job.offset, job.mediaId, job.attempts), (4096, 'obj', 0));
      expect(
        await db.transfersDao.claim(at(3), lease: const Duration(seconds: 60)),
        isNotNull,
      );
    });

    test('release does not revive a finished job', () async {
      final id = await upload();
      await db.transfersDao.markDone(id);
      await db.transfersDao.release(id, at: at(2));
      expect((await db.transfersDao.byId(id))!.state, TransferState.done);
    });

    test(
      'reschedule counts the attempt, keeps progress, never gives up',
      () async {
        final id = await upload();
        await db.transfersDao.claim(at(1), lease: const Duration(seconds: 60));
        await db.transfersDao.setProgress(id, offset: 8192, mediaId: 'obj');
        for (var i = 1; i <= 8; i++) {
          await db.transfersDao.reschedule(
            id,
            nextAttemptAt: at(100 * i),
            code: 'network',
          );
        }
        final job = (await db.transfersDao.byId(id))!;
        expect(job.state, TransferState.pending);
        expect((job.attempts, job.offset, job.lastError), (8, 8192, 'network'));
        expect(job.nextAttemptAt, at(800));
        expect(job.leaseUntil, isNull);
      },
    );

    test('resetProgress forgets the offset and the server object', () async {
      final id = await upload();
      await db.transfersDao.setProgress(id, offset: 4096, mediaId: 'obj');
      await db.transfersDao.resetProgress(id);
      final job = (await db.transfersDao.byId(id))!;
      expect(job.offset, 0);
      expect(job.mediaId, isNull);
    });

    test('a thumbnail job does not replace a download', () async {
      final download = await db.transfersDao.enqueueDownload(
        attachmentRowid: attachment,
        mediaId: 'obj',
        mediaKey: bytes(7),
        size: 1000,
        now: t0,
      );
      final id = await db.transfersDao.enqueueThumbnail(
        attachmentRowid: attachment,
        mediaId: 'thumb',
        mediaKey: bytes(8),
        size: 100,
        now: t0,
      );
      expect(id, download);
      final job = (await db.transfersDao.byId(id))!;
      expect((job.kind, job.mediaId), ('download', 'obj'));
    });

    test(
      'a thumbnail job turns into the download when one is asked for',
      () async {
        final id = await db.transfersDao.enqueueThumbnail(
          attachmentRowid: attachment,
          mediaId: 'thumb',
          mediaKey: bytes(8),
          size: 100,
          now: t0,
        );
        expect((await db.transfersDao.byId(id))!.kind, 'thumbnail');
        await db.transfersDao.markDone(id);
        final again = await db.transfersDao.enqueueDownload(
          attachmentRowid: attachment,
          mediaId: 'obj',
          mediaKey: bytes(7),
          size: 1000,
          now: at(5),
        );
        expect(again, id);
        final job = (await db.transfersDao.byId(id))!;
        expect(
          (job.kind, job.mediaId, job.state),
          ('download', 'obj', TransferState.pending),
        );
      },
    );

    test('live lists everything but done, and can be watched', () async {
      final id = await upload();
      final seen = collect(db.transfersDao.watchLive());
      await eventually(() => seen.isNotEmpty);
      expect(seen.last.map((j) => j.id), [id]);
      await db.transfersDao.fail(
        id,
        code: 'quota_exceeded',
        now: at(1),
        backoff: Duration.zero,
        maxAttempts: 1,
      );
      expect((await db.transfersDao.live()).single.state, TransferState.failed);
      await db.transfersDao.markDone(id);
      expect(await db.transfersDao.live(), isEmpty);
      await eventually(() => seen.last.isEmpty);
    });
  });

  group('attachments', () {
    test('byId, the pointer, the thumbnail', () async {
      final (_, rows) = await mediaMessage('m1');
      final id = rows.single.id;
      expect((await db.messagesDao.attachmentById(id))!.mediaId, '');
      await db.messagesDao.setAttachmentPointer(
        id,
        mediaId: 'obj',
        digest: bytes(5),
      );
      var row = (await db.messagesDao.attachmentById(id))!;
      expect(row.mediaId, 'obj');
      expect(row.digest, orderedEquals(bytes(5)));
      expect(row.thumbnail, isNull);
      await db.messagesDao.setAttachmentThumbnail(id, '{"id":"t"}');
      await db.messagesDao.setAttachmentPointer(
        id,
        mediaId: 'obj2',
        digest: bytes(6),
      );
      row = (await db.messagesDao.attachmentById(id))!;
      expect(row.thumbnail, '{"id":"t"}', reason: 'null leaves it alone');
      expect(await db.messagesDao.attachmentById(9999), isNull);
    });

    test('removeAttachments returns the rows and keeps the message', () async {
      final (message, rows) = await mediaMessage('m1', items: 2);
      final removed = await db.messagesDao.removeAttachments(
        message.localRowid,
      );
      expect(removed.map((r) => r.id), rows.map((r) => r.id));
      expect(
        await db.messagesDao.attachmentsFor([message.localRowid]),
        isEmpty,
      );
      expect(await db.messagesDao.byRowid(message.localRowid), isNotNull);
    });

    test('attachmentPaths lists media and thumbnail files', () async {
      await mediaMessage('m1', items: 2);
      expect(await db.messagesDao.attachmentPaths(), {
        'media/m1-0.jpg',
        'media/m1-0.thumb',
        'media/m1-1.jpg',
        'media/m1-1.thumb',
      });
    });

    test(
      'the attachment count is watchable and drops with the message',
      () async {
        final counts = collect(db.messagesDao.watchAttachmentCount());
        final (message, _) = await mediaMessage('m1', items: 3);
        await eventually(() => counts.contains(3));
        await db.messagesDao.removeMessages([message.localRowid]);
        await eventually(() => counts.last == 0);
      },
    );

    test(
      'view-once media to consume: opened incoming, viewed outgoing',
      () async {
        final (opened, _) = await mediaMessage(
          'm1',
          viewOnce: ViewOnceState.opened,
        );
        await mediaMessage('m2', viewOnce: ViewOnceState.unopened);
        final (viewed, _) = await mediaMessage(
          'm3',
          outgoing: true,
          status: MessageStatus.viewed,
          viewOnce: ViewOnceState.unopened,
        );
        await mediaMessage(
          'm4',
          outgoing: true,
          status: MessageStatus.read,
          viewOnce: ViewOnceState.unopened,
        );
        await mediaMessage('m5', outgoing: true, status: MessageStatus.viewed);
        final found = await db.messagesDao.viewOnceWithMediaToConsume();
        expect(
          {for (final f in found) f.rowid: f.outgoing},
          {opened.localRowid: false, viewed.localRowid: true},
        );
        await db.messagesDao.removeAttachments(opened.localRowid);
        expect(
          (await db.messagesDao.viewOnceWithMediaToConsume()).map(
            (f) => f.rowid,
          ),
          [viewed.localRowid],
        );
      },
    );
  });
}
