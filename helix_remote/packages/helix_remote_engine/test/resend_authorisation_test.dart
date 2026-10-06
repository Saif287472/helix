import 'package:helix_remote_db/helix_remote_db.dart' hide GroupRole;
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support/fake_groups.dart';
import 'support/peers.dart';

/// Who may have an own message sent again (CRYPTO_V2.md §13a): the chat's
/// peer, this account's own devices and, in a group, members that were in it
/// when the message was sent. Everyone else is ignored without an answer.
void main() {
  late Peers peers;

  setUp(() {
    peers = Peers();
    FakeGroups(peers.server);
  });
  tearDown(() => peers.dispose());

  /// [from] asks [to] to send the messages [ids] again ([to]'s sync also
  /// sends what that queued).
  Future<void> ask(Peer from, Peer to, List<String> ids) async {
    await from.engine.debugSend(
      ContentMessage(
        id: Uuid.v7(),
        sentAt: peers.clock.now,
        conversation: DirectConversation(to: to.account),
        body: ResendRequestBody(ids: ids),
      ),
      audience: [to.account],
    );
    await from.engine.drainOutbox();
    await to.sync();
    await to.engine.drainOutbox();
  }

  Future<void> askDecryptionError(Peer from, Peer to, String id) async {
    await from.engine.debugSend(
      ContentMessage(
        id: Uuid.v7(),
        sentAt: peers.clock.now,
        conversation: DirectConversation(to: to.account),
        body: DecryptionErrorBody(messageId: id, senderDevice: to.device),
      ),
      audience: [to.account],
    );
    await from.engine.drainOutbox();
    await to.sync();
    await to.engine.drainOutbox();
  }

  int waiting(Peer p) => peers.server.device(p.device).mailbox.length;

  group('direct messages', () {
    late Peer alice;
    late Peer bob;
    late Peer mallory;
    late MessageRow secret;

    setUp(() async {
      alice = await peers.register('alice', phone: '+8801711000001');
      bob = await peers.register('bob', phone: '+8801711000002');
      mallory = await peers.register('mallory', phone: '+8801711000009');
      final chat = await alice.engine.chats.openDirect(bob.account);
      secret = await alice.engine.chats.sendText(chat.id, 'for Bob only');
      await alice.engine.drainOutbox();
      await bob.sync();
      // Mallory has talked to Alice, so a session exists between them.
      final hello = await mallory.engine.chats.openDirect(alice.account);
      await mallory.engine.chats.sendText(hello.id, 'hi');
      await mallory.engine.drainOutbox();
      await alice.sync();
      await alice.engine.drainOutbox();
      await mallory.sync();
    });

    test('a stranger asking for the id of a message of another chat gets '
        'nothing, for either request type', () async {
      expect(waiting(mallory), 0);
      await ask(mallory, alice, [secret.messageId]);
      await askDecryptionError(mallory, alice, secret.messageId);
      expect(waiting(mallory), 0, reason: 'nothing was sent to the stranger');
      await mallory.sync();
      expect(await mallory.texts(alice), ['hi']);
    });

    test('the chat peer gets the message again', () async {
      await ask(bob, alice, [secret.messageId]);
      expect(waiting(bob), greaterThan(0));
    });

    test('a blocked peer gets nothing', () async {
      await alice.engine.people.block(bob.account);
      await ask(bob, alice, [secret.messageId]);
      expect(waiting(bob), 0);
    });

    test("one of the account's own devices gets it", () async {
      final alice2 = await peers.link(alice, 'alice2');
      final before = waiting(alice2);
      await ask(alice2, alice, [secret.messageId]);
      expect(waiting(alice2), greaterThan(before));
    });
  });

  group('group messages', () {
    late Peer alice;
    late Peer bob;
    late String groupId;

    setUp(() async {
      alice = await peers.register('alice', phone: '+8801711000001');
      bob = await peers.register('bob', phone: '+8801711000002');
      final created = await alice.engine.groups.create(
        name: 'Weekend',
        members: [bob.account],
      );
      groupId = created.groupId;
      await alice.engine.drainOutbox();
      await bob.sync();
      await alice.sync();
    });

    Future<MessageRow> post(String text, List<Peer> readers) async {
      final row = await alice.engine.chats.sendText(
        GroupIds.conversationId(groupId),
        text,
      );
      await alice.engine.drainOutbox();
      for (final r in readers) {
        await r.sync();
      }
      return row;
    }

    test('a member added later cannot pull earlier messages, but gets the '
        'ones sent after it joined', () async {
      final old = await post('old news', [bob]);
      peers.clock.advance(const Duration(minutes: 5));
      final dave = await peers.register('dave', phone: '+8801711000004');
      await alice.engine.groups.addMembers(groupId, [dave.account]);
      await alice.engine.drainOutbox();
      await dave.sync();
      peers.clock.advance(const Duration(minutes: 5));
      final fresh = await post('new news', [bob, dave]);
      final before = waiting(dave);

      await ask(dave, alice, [old.messageId]);
      await askDecryptionError(dave, alice, old.messageId);
      expect(waiting(dave), before, reason: 'the history is not served');

      await ask(dave, alice, [fresh.messageId]);
      expect(waiting(dave), greaterThan(before));
    });

    test('a member that was in the group when it was sent can ask', () async {
      final row = await post('hello', [bob]);
      await ask(bob, alice, [row.messageId]);
      expect(waiting(bob), greaterThan(0));
    });

    test('a blocked member gets nothing', () async {
      final row = await post('hello', [bob]);
      await alice.engine.people.block(bob.account);
      await ask(bob, alice, [row.messageId]);
      expect(waiting(bob), 0);
    });

    test('someone who is not in the group gets nothing', () async {
      final row = await post('hello', [bob]);
      final mallory = await peers.register('mallory', phone: '+8801711000009');
      final hello = await mallory.engine.chats.openDirect(alice.account);
      await mallory.engine.chats.sendText(hello.id, 'hi');
      await mallory.engine.drainOutbox();
      await alice.sync();
      await alice.engine.drainOutbox();
      await mallory.sync();
      final before = waiting(mallory);
      await ask(mallory, alice, [row.messageId]);
      expect(waiting(mallory), before);
    });
  });
}
