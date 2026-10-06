import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'support/peers.dart';

/// The small read helpers the app's chat list and conversation screens need
/// on top of the C3b chat queries. Reads need no account, so the peer is
/// never signed in.
void main() {
  late Peers peers;

  setUp(() => peers = Peers());
  tearDown(() => peers.dispose());

  Future<MessageRow> incoming(Peer peer, String chat, String id, int second) =>
      peer.db.messagesDao.insertMessage(
        MessagesCompanion.insert(
          messageId: id,
          conversationId: chat,
          sender: 'bob',
          outgoing: false,
          sortKey: SortKey.of(DateTime.utc(2026, 10, 1, 12, 0, second), id),
          sentAt: DateTime.utc(2026, 10, 1, 12, 0, second),
          receivedAt: DateTime.utc(2026, 10, 1, 12, 0, second),
          kind: 'text',
          body: Value('hello $id'),
          status: MessageStatus.received,
        ),
      );

  test('watchAllTyping follows every chat and clears when it stops', () async {
    final a = await peers.create('a');
    final seen = <Map<String, Set<String>>>[];
    final sub = a.engine.presence.watchAllTyping().listen(seen.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();
    expect(seen.last, isEmpty);

    a.engine.presence.onTyping('direct:bob', 'bob', typing: true);
    a.engine.presence.onTyping('group:g1', 'carol', typing: true);
    await pumpEventQueue();
    expect(seen.last, {
      'direct:bob': {'bob'},
      'group:g1': {'carol'},
    });

    a.engine.presence.onTyping('direct:bob', 'bob', typing: false);
    await pumpEventQueue();
    expect(seen.last, {
      'group:g1': {'carol'},
    });
  });

  test(
    'findMessage and watchMessagesFrom read a window by content id',
    () async {
      final a = await peers.create('a');
      final chat = (await a.engine.chats.openDirect('bob')).id;
      await incoming(a, chat, 'm1', 1);
      final second = await incoming(a, chat, 'm2', 2);
      await incoming(a, chat, 'm3', 3);

      expect(
        (await a.engine.chats.findMessage(chat, 'm2'))?.localRowid,
        second.localRowid,
      );
      expect(await a.engine.chats.findMessage(chat, 'nope'), isNull);

      final window = await a.engine.chats
          .watchMessagesFrom(chat, second.sortKey, limit: 10)
          .first;
      expect([for (final m in window) m.messageId], ['m2', 'm3']);
    },
  );

  test('clearChat empties the chat and keeps it in the list', () async {
    final a = await peers.create('a');
    final chat = (await a.engine.chats.openDirect('bob')).id;
    await incoming(a, chat, 'm1', 1);
    await incoming(a, chat, 'm2', 2);

    await a.engine.chats.clearChat(chat);

    final list = await a.engine.chats.watchChats().first;
    expect([for (final c in list) c.conversation.id], [chat]);
    expect(list.single.lastMessage, isNull);
    expect(list.single.conversation.unreadCount, 0);
  });
}
