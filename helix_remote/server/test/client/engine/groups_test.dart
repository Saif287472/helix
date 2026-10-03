/// Several engines per test over live sockets: allow for a busy machine.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart' hide GroupRole;
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../../support/federated.dart' as fed;
import '../../support/flows.dart';
import '../../support/harness.dart';
import '../../support/test_database.dart';
import 'support.dart';

const carolNumber = '+8801711000003';
const daveNumber = '+8801711000004';
const erinNumber = '+8801711000005';

/// Groups end to end (Phase C4-G): engines through the real server, sender
/// keys, roster, roles, invite links and join requests.
void main() {
  group('engine groups', skip: databaseTestSkipReason, () {
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

    /// Alice (owner), Bob and Carol in a group, everyone holding the key.
    Future<({EngineUser alice, EngineUser bob, EngineUser carol, String id})>
    trio() async {
      final alice = await world.register('alice', aliceNumber);
      final bob = await world.register('bob', bobNumber);
      final carol = await world.register('carol', carolNumber);
      final created = await alice.engine.groups.create(
        name: 'Weekend',
        members: [bob.account, carol.account],
      );
      expect(created.rejected, isEmpty);
      for (final user in [alice, bob, carol]) {
        await inGroup(user, created.groupId, title: 'Weekend');
      }
      return (alice: alice, bob: bob, carol: carol, id: created.groupId);
    }

    test('three members talk, each sender key reaching the others', () async {
      final g = await trio();
      final chat = GroupIds.conversationId(g.id);

      await g.alice.engine.chats.sendText(chat, 'hello from alice');
      await g.bob.engine.chats.sendText(chat, 'hello from bob');
      await g.carol.engine.chats.sendText(chat, 'hello from carol');

      for (final user in [g.alice, g.bob, g.carol]) {
        for (final text in [
          'hello from alice',
          'hello from bob',
          'hello from carol',
        ]) {
          await waitForGroupText(user, g.id, text);
        }
        final rows = await groupMessages(user, g.id);
        expect(
          rows.where((m) => m.kind == MessageKinds.undecryptable),
          isEmpty,
          reason: '${user.name} could not decrypt something',
        );
      }
      // Authorship is the server-attested sender, the chat shows it.
      final atBob = await waitForGroupText(g.bob, g.id, 'hello from alice');
      expect(atBob.sender, g.alice.account);
      expect(atBob.status, MessageStatus.received);
      expect(
        (await groupChat(g.bob, g.id))!.unreadCount,
        greaterThanOrEqualTo(2),
      );

      // The ticks mean "everyone": delivered once Bob and Carol both have it.
      await settle(() async {
        final mine = await waitForGroupText(g.alice, g.id, 'hello from alice');
        expect(mine.status, MessageStatus.delivered);
      });

      // Reading in the group sends read receipts to each author.
      await g.bob.engine.chats.markRead(chat);
      await g.carol.engine.chats.markRead(chat);
      await settle(() async {
        final mine = await waitForGroupText(g.alice, g.id, 'hello from alice');
        expect(mine.status, MessageStatus.read);
      });
      expect((await groupChat(g.bob, g.id))!.unreadCount, 0);
    });

    test(
      'replies, mentions, reactions, edits and deletes work in a group',
      () async {
        final g = await trio();
        final chat = GroupIds.conversationId(g.id);

        final first = await g.alice.engine.chats.sendText(chat, 'plan?');
        final atBob = await waitForGroupText(g.bob, g.id, 'plan?');
        await waitForGroupText(g.carol, g.id, 'plan?');

        // A reply with a mention of Carol.
        const text = 'beach, @carol?';
        await g.bob.engine.chats.sendText(
          chat,
          text,
          replyTo: MessageRef(id: atBob.messageId, author: g.alice.account),
          mentions: [Mention(account: g.carol.account, start: 7, length: 6)],
        );
        final atCarol = await waitForGroupText(g.carol, g.id, text);
        expect(atCarol.replyToId, first.messageId);
        expect(atCarol.mentionsMe, isTrue);
        expect((await groupChat(g.carol, g.id))!.mentionCount, 1);
        final atAlice = await waitForGroupText(g.alice, g.id, text);
        expect(atAlice.mentionsMe, isFalse);
        expect((await groupChat(g.alice, g.id))!.mentionCount, 0);
        await g.carol.engine.chats.markRead(chat);
        expect((await groupChat(g.carol, g.id))!.mentionCount, 0);

        // A mention of someone outside the group is refused up front.
        await expectLater(
          g.bob.engine.chats.sendText(
            chat,
            'hi @nobody',
            mentions: const [
              Mention(account: 'not-a-member', start: 3, length: 7),
            ],
          ),
          throwsA(isA<GroupException>()),
        );

        // Reactions from two members; edits and deletes by the author.
        await g.bob.engine.chats.react(atBob.localRowid, 'A');
        await g.carol.engine.chats.react(
          (await waitForGroupText(g.carol, g.id, 'plan?')).localRowid,
          'B',
        );
        await settle(() async {
          final reactions = await g.alice.db.messagesDao.reactionsFor([
            first.localRowid,
          ]);
          expect(
            {for (final r in reactions) r.reactor: r.emoji},
            {g.bob.account: 'A', g.carol.account: 'B'},
          );
        });

        await g.alice.engine.chats.edit(first.localRowid, 'plan for Sunday?');
        await waitForGroupText(g.bob, g.id, 'plan for Sunday?');
        await waitForGroupText(g.carol, g.id, 'plan for Sunday?');

        await g.alice.engine.chats.deleteForEveryone(first.localRowid);
        await settle(() async {
          for (final user in [g.bob, g.carol]) {
            final row = (await groupMessages(
              user,
              g.id,
            )).firstWhere((m) => m.messageId == first.messageId);
            expect(row.deletedAt, isNotNull, reason: user.name);
            expect(row.body, isNull);
          }
        });
      },
    );

    test(
      'a group admin can delete anyone\'s message, a member cannot',
      () async {
        final g = await trio();
        final chat = GroupIds.conversationId(g.id);
        final sent = await g.bob.engine.chats.sendText(chat, 'oops');
        final atAlice = await waitForGroupText(g.alice, g.id, 'oops');
        final atCarol = await waitForGroupText(g.carol, g.id, 'oops');

        // Carol is a plain member: refused locally.
        await expectLater(
          g.carol.engine.chats.deleteForEveryone(atCarol.localRowid),
          throwsStateError,
        );
        // Alice is the owner.
        await g.alice.engine.chats.deleteForEveryone(atAlice.localRowid);
        await settle(() async {
          for (final user in [g.bob, g.carol]) {
            final row = (await groupMessages(
              user,
              g.id,
            )).firstWhere((m) => m.messageId == sent.messageId);
            expect(row.deletedAt, isNotNull, reason: user.name);
          }
        });
      },
    );

    test('removing a member rotates the sender keys: the removed member '
        'cannot read what is written after', () async {
      final g = await trio();
      final chat = GroupIds.conversationId(g.id);
      await g.bob.engine.chats.sendText(chat, 'before removal');
      await waitForGroupText(g.carol, g.id, 'before removal');
      final before = await ownSenderKey(g.bob, g.id);
      expect(before, isNotNull);
      await g.alice.engine.chats.sendText(chat, 'alice before removal');
      await waitForGroupText(g.carol, g.id, 'alice before removal');
      final aliceBefore = await ownSenderKey(g.alice, g.id);
      final carolKnows = await g.carol.db.cryptoDao.senderKeysOf(
        groupId: g.id,
        account: g.bob.account,
        device: g.bob.device,
      );
      expect(carolKnows, isNotEmpty);

      await g.alice.engine.groups.removeMember(g.id, g.carol.account);
      // Carol learns she is out: the roster and keys are gone, the chat stays
      // as history.
      await settle(() async {
        expect(await g.carol.db.groupsDao.byId(g.id), isNull);
        expect(await g.carol.db.conversationsDao.byId(chat), isNotNull);
      });
      await settle(() async {
        final notices = [
          for (final m in await groupMessages(g.carol, g.id))
            if (m.kind == SystemBody.typeName) m.payload,
        ];
        expect(notices.any((p) => p!.contains('you_were_removed')), isTrue);
      });

      // Everyone left keeps talking; the senders rotate their keys.
      await g.bob.engine.chats.sendText(chat, 'after removal');
      await waitForGroupText(g.alice, g.id, 'after removal');
      await g.alice.engine.chats.sendText(chat, 'alice after removal');
      await waitForGroupText(g.bob, g.id, 'alice after removal');

      final after = await ownSenderKey(g.bob, g.id);
      expect(after!.distributionId, isNot(before!.distributionId));
      expect(
        (await ownSenderKey(g.alice, g.id))!.distributionId,
        isNot(aliceBefore!.distributionId),
      );

      // Carol got neither message, and her old key opens nothing new.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final texts = [
        for (final m in await groupMessages(g.carol, g.id))
          if (m.kind == 'text') m.body,
      ];
      expect(texts, ['before removal', 'alice before removal']);
      // The key the removed member holds is the old one only.
      final carolNow = await g.carol.db.cryptoDao.senderKeysOf(
        groupId: g.id,
        account: g.bob.account,
        device: g.bob.device,
      );
      expect(carolNow, isEmpty, reason: 'forgotten with the group');

      // The group key was rotated too: the state is sealed under epoch 1.
      await settle(() async {
        for (final user in [g.alice, g.bob]) {
          final row = (await user.db.groupsDao.byId(g.id))!;
          expect(row.epoch, 1, reason: user.name);
          expect(
            (await user.engine.groups.details(g.id))!.title,
            'Weekend',
            reason: user.name,
          );
        }
      });
      // Bob holds the new epoch's key: a rename under it reaches him.
      await g.alice.engine.groups.rename(g.id, 'Weekend 2');
      await settle(() async {
        expect((await g.bob.engine.groups.details(g.id))!.title, 'Weekend 2');
      });
    });

    test('a device linked mid-conversation gets the next group message '
        '(stale digest recovery)', () async {
      final g = await trio();
      final chat = GroupIds.conversationId(g.id);
      await g.alice.engine.chats.sendText(chat, 'one');
      await waitForGroupText(g.bob, g.id, 'one');

      // Bob links a second phone. Alice's roster does not know it yet.
      final bob2 = await world.link(g.bob, 'bob2');
      await settle(() async {
        expect(await bob2.db.groupsDao.byId(g.id), isNotNull);
        // The group key came from Bob's first device.
        expect((await bob2.engine.groups.details(g.id))!.title, 'Weekend');
      });

      await g.alice.engine.chats.sendText(chat, 'two');
      await waitForGroupText(g.bob, g.id, 'two');
      await waitForGroupText(bob2, g.id, 'two');
      await waitForGroupText(g.carol, g.id, 'two');
      // Alice now knows both of Bob's devices.
      final devices = await g.alice.db.groupsDao.memberDevices(
        g.id,
        g.bob.account,
      );
      expect(devices, unorderedEquals([g.bob.device, bob2.device]));

      // The new phone can answer, and Bob's first phone sees its own
      // account's other device.
      await bob2.engine.chats.sendText(chat, 'from bob two');
      await waitForGroupText(g.alice, g.id, 'from bob two');
      await waitForGroupText(g.carol, g.id, 'from bob two');
      await waitForGroupText(g.bob, g.id, 'from bob two');
    });

    test(
      'members and admins have the permissions the settings give them',
      () async {
        final g = await trio();
        final dave = await world.register('dave', daveNumber);
        final chat = GroupIds.conversationId(g.id);

        // By default only admins add people and edit the group.
        await expectLater(
          g.bob.engine.groups.addMembers(g.id, [dave.account]),
          throwsA(
            isA<GroupException>().having(
              (e) => e.reason,
              'reason',
              GroupFailure.notAllowed,
            ),
          ),
        );
        await expectLater(
          g.bob.engine.groups.rename(g.id, 'Mine now'),
          throwsA(isA<GroupException>()),
        );
        await expectLater(
          g.bob.engine.groups.setSettings(g.id, const GroupSettings()),
          throwsA(isA<GroupException>()),
        );
        await expectLater(
          g.bob.engine.groups.removeMember(g.id, g.carol.account),
          throwsA(isA<GroupException>()),
        );

        // Alice makes Bob an admin: now he may.
        await g.alice.engine.groups.setRole(
          g.id,
          g.bob.account,
          GroupRole.admin,
        );
        await settle(() async {
          expect(await g.bob.engine.groups.role(g.id), GroupRole.admin);
        });
        await g.bob.engine.groups.rename(g.id, 'Bob renamed it');
        for (final user in [g.alice, g.bob, g.carol]) {
          await inGroup(user, g.id, title: 'Bob renamed it');
        }
        final added = await g.bob.engine.groups.addMembers(g.id, [
          dave.account,
        ]);
        expect(added.added, [dave.account]);
        await inGroup(dave, g.id, title: 'Bob renamed it');
        expect((await dave.db.groupsDao.members(g.id)), hasLength(4));

        // Nobody removes the owner or demotes them.
        await expectLater(
          g.bob.engine.groups.removeMember(g.id, g.alice.account),
          throwsA(isA<ApiException>()),
        );

        // Only the owner hands ownership on.
        await expectLater(
          g.bob.engine.groups.setRole(g.id, g.carol.account, GroupRole.owner),
          throwsA(isA<ApiException>()),
        );

        // Settings: only admins may send. Carol is a member, so she cannot.
        await g.alice.engine.groups.setSettings(
          g.id,
          const GroupSettings(sendMessages: GroupPermission.admins),
        );
        await settle(() async {
          expect(
            (await g.carol.engine.groups.details(g.id))!.settings.sendMessages,
            GroupPermission.admins,
          );
        });
        await expectLater(
          g.carol.engine.chats.sendText(chat, 'let me speak'),
          throwsA(isA<GroupException>()),
        );
        await g.bob.engine.chats.sendText(chat, 'admins only now');
        await waitForGroupText(g.carol, g.id, 'admins only now');

        // And everyone may add people once the setting says so.
        await g.alice.engine.groups.setSettings(
          g.id,
          const GroupSettings(addMembers: GroupPermission.everyone),
        );
        await settle(() async {
          expect(
            (await g.carol.engine.groups.details(g.id))!.canAddMembers,
            isTrue,
          );
        });
      },
    );

    test('a link joins a group; the first admin hands over the key', () async {
      final g = await trio();
      final dave = await world.register('dave', daveNumber);
      final chat = GroupIds.conversationId(g.id);

      final invite = await g.alice.engine.groups.createInviteLink(g.id);
      expect(invite.link, contains('#HLX-GRP-'));
      // A member cannot make links.
      await expectLater(
        g.carol.engine.groups.createInviteLink(g.id),
        throwsA(isA<GroupException>()),
      );

      final preview = await dave.engine.groups.previewInvite(invite.link);
      expect(preview.name, 'Weekend');
      expect(preview.memberCount, 3);
      expect(preview.requiresApproval, isFalse);
      expect(preview.groupId, g.id);
      await expectLater(
        dave.engine.groups.previewInvite('https://x/open#HLX-GRP-bad'),
        throwsA(isA<GroupException>()),
      );

      final joined = await dave.engine.groups.joinWithLink(invite.link);
      expect(joined.joined, isTrue);
      // The key comes from the admin with the lowest account id, so the name
      // appears without anyone doing anything.
      await inGroup(dave, g.id, title: 'Weekend');

      await g.alice.engine.chats.sendText(chat, 'welcome dave');
      await waitForGroupText(dave, g.id, 'welcome dave');
      await dave.engine.chats.sendText(chat, 'thanks!');
      for (final user in [g.alice, g.bob, g.carol]) {
        await waitForGroupText(user, g.id, 'thanks!');
      }
      // Dave cannot read what was said before he joined.
      final earlier = await groupMessages(dave, g.id);
      expect([
        for (final m in earlier)
          if (m.kind == 'text') m.body,
      ], isNot(contains('hello')));

      // A revoked link stops working.
      await g.alice.engine.groups.revokeInviteLink(g.id, invite.linkId);
      final erin = await world.register('erin', erinNumber);
      await expectLater(
        erin.engine.groups.joinWithLink(invite.link),
        throwsA(isA<ApiException>()),
      );
    });

    test('an approval link makes a join request an admin decides', () async {
      final g = await trio();
      final erin = await world.register('erin', erinNumber);
      final chat = GroupIds.conversationId(g.id);
      final events = <GroupJoinRequested>[];
      final sub = g.alice.engine.events
          .where((e) => e is GroupJoinRequested)
          .cast<GroupJoinRequested>()
          .listen(events.add);
      addTearDown(sub.cancel);

      final invite = await g.alice.engine.groups.createInviteLink(
        g.id,
        requiresApproval: true,
      );
      final result = await erin.engine.groups.joinWithLink(invite.link);
      expect(result.status, JoinStatus.pending);
      expect(await erin.db.groupsDao.byId(g.id), isNull);

      // Admins hear about it; members do not.
      await settle(() async {
        expect(events, isNotEmpty);
        expect(events.first.account, erin.account);
      });
      final requests = await g.alice.engine.groups.joinRequests(g.id);
      expect(requests.single.account, erin.account);
      expect(
        [
          for (final m in await groupMessages(g.carol, g.id))
            if (m.kind == SystemBody.typeName) m.payload,
        ].where((p) => p!.contains('join_requested')),
        isEmpty,
      );

      await g.alice.engine.groups.approveJoinRequest(
        g.id,
        requests.single.requestId,
      );
      await inGroup(erin, g.id, title: 'Weekend');
      await erin.engine.chats.sendText(chat, 'hello, approved');
      await waitForGroupText(g.bob, g.id, 'hello, approved');

      // A second request can be rejected.
      final dave = await world.register('dave', daveNumber);
      await dave.engine.groups.joinWithLink(invite.link);
      final pending = await g.alice.engine.groups.joinRequests(g.id);
      await g.alice.engine.groups.rejectJoinRequest(
        g.id,
        pending.single.requestId,
      );
      expect(await dave.db.groupsDao.byId(g.id), isNull);
      expect(await g.alice.engine.groups.joinRequests(g.id), isEmpty);
    });

    test(
      'leaving and bans: the chat stays, a banned account cannot return',
      () async {
        final g = await trio();
        final chat = GroupIds.conversationId(g.id);
        await g.carol.engine.chats.sendText(chat, 'bye soon');
        await waitForGroupText(g.alice, g.id, 'bye soon');

        await g.carol.engine.groups.leave(g.id);
        // Alice is the first admin: she rotates the group key, and a rename
        // under the new epoch still reaches Bob.
        await settle(() async {
          expect((await g.bob.db.groupsDao.byId(g.id))!.epoch, 1);
          expect((await g.alice.db.groupsDao.byId(g.id))!.epoch, 1);
          // Both hold the key of epoch 1 (the rotation ran and was shared).
          for (final user in [g.alice, g.bob]) {
            final keys = await user.db.settingsDao.get(
              Setting<String?>('group.keys.${g.id}', null),
            );
            expect(keys, contains('"1"'), reason: user.name);
          }
        });
        await g.alice.engine.groups.rename(g.id, 'Two of us');
        await inGroup(g.bob, g.id, title: 'Two of us');
        expect(await g.carol.db.groupsDao.byId(g.id), isNull);
        expect(await g.carol.db.conversationsDao.byId(chat), isNotNull);
        // She can read her history but not send.
        await expectLater(
          g.carol.engine.chats.sendText(chat, 'still here?'),
          throwsA(isA<GroupException>()),
        );
        await settle(() async {
          expect(
            await g.alice.db.groupsDao.member(g.id, g.carol.account),
            isNull,
          );
        });

        // Ban Bob; he cannot come back through a link, until unbanned.
        final invite = await g.alice.engine.groups.createInviteLink(g.id);
        await g.alice.engine.groups.ban(g.id, g.bob.account);
        expect(
          [for (final b in await g.alice.engine.groups.bans(g.id)) b.accountId],
          [g.bob.account],
        );
        await settle(() async {
          expect(await g.bob.db.groupsDao.byId(g.id), isNull);
        });
        await expectLater(
          g.bob.engine.groups.joinWithLink(invite.link),
          throwsA(isA<ApiException>()),
        );
        await g.alice.engine.groups.unban(g.id, g.bob.account);
        expect(await g.alice.engine.groups.bans(g.id), isEmpty);
        final back = await g.bob.engine.groups.joinWithLink(invite.link);
        expect(back.joined, isTrue);
        await inGroup(g.bob, g.id, title: 'Two of us');
        // The old history is still in his chat, the new group works.
        await g.alice.engine.chats.sendText(chat, 'welcome back');
        await waitForGroupText(g.bob, g.id, 'welcome back');
      },
    );

    test('concurrent renames both go through: version conflicts are '
        'retried', () async {
      final g = await trio();
      await g.alice.engine.groups.setRole(g.id, g.bob.account, GroupRole.admin);
      await settle(() async {
        expect(await g.bob.engine.groups.role(g.id), GroupRole.admin);
      });
      await Future.wait([
        g.alice.engine.groups.rename(g.id, 'Alice name'),
        g.bob.engine.groups.rename(g.id, 'Bob name'),
        g.alice.engine.groups.setDescription(g.id, 'about the trip'),
      ]);
      // Everyone converges on one state.
      await settle(() async {
        final titles = <String>{};
        final descriptions = <String?>{};
        for (final user in [g.alice, g.bob, g.carol]) {
          final d = (await user.engine.groups.details(g.id))!;
          titles.add(d.title);
          descriptions.add(d.meta.description);
        }
        expect(titles, hasLength(1), reason: '$titles');
        expect(titles.single, anyOf('Alice name', 'Bob name'));
        expect(descriptions, hasLength(1), reason: '$descriptions');
      });
    });

    test('a member without the sender key quarantines the message and the '
        'sender sends the key and the message again', () async {
      final g = await trio();
      final chat = GroupIds.conversationId(g.id);
      await g.alice.engine.chats.sendText(chat, 'first');
      await waitForGroupText(g.carol, g.id, 'first');

      // Carol loses Alice's sender key (a restored backup, a bug).
      await g.carol.db.cryptoDao.deleteSenderKeys(
        g.id,
        account: g.alice.account,
      );

      await g.alice.engine.chats.sendText(chat, 'second');
      // Bob reads it; Carol cannot at first, then the repair brings it.
      await waitForGroupText(g.bob, g.id, 'second');
      await waitForGroupText(
        g.carol,
        g.id,
        'second',
        timeout: const Duration(seconds: 30),
      );
      final rows = await groupMessages(g.carol, g.id);
      expect(
        rows.where((m) => m.kind == MessageKinds.undecryptable),
        isEmpty,
        reason: 'the placeholder was replaced by the re-sent message',
      );
      // And the next message just works.
      await g.alice.engine.chats.sendText(chat, 'third');
      await waitForGroupText(g.carol, g.id, 'third');
    });

    test(
      'members sending at the same time never corrupt a sender key',
      () async {
        final g = await trio();
        final chat = GroupIds.conversationId(g.id);
        await Future.wait([
          for (final user in [g.alice, g.bob, g.carol])
            () async {
              for (var i = 0; i < 8; i++) {
                await user.engine.chats.sendText(chat, '${user.name}$i');
              }
            }(),
        ]);
        await settle(() async {
          for (final user in [g.alice, g.bob, g.carol]) {
            final texts = {
              for (final m in await groupMessages(user, g.id))
                if (m.kind == 'text') m.body,
            };
            expect(texts, hasLength(24), reason: user.name);
          }
        }, timeout: const Duration(seconds: 60));
        for (final user in [g.alice, g.bob, g.carol]) {
          expect(
            (await groupMessages(
              user,
              g.id,
            )).where((m) => m.kind == MessageKinds.undecryptable),
            isEmpty,
            reason: '${user.name} could not decrypt something',
          );
        }
      },
    );

    test('typing indicators reach the other members', () async {
      final g = await trio();
      final chat = GroupIds.conversationId(g.id);
      // The first message sets the sender keys up.
      await g.alice.engine.chats.sendText(chat, 'warm up');
      await waitForGroupText(g.bob, g.id, 'warm up');
      await waitForGroupText(g.carol, g.id, 'warm up');
      await g.bob.engine.chats.sendText(chat, 'and bob');
      await waitForGroupText(g.alice, g.id, 'and bob');
      await waitForGroupText(g.carol, g.id, 'and bob');

      await g.alice.engine.presence.sendTyping(chat, typing: true);
      await settle(() async {
        expect(g.bob.engine.presence.typingIn(chat), {g.alice.account});
        expect(g.carol.engine.presence.typingIn(chat), {g.alice.account});
      });
      // The sender does not see their own indicator.
      expect(g.alice.engine.presence.typingIn(chat), isEmpty);
      await g.alice.engine.presence.sendTyping(chat, typing: false);
      await settle(() async {
        expect(g.bob.engine.presence.typingIn(chat), isEmpty);
      });
    });

    test('disappearing messages and timer changes work in a group', () async {
      final g = await trio();
      final chat = GroupIds.conversationId(g.id);
      await g.alice.engine.chats.setDisappearing(chat, 3600);
      await settle(() async {
        for (final user in [g.bob, g.carol]) {
          expect((await groupChat(user, g.id))!.disappearingSeconds, 3600);
        }
      });
      await g.alice.engine.chats.sendText(chat, 'this will vanish');
      final atBob = await waitForGroupText(g.bob, g.id, 'this will vanish');
      expect(atBob.expireSeconds, 3600);

      // A plain member cannot change the timer for the others.
      await g.carol.engine.chats.setDisappearing(chat, 60);
      await Future<void>.delayed(const Duration(seconds: 1));
      expect((await groupChat(g.bob, g.id))!.disappearingSeconds, 3600);
    });

    test(
      'a device that was offline catches up on roster and messages',
      () async {
        final g = await trio();
        final chat = GroupIds.conversationId(g.id);
        await g.carol.engine.stop();

        await g.alice.engine.groups.rename(g.id, 'While you were away');
        await g.alice.engine.chats.sendText(chat, 'you missed this');
        await g.bob.engine.chats.sendText(chat, 'and this');
        await waitForGroupText(g.bob, g.id, 'you missed this');

        await g.carol.engine.start();
        await waitForGroupText(g.carol, g.id, 'you missed this');
        await waitForGroupText(g.carol, g.id, 'and this');
        await settle(() async {
          expect(
            (await g.carol.engine.groups.details(g.id))!.title,
            'While you were away',
          );
        });
      },
    );
  });

  // Several servers per test: allow for parallel runs on a busy machine.
  group('engine groups across two servers', skip: databaseTestSkipReason, () {
    late Harness a;
    late Harness b;
    late EngineWorld worldA;
    late EngineWorld worldB;

    setUp(() async {
      a = await fed.federated();
      b = await fed.federated();
      worldA = EngineWorld(a);
      worldB = EngineWorld(b);
    });
    tearDown(() async {
      await worldA.dispose();
      await worldB.dispose();
      await a.stop();
      await b.stop();
    });

    /// Runs [check] until it passes, letting both servers run their queued
    /// cross-server jobs in between (nothing else drives them in a test).
    Future<void> pump(
      Future<void> Function() check, {
      Duration timeout = const Duration(seconds: 40),
    }) async {
      final deadline = DateTime.now().add(timeout);
      while (true) {
        await fed.settle([a, b]);
        try {
          await check();
          return;
        } on Object {
          if (DateTime.now().isAfter(deadline)) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }
    }

    test('a group with a member on another server: roster, key and '
        'messages both ways', () async {
      final alice = await worldA.register('alice', aliceNumber);
      final bob = await worldB.register('bob', bobNumber);
      final bobOnA = '${bob.account}@${b.domain}';
      final aliceOnB = '${alice.account}@${a.domain}';

      final created = await alice.engine.groups.create(
        name: 'Two servers',
        members: [bobOnA],
      );
      expect(created.rejected, isEmpty);
      final id = created.groupId;
      final chat = GroupIds.conversationId(id);

      // Bob learns the group through his own server, with Alice qualified,
      // and reads its name once the key arrives (relayed pairwise).
      await pump(() async {
        final row = await bob.db.groupsDao.byId(id);
        expect(row, isNotNull);
        expect(row!.title, 'Two servers');
      });
      expect([
        for (final m in await bob.db.groupsDao.members(id)) m.accountId,
      ], unorderedEquals([aliceOnB, bob.account]));
      expect([
        for (final m in await alice.db.groupsDao.members(id)) m.accountId,
      ], unorderedEquals([alice.account, bobOnA]));

      await alice.engine.chats.sendText(chat, 'hello across');
      await pump(() async {
        expect(
          (await waitForGroupTextNow(bob, id, 'hello across')).sender,
          aliceOnB,
        );
      });
      await bob.engine.chats.sendText(chat, 'hello back');
      await pump(() async {
        expect(
          (await waitForGroupTextNow(alice, id, 'hello back')).sender,
          bobOnA,
        );
      });
      for (final user in [alice, bob]) {
        expect(
          (await groupMessages(
            user,
            id,
          )).where((m) => m.kind == MessageKinds.undecryptable),
          isEmpty,
        );
      }

      // Removing the remote member rotates the keys and ends their access.
      await alice.engine.groups.removeMember(id, bobOnA);
      await pump(() async {
        expect(await bob.db.groupsDao.byId(id), isNull);
      });
      await alice.engine.chats.sendText(chat, 'bob is gone');
      await fed.settle([a, b]);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await fed.settle([a, b]);
      expect(
        [
          for (final m in await groupMessages(bob, id))
            if (m.kind == 'text') m.body,
        ],
        ['hello across', 'hello back'],
      );
    });
  });
}

