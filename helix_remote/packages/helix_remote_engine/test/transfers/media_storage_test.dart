import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
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
}
