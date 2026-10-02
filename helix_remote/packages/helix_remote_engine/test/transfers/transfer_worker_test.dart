import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../support/fake_media.dart';
import 'support.dart';

/// The transfer queue worker: resume, leases, backoff, typed failures,
/// cancellation and limits, against the fake media server.
void main() {
  late FakeMedia media;
  late MediaWorld world;
  late MediaPeer alice;
  late MediaPeer bob;
  late String chat;

  Future<void> start({
    TransferConfig transfers = testTransfers,
    bool background = false,
  }) async {
    alice = await world.register(
      'alice',
      transfers: transfers,
      background: background,
    );
    bob = await world.register('bob', transfers: transfers);
    chat = await alice.openChat(bob);
    // Documents are fetched by themselves in these tests.
    await bob.engine.settings.set(
      MediaSettings.autoDownloadDocuments,
      MediaSettings.unlimited,
    );
  }

  Future<MessageRow> sendDoc(Uint8List data, {String name = 'a.bin'}) =>
      alice.engine.media.sendMedia(chat, [
        MediaInput.bytes(
          bytes: data,
          kind: MediaItemKind.document,
          mime: 'application/octet-stream',
          name: name,
        ),
      ]);

  Future<TransferRow> jobOf(MediaPeer peer, MessageRow message) async {
    final att = (await peer.attachments(message)).single;
    return (await peer.db.transfersDao.byAttachment(att.id))!;
  }

  Future<void> until(
    Future<bool> Function() condition, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!await condition()) {
      if (DateTime.now().isAfter(deadline)) fail('timed out');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<Uint8List> receivedBytes(MediaPeer peer, MediaPeer from) async {
    final message = (await peer.messages(
      from,
    )).lastWhere((m) => m.kind == 'media');
    final att = (await peer.attachments(message)).single;
    final path = await peer.engine.media.openLocalPath(att.id);
    expect(path, isNotNull, reason: 'downloaded');
    return peer.blobs.bytesOf(path!)!;
  }

  setUp(() {
    media = FakeMedia();
    world = MediaWorld(media: media);
  });
  tearDown(() => world.dispose());

  group('uploads resume after an interruption', () {
    // 20 000 plaintext bytes are 20 032 ciphertext bytes: five requests of
    // 4 096 bytes (the last is shorter).
    for (final dropped in [1, 2, 3, 5]) {
      test('at request $dropped', () async {
        await start();
        final data = patterned(20000);
        final sent = await sendDoc(data);
        media.dropPuts.add(dropped);

        await alice.engine.drainTransfers();
        var job = await jobOf(alice, sent);
        expect(job.state, TransferState.pending);
        expect(job.attempts, 1);
        expect(job.lastError, 'network');
        expect(job.offset, (dropped - 1) * 4096, reason: 'chunks before it');
        final view = (await alice.engine.media.viewsOf(sent.localRowid)).single;
        expect(view.phase, TransferPhase.queued);
        expect(view.lastError, 'network');

        // Backing off: nothing happens until the retry time.
        await alice.engine.drainTransfers();
        expect(media.putCount, dropped);

        world.clock.advance(const Duration(seconds: 3));
        await alice.engine.drainTransfers();

        // The resumed request starts where the server stopped, not at 0.
        final puts = media.of('PUT');
        expect(puts[dropped].offset, (dropped - 1) * 4096);
        expect(
          media.of('HEAD'),
          hasLength(dropped > 1 ? 1 : 0),
          reason: 'asks how far the server got',
        );
        job = await jobOf(alice, sent);
        expect(job.state, TransferState.done);
        expect(media.objects.values.where((o) => o.complete), hasLength(1));

        await alice.settle();
        await bob.settle();
        expect(await receivedBytes(bob, alice), data);
        expect(alice.blobs.pathsIn(BlobArea.staging), isEmpty);
      });
    }

    test('a lost response does not repeat the chunk', () async {
      await start();
      final data = patterned(20000);
      await sendDoc(data);
      media.loseResponsePuts.add(2);
      await alice.engine.drainTransfers();
      world.clock.advance(const Duration(seconds: 3));
      await alice.engine.drainTransfers();
      final puts = media.of('PUT');
      // The server had stored two chunks; the resume asked and went on at
      // the third, with no 409 in between.
      expect(puts.map((p) => p.offset), [0, 4096, 8192, 12288, 16384]);
      await alice.settle();
      await bob.settle();
      expect(await receivedBytes(bob, alice), data);
    });

    test('a wrong offset continues from the one the server names', () async {
      await start();
      final data = patterned(20000);
      await sendDoc(data);
      var once = false;
      media.onPut = (object, offset, bytes) async {
        // Another attempt of ours got this chunk through while this one was
        // on its way.
        if (offset == 4096 && !once) {
          once = true;
          object.append(bytes);
        }
      };
      await alice.engine.drainTransfers();
      expect(media.of('PUT').map((p) => p.offset), [
        0,
        4096, // refused with 409 {upload_offset: 8192}
        8192,
        12288,
        16384,
      ]);
      expect(media.objects.values.single.complete, isTrue);
      await alice.settle();
      await bob.settle();
      expect(await receivedBytes(bob, alice), data);
    });

    test('a restart in the middle continues the same upload', () async {
      await start();
      final data = patterned(20000);
      final sent = await sendDoc(data);
      media.dropPuts.add(4);
      await alice.engine.drainTransfers();
      expect((await jobOf(alice, sent)).offset, 3 * 4096);
      final objectsBefore = media.objects.keys.toSet();

      // The app was killed: a new engine over the same database and files.
      alice = await world.restart(alice);
      world.clock.advance(const Duration(seconds: 3));
      await alice.engine.drainTransfers();
      await alice.engine.drainOutbox();

      expect(media.objects.keys.toSet(), objectsBefore, reason: 'same object');
      expect(world.server.sends, hasLength(1));
      await bob.settle();
      expect(await receivedBytes(bob, alice), data);
    });

    test('lost staged bytes restart the upload from nothing', () async {
      await start();
      final data = patterned(20000);
      final sent = await sendDoc(data);
      media.dropPuts.add(3);
      await alice.engine.drainTransfers();
      final first = media.objects.keys.single;
      // The OS cleared the cache directory.
      for (final path in alice.blobs.pathsIn(BlobArea.staging).toList()) {
        await alice.blobs.delete(path);
      }
      world.clock.advance(const Duration(seconds: 3));
      await alice.engine.drainTransfers();
      expect((await jobOf(alice, sent)).state, TransferState.done);
      expect(
        media.objects.keys,
        isNot(contains(first)),
        reason: 'the half-written object was replaced',
      );
      await alice.settle();
      await bob.settle();
      expect(await receivedBytes(bob, alice), data);
    });

    test('a presigned upload is one request of exactly the size', () async {
      media.presigned = true;
      await start();
      final data = patterned(20000);
      await sendDoc(data);
      await alice.engine.drainTransfers();
      expect(media.of('PUT'), isEmpty);
      final s3 = media.of('S3 PUT');
      expect(s3, hasLength(1));
      expect(s3.single.length, media.objects.values.single.size);
      await alice.settle();
      await bob.settle();
      expect(await receivedBytes(bob, alice), data);
    });

    test('an empty-but-for-the-header size is still one chunk', () async {
      await start();
      final sent = await sendDoc(patterned(1));
      await alice.engine.drainTransfers();
      expect((await jobOf(alice, sent)).state, TransferState.done);
    });
  });

  group('downloads resume after an interruption', () {
    for (final dropped in [1, 3, 6]) {
      test('at request $dropped', () async {
        await start();
        final data = patterned(40000, seed: 9);
        await sendDoc(data);
        await alice.settle();
        media.dropGets.add(dropped);
        await bob.engine.syncOnce();
        await bob.engine.drainTransfers();

        final received = (await bob.messages(alice)).single;
        var job = await jobOf(bob, received);
        expect(job.state, TransferState.pending);
        expect(job.offset, (dropped - 1) * 4096);
        final view = (await bob.engine.media.viewsOf(
          received.localRowid,
        )).single;
        expect(view.phase, TransferPhase.queued);
        expect(view.direction, TransferDirection.download);
        expect(view.bytesDone, (dropped - 1) * 4096);

        world.clock.advance(const Duration(seconds: 3));
        await bob.engine.drainTransfers();
        final gets = media.of('GET');
        // The failed request and its retry start at the same byte.
        expect(gets[dropped - 1].offset, (dropped - 1) * 4096);
        expect(gets[dropped].offset, (dropped - 1) * 4096);
        job = await jobOf(bob, received);
        expect(job.state, TransferState.done);
        expect(await receivedBytes(bob, alice), data);
        expect(bob.blobs.pathsIn(BlobArea.staging), isEmpty);
      });
    }

    test('a restart in the middle continues from the staged bytes', () async {
      await start();
      final data = patterned(40000, seed: 9);
      await sendDoc(data);
      await alice.settle();
      media.dropGets.add(4);
      await bob.engine.syncOnce();
      await bob.engine.drainTransfers();

      bob = await world.restart(bob);
      world.clock.advance(const Duration(seconds: 3));
      await bob.engine.drainTransfers();
      expect(media.of('GET').map((g) => g.offset), [
        0,
        4096,
        8192,
        12288, // dropped
        12288,
        16384,
        20480,
        24576,
        28672,
        32768,
        36864,
      ]);
      expect(await receivedBytes(bob, alice), data);
    });

    test('a server that ignores Range still delivers', () async {
      media.ignoreRange = true;
      await start();
      final data = patterned(9000, seed: 4);
      await sendDoc(data);
      await alice.settle();
      await bob.settle();
      expect(await receivedBytes(bob, alice), data);
    });

    test('follows the redirect to a presigned GET with ranges', () async {
      media.redirectDownloads = true;
      await start();
      final data = patterned(9000, seed: 4);
      await sendDoc(data);
      await alice.settle();
      await bob.settle();
      expect(await receivedBytes(bob, alice), data);
      final s3 = media.of('S3 GET');
      expect(s3, isNotEmpty);
      expect(s3.first.offset, 0);
    });

    test('an object past its 30 days fails as expired, for good', () async {
      await start();
      await sendDoc(patterned(3000));
      await alice.settle();
      media.expireAll();
      await bob.settle();
      final received = (await bob.messages(alice)).single;
      final view = (await bob.engine.media.viewsOf(received.localRowid)).single;
      expect(view.phase, TransferPhase.failed);
      expect(view.failure, TransferFailure.expired);
      // Retrying cannot help, and says so again.
      await bob.engine.media.retry(received.localRowid);
      await bob.engine.drainTransfers();
      expect(
        (await bob.engine.media.viewsOf(received.localRowid)).single.failure,
        TransferFailure.expired,
      );
    });
  });

  group('integrity', () {
    test('damaged bytes fail the digest check and are dropped', () async {
      await start();
      final data = patterned(9000, seed: 4);
      await sendDoc(data);
      await alice.settle();
      media.corruptDownloads = true;
      await bob.settle();
      final received = (await bob.messages(alice)).single;
      final view = (await bob.engine.media.viewsOf(received.localRowid)).single;
      expect(view.phase, TransferPhase.failed);
      expect(view.failure, TransferFailure.digestMismatch);
      expect(
        (await bob.attachments(received)).single.transfer,
        AttachmentTransfer.failed,
      );
      expect(await bob.engine.media.openLocalPath(view.attachmentId), isNull);
      expect(bob.blobs.pathsIn(BlobArea.staging), isEmpty);
      expect(bob.blobs.pathsIn(BlobArea.media), isEmpty);

      // The user taps retry once the network behaves.
      media.corruptDownloads = false;
      await bob.engine.media.retry(received.localRowid);
      await bob.engine.drainTransfers();
      expect(await receivedBytes(bob, alice), data);
    });

    test('bytes that do not decrypt under the pointer fail', () async {
      await start();
      await sendDoc(patterned(9000));
      await alice.settle();
      await bob.settle();
      final real = (await alice.attachments(
        (await alice.messages(bob)).single,
      )).single;
      // A pointer with the right object and digest but the wrong key.
      await alice.engine.debugSend(
        ContentMessage(
          id: Uuid.v7(),
          sentAt: world.clock.now,
          conversation: DirectConversation(to: bob.account),
          body: MediaBody(
            items: [
              MediaItem(
                kind: MediaItemKind.document,
                media: MediaPointer(
                  id: real.mediaId,
                  key: Uint8List.fromList(List.filled(32, 9)),
                  digest: real.digest,
                  size: real.size,
                  mime: 'text/plain',
                ),
              ),
            ],
          ),
        ),
        audience: [bob.account],
        conversationId: chat,
      );
      await alice.settle();
      await bob.settle();
      final forged = (await bob.messages(
        alice,
      )).where((m) => m.kind == 'media');
      expect(forged, hasLength(2));
      final views = await bob.engine.media.viewsOf(forged.last.localRowid);
      expect(views.single.failure, TransferFailure.decryptFailed);
      expect(bob.blobs.pathsIn(BlobArea.staging), isEmpty);
    });

    test('a pointer that lies about the size is refused', () async {
      await start();
      await sendDoc(patterned(9000));
      await alice.settle();
      final real = (await alice.attachments(
        (await alice.messages(bob)).single,
      )).single;
      await alice.engine.debugSend(
        ContentMessage(
          id: Uuid.v7(),
          sentAt: world.clock.now,
          conversation: DirectConversation(to: bob.account),
          body: MediaBody(
            items: [
              MediaItem(
                kind: MediaItemKind.document,
                media: MediaPointer(
                  id: real.mediaId,
                  key: real.mediaKey,
                  digest: real.digest,
                  size: 100, // the object holds 9 000
                  mime: 'text/plain',
                ),
              ),
            ],
          ),
        ),
        audience: [bob.account],
        conversationId: chat,
      );
      await alice.settle();
      await bob.settle();
      final forged = (await bob.messages(
        alice,
      )).where((m) => m.kind == 'media');
      final views = await bob.engine.media.viewsOf(forged.last.localRowid);
      expect(views.single.failure, TransferFailure.sizeMismatch);
      expect(bob.blobs.pathsIn(BlobArea.staging), isEmpty);
    });
  });

  group('failures on upload', () {
    test('a full quota fails the message with a typed error', () async {
      media.quotaBytes = 100;
      await start();
      final events = <EngineEvent>[];
      final sub = alice.engine.events.listen(events.add);
      final sent = await sendDoc(patterned(5000));
      await alice.engine.drainTransfers();
      await alice.engine.drainOutbox();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      final view = (await alice.engine.media.viewsOf(sent.localRowid)).single;
      expect(view.phase, TransferPhase.failed);
      expect(view.failure, TransferFailure.quotaExceeded);
      final row = await alice.db.messagesDao.byRowid(sent.localRowid);
      expect(row!.status, MessageStatus.failed);
      expect(world.server.sends, isEmpty, reason: 'never sent half-made');
      final failed = events.whereType<SendFailedEvent>().single;
      expect(failed.messageRowid, sent.localRowid);
      expect(failed.errorCode, 'quota_exceeded');
      final op = (await alice.db.outboxDao.forMessage(sent.localRowid)).single;
      expect(op.state, OutboxState.failed);
      expect(op.lastError, 'quota_exceeded');

      // Space is freed; the user taps retry on the message.
      media.quotaBytes = 1024 * 1024;
      await alice.engine.chats.retrySend(sent.localRowid);
      expect(
        (await alice.db.messagesDao.byRowid(sent.localRowid))!.status,
        MessageStatus.pending,
      );
      await alice.engine.drainTransfers();
      await alice.engine.drainOutbox();
      expect(world.server.sends, hasLength(1));
      expect(
        (await alice.db.messagesDao.byRowid(sent.localRowid))!.status,
        MessageStatus.sent,
      );
      await bob.settle();
      expect(await receivedBytes(bob, alice), patterned(5000));
    });

    test('a file over the server limit fails as too large', () async {
      media.maxBytes = 1000;
      await start();
      final sent = await sendDoc(patterned(5000));
      await alice.engine.drainTransfers();
      final view = (await alice.engine.media.viewsOf(sent.localRowid)).single;
      expect(view.failure, TransferFailure.tooLarge);
      expect(media.objects, isEmpty);
    });

    test('a vanished source file fails as file_missing', () async {
      await start();
      final sent = await sendDoc(patterned(3000));
      final att = (await alice.attachments(sent)).single;
      await alice.blobs.delete(att.localPath!);
      await alice.engine.drainTransfers();
      final view = (await alice.engine.media.viewsOf(sent.localRowid)).single;
      expect(view.failure, TransferFailure.fileMissing);
    });

    test(
      'one failed item fails the album, and retry resends only it',
      () async {
        await start();
        final sent = await alice.engine.media.sendMedia(chat, [
          MediaInput.bytes(
            bytes: patterned(3000),
            kind: MediaItemKind.document,
            mime: 'text/plain',
            name: 'ok.txt',
          ),
          MediaInput.bytes(
            bytes: patterned(3000, seed: 2),
            kind: MediaItemKind.document,
            mime: 'text/plain',
            name: 'bad.txt',
          ),
        ]);
        final items = await alice.attachments(sent);
        await alice.blobs.delete(items.last.localPath!);
        await alice.engine.drainTransfers();
        expect(
          (await alice.db.messagesDao.byRowid(sent.localRowid))!.status,
          MessageStatus.failed,
        );
        final views = await alice.engine.media.viewsOf(sent.localRowid);
        expect(views.map((v) => v.phase), [
          TransferPhase.ready,
          TransferPhase.failed,
        ]);
        final uploaded = media.objects.length;

        // The file is back (the user picked it again): retry.
        await alice.blobs.writeBytes(
          items.last.localPath!,
          patterned(3000, seed: 2),
        );
        await alice.engine.media.retry(sent.localRowid);
        await alice.engine.drainTransfers();
        await alice.engine.drainOutbox();
        expect(
          media.objects.length,
          uploaded + 1,
          reason: 'only the failed one',
        );
        expect(world.server.sends, hasLength(1));
        await bob.settle();
        final received = (await bob.messages(alice)).single;
        expect((await bob.attachments(received)).map((a) => a.name), [
          'ok.txt',
          'bad.txt',
        ]);
      },
    );
  });

  group('backoff', () {
    test('doubles after each failure and keeps the progress', () async {
      await start();
      final sent = await sendDoc(patterned(20000));
      media.dropPuts.add(3);
      await alice.engine.drainTransfers();
      var job = await jobOf(alice, sent);
      expect(job.offset, 2 * 4096);
      Duration wait(TransferRow row) =>
          row.nextAttemptAt.difference(world.clock.now);

      // First failure: 2 s. Offline for the next tries: 4 s, then 8 s.
      expect(wait(job), closeTo(const Duration(seconds: 2), 200));
      media.offlineNext = 1000;
      world.clock.advance(const Duration(seconds: 3));
      await alice.engine.drainTransfers();
      job = await jobOf(alice, sent);
      expect(job.attempts, 2);
      expect(wait(job), closeTo(const Duration(seconds: 4), 200));
      world.clock.advance(const Duration(seconds: 5));
      await alice.engine.drainTransfers();
      job = await jobOf(alice, sent);
      expect(job.attempts, 3);
      expect(wait(job), closeTo(const Duration(seconds: 8), 200));
      expect(job.offset, 2 * 4096, reason: 'progress is kept');

      media.offlineNext = 0;
      world.clock.advance(const Duration(seconds: 9));
      await alice.engine.drainTransfers();
      job = await jobOf(alice, sent);
      expect(job.state, TransferState.done);
    });

    test('a server that says Retry-After is waited for', () async {
      await start();
      final sent = await sendDoc(patterned(2000));
      media.failNext(
        ErrorCode.rateLimited,
        retryAfter: const Duration(seconds: 30),
      );
      await alice.engine.drainTransfers();
      final job = await jobOf(alice, sent);
      expect(job.attempts, 1);
      expect(job.lastError, 'rate_limited');
      expect(
        job.nextAttemptAt.difference(world.clock.now),
        closeTo(const Duration(seconds: 30), 300),
        reason: 'longer than the 2 s backoff',
      );
      world.clock.advance(const Duration(seconds: 31));
      await alice.engine.drainTransfers();
      expect((await jobOf(alice, sent)).state, TransferState.done);
    });

    test('gives up after maxAge and the UI offers a retry', () async {
      await start();
      final sent = await sendDoc(patterned(2000));
      media.offlineNext = 1000;
      await alice.engine.drainTransfers();
      world.clock.advance(const Duration(days: 4));
      await alice.engine.drainTransfers();
      final view = (await alice.engine.media.viewsOf(sent.localRowid)).single;
      expect(view.phase, TransferPhase.failed);
      expect(view.failure, TransferFailure.gaveUp);
      expect(
        (await alice.db.messagesDao.byRowid(sent.localRowid))!.status,
        MessageStatus.failed,
      );
      media.offlineNext = 0;
      await alice.engine.media.retry(sent.localRowid);
      await alice.engine.drainTransfers();
      await alice.engine.drainOutbox();
      expect(world.server.sends, hasLength(1));
    });
  });

  group('leases', () {
    test('a job whose worker died is taken over when the lease ends', () async {
      await start();
      final sent = await sendDoc(patterned(8000));
      // A worker claimed the job and died without a word.
      final claimed = await alice.db.transfersDao.claim(
        world.clock.now,
        lease: const Duration(seconds: 60),
      );
      expect(claimed, isNotNull);
      await alice.engine.drainTransfers();
      expect(media.objects, isEmpty, reason: 'still leased: left alone');
      expect((await jobOf(alice, sent)).state, TransferState.inFlight);

      world.clock.advance(const Duration(seconds: 61));
      await alice.engine.drainTransfers();
      expect((await jobOf(alice, sent)).state, TransferState.done);
      await alice.engine.drainOutbox();
      expect(world.server.sends, hasLength(1));
    });

    test('an expired lease keeps the stored offset', () async {
      await start();
      final sent = await sendDoc(patterned(20000));
      media.dropPuts.add(4);
      await alice.engine.drainTransfers();
      // Make it look claimed by a dead worker with some progress.
      await alice.db.transfersDao.claim(
        world.clock.now.add(const Duration(seconds: 5)),
        lease: const Duration(seconds: 10),
      );
      expect((await jobOf(alice, sent)).offset, 3 * 4096);
      world.clock.advance(const Duration(minutes: 1));
      await alice.engine.drainTransfers();
      expect(media.of('PUT').last.offset, 4 * 4096);
      expect((await jobOf(alice, sent)).state, TransferState.done);
    });
  });

  group('cancellation', () {
    test(
      'cancelling a send mid-upload stops it and cleans everything',
      () async {
        await start();
        final sent = await sendDoc(patterned(20000));
        final reached = Completer<void>();
        final gate = Completer<void>();
        media.onPut = (object, offset, bytes) async {
          if (offset == 4096 && !reached.isCompleted) {
            reached.complete();
            await gate.future;
          }
        };
        final draining = alice.engine.drainTransfers();
        await reached.future;
        final att = (await alice.attachments(sent)).single;
        final paths = [att.localPath!];

        await alice.engine.media.cancelSend(sent.localRowid);
        gate.complete();
        await draining;

        expect(await alice.db.messagesDao.byRowid(sent.localRowid), isNull);
        expect(await alice.db.transfersDao.live(), isEmpty);
        expect(await alice.db.outboxDao.forMessage(sent.localRowid), isEmpty);
        expect(alice.blobs.pathsIn(BlobArea.staging), isEmpty);
        for (final path in paths) {
          expect(alice.blobs.exists(path), isFalse);
        }
        expect(media.objects, isEmpty, reason: 'the part-uploaded object went');
        await alice.engine.drainOutbox();
        expect(world.server.sends, isEmpty);
      },
    );

    test('cancelling a download returns it to not downloaded', () async {
      await start();
      await sendDoc(patterned(40000));
      await alice.settle();
      final reached = Completer<void>();
      final gate = Completer<void>();
      media.onGet = (object) async {
        if (!reached.isCompleted) {
          reached.complete();
          await gate.future;
        }
      };
      await bob.engine.syncOnce();
      final draining = bob.engine.drainTransfers();
      await reached.future;
      final received = (await bob.messages(alice)).single;
      final att = (await bob.attachments(received)).single;

      await bob.engine.media.cancel(att.id);
      gate.complete();
      await draining;

      final view = (await bob.engine.media.viewsOf(received.localRowid)).single;
      expect(view.phase, TransferPhase.notDownloaded);
      expect(await bob.db.transfersDao.live(), isEmpty);
      expect(bob.blobs.pathsIn(BlobArea.staging), isEmpty);
      // The user can still fetch it later.
      media.onGet = null;
      await bob.engine.media.downloadNow(att.id);
      await bob.engine.drainTransfers();
      expect(await receivedBytes(bob, alice), patterned(40000));
    });

    test('cancelling an upload by attachment cancels the send', () async {
      await start();
      final sent = await sendDoc(patterned(2000));
      final att = (await alice.attachments(sent)).single;
      await alice.engine.media.cancel(att.id);
      expect(await alice.db.messagesDao.byRowid(sent.localRowid), isNull);
    });

    test('a message that already left cannot be cancelled', () async {
      await start();
      final sent = await sendDoc(patterned(2000));
      await alice.settle();
      expect(
        () => alice.engine.media.cancelSend(sent.localRowid),
        throwsStateError,
      );
    });

    test(
      'stopping hands running jobs back without counting an attempt',
      () async {
        await start(background: true);
        final sent = await sendDoc(patterned(20000));
        final reached = Completer<void>();
        final gate = Completer<void>();
        media.onPut = (object, offset, bytes) async {
          if (offset == 4096 && !reached.isCompleted) {
            reached.complete();
            await gate.future;
          }
        };
        await reached.future;
        final stopping = alice.engine.stop();
        gate.complete();
        await stopping;
        final job = await jobOf(alice, sent);
        expect(job.state, TransferState.pending);
        expect(job.attempts, 0);
        expect(job.leaseUntil, isNull);
      },
    );
  });

  group('the running worker', () {
    test('wakes up on an enqueue and sends the message by itself', () async {
      await start(background: true);
      final data = patterned(20000);
      await sendDoc(data);
      await until(() async => world.server.sends.isNotEmpty);
      expect(media.objects.values.single.complete, isTrue);
      await bob.settle();
      expect(await receivedBytes(bob, alice), data);
    });

    test('limits uploads running at once', () async {
      await start(
        transfers: testTransfers.copyWith(maxUploads: 2, maxDownloads: 1),
      );
      var running = 0;
      var peak = 0;
      media.onPut = (object, offset, bytes) async {
        peak = math.max(peak, ++running);
        await Future<void>.delayed(const Duration(milliseconds: 15));
        running--;
      };
      for (var i = 0; i < 5; i++) {
        await sendDoc(patterned(9000, seed: i));
      }
      await alice.engine.drainTransfers();
      expect(peak, 2);
      expect(media.objects.values.where((o) => o.complete), hasLength(5));
    });

    test('limits downloads running at once', () async {
      await start(
        transfers: testTransfers.copyWith(maxUploads: 4, maxDownloads: 2),
      );
      for (var i = 0; i < 5; i++) {
        await sendDoc(patterned(9000, seed: i));
      }
      await alice.settle();
      var running = 0;
      var peak = 0;
      media.onGet = (object) async {
        peak = math.max(peak, ++running);
        await Future<void>.delayed(const Duration(milliseconds: 15));
        running--;
      };
      await bob.engine.syncOnce();
      await bob.engine.drainTransfers();
      expect(peak, 2);
      final views = [
        for (final m in await bob.messages(alice))
          ...await bob.engine.media.viewsOf(m.localRowid),
      ];
      expect(views.map((v) => v.phase).toSet(), {TransferPhase.ready});
    });
  });

  group('progress for the UI', () {
    test('a watch stream shows the upload advancing to ready', () async {
      await start();
      final sent = await sendDoc(patterned(30000));
      media.onPut = (object, offset, bytes) =>
          Future<void>.delayed(const Duration(milliseconds: 10));
      final seen = <AttachmentTransferView>[];
      final sub = alice.engine.media
          .watchMessage(sent.localRowid)
          .listen((views) => seen.add(views.single));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await alice.engine.drainTransfers();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(seen.first.phase, TransferPhase.queued);
      expect(seen.last.phase, TransferPhase.ready);
      expect(seen.last.fraction, 1);
      final done = [for (final v in seen) v.bytesDone];
      expect(done, orderedEquals([...done]..sort()), reason: 'never backwards');
      expect(
        seen.where((v) => v.bytesDone > 0 && v.bytesDone < v.bytesTotal),
        isNotEmpty,
        reason: 'intermediate progress was shown',
      );
      expect(seen.any((v) => v.phase == TransferPhase.active), isTrue);
      expect(
        seen.where((v) => v.direction == TransferDirection.upload),
        isNotEmpty,
      );
    });

    test('watchAttachment ends with null when the message goes', () async {
      await start();
      final sent = await sendDoc(patterned(1000));
      final att = (await alice.attachments(sent)).single;
      final seen = <AttachmentTransferView?>[];
      final sub = alice.engine.media.watchAttachment(att.id).listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await alice.engine.media.cancelSend(sent.localRowid);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();
      expect(seen.first, isNotNull);
      expect(seen.last, isNull);
    });

    test('the queue as a whole can be watched and retried', () async {
      media.maxBytes = 1000;
      await start();
      await sendDoc(patterned(5000));
      await sendDoc(patterned(500));
      final seen = <int>[];
      final sub = alice.engine.transfers.watchQueue().listen(
        (jobs) => seen.add(jobs.length),
      );
      await alice.engine.drainTransfers();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();
      expect(seen.first, 2);
      // The big one failed for good and is still listed, as failed.
      final queue = await alice.db.transfersDao.live();
      expect(queue.single.state, TransferState.failed);
      media.maxBytes = 1024 * 1024;
      expect(await alice.engine.transfers.retryFailed(), 1);
      await alice.engine.drainTransfers();
      await alice.engine.drainOutbox();
      expect(await alice.db.transfersDao.live(), isEmpty);
      expect(world.server.sends, hasLength(2));
    });
  });

  group('housekeeping', () {
    test('deleting an unsent media message frees the chat', () async {
      await start();
      final sent = await sendDoc(patterned(9000));
      final text = await alice.engine.chats.sendText(chat, 'after');
      await alice.engine.drainOutbox();
      expect(world.server.sends, isEmpty, reason: 'behind the upload');

      // The user deletes the message before it left.
      await alice.engine.chats.deleteForMe([sent.localRowid]);
      await alice.engine.runMaintenance();
      await alice.engine.drainOutbox();
      expect(world.server.sends.map((s) => s.request.id), [text.messageId]);
      expect(await alice.db.transfersDao.live(), isEmpty);
    });

    test('deleting for everyone before it left drops the send', () async {
      await start();
      final sent = await sendDoc(patterned(9000));
      await alice.engine.chats.deleteForEveryone(sent.localRowid);
      await alice.engine.runMaintenance();
      await alice.engine.drainTransfers();
      await alice.engine.drainOutbox();
      expect(
        world.server.sends.where((s) => s.request.id == sent.messageId),
        isEmpty,
      );
      expect(alice.blobs.pathsIn(BlobArea.media), isEmpty);
      expect(alice.blobs.pathsIn(BlobArea.staging), isEmpty);
    });

    test(
      'the sender of a view-once photo loses the file once it is seen',
      () async {
        await start();
        final sent = await alice.engine.media.sendMedia(chat, [
          MediaInput.bytes(
            bytes: pngLike(10, 10),
            kind: MediaItemKind.image,
            mime: 'image/png',
          ),
        ], viewOnce: true);
        await alice.settle();
        await bob.settle();
        await alice.engine.runMaintenance();
        expect(
          await alice.attachments(sent),
          isNotEmpty,
          reason: 'not yet seen',
        );

        final received = (await bob.messages(alice)).single;
        await bob.engine.chats.openViewOnce(received.localRowid);
        await bob.settle();
        await alice.settle();
        expect(
          (await alice.db.messagesDao.byRowid(sent.localRowid))!.status,
          MessageStatus.viewed,
        );
        await alice.engine.runMaintenance();
        expect(await alice.attachments(sent), isEmpty);
        expect(alice.blobs.pathsIn(BlobArea.media), isEmpty);
        // The recipient's copy is for the recipient to consume.
        expect(await bob.attachments(received), isNotEmpty);
      },
    );

    test(
      'opened-but-not-consumed view-once media goes at the next start',
      () async {
        await start();
        await alice.engine.media.sendMedia(chat, [
          MediaInput.bytes(
            bytes: pngLike(10, 10),
            kind: MediaItemKind.image,
            mime: 'image/png',
          ),
        ], viewOnce: true);
        await alice.settle();
        await bob.settle();
        final received = (await bob.messages(alice)).single;
        await bob.engine.chats.openViewOnce(received.localRowid);
        // The app died with the viewer open; nothing consumed it.
        await bob.engine.runMaintenance();
        expect(await bob.attachments(received), isNotEmpty);
        bob = await world.restart(bob);
        await bob.engine.media.consumeOpenedViewOnce();
        expect(await bob.attachments(received), isEmpty);
      },
    );
  });

  group('the file sweep', () {
    test(
      'keeps what is referenced, removes leftovers after the grace',
      () async {
        await start(
          transfers: testTransfers.copyWith(
            sweepGrace: const Duration(minutes: 10),
          ),
        );
        final sent = await sendDoc(patterned(9000));
        final stray = await alice.blobs.newPath(BlobArea.media);
        await alice.blobs.writeBytes(stray, patterned(10));
        final strayStaging = await alice.blobs.newPath(BlobArea.staging);
        await alice.blobs.writeBytes(strayStaging, patterned(10));

        // Fresh files are never taken for leftovers.
        expect(await alice.engine.media.sweep(), 0);
        alice.blobs.age(const Duration(minutes: 11));
        world.clock.advance(Duration.zero);
        expect(await alice.engine.media.sweep(), 2);
        expect(alice.blobs.exists(stray), isFalse);
        expect(alice.blobs.exists(strayStaging), isFalse);
        final att = (await alice.attachments(sent)).single;
        expect(alice.blobs.exists(att.localPath!), isTrue);

        // Staged bytes of a live job are kept however old.
        media.dropPuts.add(2);
        await alice.engine.drainTransfers();
        alice.blobs.age(const Duration(days: 1));
        expect(await alice.engine.media.sweep(), 0);
        expect(alice.blobs.pathsIn(BlobArea.staging), hasLength(1));
      },
    );

    test('sign-out deletes every file', () async {
      await start();
      await sendDoc(patterned(2000));
      await alice.settle();
      expect(alice.blobs.paths, isNotEmpty);
      await alice.engine.signOut();
      expect(alice.blobs.paths, isEmpty);
    });
  });
}

/// Within [tolerance] milliseconds of [expected].
Matcher closeTo(Duration expected, int tolerance) => predicate<Duration>(
  (actual) => (actual - expected).inMilliseconds.abs() <= tolerance,
  'within $tolerance ms of $expected',
);