/// The message with [text] if [user] has it now, else throws (for pump).
Future<MessageRow> waitForGroupTextNow(
  EngineUser user,
  String groupId,
  String text,
) async {
  final all = await groupMessages(user, groupId);
  final match = all.where((m) => m.body == text && m.deletedAt == null);
  expect(match, isNotEmpty, reason: '${user.name} has no "$text"');
  return match.first;
}

// ------------------------------------------------------------- helpers

/// Waits until [user] is in [groupId] (the chat exists and, with [title],
/// the group's name has been read with the group key).
Future<void> inGroup(EngineUser user, String groupId, {String? title}) =>
    settle(() async {
      final row = await user.db.groupsDao.byId(groupId);
      expect(row, isNotNull, reason: '${user.name} is not in the group yet');
      expect(
        await user.db.conversationsDao.byId(GroupIds.conversationId(groupId)),
        isNotNull,
      );
      if (title != null) {
        expect(row!.title, title, reason: '${user.name} cannot read the name');
      }
    });

Future<ConversationRow?> groupChat(EngineUser user, String groupId) =>
    user.db.conversationsDao.byId(GroupIds.conversationId(groupId));

Future<List<MessageRow>> groupMessages(EngineUser user, String groupId) async =>
    (await user.db.messagesDao.pageOlder(
      GroupIds.conversationId(groupId),
      limit: 500,
    )).messages;

/// Waits for a text message with [text] in the group chat of [user].
Future<MessageRow> waitForGroupText(
  EngineUser user,
  String groupId,
  String text, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  late MessageRow found;
  await settle(() async {
    final all = await groupMessages(user, groupId);
    final match = all.where((m) => m.body == text && m.deletedAt == null);
    expect(match, isNotEmpty, reason: '${user.name} has no "$text"');
    found = match.first;
  }, timeout: timeout);
  return found;
}

/// This device's sender key for the group (decoded).
Future<SenderKeyView?> ownSenderKey(EngineUser user, String groupId) async {
  final row = await user.db.cryptoDao.latestSenderKey(
    groupId: groupId,
    account: user.account,
    device: user.device,
  );
  return row == null ? null : SenderKeyView(row.distId);
}

final class SenderKeyView {
  const SenderKeyView(this.distributionId);

  final String distributionId;
}
