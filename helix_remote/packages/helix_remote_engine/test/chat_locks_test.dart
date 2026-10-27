import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:test/test.dart';

import 'support/peers.dart';

/// A locked chat: private to this device, quiet about who and what.
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

  test(
    'locking moves the chat to Locked, and unlocking brings it back',
    () async {
      final chat = await alice.engine.chats.openDirect(bob.account);
      await alice.engine.chats.sendText(chat.id, 'hello');
      await alice.engine.chats.setLocked(chat.id, locked: true);
      expect(await alice.db.conversationsDao.watchList().first, isEmpty);
      expect(
        [
          for (final c in await alice.engine.chats.watchLockedChats().first)
            c.conversation.id,
        ],
        [chat.id],
      );
      await alice.engine.chats.setLocked(chat.id, locked: false);
      expect(await alice.engine.chats.watchLockedChats().first, isEmpty);
      expect(await alice.db.conversationsDao.watchList().first, hasLength(1));
    },
  );

  test(
    'a message into a locked chat arrives, flagged for a bare alert',
    () async {
      final chat = await bob.engine.chats.openDirect(alice.account);
      await bob.engine.chats.sendText(chat.id, 'first');
      await bob.engine.drainOutbox();
      await alice.sync();

      await alice.engine.chats.setLocked(alice.chatWith(bob), locked: true);
      await bob.engine.chats.sendText(chat.id, 'private');
      await bob.engine.drainOutbox();
      final summary = await alice.sync();
      expect(summary.notices.single.locked, isTrue);
      expect(await alice.texts(bob), ['first', 'private']);
    },
  );

  test('an ordinary chat is not flagged', () async {
    final chat = await bob.engine.chats.openDirect(alice.account);
    await bob.engine.chats.sendText(chat.id, 'hi');
    await bob.engine.drainOutbox();
    final summary = await alice.sync();
    expect(summary.notices.single.locked, isFalse);
  });

  test('a lock is never sent', () async {
    final chat = await alice.engine.chats.openDirect(bob.account);
    final before = peers.server.sends.length;
    await alice.engine.chats.setLocked(chat.id, locked: true);
    await alice.engine.drainOutbox();
    expect(peers.server.sends.length, before);
  });
}
