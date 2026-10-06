import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../../support/flows.dart';
import '../../support/harness.dart';
import '../../support/test_database.dart';
import 'support.dart';

/// Two engines (Alice and Bob) through the real server: the messaging core
/// of Phase C3b, end to end.
void main() {
  group('engine messaging', skip: databaseTestSkipReason, () {
    late Harness h;
    late EngineWorld world;

    setUp(() async {
      h = await Harness.start();
      world = EngineWorld(h);
    });
    tearDown(() async {
      await world.dispose();
      await h.stop();
    });

    test('Alice and Bob exchange text both ways with receipts', () async {
      final alice = await world.register('alice', aliceNumber);
      final bob = await world.register('bob', bobNumber);

      final chat = await alice.engine.chats.openDirect(bob.account);
      final sent = await alice.engine.chats.sendText(chat.id, 'hello Bob');
      expect(sent.status, MessageStatus.pending);

      final received = await waitForText(bob, alice, 'hello Bob');
      expect(received.sender, alice.account);
      expect(received.status, MessageStatus.received);
      expect((await chatWith(bob, alice))!.unreadCount, 1);

      // The delivered receipt makes Alice's message "delivered".
      await settle(() async {
        final row = await alice.db.messagesDao.byRowid(sent.localRowid);
        expect(row!.status, MessageStatus.delivered);
      });

      // Bob reads and replies; Alice sees "read".
      await bob.engine.chats.markRead(directConversationId(alice.account));
      await bob.engine.chats.sendText(
        directConversationId(alice.account),
        'hi Alice',
        replyTo: MessageRef(id: received.messageId, author: alice.account),
      );
      final reply = await waitForText(alice, bob, 'hi Alice');
      expect(reply.replyToId, sent.messageId);
      await settle(() async {
        final row = await alice.db.messagesDao.byRowid(sent.localRowid);
        expect(row!.status, MessageStatus.read);
      });
      expect((await chatWith(bob, alice))!.unreadCount, 0);
    });

    test('two engines talking at once never corrupt a session', () async {
      // Both directions at full speed over the live sockets: every send and
      // receive on a device pair is serialised by the per-device lock, so
      // the ratchets never share a message key.
      final alice = await world.register('alice', aliceNumber);
      final bob = await world.register('bob', bobNumber);
      final toBob = await alice.engine.chats.openDirect(bob.account);
      final toAlice = await bob.engine.chats.openDirect(alice.account);
      await Future.wait([
        for (var i = 0; i < 25; i++) ...[
          alice.engine.chats.sendText(toBob.id, 'a$i'),
          bob.engine.chats.sendText(toAlice.id, 'b$i'),
        ],
      ]);
      await settle(() async {
        final atBob = [
          for (final m in await messagesWith(bob, alice))
            if (!m.outgoing) m.body,
        ];
        final atAlice = [
          for (final m in await messagesWith(alice, bob))
            if (!m.outgoing) m.body,
        ];
        expect(atBob, hasLength(25));
        expect(atAlice, hasLength(25));
      }, timeout: const Duration(seconds: 40));
      for (final (user, peer) in [(alice, bob), (bob, alice)]) {
        final rows = await messagesWith(user, peer);
        expect(
          rows.where((m) => m.kind == MessageKinds.undecryptable),
          isEmpty,
          reason: '${user.name} could not decrypt something',
        );
        // Order within one sender is the order of sending.
        final mine = [
          for (final m in rows)
            if (m.outgoing) m.body,
        ];
        expect(mine, [for (var i = 0; i < 25; i++) '${user.name[0]}$i']);
      }
      await settle(() async {
        for (final (user, peer) in [(alice, bob), (bob, alice)]) {
          for (final m in await messagesWith(user, peer)) {
            if (m.outgoing) expect(m.status, MessageStatus.delivered);
          }
        }
      }, timeout: const Duration(seconds: 40));
    });

    test('reactions, edits and deletes travel both ways', () async {
      final alice = await world.register('alice', aliceNumber);
      final bob = await world.register('bob', bobNumber);
      final chat = await alice.engine.chats.openDirect(bob.account);
      final sent = await alice.engine.chats.sendText(chat.id, 'first');
      final bobRow = await waitForText(bob, alice, 'first');

      Future<List<String>> reactionsSeenBy(EngineUser user, int rowid) async =>
          [
            for (final r in await user.db.messagesDao.reactionsFor([rowid]))
              '${r.reactor == bob.account ? 'bob' : 'alice'}:${r.emoji}',
          ];

      await bob.engine.chats.react(bobRow.localRowid, 'A');
      await settle(
        () async =>
            expect(await reactionsSeenBy(alice, sent.localRowid), ['bob:A']),
      );
      // A new reaction replaces the old one.
      await bob.engine.chats.react(bobRow.localRowid, 'B');
      await settle(
        () async =>
            expect(await reactionsSeenBy(alice, sent.localRowid), ['bob:B']),
      );
      await alice.engine.chats.react(sent.localRowid, 'C');
      await settle(
        () async => expect(
          (await reactionsSeenBy(bob, bobRow.localRowid))..sort(),
          ['alice:C', 'bob:B'],
        ),
      );
      await bob.engine.chats.react(bobRow.localRowid, null);
      await settle(
        () async =>
            expect(await reactionsSeenBy(alice, sent.localRowid), ['alice:C']),
      );

      await alice.engine.chats.edit(sent.localRowid, 'first (edited)');
      await settle(() async {
        final row = await bob.db.messagesDao.byRowid(bobRow.localRowid);
        expect(row!.body, 'first (edited)');
        expect(row.editedAt, isNotNull);
      });
      // The edited text is what the chat list shows.
      expect(
        (await chatWith(bob, alice))!.lastMessagePreview,
        'first (edited)',
      );

      // Bob cannot edit or delete Alice's message: the engine refuses to
      // send it, and the receive side ignores forged ones (unit tests).
      expect(
        () => bob.engine.chats.edit(bobRow.localRowid, 'nope'),
        throwsStateError,
      );

      await alice.engine.chats.deleteForEveryone(sent.localRowid);
      await settle(() async {
        final row = await bob.db.messagesDao.byRowid(bobRow.localRowid);
        expect(row!.deletedAt, isNotNull);
        expect(row.body, isNull);
      });
      expect(await reactionsSeenBy(bob, bobRow.localRowid), isEmpty);
    });

    test(
      'unknown content types become a placeholder row, not a crash',
      () async {
        final alice = await world.register('alice', aliceNumber);
        final bob = await world.register('bob', bobNumber);
        final chat = await alice.engine.chats.openDirect(bob.account);
        await alice.engine.chats.sendBody(
          chat.id,
          const UnknownBody(type: 'hologram', raw: {'depth': 3}),
        );
        await alice.engine.chats.sendText(chat.id, 'after the hologram');
        await waitForText(bob, alice, 'after the hologram');
        final rows = await messagesWith(bob, alice);
        final unknown = rows.firstWhere((m) => m.kind == 'hologram');
        expect(MessageKinds.isRenderable(unknown.kind), isFalse);
        expect(unknown.payload, contains('depth'));
      },
    );

    test('typing indicators are ephemeral and expire', () async {
      final alice = await world.register('alice', aliceNumber);
      final bob = await world.register('bob', bobNumber);
      final chat = await alice.engine.chats.openDirect(bob.account);
      await alice.engine.chats.sendText(chat.id, 'sessions first');
      await waitForText(bob, alice, 'sessions first');

      final fromAlice = directConversationId(alice.account);
      final events = <TypingEvent>[];
      bob.engine.events.listen((e) {
        if (e is TypingEvent) events.add(e);
      });
      await alice.engine.presence.sendTyping(chat.id, typing: true);
      await settle(() async => expect(events, isNotEmpty));
      expect(events.first.typing, isTrue);
      expect(events.first.account, alice.account);
      expect(bob.engine.presence.typingIn(fromAlice), {alice.account});
      await alice.engine.presence.sendTyping(chat.id, typing: false);
      await settle(
        () async => expect(bob.engine.presence.typingIn(fromAlice), isEmpty),
      );
      // Nothing about typing is stored or left in the mailbox.
      expect((await bob.api.messaging.mailbox()).envelopes, isEmpty);
    });

    test(
      'a blocked sender reaches nobody, and the sender is not told',
      () async {
        final alice = await world.register('alice', aliceNumber);
        final bob = await world.register('bob', bobNumber);
        final chat = await alice.engine.chats.openDirect(bob.account);
        await alice.engine.chats.sendText(chat.id, 'before');
        await waitForText(bob, alice, 'before');
        await bob.engine.people.block(alice.account);

        final blocked = await alice.engine.chats.sendText(chat.id, 'blocked');
        await settle(() async {
          final row = await alice.db.messagesDao.byRowid(blocked.localRowid);
          expect(row!.status, MessageStatus.sent);
        });
        await alice.engine.chats.sendText(chat.id, 'blocked too');
        await Future<void>.delayed(const Duration(milliseconds: 400));
        final texts = [for (final m in await messagesWith(bob, alice)) m.body];
        expect(texts, ['before']);
      },
    );

    test('disappearing messages start counting when first displayed', () async {
      final alice = await world.register('alice', aliceNumber);
      final bob = await world.register('bob', bobNumber);
      final chat = await alice.engine.chats.openDirect(bob.account);
      await alice.engine.chats.setDisappearing(chat.id, 1);
      await settle(() async {
        expect((await chatWith(bob, alice))?.disappearingSeconds, 1);
      });
      await alice.engine.chats.sendText(chat.id, 'vanish');
      final row = await waitForText(bob, alice, 'vanish');
      expect(row.expireSeconds, 1);
      expect(row.expiresAt, isNull, reason: 'the timer waits for display');

      await bob.engine.chats.markDisplayed(row.localRowid);
      await settle(() async {
        expect(await bob.db.messagesDao.byRowid(row.localRowid), isNull);
      });
      // The sender saw it at once, so its copy goes by itself too.
      await settle(() async {
        final mine = await messagesWith(alice, bob);
        expect(mine.where((m) => m.body == 'vanish'), isEmpty);
      });
    });
  });
}
