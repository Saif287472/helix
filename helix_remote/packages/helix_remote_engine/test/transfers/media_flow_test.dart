import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:helix_remote_crypto/v2.dart' show AttachmentCrypto;
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_engine/src/messaging/content_codec.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Sending and receiving attachments through the pipelines, with the fake
/// server and the fake media server.
void main() {
  late MediaWorld world;
  late MediaPeer alice;
  late MediaPeer bob;
  late String chat;

  Future<void> start({
    MediaProcessor? aliceProcessor,
    TransferConfig transfers = testTransfers,
  }) async {
    alice = await world.register(
      'alice',
      processor: aliceProcessor,
      transfers: transfers,
    );
    bob = await world.register('bob', transfers: transfers);
    chat = await alice.openChat(bob);
  }

  setUp(() {
    world = MediaWorld();
  });
  tearDown(() => world.dispose());

  group('sending an image', () {
    test('writes the optimistic row at once, uploads, then sends', () async {
      await start(
        aliceProcessor: FakeProcessor(
          thumbnail: thumbnailBytes(),
          blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj',
        ),
      );
      final photo = pngLike(640, 480, length: 20000);
      final sent = await alice.engine.media.sendMedia(chat, [
        MediaInput.bytes(
          bytes: photo,
          kind: MediaItemKind.image,
          mime: 'image/png',
        ),
      ], caption: 'Holiday');

      // The row exists before anything has moved.
      expect(sent.status, MessageStatus.pending);
      expect(sent.kind, 'media');
      expect(sent.body, 'Holiday');
      final rows = await alice.attachments(sent);
      expect(rows, hasLength(1));
      expect(rows.single.transfer, AttachmentTransfer.uploading);
      expect(rows.single.mediaId, isEmpty);
      expect(rows.single.localPath, isNotNull);
      final views = await alice.engine.media.viewsOf(sent.localRowid);
      expect(views.single.phase, TransferPhase.queued);
      expect(views.single.direction, TransferDirection.upload);

      // The send waits for the upload: the outbox op is held.
      await alice.engine.drainOutbox();
      expect(world.server.sends, isEmpty);
      expect(world.media.objects, isEmpty);

      await alice.engine.drainTransfers();
      // The file and its thumbnail are on the media server, encrypted.
      expect(world.media.objects, hasLength(2));
      final done = (await alice.attachments(sent)).single;
      expect(done.transfer, AttachmentTransfer.ready);
      expect(done.mediaId, isNotEmpty);
      expect(done.thumbnail, isNotNull);
      final stored = world.media.objects[done.mediaId]!;
      expect(stored.complete, isTrue);
      expect(String.fromCharCodes(stored.bytes.sublist(0, 4)), 'HXS2');
      expect(
        stored.size,
        AttachmentCrypto.ciphertextLength(photo.length),
        reason: 'the object is the STREAM ciphertext, not the file',
      );
      expect(
        Uint8List.fromList(hashes.sha256.convert(stored.bytes).bytes),
        done.digest,
      );
      // Dimensions came from the basic header sniff of the processor, the
      // blurhash from the processor.
      expect((done.width, done.height), (640, 480));
      expect(done.blurhash, 'LEHV6nWB2yk8pyo0adR*.7kCMdnj');

      await alice.engine.drainOutbox();
      expect(world.server.sends, hasLength(1));
      final after = await alice.db.messagesDao.byRowid(sent.localRowid);
      expect(after!.status, MessageStatus.sent);
      // The stored payload now carries the real pointer (for re-sends).
      final body = ContentCodec.join(after) as MediaBody;
      expect(body.items.single.media.id, done.mediaId);
    });

    test('the receiver gets the message and downloads the bytes', () async {
      await start(aliceProcessor: FakeProcessor(thumbnail: thumbnailBytes()));
      final photo = pngLike(640, 480, length: 30001);
      await alice.engine.media.sendMedia(chat, [
        MediaInput.bytes(
          bytes: photo,
          kind: MediaItemKind.image,
          mime: 'image/png',
          name: 'beach.png',
        ),
      ]);
      await alice.settle();
      await bob.settle();

      final received = await lastMessage(bob, alice);
      expect(received.status, MessageStatus.received);
      final att = (await bob.attachments(received)).single;
      expect(att.transfer, AttachmentTransfer.ready);
      final path = await bob.engine.media.openLocalPath(att.id);
      expect(path, isNotNull);
      expect(bob.blobs.bytesOf(path!), photo);
      expect(att.name, 'beach.png');
      expect(att.size, 30001);
      expect((att.width, att.height), (640, 480));
      // Auto-download fetched the thumbnail too.
      final thumb = await bob.engine.media.thumbnailPath(att.id);
      expect(bob.blobs.bytesOf(thumb!), thumbnailBytes());
      // Nothing is left in staging.
      expect(bob.blobs.pathsIn(BlobArea.staging), isEmpty);
      expect(alice.blobs.pathsIn(BlobArea.staging), isEmpty);
    });

    test('an album, a voice note and a document keep their details', () async {
      await start();
      final voice = patterned(5000, seed: 3);
      final waveform = Uint8List.fromList(List.generate(40, (i) => i * 6));
      final doc = patterned(9000, seed: 5);
      await alice.engine.media.sendMedia(chat, [
        MediaInput.bytes(
          bytes: pngLike(10, 20),
          kind: MediaItemKind.image,
          mime: 'image/png',
          caption: 'first',
        ),
        MediaInput.bytes(
          bytes: pngLike(30, 40),
          kind: MediaItemKind.image,
          mime: 'image/png',
        ),
      ]);
      await alice.engine.media.sendMedia(chat, [
        MediaInput.bytes(
          bytes: voice,
          kind: MediaItemKind.voiceNote,
          mime: 'audio/ogg',
          durationMs: 12000,
          waveform: waveform,
        ),
      ]);
      await alice.engine.media.sendMedia(chat, [
        MediaInput.bytes(
          bytes: doc,
          kind: MediaItemKind.document,
          mime: 'application/pdf',
          name: 'invoice.pdf',
        ),
      ], caption: 'the invoice');
      await alice.settle();
      await bob.settle();

      final messages = (await bob.messages(
        alice,
      )).where((m) => m.kind == 'media');
      expect(messages, hasLength(3));
      final album = await bob.attachments(messages.first);
      expect(album.map((a) => (a.position, a.width, a.height)), [
        (0, 10, 20),
        (1, 30, 40),
      ]);
      expect(album.first.caption, 'first');
      final note = (await bob.attachments(messages.elementAt(1))).single;
      expect(note.kind, 'voice_note');
      expect(note.durationMs, 12000);
      expect(note.waveform, waveform);
      expect(note.transfer, AttachmentTransfer.ready);
      expect(
        bob.blobs.bytesOf((await bob.engine.media.openLocalPath(note.id))!),
        voice,
      );
      final pdf = (await bob.attachments(messages.last)).single;
      expect(pdf.name, 'invoice.pdf');
      expect(messages.last.body, 'the invoice');
      // Documents are not fetched by themselves (the policy is on demand).
      expect(pdf.transfer, AttachmentTransfer.remote);
      expect(
        (await bob.engine.media.viewsOf(messages.last.localRowid)).single.phase,
        TransferPhase.notDownloaded,
      );
      await bob.engine.media.downloadNow(pdf.id);
      await bob.engine.drainTransfers();
      expect(
        bob.blobs.bytesOf((await bob.engine.media.openLocalPath(pdf.id))!),
        doc,
      );
      // The extension comes from the file name, so the OS can open it.
      expect(await bob.engine.media.openLocalPath(pdf.id), endsWith('.pdf'));
    });

    test('a failing processor still sends the file', () async {
      await start(aliceProcessor: FakeProcessor(fail: true));
      await alice.engine.media.sendMedia(chat, [
        MediaInput.bytes(
          bytes: patterned(900),
          kind: MediaItemKind.video,
          mime: 'video/mp4',
        ),
      ]);
      await alice.settle();
      await bob.settle();
      final received = await lastMessage(bob, alice);
      final att = (await bob.attachments(received)).single;
      expect(att.kind, 'video');
      expect(att.width, isNull);
      expect(att.thumbnail, isNull);
    });

    test('rejects an empty file, no items and too many items', () async {
      await start();
      expect(() => alice.engine.media.sendMedia(chat, []), throwsArgumentError);
      expect(
        () => alice.engine.media.sendMedia(chat, [
          MediaInput.bytes(
            bytes: Uint8List(0),
            kind: MediaItemKind.document,
            mime: 'text/plain',
          ),
        ]),
        throwsArgumentError,
      );
      expect(
        () => alice.engine.media.sendMedia(chat, [
          for (var i = 0; i < 31; i++)
            MediaInput.bytes(
              bytes: patterned(10),
              kind: MediaItemKind.document,
              mime: 'text/plain',
            ),
        ]),
        throwsArgumentError,
      );
      // Nothing was left behind by the failed sends.
      await alice.engine.media.sweep();
      expect(alice.blobs.paths, isEmpty);
      expect(await alice.db.messagesDao.pageOlder(chat), isNotNull);
    });
  });

  group('order', () {
    test('a text sent after a media message leaves after it', () async {
      await start();
      final media = await alice.engine.media.sendMedia(chat, [
        MediaInput.bytes(
          bytes: patterned(20000),
          kind: MediaItemKind.document,
          mime: 'application/zip',
          name: 'a.zip',
        ),
      ]);
      final text = await alice.engine.chats.sendText(chat, 'see attached');

      // The text must not overtake the upload.
      await alice.engine.drainOutbox();
      expect(world.server.sends, isEmpty);
      expect(
        (await alice.db.messagesDao.byRowid(text.localRowid))!.status,
        MessageStatus.pending,
      );

      await alice.engine.drainTransfers();
      await alice.engine.drainOutbox();
      expect(world.server.sends, hasLength(2));
      expect(world.server.sends.map((s) => s.request.id), [
        media.messageId,
        text.messageId,
      ]);

      await bob.engine.syncOnce();
      final order = [
        for (final m in await bob.messages(alice))
          if (m.kind != 'system') m.kind,
      ];
      expect(order, ['media', 'text']);
    });

    test('a text sent before a media message is not held by it', () async {
      await start();
      final text = await alice.engine.chats.sendText(chat, 'one moment');
      await alice.engine.media.sendMedia(chat, [
        MediaInput.bytes(
          bytes: patterned(3000),
          kind: MediaItemKind.document,
          mime: 'text/plain',
          name: 'a.txt',
        ),
      ]);
      await alice.engine.drainOutbox();
      expect(world.server.sends.map((s) => s.request.id), [text.messageId]);
    });
  });

  group('auto-download policy', () {
    Future<List<TransferPhase>> phases() async {
      await alice.settle();
      await bob.settle();
      final received = [
        for (final m in await bob.messages(alice))
          if (m.kind == 'media') m,
      ];
      return [
        for (final m in received)
          for (final v in await bob.engine.media.viewsOf(m.localRowid)) v.phase,
      ];
    }

    test('images and voice notes by themselves, videos on demand', () async {
      await start(aliceProcessor: FakeProcessor(thumbnail: thumbnailBytes()));
      for (final (kind, mime) in [
        (MediaItemKind.image, 'image/png'),
        (MediaItemKind.voiceNote, 'audio/ogg'),
        (MediaItemKind.video, 'video/mp4'),
      ]) {
        await alice.engine.media.sendMedia(chat, [
          MediaInput.bytes(bytes: patterned(2000), kind: kind, mime: mime),
        ]);
      }
      expect(await phases(), [
        TransferPhase.ready,
        TransferPhase.ready,
        TransferPhase.notDownloaded,
      ]);
      // The video's thumbnail came anyway, as its own small transfer.
      final video = (await bob.messages(
        alice,
      )).lastWhere((m) => m.kind == 'media');
      final att = (await bob.attachments(video)).single;
      expect(att.thumbnailPath, isNotNull);
      expect(att.localPath, isNull);
    });

    test('a size limit applies per kind, and settings change it', () async {
      await start();
      await bob.engine.settings.set(MediaSettings.autoDownloadImages, 1000);
      await bob.engine.settings.set(
        MediaSettings.autoDownloadDocuments,
        MediaSettings.unlimited,
      );
      await alice.engine.media.sendMedia(chat, [
        MediaInput.bytes(
          bytes: patterned(5000),
          kind: MediaItemKind.image,
          mime: 'image/jpeg',
        ),
        MediaInput.bytes(
          bytes: patterned(500),
          kind: MediaItemKind.image,
          mime: 'image/jpeg',
        ),
        MediaInput.bytes(
          bytes: patterned(8000),
          kind: MediaItemKind.document,
          mime: 'text/plain',
        ),
      ]);
      expect(await phases(), [
        TransferPhase.notDownloaded, // over the image limit
        TransferPhase.ready,
        TransferPhase.ready,
      ]);
    });

    test('never fetches more than the engine allows', () async {
      await start(transfers: testTransfers.copyWith(maxDownloadBytes: 1000));
      await alice.engine.media.sendMedia(chat, [
        MediaInput.bytes(
          bytes: patterned(5000),
          kind: MediaItemKind.image,
          mime: 'image/jpeg',
        ),
      ]);
      await bob.engine.settings.set(
        MediaSettings.autoDownloadImages,
        MediaSettings.unlimited,
      );
      expect(await phases(), [TransferPhase.notDownloaded]);
      final received = await lastMessage(bob, alice);
      final att = (await bob.attachments(received)).single;
      await bob.engine.media.downloadNow(att.id);
      await bob.engine.drainTransfers();
      final view = (await bob.engine.media.viewsOf(received.localRowid)).single;
      expect(view.phase, TransferPhase.failed);
      expect(view.failure, TransferFailure.tooLarge);
    });
  });

  group('forwarding', () {
    test('reuses the uploaded object, with no upload', () async {
      await start();
      final carol = await world.register('carol');
      final original = await alice.engine.media.sendMedia(chat, [
        MediaInput.bytes(
          bytes: patterned(4000),
          kind: MediaItemKind.document,
          mime: 'text/plain',
          name: 'notes.txt',
        ),
      ], caption: 'notes');
      await alice.settle();
      final uploads = world.media.of('POST').length;
      final carolChat = await alice.openChat(carol);

      final forwarded = await alice.engine.media.forward(
        original.localRowid,
        carolChat,
      );
      expect(forwarded.forwarded, isTrue);
      expect(forwarded.body, 'notes');
      // Nothing to upload: the op is a normal one, not held.
      await alice.engine.drainOutbox();
      expect(world.media.of('POST'), hasLength(uploads));

      final first = (await alice.attachments(original)).single;
      final second = (await alice.attachments(forwarded)).single;
      expect(second.mediaId, first.mediaId);
      expect(second.mediaKey, first.mediaKey);
      expect(second.digest, first.digest);
      // The copy the forwarder holds is its own file.
      expect(second.localPath, isNot(first.localPath));
      expect(alice.blobs.bytesOf(second.localPath!), patterned(4000));

      // Carol fetches it from the same object.
      await carol.engine.settings.set(
        MediaSettings.autoDownloadDocuments,
        MediaSettings.unlimited,
      );
      await carol.settle();
      final fetched = (await carol.messages(alice)).single;
      final att = (await carol.attachments(fetched)).single;
      expect(
        carol.blobs.bytesOf((await carol.engine.media.openLocalPath(att.id))!),
        patterned(4000),
      );
    });

    test('an old message is uploaded again under a new key', () async {
      await start();
      final carol = await world.register('carol');
      final original = await alice.engine.media.sendMedia(chat, [
        MediaInput.bytes(
          bytes: patterned(4000),
          kind: MediaItemKind.document,
          mime: 'text/plain',
        ),
      ]);
      await alice.settle();
      world.clock.advance(const Duration(days: 25));
      world.media.expireAll();
      final carolChat = await alice.openChat(carol);
      final forwarded = await alice.engine.media.forward(
        original.localRowid,
        carolChat,
      );
      await alice.settle();
      final first = (await alice.attachments(original)).single;
      final second = (await alice.attachments(forwarded)).single;
      expect(second.mediaId, isNotEmpty);
      expect(second.mediaId, isNot(first.mediaId));
      expect(second.mediaKey, isNot(first.mediaKey));
      expect(world.media.objects[second.mediaId]!.complete, isTrue);
      expect(world.server.sends.last.request.id, forwarded.messageId);
    });

    test('refuses a view-once message and an unfinished one', () async {
      await start();
      final carol = await world.register('carol');
      final carolChat = await alice.openChat(carol);
      final once = await alice.engine.media.sendMedia(chat, [
        MediaInput.bytes(
          bytes: pngLike(8, 8),
          kind: MediaItemKind.image,
          mime: 'image/png',
        ),
      ], viewOnce: true);
      expect(
        () => alice.engine.media.forward(once.localRowid, carolChat),
        throwsStateError,
      );
      final plain = await alice.engine.media.sendMedia(chat, [
        MediaInput.bytes(
          bytes: patterned(100),
          kind: MediaItemKind.document,
          mime: 'text/plain',
        ),
      ]);
      expect(
        () => alice.engine.media.forward(plain.localRowid, carolChat),
        throwsStateError,
      );
    });
  });

  group('view once and disappearing', () {
    test(
      'a view-once photo has no preview and is deleted after viewing',
      () async {
        await start(
          aliceProcessor: FakeProcessor(
            thumbnail: thumbnailBytes(),
            blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj',
          ),
        );
        await alice.engine.media.sendMedia(chat, [
          MediaInput.bytes(
            bytes: pngLike(50, 60, length: 4000),
            kind: MediaItemKind.image,
            mime: 'image/png',
          ),
        ], viewOnce: true);
        await alice.settle();
        await bob.settle();

        final received = await lastMessage(bob, alice);
        expect(received.viewOnceState, ViewOnceState.unopened);
        final att = (await bob.attachments(received)).single;
        expect(att.thumbnail, isNull);
        expect(att.blurhash, isNull);
        expect(att.transfer, AttachmentTransfer.ready);
        final path = att.localPath!;
        expect(bob.blobs.exists(path), isTrue);

        // Not consumable before it was opened.
        expect(
          () => bob.engine.media.consumeViewOnce(received.localRowid),
          throwsStateError,
        );
        await bob.engine.chats.openViewOnce(received.localRowid);
        expect(bob.blobs.exists(path), isTrue, reason: 'still on screen');
        await bob.engine.media.consumeViewOnce(received.localRowid);

        expect(bob.blobs.exists(path), isFalse);
        expect(await bob.attachments(received), isEmpty);
        final row = await bob.db.messagesDao.byRowid(received.localRowid);
        expect(
          row!.payload,
          isNull,
          reason: 'the key is gone with the pointer',
        );
        expect(row.viewOnceState, ViewOnceState.opened);
      },
    );

    test('files go when the message disappears', () async {
      await start();
      await alice.engine.chats.setDisappearing(chat, 60);
      await alice.settle();
      await bob.settle();
      await alice.engine.media.sendMedia(chat, [
        MediaInput.bytes(
          bytes: patterned(2500),
          kind: MediaItemKind.image,
          mime: 'image/jpeg',
        ),
      ]);
      await alice.settle();
      await bob.settle();
      final received = await lastMessage(bob, alice);
      final att = (await bob.attachments(received)).single;
      final path = att.localPath!;
      expect(bob.blobs.exists(path), isTrue);

      // Bob sees it; the timer starts; a minute later it is gone.
      await bob.engine.chats.markDisplayed(received.localRowid);
      world.clock.advance(const Duration(minutes: 2));
      await bob.engine.runMaintenance();
      expect(await bob.db.messagesDao.byRowid(received.localRowid), isNull);
      expect(bob.blobs.exists(path), isFalse);
      expect(bob.blobs.pathsIn(BlobArea.media), isEmpty);

      // Alice's own copy goes the same way.
      await alice.engine.runMaintenance();
      expect(alice.blobs.pathsIn(BlobArea.media), isEmpty);
    });

    test(
      'deleting for everyone removes the local files on both sides',
      () async {
        await start();
        final sent = await alice.engine.media.sendMedia(chat, [
          MediaInput.bytes(
            bytes: patterned(2500),
            kind: MediaItemKind.image,
            mime: 'image/jpeg',
          ),
        ]);
        await alice.settle();
        await bob.settle();
        expect(bob.blobs.pathsIn(BlobArea.media), hasLength(1));
        await alice.engine.chats.deleteForEveryone(sent.localRowid);
        await alice.settle();
        await bob.settle();
        await alice.engine.media.sweep();
        await bob.engine.media.sweep();
        expect(alice.blobs.pathsIn(BlobArea.media), isEmpty);
        expect(bob.blobs.pathsIn(BlobArea.media), isEmpty);
      },
    );
  });

  group('engine without a file store', () {
    test('cannot send, and keeps incoming attachments remote', () async {
      await start();
      // Bob's engine, built without a BlobStore, on the same server.
      final bare = await world.registerWithoutBlobs('bare');
      expect(bare.engine.media.isAvailable, isFalse);
      final bareChat = await alice.openChat(bare);
      await alice.engine.media.sendMedia(bareChat, [
        MediaInput.bytes(
          bytes: patterned(300),
          kind: MediaItemKind.image,
          mime: 'image/png',
        ),
      ]);
      await alice.settle();
      await bare.engine.syncOnce();
      final received = (await bare.db.messagesDao.pageOlder(
        directConversationId(alice.account),
      )).messages.single;
      expect(
        (await bare.db.messagesDao.attachmentsFor([
          received.localRowid,
        ])).single.transfer,
        AttachmentTransfer.remote,
      );
      expect(
        () => bare.engine.media.sendMedia(directConversationId(alice.account), [
          MediaInput.bytes(
            bytes: patterned(30),
            kind: MediaItemKind.image,
            mime: 'image/png',
          ),
        ]),
        throwsStateError,
      );
    });
  });
}
