import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_engine/src/transfers/media_settings.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

/// What this device keeps and what "free up space" removes, over the fake
/// server and file store.
void main() {
  late MediaWorld world;
  late MediaPeer alice;
  late MediaPeer bob;
  late String chat;

  setUp(() async {
    world = MediaWorld();
    alice = await world.register(
      'alice',
      processor: FakeProcessor(thumbnail: thumbnailBytes()),
    );
    bob = await world.register('bob');
    chat = await alice.openChat(bob);
  });

  tearDown(() => world.dispose());

  /// Sends one message of each kind from Alice and downloads all of them on
  /// Bob's side, video and document included (auto-download is off for those).
  Future<Map<String, AttachmentRow>> receiveMedia() async {
    for (final (kind, mime, size, name) in [
      (MediaItemKind.image, 'image/png', 20000, null),
      (MediaItemKind.video, 'video/mp4', 30000, null),
      (MediaItemKind.document, 'application/pdf', 9000, 'invoice.pdf'),
      (MediaItemKind.voiceNote, 'audio/ogg', 5000, null),
    ]) {
      await alice.engine.media.sendMedia(chat, [
        MediaInput.bytes(
          bytes: patterned(size, seed: size),
          kind: kind,
          mime: mime,
          name: name,
        ),
      ]);
    }
    await alice.settle();
    await bob.settle();
    // Video and document wait for a tap under the default policy.
    for (final message in await bob.messages(alice)) {
      for (final a in await bob.attachments(message)) {
        await bob.engine.media.downloadNow(a.id);
      }
    }
    await bob.settle();
    final attachments = <String, AttachmentRow>{};
    for (final message in await bob.messages(alice)) {
      for (final a in await bob.attachments(message)) {
        expect(
          await bob.engine.media.openLocalPath(a.id),
          isNotNull,
          reason: '${a.kind} should have arrived',
        );
        attachments[a.kind] = a;
      }
    }
    return attachments;
  }

  test('the totals split local media by kind', () async {
    await receiveMedia();

    final usage = await bob.engine.media.storageUsage();
    expect(usage.photosVideosBytes, 20000 + 30000);
    expect(usage.filesBytes, 9000);
    expect(usage.voiceNoteBytes, 5000);
    expect(usage.totalBytes, 64000);

    final chats = await bob.engine.media.biggestChats();
    expect(chats, hasLength(1));
    expect(chats.single.conversationId, bob.chatWith(alice));
    expect(chats.single.photosVideosBytes, 50000);
    expect(chats.single.filesBytes, 9000);
    expect(chats.single.totalBytes, 59000);
  });

  test('freeing photos keeps the messages and fetches them again', () async {
    final attachments = await receiveMedia();
    final image = attachments['image']!;
    final thumbnail = await bob.engine.media.thumbnailPath(image.id);
    expect(thumbnail, isNotNull);

    final freed = await bob.engine.media.freeChatSpace(
      bob.chatWith(alice),
      FreeKind.photosVideos,
    );
    expect(freed, 50000);

    final after = (await bob.db.messagesDao.attachmentById(image.id))!;
    expect(after.transfer, AttachmentTransfer.remote);
    expect(after.localPath, isNull);
    expect(after.thumbnailPath, isNull);
    expect(after.mediaId, image.mediaId, reason: 'the pointer stays');
    expect(after.digest, image.digest);
    expect(await bob.engine.media.openLocalPath(image.id), isNull);
    expect(await bob.engine.media.thumbnailPath(image.id), isNull);
    expect(await bob.blobs.length(image.localPath!), isNull);
    expect(await bob.blobs.length(thumbnail!), isNull);
    expect(
      await bob.db.messagesDao.byRowid(image.messageRowid),
      isNotNull,
      reason: 'the message stays',
    );

    final usage = await bob.engine.media.storageUsage();
    expect(usage.photosVideosBytes, 0);
    expect(usage.filesBytes, 9000);
    expect(usage.voiceNoteBytes, 5000);
    final chats = await bob.engine.media.biggestChats();
    expect(chats.single.photosVideosBytes, 0);
    expect(chats.single.filesBytes, 9000);

    // The server still has the object: a tap fetches it again.
    await bob.engine.media.downloadNow(image.id);
    await bob.settle();
    final path = await bob.engine.media.openLocalPath(image.id);
    expect(path, isNotNull);
    expect(bob.blobs.bytesOf(path!), patterned(20000, seed: 20000));
    expect(await bob.engine.media.thumbnailPath(image.id), isNotNull);
    expect((await bob.engine.media.storageUsage()).photosVideosBytes, 20000);
  });

  test('freeing documents leaves the photos and voice notes', () async {
    final attachments = await receiveMedia();

    final freed = await bob.engine.media.freeChatSpace(
      bob.chatWith(alice),
      FreeKind.documents,
    );
    expect(freed, 9000);

    final document = (await bob.db.messagesDao.attachmentById(
      attachments['document']!.id,
    ))!;
    expect(document.transfer, AttachmentTransfer.remote);
    expect(document.localPath, isNull);
    expect(
      (await bob.db.messagesDao.attachmentById(
        attachments['image']!.id,
      ))!.transfer,
      AttachmentTransfer.ready,
    );
    expect(
      (await bob.db.messagesDao.attachmentById(
        attachments['voice_note']!.id,
      ))!.transfer,
      AttachmentTransfer.ready,
    );

    final usage = await bob.engine.media.storageUsage();
    expect(usage.photosVideosBytes, 50000);
    expect(usage.filesBytes, 0);
    expect(usage.voiceNoteBytes, 5000);
    expect((await bob.engine.media.biggestChats()).single.filesBytes, 0);
  });

  test('biggest chats is ordered and leaves voice notes out', () async {
    final charlie = await world.register('charlie');
    final charlieChat = await charlie.openChat(bob);
    final otherChat = bob.chatWith(charlie);
    await charlie.engine.media.sendMedia(charlieChat, [
      MediaInput.bytes(
        bytes: patterned(40000, seed: 4),
        kind: MediaItemKind.image,
        mime: 'image/png',
      ),
    ]);
    // Alice's chat has only a voice note: nothing there can be freed.
    await alice.engine.media.sendMedia(chat, [
      MediaInput.bytes(
        bytes: patterned(7000, seed: 7),
        kind: MediaItemKind.voiceNote,
        mime: 'audio/ogg',
      ),
    ]);
    await charlie.settle();
    await alice.settle();
    await bob.settle();
    for (final message in await bob.messages(charlie)) {
      for (final a in await bob.attachments(message)) {
        await bob.engine.media.downloadNow(a.id);
      }
    }
    await bob.settle();

    final chats = await bob.engine.media.biggestChats();
    expect(chats, hasLength(1));
    expect(chats.single.conversationId, otherChat);
    expect(chats.single.photosVideosBytes, 40000);
    expect(chats.single.filesBytes, 0);

    final usage = await bob.engine.media.storageUsage();
    expect(usage.photosVideosBytes, 40000);
    expect(usage.voiceNoteBytes, 7000);

    // Freeing one chat does not touch the other.
    await bob.engine.media.freeChatSpace(
      bob.chatWith(alice),
      FreeKind.photosVideos,
    );
    expect((await bob.engine.media.storageUsage()).photosVideosBytes, 40000);
  });

  /// Media this account sent keeps the app's copy as the only file its bubble
  /// has; once the server drops the object (30 days) it cannot be fetched
  /// again, so the Storage page does not count it and "free up space" does
  /// not delete it (AUD-12m-1).
  test('sent media is neither counted nor freed', () async {
    await alice.engine.media.sendMedia(chat, [
      MediaInput.bytes(
        bytes: patterned(12000, seed: 3),
        kind: MediaItemKind.image,
        mime: 'image/png',
      ),
    ]);
    await alice.settle();
    final sent = (await alice.attachments(
      (await alice.messages(bob)).single,
    )).single;
    expect(sent.localPath, isNotNull);

    expect((await alice.engine.media.storageUsage()).totalBytes, 0);
    expect(await alice.engine.media.biggestChats(), isEmpty);
    expect(
      await alice.engine.media.freeChatSpace(chat, FreeKind.photosVideos),
      0,
    );
    final after = (await alice.db.messagesDao.attachmentById(sent.id))!;
    expect(after.transfer, AttachmentTransfer.ready);
    expect(alice.blobs.bytesOf(after.localPath!), patterned(12000, seed: 3));
  });

  /// One mapping for the three views (AUD-12m-4): whatever the Storage page
  /// counts as a file, `FreeKind.documents` frees - a kind from a newer client
  /// included - and the totals and the per-chat list add up.
  test('the page and the free action agree on every kind', () async {
    final attachments = await receiveMedia();
    // A kind this version has never heard of, downloaded here.
    final stranger = attachments['document']!;
    await bob.db.customStatement(
      "UPDATE attachments SET kind = 'hologram' WHERE id = ?",
      [stranger.id],
    );
    final usage = await bob.engine.media.storageUsage();
    final chats = await bob.engine.media.biggestChats();
    expect(usage.filesBytes, 9000);
    expect(
      usage.totalBytes - usage.voiceNoteBytes,
      chats.fold<int>(0, (sum, c) => sum + c.totalBytes),
    );

    expect(
      await bob.engine.media.freeChatSpace(
        bob.chatWith(alice),
        FreeKind.documents,
      ),
      9000,
    );
    expect((await bob.engine.media.storageUsage()).filesBytes, 0);
    expect(MediaSettings.groupOf('video_note'), MediaKindGroup.photoVideo);
    expect(MediaSettings.groupOf('voice_note'), MediaKindGroup.voice);
    expect(MediaSettings.groupOf('hologram'), MediaKindGroup.file);
  });
}
