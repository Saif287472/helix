import 'dart:io';
import 'dart:typed_data';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'support.dart';

/// The revision of a job nobody has claimed yet; `claim` raises it.
const unclaimed = 0;

void main() {
  late HelixDb db;
  late TransfersDao transfers;
  late int attachment;

  Uint8List key() => Uint8List.fromList(List.filled(32, 7));

  Future<int> newAttachment(String mediaId) async {
    final chat = await directChat(db, 'bob');
    final message = await db.messagesDao.insertMessage(
      textMessage(chat.id, 'm-$mediaId', sentAt: at(1)),
      media: [
        AttachmentsCompanion.insert(
          messageRowid: 0,
          position: 0,
          kind: 'image',
          mediaId: mediaId,
          mediaKey: key(),
          digest: Uint8List(32),
          mime: 'image/jpeg',
          size: 1000,
          transfer: AttachmentTransfer.remote,
        ),
      ],
    );
    return (await db.messagesDao.attachmentsFor([
      message.localRowid,
    ])).single.id;
  }

  setUp(() async {
    db = memoryDb();
    transfers = db.transfersDao;
    attachment = await newAttachment('media-1');
  });

  Future<int> upload({DateTime? now}) => transfers.enqueueUpload(
    attachmentRowid: attachment,
    localPath: 'media/abc.bin',
    size: 5000,
    mediaKey: key(),
    now: now ?? t0,
  );

  group('the queue', () {
    test('an upload is queued pending with its path, size and key', () async {
      final id = await upload();
      final job = (await transfers.byId(id))!;
      expect(
        (job.kind, job.state, job.offset, job.attempts),
        ('upload', TransferState.pending, 0, 0),
      );
      expect((job.localPath, job.size), ('media/abc.bin', 5000));
      expect(job.mediaKey, key());
      expect(job.attachmentRowid, attachment);
      expect((await transfers.byAttachment(attachment))!.id, id);
    });

    test('asking again returns the same job, not a second transfer', () async {
      final first = await upload();
      final second = await upload(now: at(5));
      expect(second, first);
      expect(await transfers.pending(), hasLength(1));
    });

    test('re-queuing a failed job makes it retryable from scratch', () async {
      final id = await upload();
      await transfers.fail(
        id,
        version: unclaimed,
        code: 'network',
        now: t0,
        backoff: const Duration(seconds: 1),
        maxAttempts: 1,
      );
      expect((await transfers.byId(id))!.state, TransferState.failed);
      await upload(now: at(10));
      final job = (await transfers.byId(id))!;
      expect(
        (job.state, job.attempts, job.lastError),
        (TransferState.pending, 0, null),
      );
      expect(job.nextAttemptAt, at(10));
    });

    test('re-queuing leaves a job a worker holds in flight', () async {
      final id = await upload();
      final held = (await transfers.claim(
        at(1),
        lease: const Duration(minutes: 1),
      ))!;
      await upload(now: at(2));
      expect((await transfers.byId(id))!.state, TransferState.inFlight);
      expect(
        await transfers.markDone(id, version: held.version),
        isTrue,
        reason: 'the same job asked for again is still the worker\'s',
      );
    });

    test(
      'a download keeps the object id; a standalone job is per purpose',
      () async {
        final other = await newAttachment('media-2');
        final id = await transfers.enqueueDownload(
          attachmentRowid: other,
          mediaId: 'media-2',
          mediaKey: key(),
          size: 42,
          now: t0,
        );
        final job = (await transfers.byId(id))!;
        expect((job.kind, job.mediaId, job.size), ('download', 'media-2', 42));

        final a = await transfers.enqueueStandalone(
          kind: 'upload',
          purpose: 'group_avatar',
          localPath: 'media/avatar.bin',
          now: t0,
        );
        final b = await transfers.enqueueStandalone(
          kind: 'upload',
          purpose: 'group_avatar',
          localPath: 'media/avatar2.bin',
          now: t0,
        );
        expect(b, a);
        final standalone = (await transfers.byPurpose('group_avatar'))!;
        expect(standalone.attachmentRowid, isNull);
        expect(
          standalone.localPath,
          'media/avatar2.bin',
          reason: 'asking again moves the new file (AUD-10-4)',
        );
      },
    );

    /// A reused purpose used to return the first job untouched: its old path,
    /// its old state - `done`, so the new file never went up (AUD-10-4).
    group('a standalone purpose asked for again', () {
      Future<int> avatar(String path, {DateTime? now}) =>
          transfers.enqueueStandalone(
            kind: 'upload',
            purpose: 'group_avatar',
            localPath: path,
            now: now ?? t0,
          );

      test('after it finished, moves the new file from nothing', () async {
        final id = await avatar('media/avatar.bin');
        final held = (await transfers.claim(
          at(1),
          lease: const Duration(seconds: 30),
        ))!;
        await transfers.setProgress(
          id,
          version: held.version,
          offset: 4096,
          mediaId: 'srv-1',
        );
        await transfers.fail(
          id,
          version: held.version,
          code: 'network',
          now: at(2),
          backoff: Duration.zero,
        );
        final again = (await transfers.claim(
          at(3),
          lease: const Duration(seconds: 30),
        ))!;
        expect(await transfers.markDone(id, version: again.version), isTrue);

        expect(await avatar('media/avatar2.bin', now: at(40 * 86400)), id);
        final job = (await transfers.byId(id))!;
        expect(
          (job.kind, job.localPath, job.state, job.offset, job.mediaId),
          ('upload', 'media/avatar2.bin', TransferState.pending, 0, null),
        );
        expect((job.attempts, job.lastError, job.leaseUntil), (0, null, null));
        expect(
          job.createdAt,
          at(40 * 86400),
          reason: 'its give-up age starts with the new file',
        );
        expect(
          (await transfers.claim(
            at(40 * 86400),
            lease: const Duration(seconds: 30),
          ))!.id,
          id,
        );
      });

      test('while a worker moves the old file, takes the job back', () async {
        final id = await avatar('media/avatar.bin');
        final held = (await transfers.claim(
          at(1),
          lease: const Duration(seconds: 30),
        ))!;
        await avatar('media/avatar2.bin', now: at(2));
        final job = (await transfers.byId(id))!;
        expect(
          (job.state, job.leaseUntil, job.localPath),
          (TransferState.pending, null, 'media/avatar2.bin'),
        );
        expect(await transfers.markDone(id, version: held.version), isFalse);
        expect(
          await transfers.renewLease(id, version: held.version, until: at(60)),
          isFalse,
        );
        final next = (await transfers.claim(
          at(2),
          lease: const Duration(seconds: 30),
        ))!;
        expect((next.id, next.localPath), (id, 'media/avatar2.bin'));
      });

      test('other purposes are their own jobs', () async {
        final a = await avatar('media/avatar.bin');
        final b = await transfers.enqueueStandalone(
          kind: 'upload',
          purpose: 'full_backup',
          localPath: 'backup/blob.bin',
          now: t0,
        );
        expect(b, isNot(a));
        expect(await transfers.pending(), hasLength(2));
      });
    });

    test('deleting the attachment deletes its job', () async {
      final id = await upload();
      await (db.delete(
        db.attachments,
      )..where((a) => a.id.equals(attachment))).go();
      expect(await transfers.byId(id), isNull);
    });

    test('watchPending follows the queue', () async {
      final stream = collect(transfers.watchPending());
      await eventually(() => stream.isNotEmpty);
      final id = await upload();
      await eventually(() => stream.last.length == 1);
      await transfers.markDone(id, version: unclaimed);
      await eventually(() => stream.last.isEmpty);
    });
  });

  group('lease and claim', () {
    test('a job is claimed once; a second worker gets nothing', () async {
      final id = await upload();
      final claimed = (await transfers.claim(
        at(1),
        lease: const Duration(seconds: 30),
      ))!;
      expect(claimed.id, id);
      expect(claimed.state, TransferState.inFlight);
      expect(claimed.leaseUntil, at(31));
      expect(
        await transfers.claim(at(2), lease: const Duration(seconds: 30)),
        isNull,
      );
    });

    test('a job is not due before its retry time', () async {
      await upload(now: at(100));
      expect(
        await transfers.claim(at(50), lease: const Duration(seconds: 30)),
        isNull,
      );
      expect(await transfers.due(at(50)), isEmpty);
      expect(await transfers.due(at(100)), hasLength(1));
    });

    test('claims go oldest first, one at a time', () async {
      final first = await upload(now: at(1));
      final other = await newAttachment('media-2');
      final second = await transfers.enqueueDownload(
        attachmentRowid: other,
        mediaId: 'media-2',
        mediaKey: key(),
        size: 1,
        now: at(2),
      );
      const lease = Duration(minutes: 1);
      expect((await transfers.claim(at(5), lease: lease))!.id, first);
      expect((await transfers.claim(at(5), lease: lease))!.id, second);
      expect(await transfers.claim(at(5), lease: lease), isNull);
    });

    test(
      'a dead worker\'s lease runs out and the job resumes from its offset',
      () async {
        final id = await upload();
        final held = (await transfers.claim(
          at(1),
          lease: const Duration(seconds: 30),
        ))!;
        await transfers.setProgress(
          id,
          version: held.version,
          offset: 2048,
          mediaId: 'srv-1',
        );
        // Still leased at +30 s.
        expect(
          await transfers.claim(at(30), lease: const Duration(seconds: 30)),
          isNull,
        );
        // Expired: another worker takes it and finds the progress.
        final again = (await transfers.claim(
          at(32),
          lease: const Duration(seconds: 30),
        ))!;
        expect(again.id, id);
        expect((again.offset, again.mediaId), (2048, 'srv-1'));
      },
    );

    test('done, failed and given-up jobs are never claimed', () async {
      final id = await upload();
      await transfers.markDone(id, version: unclaimed);
      expect(
        await transfers.claim(at(1), lease: const Duration(seconds: 30)),
        isNull,
      );
    });

    test('a job the caller is still running is not claimed again', () async {
      final id = await upload();
      expect(
        await transfers.claim(
          at(1),
          lease: const Duration(seconds: 30),
          running: {id},
        ),
        isNull,
      );
      expect(
        (await transfers.claim(at(1), lease: const Duration(seconds: 30)))!.id,
        id,
      );
    });
  });

  /// A worker's writes name the revision it claimed (AUD-10-3). One row
  /// serves an attachment's thumbnail and its full download, so asking for the
  /// file while the thumbnail runs turns the row the thumbnail worker holds
  /// into a download. That worker used to finish by marking the row done by id
  /// alone - the download it never ran - and the attachment, already shown as
  /// downloading, waited for ever.
  group('the claim token', () {
    Future<int> thumbnail() => transfers.enqueueThumbnail(
      attachmentRowid: attachment,
      mediaId: 'thumb-1',
      mediaKey: key(),
      size: 100,
      now: t0,
    );

    Future<int> download({DateTime? now}) => transfers.enqueueDownload(
      attachmentRowid: attachment,
      mediaId: 'media-1',
      mediaKey: key(),
      size: 1000,
      now: now ?? t0,
    );

    test('every claim is a new revision', () async {
      final id = await upload();
      expect((await transfers.byId(id))!.version, unclaimed);
      final first = (await transfers.claim(
        at(1),
        lease: const Duration(seconds: 30),
      ))!;
      await transfers.release(id, version: first.version, at: at(2));
      final second = (await transfers.claim(
        at(3),
        lease: const Duration(seconds: 30),
      ))!;
      expect(second.version, greaterThan(first.version));
      expect(first.version, greaterThan(unclaimed));
    });

    test('a thumbnail turned into a download under its worker is not completed '
        'by that worker', () async {
      final id = await thumbnail();
      final held = (await transfers.claim(
        at(1),
        lease: const Duration(minutes: 1),
      ))!;
      expect(held.kind, 'thumbnail');

      // The person opens the file while the thumbnail is still coming in.
      expect(await download(now: at(2)), id);
      final converted = (await transfers.byId(id))!;
      expect(
        (converted.kind, converted.state, converted.leaseUntil),
        ('download', TransferState.pending, null),
        reason: 'taken back from the thumbnail worker, claimable at once',
      );
      expect(converted.version, greaterThan(held.version));

      // The thumbnail worker finishes, or fails, or stops: none of it lands.
      expect(await transfers.markDone(id, version: held.version), isFalse);
      expect(
        await transfers.setProgress(id, version: held.version, offset: 64),
        isFalse,
      );
      expect(
        await transfers.renewLease(id, version: held.version, until: at(90)),
        isFalse,
      );
      expect(
        await transfers.release(id, version: held.version, at: at(90)),
        isFalse,
      );
      expect(
        await transfers.reschedule(
          id,
          version: held.version,
          nextAttemptAt: at(90),
          code: 'network',
        ),
        isFalse,
      );
      expect(
        await transfers.fail(
          id,
          version: held.version,
          code: 'size_mismatch',
          now: at(3),
          backoff: Duration.zero,
          maxAttempts: 1,
        ),
        isFalse,
      );
      expect(await transfers.resetProgress(id, version: held.version), isFalse);
      final after = (await transfers.byId(id))!;
      expect(
        (after.kind, after.state, after.offset, after.attempts),
        ('download', TransferState.pending, 0, 0),
      );
      expect(after.version, converted.version);

      // And the download runs.
      final next = (await transfers.claim(
        at(3),
        lease: const Duration(minutes: 1),
        kinds: {'download'},
      ))!;
      expect((next.id, next.kind, next.mediaId), (id, 'download', 'media-1'));
      expect(await transfers.markDone(id, version: next.version), isTrue);
    });

    test('a lease that ran out belongs to whoever claimed it next', () async {
      final id = await upload();
      final dead = (await transfers.claim(
        at(1),
        lease: const Duration(seconds: 30),
      ))!;
      final next = (await transfers.claim(
        at(40),
        lease: const Duration(seconds: 30),
      ))!;
      expect(next.id, id);
      // The first worker's heartbeat no longer stretches the second's lease,
      // and its late completion does not end the second's attempt.
      expect(
        await transfers.renewLease(id, version: dead.version, until: at(500)),
        isFalse,
      );
      expect((await transfers.byId(id))!.leaseUntil, at(70));
      expect(await transfers.markDone(id, version: dead.version), isFalse);
      expect((await transfers.byId(id))!.state, TransferState.inFlight);
      expect(await transfers.markDone(id, version: next.version), isTrue);
    });
  });

  group('progress and resume', () {
    test(
      'setProgress records the offset and keeps what it is not given',
      () async {
        final id = await upload();
        await transfers.setProgress(
          id,
          version: unclaimed,
          offset: 1000,
          mediaId: 'srv-1',
          localPath: 'media/abc.bin',
        );
        await transfers.setProgress(id, version: unclaimed, offset: 2000);
        final job = (await transfers.byId(id))!;
        expect(
          (job.offset, job.mediaId, job.localPath),
          (2000, 'srv-1', 'media/abc.bin'),
        );
      },
    );

    test('markDone clears the offset, the lease and the error', () async {
      final id = await upload();
      final held = (await transfers.claim(
        at(1),
        lease: const Duration(seconds: 30),
      ))!;
      await transfers.setProgress(id, version: held.version, offset: 4000);
      await transfers.markDone(id, version: held.version);
      final job = (await transfers.byId(id))!;
      expect(
        (job.state, job.offset, job.leaseUntil, job.lastError),
        (TransferState.done, 0, null, null),
      );
    });

    test(
      'a failure backs off, releases the lease and gives up at the limit',
      () async {
        final id = await upload();
        const backoff = Duration(seconds: 10);
        for (var attempt = 1; attempt < 3; attempt++) {
          final held = (await transfers.claim(
            at(attempt * 100),
            lease: backoff,
          ))!;
          final givenUp = await transfers.fail(
            id,
            version: held.version,
            code: 'http_503',
            now: at(attempt * 100),
            backoff: backoff,
            maxAttempts: 3,
          );
          expect(givenUp, isFalse);
          final job = (await transfers.byId(id))!;
          expect(job.state, TransferState.pending);
          expect(job.leaseUntil, isNull);
          expect(job.attempts, attempt);
          expect(job.nextAttemptAt, at(attempt * 100 + 10 * attempt));
          expect(job.lastError, 'http_503');
        }
        final last = (await transfers.claim(at(500), lease: backoff))!;
        expect(
          await transfers.fail(
            id,
            version: last.version,
            code: 'http_503',
            now: at(500),
            backoff: backoff,
            maxAttempts: 3,
          ),
          isTrue,
        );
        expect((await transfers.byId(id))!.state, TransferState.failed);
        expect(await transfers.pending(), isEmpty);
      },
    );

    test('remove deletes the job and its file', () async {
      final dir = tempDir();
      final file = File('${dir.path}/blob.bin')..writeAsBytesSync([1, 2, 3]);
      final id = await transfers.enqueueStandalone(
        kind: 'upload',
        purpose: 'full_backup',
        localPath: file.path,
        now: t0,
      );
      await transfers.remove(id);
      expect(await transfers.byId(id), isNull);
      expect(file.existsSync(), isFalse);
      // A job with no file, or an unknown one, is fine.
      await transfers.remove(id);
      final plain = await upload();
      await transfers.remove(plain);
      expect(await transfers.byId(plain), isNull);
    });
  });

  group('device-to-device chunks', () {
    Future<void> chunk(
      int sequence,
      List<int> bytes, {
      int total = 3,
      String transfer = 't1',
      bool isFinal = false,
    }) => transfers.addChunk(
      transferId: transfer,
      sequence: sequence,
      payload: Uint8List.fromList(bytes),
      total: total,
      isFinal: isFinal,
      now: t0,
    );

    test('chunks in any order assemble in sequence order', () async {
      await chunk(2, [5, 6], isFinal: true);
      await chunk(0, [1, 2]);
      expect(await transfers.isComplete('t1'), isFalse);
      expect(await transfers.assemble('t1'), isNull);
      await chunk(1, [3, 4]);
      expect(await transfers.isComplete('t1'), isTrue);
      expect(await transfers.assemble('t1'), [1, 2, 3, 4, 5, 6]);
      expect((await transfers.chunks('t1')).map((c) => c.sequence), [0, 1, 2]);
    });

    test('a gap is reported, never assembled', () async {
      await chunk(0, [1], total: 5);
      await chunk(3, [4], total: 5);
      expect(await transfers.missingSequences('t1'), [1, 2, 4]);
      expect(await transfers.isComplete('t1'), isFalse);
      expect(await transfers.assemble('t1'), isNull);
    });

    test('nothing received yet is unknown, not complete', () async {
      expect(await transfers.missingSequences('t1'), isNull);
      expect(await transfers.isComplete('t1'), isFalse);
      expect(await transfers.assemble('t1'), isNull);
    });

    test('a repeated chunk replaces the first (retransmission)', () async {
      await chunk(0, [1], total: 2);
      await chunk(0, [9], total: 2);
      await chunk(1, [2], total: 2);
      expect(await transfers.assemble('t1'), [9, 2]);
    });

    test('pieces that disagree about the total are never complete', () async {
      await chunk(0, [1], total: 2);
      await chunk(1, [2], total: 3);
      expect(await transfers.isComplete('t1'), isFalse);
      expect(await transfers.assemble('t1'), isNull);
      expect(await transfers.missingSequences('t1'), [0, 1]);
    });

    test(
      'a chunk numbered past the total does not complete a transfer',
      () async {
        await chunk(0, [1], total: 2);
        await chunk(5, [9], total: 2);
        expect(await transfers.missingSequences('t1'), [1]);
        expect(await transfers.isComplete('t1'), isFalse);
      },
    );

    test(
      'transfers are independent and dropTransfer removes only one',
      () async {
        await chunk(0, [1], total: 1, transfer: 'a');
        await chunk(0, [2], total: 1, transfer: 'b');
        await transfers.dropTransfer('a');
        expect(await transfers.chunks('a'), isEmpty);
        expect(await transfers.assemble('b'), [2]);
      },
    );

    test('an empty-total chunk is never complete', () async {
      await chunk(0, [1], total: 0);
      expect(await transfers.isComplete('t1'), isFalse);
      expect(await transfers.assemble('t1'), isNull);
    });
  });
}
