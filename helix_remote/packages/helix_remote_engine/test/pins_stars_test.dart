import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support/peers.dart';

/// Pinned messages (shared, a `pin` action), starred messages and favourite
/// chats (private to this device).
void main() {
  late Peers peers;
  late Peer alice;
  late Peer bob;

  setUp(() async {
    peers = Peers();
    alice = await peers.register('alice', phone: '+8801711000001');
    bob = await peers.register('bob', phone: '+8801711000002');
  });
  tearDown(() => peers.dispose());

  /// Alice says [text]; Bob fetches it. Both rows come back.
  Future<({MessageRow mine, MessageRow theirs})> say(String text) async {
    final chat = await alice.engine.chats.openDirect(bob.account);
    final mine = await alice.engine.chats.sendText(chat.id, text);
    await alice.engine.drainOutbox();
    await bob.sync();
    final theirs = (await bob.messages(
      alice,
    )).firstWhere((m) => m.body == text);
    return (mine: mine, theirs: theirs);
  }

  Future<MessageRow> row(Peer peer, int rowid) async =>
      (await peer.db.messagesDao.byRowid(rowid))!;

  group('a pin', () {
    test('reaches the other side, and so does taking it off', () async {
      final m = await say('meet at 5');
      await bob.engine.chats.pinMessage(m.theirs.localRowid, pinned: true);
      expect((await row(bob, m.theirs.localRowid)).pinnedAt, isNotNull);
      await bob.engine.drainOutbox();
      await alice.sync();
      expect((await row(alice, m.mine.localRowid)).pinnedAt, isNotNull);
      expect(
        [
          for (final p in await alice.db.messagesDao.pinnedIn(
            m.mine.conversationId,
          ))
            p.body,
        ],
        ['meet at 5'],
      );

      peers.clock.advance(const Duration(minutes: 1));
      await alice.engine.chats.pinMessage(m.mine.localRowid, pinned: false);
      await alice.engine.drainOutbox();
      await bob.sync();
      expect((await row(bob, m.theirs.localRowid)).pinnedAt, isNull);
    });

    test('is sent as a quiet action, not a message', () async {
      final m = await say('hello');
      final sends = peers.server.sends.length;
      await bob.engine.chats.pinMessage(m.theirs.localRowid, pinned: true);
      await bob.engine.drainOutbox();
      expect(peers.server.sends.length, sends + 1);
      expect(
        (await bob.messages(alice)).length,
        1,
        reason: 'a pin adds no bubble',
      );
    });

    test(
      'pinning twice, or unpinning what is not pinned, sends nothing',
      () async {
        final m = await say('hello');
        await bob.engine.chats.pinMessage(m.theirs.localRowid, pinned: false);
        await bob.engine.chats.pinMessage(m.theirs.localRowid, pinned: true);
        await bob.engine.chats.pinMessage(m.theirs.localRowid, pinned: true);
        await bob.engine.drainOutbox();
        final pins = peers.server.sends.length;
        await bob.engine.chats.pinMessage(m.theirs.localRowid, pinned: true);
        await bob.engine.drainOutbox();
        expect(peers.server.sends.length, pins);
      },
    );

    test('a chat keeps at most three, and one more is refused', () async {
      final rows = [for (var i = 0; i < 4; i++) await say('m$i')];
      for (final m in rows.take(3)) {
        await bob.engine.chats.pinMessage(m.theirs.localRowid, pinned: true);
        peers.clock.advance(const Duration(seconds: 1));
      }
      await expectLater(
        bob.engine.chats.pinMessage(rows.last.theirs.localRowid, pinned: true),
        throwsA(isA<EngineStateException>()),
      );
      expect((await row(bob, rows.last.theirs.localRowid)).pinnedAt, isNull);

      await bob.engine.chats.pinMessage(
        rows.first.theirs.localRowid,
        pinned: false,
      );
      await bob.engine.chats.pinMessage(
        rows.last.theirs.localRowid,
        pinned: true,
      );
      expect(
        [
          for (final p in await bob.db.messagesDao.pinnedIn(
            rows.last.theirs.conversationId,
          ))
            p.body,
        ],
        ['m3', 'm2', 'm1'],
        reason: 'the newest pin first',
      );
    });

    test(
      'a pin that arrives before its message is kept until it comes',
      () async {
        final chat = await alice.engine.chats.openDirect(bob.account);
        final sent = await alice.engine.chats.sendText(chat.id, 'late one');
        // The pin goes out first: Bob has not fetched the message yet.
        await alice.engine.chats.pinMessage(sent.localRowid, pinned: true);
        await alice.engine.drainOutbox();
        await bob.sync();
        expect(
          (await bob.messages(alice)).single.pinnedAt,
          isNotNull,
          reason: 'applied once the message was there',
        );
      },
    );

    test('an older unpin does not undo a newer pin', () async {
      final m = await say('hello');
      final target = MessageRef(id: m.theirs.messageId, author: alice.account);
      final earlier = peers.clock.now;
      peers.clock.advance(const Duration(minutes: 5));
      await bob.engine.chats.pinMessage(m.theirs.localRowid, pinned: true);
      final pinnedAt = (await row(bob, m.theirs.localRowid)).pinnedAt!;
      expect(pinnedAt.isAfter(earlier), isTrue);

      // Alice's unpin, stamped before Bob's pin, arrives late.
      await alice.engine.debugSend(
        ContentMessage(
          id: Uuid.v7(),
          sentAt: earlier,
          conversation: DirectConversation(to: bob.account),
          body: PinBody(target: target, remove: true),
        ),
        audience: [bob.account],
      );
      await alice.engine.drainOutbox();
      await bob.sync();
      expect((await row(bob, m.theirs.localRowid)).pinnedAt, pinnedAt);
    });

    test('a message deleted for everyone is unpinned', () async {
      final m = await say('oops');
      await bob.engine.chats.pinMessage(m.theirs.localRowid, pinned: true);
      await bob.engine.drainOutbox();
      await alice.sync();
      await alice.engine.chats.deleteForEveryone(m.mine.localRowid);
      await alice.engine.drainOutbox();
      await bob.sync();
      final gone = await row(bob, m.theirs.localRowid);
      expect(gone.deletedAt, isNotNull);
      expect(gone.pinnedAt, isNull);
    });
  });

  group('a star', () {
    test(
      'is private: nothing is sent, and the other side never sees it',
      () async {
        final m = await say('remember this');
        final sends = peers.server.sends.length;
        await bob.engine.chats.setStarred(m.theirs.localRowid, starred: true);
        await bob.engine.drainOutbox();
        await alice.sync();
        expect(peers.server.sends.length, sends);
        expect((await row(alice, m.mine.localRowid)).starredAt, isNull);
        expect(
          [for (final s in await bob.engine.chats.watchStarred().first) s.body],
          ['remember this'],
        );
        await bob.engine.chats.setStarred(m.theirs.localRowid, starred: false);
        expect(await bob.engine.chats.watchStarred().first, isEmpty);
      },
    );

    test('a deleted message cannot be starred', () async {
      final m = await say('oops');
      await alice.engine.chats.deleteForEveryone(m.mine.localRowid);
      await alice.engine.drainOutbox();
      await bob.sync();
      await bob.engine.chats.setStarred(m.theirs.localRowid, starred: true);
      expect(await bob.engine.chats.watchStarred().first, isEmpty);
    });
  });

  test('a favourite chat is private and can be undone', () async {
    final chat = await alice.engine.chats.openDirect(bob.account);
    await alice.engine.chats.setFavourite(chat.id, favourite: true);
    expect(
      (await alice.db.conversationsDao.byId(chat.id))!.favouriteAt,
      isNotNull,
    );
    await alice.engine.chats.setFavourite(chat.id, favourite: false);
    expect(
      (await alice.db.conversationsDao.byId(chat.id))!.favouriteAt,
      isNull,
    );
  });
}
