import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:test/test.dart';

import 'support/peers.dart';

/// The person's own lists of chats: private, named, capped.
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

  ChatsService chats() => alice.engine.chats;

  test('a list is made, renamed, filled, emptied and deleted', () async {
    final chat = await chats().openDirect(bob.account);
    final id = await chats().createChatList('  Work ');
    expect((await chats().watchChatLists().first).single.name, 'Work');

    await chats().renameChatList(id, 'Office');
    await chats().setChatsOnList(id, [chat.id], member: true);
    expect(
      (await chats().watchChatListMembers().first).single.conversationId,
      chat.id,
    );
    await chats().setChatsOnList(id, [chat.id], member: false);
    expect(await chats().watchChatListMembers().first, isEmpty);

    await chats().deleteChatList(id);
    expect(await chats().watchChatLists().first, isEmpty);
    expect(await alice.db.conversationsDao.byId(chat.id), isNotNull);
  });

  test('a name must be 1 to 24 characters and not already used', () async {
    for (final bad in ['', '   ', 'x' * 25]) {
      expect(() => chats().createChatList(bad), throwsArgumentError);
    }
    final id = await chats().createChatList('Family');
    expect(
      () => chats().createChatList('family'),
      throwsA(isA<EngineStateException>()),
    );
    // Its own name is not a clash when it is renamed to a new case.
    await chats().renameChatList(id, 'FAMILY');
    await chats().createChatList('Work');
    expect(
      () => chats().renameChatList(id, 'work'),
      throwsA(isA<EngineStateException>()),
    );
  });

  test('a person keeps at most ten lists', () async {
    for (var i = 0; i < ChatsService.maxChatLists; i++) {
      await chats().createChatList('List $i');
    }
    expect(
      () => chats().createChatList('One more'),
      throwsA(isA<EngineStateException>()),
    );
  });

  test('a list is never sent: it adds nothing to the outbox', () async {
    final chat = await chats().openDirect(bob.account);
    final before = peers.server.sends.length;
    final id = await chats().createChatList('Work');
    await chats().setChatsOnList(id, [chat.id], member: true);
    await alice.engine.drainOutbox();
    expect(peers.server.sends.length, before);
  });
}
