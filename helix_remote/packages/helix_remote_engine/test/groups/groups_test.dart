import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart' hide GroupRole;
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../support/fake_groups.dart';
import '../support/peers.dart';

/// The group pipeline against the in-memory fake server (groups, sender
/// keys, roster, quarantine) without Postgres: the engine's own checks. The
/// end-to-end tests on the real server are in
/// `server/test/client/engine/groups_test.dart`.
void main() {
  late Peers peers;
  late FakeGroups server;

  setUp(() {
    peers = Peers();
    server = FakeGroups(peers.server);
  });
  tearDown(() => peers.dispose());

  /// Alice (owner), Bob and Carol, in one group, all holding the key.
  Future<({Peer alice, Peer bob, Peer carol, String id, String chat})>
  trio() async {
    final alice = await peers.register('alice', phone: '+8801711000001');
    final bob = await peers.register('bob', phone: '+8801711000002');
    final carol = await peers.register('carol', phone: '+8801711000003');
    final created = await alice.engine.groups.create(
      name: 'Weekend',
      members: [bob.account, carol.account],
    );
    await alice.engine.drainOutbox();
    await bob.sync();
    await carol.sync();
    await alice.sync();
    return (
      alice: alice,
      bob: bob,
      carol: carol,
      id: created.groupId,
      chat: GroupIds.conversationId(created.groupId),
    );
  }

  Future<String?> ownKeyId(Peer peer, String groupId) async =>
      (await peer.db.cryptoDao.latestSenderKey(
        groupId: groupId,
        account: peer.account,
        device: peer.device,
      ))?.distId;

  /// Sends [text] to the group and delivers it: the sender's outbox runs,
  /// then each of [to] fetches.
  Future<MessageRow> say(
    Peer from,
    String chat,
    String text,
    List<Peer> to, {
    List<Mention> mentions = const [],
  }) async {
    final row = await from.engine.chats.sendText(
      chat,
      text,
      mentions: mentions,
    );
    await from.engine.drainOutbox();
    for (final peer in to) {
      await peer.sync();
    }
    return row;
  }

  Future<List<String?>> texts(Peer peer, String chat) async => [
    for (final m in (await peer.db.messagesDao.pageOlder(
      chat,
      limit: 200,
    )).messages)
      if (m.kind == 'text') m.body,
  ];

  group('roster and state', () {
    test('create keeps groups, group_members and the chat consistent, and '
        'the key reaches the members', () async {
      final g = await trio();
      final row = (await g.alice.db.groupsDao.byId(g.id))!;
      expect((row.title, row.role, row.epoch), ('Weekend', 'owner', 0));
      final members = await g.alice.db.groupsDao.members(g.id);
      expect(
        {for (final m in members) m.accountId: (m.role, m.isSelf)},
        {
          g.alice.account: ('owner', true),
          g.bob.account: ('member', false),
          g.carol.account: ('member', false),
        },
      );
      // The chat list reads `conversations`: kind, title, other members.
      final chat = (await g.alice.db.conversationsDao.byId(g.chat))!;
      expect((chat.kind, chat.title), (ConversationKind.group, 'Weekend'));
      expect(
        await g.alice.db.conversationsDao.membersOf(g.chat),
        unorderedEquals([g.bob.account, g.carol.account]),
      );
      // The `groups` summary columns stay unused.
      expect(row.lastMessageRowid, isNull);

      for (final peer in [g.bob, g.carol]) {
        final theirs = (await peer.db.groupsDao.byId(g.id))!;
        expect((theirs.title, theirs.role), ('Weekend', 'member'));
        expect(await peer.engine.groups.role(g.id), GroupRole.member);
        // The roster envelope became a notice in the chat.
        final notices = [
          for (final m in (await peer.db.messagesDao.pageOlder(
            g.chat,
          )).messages)
            if (m.kind == 'system') m.payload,
        ];
        expect(notices.single, contains('group_created'));
      }
    });

    test('a member without the key sees the group, then its name once the '
        'key arrives', () async {
      final alice = await peers.register('alice', phone: '+8801711000001');
      final bob = await peers.register('bob', phone: '+8801711000002');
      final created = await alice.engine.groups.create(
        name: 'Secret name',
        members: [bob.account],
      );
      // Bob processes the roster envelope, but the key is still queued at
      // Alice.
      await bob.sync();
      var row = (await bob.db.groupsDao.byId(created.groupId))!;
      expect(row.title, isEmpty);
      expect(
        (await bob.engine.groups.details(created.groupId))!.title,
        isEmpty,
      );
      await alice.engine.drainOutbox();
      await bob.sync();
      row = (await bob.db.groupsDao.byId(created.groupId))!;
      expect(row.title, 'Secret name');
      expect(
        (await bob.db.conversationsDao.byId(
          GroupIds.conversationId(created.groupId),
        ))!.title,
        'Secret name',
      );
    });

    test('a roster older than the stored epoch is refused', () async {
      final g = await trio();
      await g.alice.engine.groups.removeMember(g.id, g.carol.account);
      var row = (await g.alice.db.groupsDao.byId(g.id))!;
      expect(row.epoch, 1);
      expect(await g.alice.db.groupsDao.members(g.id), hasLength(2));

      // An answer from before the removal (epoch 0, Carol still listed)
      // arrives late: nothing changes.
      final stale = server.groups[g.id]!;
      stale.roles[g.carol.account] = GroupRole.member;
      stale.joinedAt[g.carol.account] = DateTime.now().toUtc();
      server.epochOverride = 0;
      await g.alice.engine.groups.refresh(g.id);
      server.epochOverride = null;
      row = (await g.alice.db.groupsDao.byId(g.id))!;
      expect(row.epoch, 1);
      final members = {
        for (final m in await g.alice.db.groupsDao.members(g.id)) m.accountId,
      };
      expect(members, {g.alice.account, g.bob.account});

      // A current answer is applied again (same epoch is a refresh).
      stale.roles.remove(g.carol.account);
      await g.alice.engine.groups.refresh(g.id);
      expect(await g.alice.db.groupsDao.members(g.id), hasLength(2));
    });

    test(
      'state writes retry on version_conflict and give up after a few',
      () async {
        final g = await trio();
        server.conflictsOnNextState = 2;
        await g.alice.engine.groups.rename(g.id, 'Renamed');
        expect((await g.alice.engine.groups.details(g.id))!.title, 'Renamed');
        expect(server.groups[g.id]!.stateVersion, greaterThan(0));

        server.conflictsOnNextState = 50;
        await expectLater(
          g.alice.engine.groups.rename(g.id, 'Never'),
          throwsA(
            isA<GroupException>().having(
              (e) => e.reason,
              'reason',
              GroupFailure.versionConflict,
            ),
          ),
        );
        server.conflictsOnNextState = 0;
        expect((await g.alice.engine.groups.details(g.id))!.title, 'Renamed');

        // Bob reads the new name after the roster envelope.
        await g.bob.sync();
        expect((await g.bob.engine.groups.details(g.id))!.title, 'Renamed');
      },
    );

    test('settings are kept next to the roster and checked before asking '
        'the server', () async {
      final g = await trio();
      await g.alice.engine.groups.setSettings(
        g.id,
        const GroupSettings(
          sendMessages: GroupPermission.admins,
          editInfo: GroupPermission.everyone,
        ),
      );
      await g.bob.sync();
      final details = (await g.bob.engine.groups.details(g.id))!;
      expect(details.canSend, isFalse);
      expect(details.canEditInfo, isTrue);
      expect(details.canAddMembers, isFalse);
      await expectLater(
        g.bob.engine.chats.sendText(g.chat, 'let me in'),
        throwsA(isA<GroupException>()),
      );
      // Rename is allowed for everyone now.
      await g.bob.engine.groups.rename(g.id, 'Bob renamed');
      await g.alice.sync();
      expect((await g.alice.engine.groups.details(g.id))!.title, 'Bob renamed');
    });
  });

  group('sending', () {
    test('the first send learns the devices from device_list_stale, '
        'distributes the sender key, and later sends do not', () async {
      final g = await trio();
      await say(g.alice, g.chat, 'one', [g.bob, g.carol]);
      final sends = server.sendsOf(g.id);
      expect([for (final s in sends) s.status], [409, 200]);
      final ok = sends.last.request;
      // Distributions: one device of Bob, one of Carol, before the message.
      expect(
        {for (final r in ok.distributions) r.account},
        {g.bob.account, g.carol.account},
      );
      expect(await texts(g.bob, g.chat), ['one']);
      expect(await texts(g.carol, g.chat), ['one']);

      await say(g.alice, g.chat, 'two', [g.bob, g.carol]);
      final again = server.sendsOf(g.id);
      expect(again.last.status, 200);
      expect(again.length, sends.length + 1, reason: 'no stale retry');
      expect(again.last.request.distributions, isEmpty);
      expect(await texts(g.bob, g.chat), ['one', 'two']);
      expect(await g.alice.db.groupsDao.memberDevices(g.id, g.bob.account), [
        g.bob.device,
      ]);
    });

    test('a device added to a member is found by the digest and gets the '
        'key without a rotation', () async {
      final g = await trio();
      await say(g.alice, g.chat, 'one', [g.bob, g.carol]);
      final key = await ownKeyId(g.alice, g.id);
      final before = server.sendsOf(g.id).length;

      final bob2 = await peers.link(g.bob, 'bob2');
      await say(g.alice, g.chat, 'two', [g.bob, g.carol, bob2]);
      final sends = server.sendsOf(g.id).skip(before).toList();
      expect([for (final s in sends) s.status], [409, 200]);
      // Only the new device needs the key.
      final distributed = [
        for (final r in sends.last.request.distributions)
          for (final d in r.devices) d.device,
      ];
      expect(distributed, [bob2.device]);
      // Adding a device of another member does not rotate (CRYPTO_V2.md §7).
      expect(await ownKeyId(g.alice, g.id), key);
      expect(await texts(bob2, g.chat), ['two']);
      expect(await texts(g.bob, g.chat), ['one', 'two']);
    });

    test(
      'a failed send backs off and later messages of the chat wait for it',
      () async {
        final g = await trio();
        await say(g.alice, g.chat, 'warm up', [g.bob, g.carol]);
        peers.server.failNext(Routes.sendGroupMessage, times: 1);
        final first = await g.alice.engine.chats.sendText(g.chat, 'first');
        final second = await g.alice.engine.chats.sendText(g.chat, 'second');
        await g.alice.engine.drainOutbox();
        // Nothing arrived: the first backs off, the second waits behind it.
        await g.bob.sync();
        expect(await texts(g.bob, g.chat), ['warm up']);
        expect(
          (await g.alice.db.messagesDao.byRowid(first.localRowid))!.status,
          MessageStatus.pending,
        );
        expect(
          (await g.alice.db.messagesDao.byRowid(second.localRowid))!.status,
          MessageStatus.pending,
        );

        peers.clock.advance(const Duration(seconds: 3));
        await g.alice.engine.drainOutbox();
        await g.bob.sync();
        await g.carol.sync();
        expect(await texts(g.bob, g.chat), ['warm up', 'first', 'second']);
        expect(await texts(g.carol, g.chat), ['warm up', 'first', 'second']);
        expect(
          (await g.alice.db.messagesDao.byRowid(first.localRowid))!.status,
          MessageStatus.sent,
        );
      },
    );

    test('a message that cannot be sent for good is marked failed', () async {
      final g = await trio();
      // Alice is no longer allowed to speak: the server says forbidden.
      server.groups[g.id]!.settings = const GroupSettings(
        sendMessages: GroupPermission.admins,
      );
      server.groups[g.id]!.roles[g.alice.account] = GroupRole.member;
      final row = await g.alice.engine.chats.sendText(g.chat, 'denied');
      await g.alice.engine.drainOutbox();
      expect(
        (await g.alice.db.messagesDao.byRowid(row.localRowid))!.status,
        MessageStatus.failed,
      );
    });

    test(
      'mentions are validated and count as mentions at the receiver',
      () async {
        final g = await trio();
        await expectLater(
          g.alice.engine.chats.sendText(
            g.chat,
            'hello @zed',
            mentions: const [Mention(account: 'zed', start: 6, length: 4)],
          ),
          throwsA(
            isA<GroupException>().having(
              (e) => e.reason,
              'reason',
              GroupFailure.badMention,
            ),
          ),
        );
        await expectLater(
          g.alice.engine.chats.sendText(
            g.chat,
            'short',
            mentions: [Mention(account: g.bob.account, start: 3, length: 20)],
          ),
          throwsA(isA<GroupException>()),
        );

        await g.alice.engine.chats.sendText(
          g.chat,
          'hi @bob and @carol',
          mentions: [
            Mention(account: g.bob.account, start: 3, length: 4),
            Mention(account: g.carol.account, start: 12, length: 6),
          ],
        );
        await g.alice.engine.chats.sendText(g.chat, 'no mention');
        await g.alice.engine.drainOutbox();
        final summary = await g.bob.sync();
        final mentioned = summary.notices.where((n) => n.mentionsMe);
        expect(mentioned, hasLength(1));
        expect(summary.notices, hasLength(2));
        var chat = (await g.bob.db.conversationsDao.byId(g.chat))!;
        expect((chat.unreadCount, chat.mentionCount), (2, 1));
        await g.carol.sync();
        expect(
          (await g.carol.db.conversationsDao.byId(g.chat))!.mentionCount,
          1,
        );
        // Reading clears both counts.
        await g.bob.engine.chats.markRead(g.chat);
        chat = (await g.bob.db.conversationsDao.byId(g.chat))!;
        expect((chat.unreadCount, chat.mentionCount), (0, 0));
      },
    );

    test('receipts: delivered and read mean everyone', () async {
      final g = await trio();
      final sent = await say(g.alice, g.chat, 'ticks', [g.bob]);
      await g.bob.engine.drainOutbox();
      await g.alice.sync();
      // Only Bob has it so far.
      expect(
        (await g.alice.db.messagesDao.byRowid(sent.localRowid))!.status,
        MessageStatus.sent,
      );
      await g.carol.sync();
      await g.carol.engine.drainOutbox();
      await g.alice.sync();
      expect(
        (await g.alice.db.messagesDao.byRowid(sent.localRowid))!.status,
        MessageStatus.delivered,
      );

      await g.bob.engine.chats.markRead(g.chat);
      await g.bob.engine.drainOutbox();
      await g.alice.sync();
      expect(
        (await g.alice.db.messagesDao.byRowid(sent.localRowid))!.status,
        MessageStatus.delivered,
        reason: 'Carol has not read it',
      );
      await g.carol.engine.chats.markRead(g.chat);
      await g.carol.engine.drainOutbox();
      await g.alice.sync();
      expect(
        (await g.alice.db.messagesDao.byRowid(sent.localRowid))!.status,
        MessageStatus.read,
      );
      final receipts = await g.alice.db.messagesDao.receiptsFor(
        sent.localRowid,
      );
      expect(
        {for (final r in receipts) r.accountId},
        {g.bob.account, g.carol.account},
      );
    });

    test('a replayed group envelope is applied once', () async {
      final g = await trio();
      await say(g.alice, g.chat, 'once', [g.bob]);
      final delivered = peers.server
          .device(g.bob.device)
          .mailbox
          .where((e) => e.kind == EnvelopeKind.groupMessage)
          .toList();
      expect(delivered, isEmpty, reason: 'acked after processing');
      // The server replays the same envelope id (a reconnect before the ack).
      final sends = server.sendsOf(g.id);
      peers.server.deliver(
        g.bob.device,
        kind: EnvelopeKind.groupMessage,
        id: sends.last.request.id,
        from: EnvelopeSender(account: g.alice.account, device: g.alice.device),
        groupId: g.id,
        payload: sends.last.request.payload,
        urgent: true,
      );
      await g.bob.sync();
      expect(await texts(g.bob, g.chat), ['once']);
    });
  });

  group('sender key rotation (CRYPTO_V2.md §7)', () {
    test('removing a member rotates every remaining sender key, and the '
        'removed member cannot read the new messages', () async {
      final g = await trio();
      await say(g.bob, g.chat, 'before', [g.alice, g.carol]);
      await say(g.alice, g.chat, 'alice before', [g.bob, g.carol]);
      final bobKey = await ownKeyId(g.bob, g.id);
      final aliceKey = await ownKeyId(g.alice, g.id);
      // Carol holds Bob's current sender key.
      final held = ReceivedSenderKey.decode(
        (await g.carol.db.cryptoDao.senderKey(
          groupId: g.id,
          account: g.bob.account,
          device: g.bob.device,
          distId: bobKey!,
        ))!.state,
      );

      await g.alice.engine.groups.removeMember(g.id, g.carol.account);
      await g.alice.engine.drainOutbox(); // the key rotation
      await g.bob.sync();
      await g.carol.sync();

      await say(g.bob, g.chat, 'after', [g.alice]);
      expect(await ownKeyId(g.bob, g.id), isNot(bobKey));
      final fresh = server.sendsOf(g.id).last.request;
      // The new key goes to Alice's device only: Carol is not a member.
      expect(
        {for (final r in fresh.distributions) r.account},
        {g.alice.account},
      );
      await say(g.alice, g.chat, 'alice after', [g.bob]);
      expect(await ownKeyId(g.alice, g.id), isNot(aliceKey));

      // Carol received nothing, and what she holds opens nothing new.
      await g.carol.sync();
      expect(await texts(g.carol, g.chat), ['before', 'alice before']);
      await expectLater(
        GroupSenderChain.decrypt(
          held,
          SealedPayload.decode(fresh.payload) as SenderKeyMessage,
          now: peers.clock.now,
        ),
        throwsA(isA<NoSenderKeyException>()),
      );
      expect(await texts(g.alice, g.chat), [
        'before',
        'alice before',
        'after',
        'alice after',
      ]);
    });

    test('a send after a removal this device has not heard of reads the '
        'roster again and rotates before anything leaves', () async {
      final g = await trio();
      await say(g.bob, g.chat, 'one', [g.alice, g.carol]);
      final key = await ownKeyId(g.bob, g.id);
      final before = server.sendsOf(g.id).length;
      // The server removes Carol; Bob's envelope for it is still unread.
      server.removeMember(
        server.groups[g.id]!,
        g.carol.account,
        actor: g.alice.account,
      );
      final row = await g.bob.engine.chats.sendText(g.chat, 'two');
      await g.bob.engine.drainOutbox();
      final sends = server.sendsOf(g.id).skip(before).toList();
      expect([for (final s in sends) s.status], [409, 200]);
      expect(
        (await g.bob.db.messagesDao.byRowid(row.localRowid))!.status,
        MessageStatus.sent,
      );
      // The roster is the server's, the key is new, and the one message that
      // left went to Alice only.
      expect(await g.bob.db.groupsDao.members(g.id), hasLength(2));
      expect(await ownKeyId(g.bob, g.id), isNot(key));
      expect(
        {for (final r in sends.last.request.distributions) r.account},
        {g.alice.account},
      );
      await g.alice.sync();
      await g.carol.sync();
      expect(await texts(g.alice, g.chat), contains('two'));
      expect(await texts(g.carol, g.chat), ['one']);
    });

    test(
      'a revoked device of a member rotates the key at the next send',
      () async {
        final g = await trio();
        final bob2 = await peers.link(g.bob, 'bob2');
        await say(g.alice, g.chat, 'one', [g.bob, g.carol, bob2]);
        final key = await ownKeyId(g.alice, g.id);
        peers.server.revoke(bob2.device);
        await say(g.alice, g.chat, 'two', [g.bob, g.carol]);
        expect(await ownKeyId(g.alice, g.id), isNot(key));
        // Everyone left holds the new key and reads on.
        await say(g.alice, g.chat, 'three', [g.bob, g.carol]);
        expect(await texts(g.carol, g.chat), ['one', 'two', 'three']);
      },
    );

    test('a change of the sender\'s own devices rotates the key', () async {
      final g = await trio();
      await say(g.alice, g.chat, 'one', [g.bob, g.carol]);
      final key = await ownKeyId(g.alice, g.id);
      final alice2 = await peers.link(g.alice, 'alice2');
      await say(g.alice, g.chat, 'two', [g.bob, g.carol, alice2]);
      expect(await ownKeyId(g.alice, g.id), isNot(key));
      expect(await texts(alice2, g.chat), ['two']);
    });

    test('adding a member does not rotate; the newcomer gets the current '
        'key and cannot read older messages', () async {
      final g = await trio();
      final dave = await peers.register('dave', phone: '+8801711000004');
      await say(g.alice, g.chat, 'old news', [g.bob, g.carol]);
      final key = await ownKeyId(g.alice, g.id);
      final added = await g.alice.engine.groups.addMembers(g.id, [
        dave.account,
      ]);
      expect(added.added, [dave.account]);
      await g.alice.engine.drainOutbox(); // the group key for Dave
      await dave.sync();
      await say(g.alice, g.chat, 'new news', [g.bob, g.carol, dave]);
      expect(await ownKeyId(g.alice, g.id), key);
      expect(await texts(dave, g.chat), ['new news']);
      expect((await dave.engine.groups.details(g.id))!.title, 'Weekend');
    });

    test('a key older than seven days is replaced', () async {
      final g = await trio();
      await say(g.alice, g.chat, 'one', [g.bob, g.carol]);
      final key = await ownKeyId(g.alice, g.id);
      peers.clock.advance(const Duration(days: 8));
      await say(g.alice, g.chat, 'two', [g.bob, g.carol]);
      expect(await ownKeyId(g.alice, g.id), isNot(key));
      expect(await texts(g.carol, g.chat), ['one', 'two']);
    });
  });

  group('server-driven state and membership (CRYPTO_V2.md §9, §14)', () {
    test('a state is never replaced by an older version, and an old blob '
        'under a newer version does not open', () async {
      final g = await trio();
      final oldBlob = Uint8List.fromList(server.groups[g.id]!.encryptedState);
      await g.alice.engine.groups.rename(g.id, 'Renamed');
      await g.bob.sync();
      expect((await g.bob.engine.groups.details(g.id))!.title, 'Renamed');
      final current = (await g.bob.db.groupsDao.byId(g.id))!;
      expect(current.stateVersion, 2);

      // The server serves the first blob again, under the old version.
      final group = server.groups[g.id]!;
      final goodBlob = Uint8List.fromList(group.encryptedState);
      group
        ..encryptedState = oldBlob
        ..stateVersion = 1;
      await g.bob.engine.groups.refresh(g.id);
      var row = (await g.bob.db.groupsDao.byId(g.id))!;
      expect(row.title, 'Renamed');
      expect(row.stateVersion, 2, reason: 'the stored version did not go back');
      expect(row.state, goodBlob, reason: 'the stored state was kept');

      // ... or under a higher one: it was sealed for version 1, so it does
      // not open for 7, and the name stays.
      group.stateVersion = 7;
      await g.bob.engine.groups.refresh(g.id);
      row = (await g.bob.db.groupsDao.byId(g.id))!;
      expect(row.title, 'Renamed');
      expect((await g.bob.engine.groups.details(g.id))!.title, 'Renamed');
    });

    test('a member the server adds with no announcement is held back: no '
        'sender key, no group key, a notice and an event; confirming them '
        'releases them', () async {
      final g = await trio();
      final dave = await peers.register('dave', phone: '+8801711000004');
      await say(g.alice, g.chat, 'before', [g.bob, g.carol]);
      final events = <EngineEvent>[];
      g.alice.engine.events.listen(events.add);

      server.injectMember(server.groups[g.id]!, dave.account);
      await g.alice.engine.groups.refresh(g.id);
      expect(await g.alice.engine.groups.pendingMembers(g.id), {
        dave.account: 'unattributed',
      });
      final notices = [
        for (final m in (await g.alice.db.messagesDao.pageOlder(
          g.chat,
        )).messages)
          if (m.kind == 'system') m.payload!,
      ];
      expect(
        notices.where((p) => p.contains(GroupNoticeKinds.memberUnconfirmed)),
        hasLength(1),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        events.whereType<GroupMemberUnconfirmed>().single.account,
        dave.account,
      );

      // The next message goes to Bob and Carol; Dave is delivered the
      // ciphertext (the server fans out to everyone) but gets no key.
      await say(g.alice, g.chat, 'secret', [g.bob, g.carol]);
      await dave.sync();
      expect(await texts(dave, g.chat), isEmpty);
      expect(
        await dave.db.cryptoDao.latestSenderKey(
          groupId: g.id,
          account: g.alice.account,
          device: g.alice.device,
        ),
        isNull,
      );
      expect(await texts(g.bob, g.chat), ['before', 'secret']);

      // The user confirms Dave: the group key now, the sender key with the
      // next message.
      expect(
        await g.alice.engine.groups.confirmMember(g.id, dave.account),
        isTrue,
      );
      expect(await g.alice.engine.groups.pendingMembers(g.id), isEmpty);
      await g.alice.engine.drainOutbox();
      await say(g.alice, g.chat, 'after', [g.bob, g.carol, dave]);
      expect(await texts(dave, g.chat), ['after']);
      expect(
        await g.alice.engine.groups.confirmMember(g.id, dave.account),
        isFalse,
      );
    });

    test('an announcement attributed to an admin explains the member; one '
        'attributed to a plain member does not', () async {
      final g = await trio();
      final dave = await peers.register('dave', phone: '+8801711000004');
      final erin = await peers.register('erin', phone: '+8801711000005');
      final group = server.groups[g.id]!;

      // Announced by Alice (the owner): Bob and Carol accept Dave.
      server.injectMember(
        group,
        dave.account,
        announce: true,
        announceActor: g.alice.account,
      );
      await g.bob.sync();
      await g.carol.sync();
      expect(await g.bob.engine.groups.pendingMembers(g.id), isEmpty);
      expect(await g.carol.engine.groups.pendingMembers(g.id), isEmpty);

      // Attributed to Bob, a plain member, while only admins may add.
      server.injectMember(
        group,
        erin.account,
        announce: true,
        announceActor: g.bob.account,
      );
      await g.carol.sync();
      expect(await g.carol.engine.groups.pendingMembers(g.id), {
        erin.account: 'unattributed',
      });
    });

    test('a member who joins a group by themselves is held back', () async {
      final g = await trio();
      final dave = await peers.register('dave', phone: '+8801711000004');
      server.injectMember(
        server.groups[g.id]!,
        dave.account,
        announce: true,
        announceActor: dave.account,
      );
      await g.bob.sync();
      expect(await g.bob.engine.groups.pendingMembers(g.id), {
        dave.account: 'link_join',
      });
    });

    test('link joins are accepted when the config trusts them', () async {
      final alice = await peers.register('alice', phone: '+8801711000001');
      final bob = await peers.register(
        'bob',
        phone: '+8801711000002',
        config: fastConfig.copyWith(trustLinkJoins: true),
      );
      final dave = await peers.register('dave', phone: '+8801711000004');
      final created = await alice.engine.groups.create(
        name: 'Weekend',
        members: [bob.account],
      );
      await alice.engine.drainOutbox();
      await bob.sync();
      server.injectMember(
        server.groups[created.groupId]!,
        dave.account,
        announce: true,
        announceActor: dave.account,
      );
      await bob.sync();
      expect(await bob.engine.groups.pendingMembers(created.groupId), isEmpty);
    });

    test('a member this account adds itself is never held back', () async {
      final g = await trio();
      final dave = await peers.register('dave', phone: '+8801711000004');
      await g.alice.engine.groups.addMembers(g.id, [dave.account]);
      await g.alice.engine.drainOutbox();
      await g.bob.sync();
      await dave.sync();
      for (final p in [g.alice, g.bob, g.carol]) {
        await p.sync();
        expect(await p.engine.groups.pendingMembers(g.id), isEmpty);
      }
      await say(g.alice, g.chat, 'welcome', [g.bob, g.carol, dave]);
      expect(await texts(dave, g.chat), ['welcome']);
    });
  });

  group('quarantine and recovery', () {
    test('a message without its sender key is quarantined, the sender sends '
        'the key and the message again', () async {
      final g = await trio();
      await say(g.alice, g.chat, 'first', [g.bob, g.carol]);
      await g.carol.db.cryptoDao.deleteSenderKeys(
        g.id,
        account: g.alice.account,
      );

      await say(g.alice, g.chat, 'second', [g.bob, g.carol]);
      expect(await texts(g.bob, g.chat), ['first', 'second']);
      // Carol: a visible placeholder, a repair queued.
      var rows = (await g.carol.db.messagesDao.pageOlder(g.chat)).messages;
      final placeholder = rows.singleWhere(
        (m) => m.kind == MessageKinds.undecryptable,
      );
      expect(placeholder.sender, g.alice.account);
      expect(placeholder.payload, contains('no_sender_key'));
      expect(placeholder.payload, contains('"waiting":true'));
      expect(await g.carol.db.outboxDao.failed(), isEmpty);

      // The repair round trip: Carol tells Alice, Alice sends again.
      await g.carol.engine.drainOutbox();
      await g.alice.sync();
      await g.carol.sync();
      rows = (await g.carol.db.messagesDao.pageOlder(g.chat)).messages;
      expect(rows.where((m) => m.kind == MessageKinds.undecryptable), isEmpty);
      expect(await texts(g.carol, g.chat), ['first', 'second']);
      // Bob, who had it, still has it once.
      await g.bob.sync();
      expect(await texts(g.bob, g.chat), ['first', 'second']);
      // And the next message needs no repair.
      await say(g.alice, g.chat, 'third', [g.bob, g.carol]);
      expect(await texts(g.carol, g.chat), ['first', 'second', 'third']);
    });

    test(
      'a forged message is quarantined without asking for a re-send',
      () async {
        final g = await trio();
        await say(g.alice, g.chat, 'real', [g.bob, g.carol]);
        // A group message under Alice's key id with a wrong signature.
        final key = ReceivedSenderKey.decode(
          (await g.bob.db.cryptoDao.senderKey(
            groupId: g.id,
            account: g.alice.account,
            device: g.alice.device,
            distId: (await ownKeyId(g.alice, g.id))!,
          ))!.state,
        );
        final forged = SenderKeyMessage(
          distributionId: key.distributionId,
          iteration: key.iteration,
          ciphertext: Uint8List.fromList(List.filled(40, 7)),
          signature: Uint8List.fromList(List.filled(64, 9)),
        );
        peers.server.deliver(
          g.bob.device,
          kind: EnvelopeKind.groupMessage,
          from: EnvelopeSender(
            account: g.alice.account,
            device: g.alice.device,
          ),
          groupId: g.id,
          payload: forged.encode(),
          urgent: true,
        );
        await g.bob.sync();
        final rows = (await g.bob.db.messagesDao.pageOlder(g.chat)).messages;
        final bad = rows.singleWhere(
          (m) => m.kind == MessageKinds.undecryptable,
        );
        expect(bad.payload, contains('untrusted_identity'));
        expect(bad.payload, contains('"waiting":false'));
        // No reset was queued, and the stream went on.
        await g.bob.engine.drainOutbox();
        expect(
          peers.server.calls
              .where((c) => c.contains('POST /v1/messages'))
              .length,
          greaterThan(0),
        );
        await say(g.alice, g.chat, 'after the forgery', [g.bob]);
        expect(await texts(g.bob, g.chat), ['real', 'after the forgery']);
      },
    );

    test('crafted numbers in group content are quarantined at once and the '
        'stream goes on', () async {
      final g = await trio();
      await say(g.alice, g.chat, 'works', [g.bob, g.carol]);
      for (final patch in [
        {'ts': 9223372036854775807},
        {'exp': 9007199254740991},
        {'ts': -1},
      ]) {
        final json = ContentMessage(
          id: Uuid.v7(),
          sentAt: peers.clock.now,
          conversation: GroupConversation(group: g.id),
          body: const TextBody(text: 'crafted'),
        ).toJson();
        await g.alice.engine.debugSendRawGroup(
          g.id,
          Uint8List.fromList(utf8.encode(jsonEncode({...json, ...patch}))),
        );
      }
      await say(g.alice, g.chat, 'after', [g.bob, g.carol]);
      final rows = (await g.bob.db.messagesDao.pageOlder(g.chat)).messages;
      final bad = rows.where((m) => m.kind == MessageKinds.undecryptable);
      expect(bad, hasLength(3));
      for (final row in bad) {
        expect(row.payload, contains('bad_content'));
        expect(row.payload, contains('"waiting":false'));
      }
      expect(await texts(g.bob, g.chat), ['works', 'after']);
      expect(await texts(g.carol, g.chat), ['works', 'after']);
    });

    test('group content from outside the group is dropped', () async {
      final g = await trio();
      final mallory = await peers.register('mallory', phone: '+8801711000009');
      // Mallory is not in the group; a pairwise "group message" is refused.
      await mallory.engine.debugSend(
        ContentMessage(
          id: Uuid.v7(),
          sentAt: DateTime.now().toUtc(),
          conversation: GroupConversation(group: g.id),
          body: const TextBody(text: 'let me in'),
        ),
        audience: [g.bob.account],
      );
      await mallory.engine.drainOutbox();
      await g.bob.sync();
      expect(await texts(g.bob, g.chat), isEmpty);

      // Even a member cannot push group content around the group send,
      // where the server checks the send permission.
      await g.carol.engine.debugSend(
        ContentMessage(
          id: Uuid.v7(),
          sentAt: DateTime.now().toUtc(),
          conversation: GroupConversation(group: g.id),
          body: const TextBody(text: 'pairwise sneak'),
        ),
        audience: [g.bob.account],
      );
      await g.carol.engine.drainOutbox();
      await g.bob.sync();
      expect(await texts(g.bob, g.chat), isEmpty);
    });
  });

  group('membership changes', () {
    test('removed members lose the roster and keys; the chat stays as '
        'history', () async {
      final g = await trio();
      await say(g.carol, g.chat, 'mine', [g.alice, g.bob]);
      final lost = <GroupMembershipLost>[];
      final sub = g.carol.engine.events
          .where((e) => e is GroupMembershipLost)
          .cast<GroupMembershipLost>()
          .listen(lost.add);
      addTearDown(sub.cancel);
      await g.alice.engine.groups.removeMember(g.id, g.carol.account);
      await g.carol.sync();
      await Future<void>.delayed(Duration.zero);
      expect(lost.single.reason, 'removed');
      expect(await g.carol.db.groupsDao.byId(g.id), isNull);
      expect(await g.carol.db.groupsDao.members(g.id), isEmpty);
      expect(
        await g.carol.db.cryptoDao.senderKeysOf(
          groupId: g.id,
          account: g.alice.account,
          device: g.alice.device,
        ),
        isEmpty,
      );
      expect(await texts(g.carol, g.chat), ['mine']);
      await expectLater(
        g.carol.engine.chats.sendText(g.chat, 'still here'),
        throwsA(isA<GroupException>()),
      );
      // The remaining members rotated the group key: a rename under the
      // new epoch reaches Bob.
      await g.alice.engine.drainOutbox();
      await g.bob.sync();
      await g.alice.engine.groups.rename(g.id, 'Two left');
      await g.bob.sync();
      expect((await g.bob.engine.groups.details(g.id))!.title, 'Two left');
      expect((await g.bob.db.groupsDao.byId(g.id))!.epoch, 1);
    });

    test(
      'leaving keeps the history; the group is gone for the leaver',
      () async {
        final g = await trio();
        await g.bob.engine.groups.leave(g.id);
        expect(await g.bob.db.groupsDao.byId(g.id), isNull);
        expect(await g.bob.db.conversationsDao.byId(g.chat), isNotNull);
        await g.alice.sync();
        expect(await g.alice.db.groupsDao.member(g.id, g.bob.account), isNull);
        final notices = [
          for (final m in (await g.alice.db.messagesDao.pageOlder(
            g.chat,
          )).messages)
            if (m.kind == 'system') m.payload,
        ];
        expect(notices.any((p) => p!.contains('member_left')), isTrue);
      },
    );

    test('bans are kept locally and the banned member is removed', () async {
      final g = await trio();
      await g.alice.engine.groups.ban(g.id, g.carol.account);
      expect(
        [for (final b in await g.alice.engine.groups.bans(g.id)) b.accountId],
        [g.carol.account],
      );
      expect(await g.alice.db.groupsDao.member(g.id, g.carol.account), isNull);
      await g.carol.sync();
      expect(await g.carol.db.groupsDao.byId(g.id), isNull);
      await g.alice.engine.groups.unban(g.id, g.carol.account);
      expect(await g.alice.engine.groups.bans(g.id), isEmpty);
    });

    test('a group the server does not list any more is forgotten by a '
        'full refresh', () async {
      final g = await trio();
      server.groups.remove(g.id);
      await g.bob.engine.groups.refreshAll();
      expect(await g.bob.db.groupsDao.byId(g.id), isNull);
      expect(await g.bob.db.conversationsDao.byId(g.chat), isNotNull);
    });
  });
}
