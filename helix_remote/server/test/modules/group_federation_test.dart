/// Several servers per test: allow for parallel runs on a busy machine.
@Timeout(Duration(minutes: 2))
library;

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../support/federated.dart';
import '../support/flows.dart';
import '../support/harness.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';

const carolNumber = '+8801711000003';

/// Alice on server A owns the groups; Bob and Carol are on server B.
void main() {
  group('group federation', skip: databaseTestSkipReason, () {
    late Harness a;
    late Harness b;
    late TestDevice alice;
    late TestDevice bob;
    late TestDevice carol;

    setUp(() async {
      a = await federated();
      b = await federated();
      alice = await a.registerGlobal(aliceNumber);
      bob = await b.registerGlobal(bobNumber);
      carol = await b.registerGlobal(carolNumber);
    });
    tearDown(() async {
      await a.stop();
      await b.stop();
    });

    String onB(TestDevice d) => '${d.accountId}@${b.domain}';
    String onA(TestDevice d) => '${d.accountId}@${a.domain}';

    Future<Group> create(List<String> members) async {
      final r = await a.api.call(
        Routes.createGroup,
        bearer: alice.bearer,
        body: CreateGroupRequest(
          groupId: Uuid.v7(),
          encryptedState: bytes(40),
          members: members,
        ).toJson(),
      );
      expect(r.status, 201, reason: r.body);
      await settle([a, b]);
      return Group.fromJson(r.json);
    }

    Future<List<Envelope>> envelopes(
      Harness h,
      TestDevice d,
      EnvelopeKind kind,
    ) async => [
      for (final e in (await mailbox(h, d)).envelopes)
        if (e.kind == kind) e,
    ];

    Future<Group> viewOn(Harness h, TestDevice d, String groupId) async {
      final r = await h.api.call(
        Routes.group,
        params: {'group_id': groupId},
        bearer: d.bearer,
      );
      expect(r.status, 200, reason: r.body);
      return Group.fromJson(r.json);
    }

    Future<TestResponse> sendGroup(
      Harness h,
      TestDevice from,
      String groupId,
      Map<String, List<String>> devices, {
      List<Recipient> distributions = const [],
    }) => h.api.call(
      Routes.sendGroupMessage,
      params: {'group_id': groupId},
      bearer: from.bearer,
      body: GroupMessageRequest(
        id: Uuid.v7(),
        payload: bytes(120, 3),
        devicesDigest: membersDigest(devices),
        distributions: distributions,
      ).toJson(),
    );

    test('members on another server get the roster through it', () async {
      final g = await create([onB(bob)]);
      expect(g.members.map((m) => m.account), [alice.accountId, onB(bob)]);

      final events = await envelopes(b, bob, EnvelopeKind.rosterChange);
      final created = RosterChangeEvent.fromJson(
        JsonReader(events.single.data!),
      );
      expect(created.change, RosterChangeKind.created);
      expect(created.actor, onA(alice));
      expect(created.members, [bob.accountId]);

      final mine = GroupList.fromJson(
        (await b.api.call(Routes.myGroups, bearer: bob.bearer)).json,
      );
      expect(mine.groups.single.groupId, g.groupId);

      final seen = await viewOn(b, bob, g.groupId);
      expect(seen.homeServer, a.domain);
      expect(seen.members.map((m) => (m.account, m.role)), [
        (onA(alice), GroupRole.owner),
        (bob.accountId, GroupRole.member),
      ]);
      expect(
        (await b.api.call(
          Routes.group,
          params: {'group_id': g.groupId},
          bearer: carol.bearer,
        )).status,
        404,
      );
    });

    test('group messages cross servers both ways', () async {
      final g = await create([onB(bob)]);
      final fromAlice = await sendGroup(
        a,
        alice,
        g.groupId,
        {
          alice.accountId: [],
          onB(bob): [bob.id],
        },
        distributions: [
          Recipient(
            account: onB(bob),
            devices: [DevicePayload(device: bob.id, payload: bytes(60, 4))],
          ),
        ],
      );
      expect(fromAlice.status, 200, reason: fromAlice.body);
      await settle([a, b]);
      final received = await envelopes(b, bob, EnvelopeKind.groupMessage);
      expect(received.single.from!.account, onA(alice));
      expect(received.single.groupId, g.groupId);
      final keys = await envelopes(b, bob, EnvelopeKind.message);
      expect(keys.single.payload, bytes(60, 4));

      final fromBob = await sendGroup(b, bob, g.groupId, {
        onA(alice): [alice.id],
        bob.accountId: [],
      });
      expect(fromBob.status, 200, reason: fromBob.body);
      await settle([a, b]);
      final back = await envelopes(a, alice, EnvelopeKind.groupMessage);
      expect(back.single.from!.account, onB(bob));
    });

    test('a new device on the member server joins the digest', () async {
      final g = await create([onB(bob)]);
      final bob2 = await secondDevice(b, bob, bobNumber);
      await settle([a, b]);
      final stale = await sendGroup(a, alice, g.groupId, {
        alice.accountId: [],
        onB(bob): [bob.id],
      });
      expect(stale.errorCode, 'device_list_stale');
      final details = StaleDevices.fromJson(
        stale.json.object('error').object('details'),
      );
      final bobs = details.accounts.firstWhere((x) => x.account == onB(bob));
      expect(bobs.missing.toSet(), {bob.id, bob2.id});
    });

    test('leaving through the member server updates the home', () async {
      final g = await create([onB(bob)]);
      final left = await b.api.call(
        Routes.removeGroupMember,
        params: {'group_id': g.groupId, 'account': bob.accountId},
        bearer: bob.bearer,
      );
      expect(left.status, 200, reason: left.body);
      expect(GroupVersionResponse.fromJson(left.json).epoch, 1);
      await settle([a, b]);
      final home = await viewOn(a, alice, g.groupId);
      expect(home.members.map((m) => m.account), [alice.accountId]);
      final mine = GroupList.fromJson(
        (await b.api.call(Routes.myGroups, bearer: bob.bearer)).json,
      );
      expect(mine.groups, isEmpty);
      final events = await envelopes(b, bob, EnvelopeKind.rosterChange);
      expect(
        RosterChangeEvent.fromJson(JsonReader(events.last.data!)).change,
        RosterChangeKind.left,
      );
    });

    test(
      'the member server enforces its people\'s group-add privacy',
      () async {
        await b.api.call(
          Routes.setPrivacy,
          bearer: carol.bearer,
          body: const PrivacySettings(groupAdd: Audience.nobody).toJson(),
        );
        final g = await create([onB(bob), onB(carol)]);
        final home = await viewOn(a, alice, g.groupId);
        expect(home.members.map((m) => m.account), [alice.accountId, onB(bob)]);
        expect(await envelopes(b, carol, EnvelopeKind.rosterChange), isEmpty);
      },
    );

    test('remote admins act through their own server', () async {
      final g = await create([onB(bob)]);
      expect(
        (await a.api.call(
          Routes.setGroupRole,
          params: {'group_id': g.groupId, 'account': onB(bob)},
          bearer: alice.bearer,
          body: const SetRoleRequest(role: GroupRole.admin).toJson(),
        )).status,
        204,
      );
      await settle([a, b]);
      final added = await b.api.call(
        Routes.addGroupMembers,
        params: {'group_id': g.groupId},
        bearer: bob.bearer,
        body: AddMembersRequest(accounts: [carol.accountId]).toJson(),
      );
      expect(added.status, 200, reason: added.body);
      expect(AddMembersResponse.fromJson(added.json).added, [carol.accountId]);
      await settle([a, b]);
      final home = await viewOn(a, alice, g.groupId);
      expect(home.members.map((m) => m.account), contains(onB(carol)));
      expect(
        (await viewOn(b, carol, g.groupId)).members.map((m) => m.account),
        contains(carol.accountId),
      );
    });

    test('people on other servers join by link through their own', () async {
      final g = await create([]);
      final link = InviteLink.fromJson(
        (await a.api.call(
          Routes.createInviteLink,
          params: {'group_id': g.groupId},
          bearer: alice.bearer,
          body: CreateInviteLinkRequest(encryptedPreview: bytes(30)).toJson(),
        )).json,
      );
      expect(link.token, endsWith('.${g.groupId}@${a.domain}'));
      final preview = await b.api.call(
        Routes.previewInviteLink,
        bearer: carol.bearer,
        body: InviteTokenRequest(token: link.token).toJson(),
      );
      expect(preview.status, 200, reason: preview.body);
      expect(InvitePreview.fromJson(preview.json).memberCount, 1);
      final joined = await b.api.call(
        Routes.joinGroup,
        bearer: carol.bearer,
        body: InviteTokenRequest(token: link.token).toJson(),
      );
      expect(JoinGroupResponse.fromJson(joined.json).status, JoinStatus.joined);
      await settle([a, b]);
      final home = await viewOn(a, alice, g.groupId);
      expect(home.members.map((m) => m.account), contains(onB(carol)));
    });

    test('a member server delivers its own senders\' messages', () async {
      final g = await create([onB(bob), onB(carol)]);
      final sent = await sendGroup(
        b,
        bob,
        g.groupId,
        {
          onA(alice): [alice.id],
          bob.accountId: [],
          carol.accountId: [carol.id],
        },
        distributions: [
          Recipient(
            account: carol.accountId,
            devices: [DevicePayload(device: carol.id, payload: bytes(60, 5))],
          ),
        ],
      );
      expect(sent.status, 200, reason: sent.body);
      await settle([a, b]);
      final atCarol = await envelopes(b, carol, EnvelopeKind.groupMessage);
      expect(atCarol.single.from!.account, bob.accountId);
      final keys = await envelopes(b, carol, EnvelopeKind.message);
      expect(keys.single.from!.account, bob.accountId);
      expect(keys.single.payload, bytes(60, 5));
      expect(
        (await envelopes(
          a,
          alice,
          EnvelopeKind.groupMessage,
        )).single.from!.account,
        onB(bob),
      );
    });

    group('a malicious home server', () {
      late Group g;
      var version = 100;

      setUp(() async {
        g = await create([onB(bob)]);
      });

      Future<S2SGroupSyncResponse> push(RosterChangeEvent? event) async {
        final snapshot = Group(
          groupId: g.groupId,
          epoch: 0,
          stateVersion: 1,
          encryptedState: bytes(4),
          settings: const GroupSettings(),
          members: [
            GroupMember(
              account: onA(alice),
              role: GroupRole.owner,
              joinedAt: DateTime.utc(2026),
            ),
            for (final d in [bob, carol])
              GroupMember(
                account: d.accountId,
                role: GroupRole.member,
                joinedAt: DateTime.utc(2026),
              ),
          ],
          createdAt: DateTime.utc(2026),
          homeServer: a.domain,
        );
        final json = await a.federation.client.call(
          b.domain,
          'POST',
          Routes.s2sGroupSync.expand({'group_id': g.groupId}),
          body: S2SGroupSync(
            rosterVersion: version++,
            group: snapshot,
            event: event,
            notify: [carol.accountId],
          ).toJson(),
        );
        return S2SGroupSyncResponse.fromJson(json!);
      }

      RosterChangeEvent change(RosterChangeKind kind, String? actor) =>
          RosterChangeEvent(
            groupId: g.groupId,
            change: kind,
            epoch: 0,
            actor: actor,
            members: [carol.accountId],
          );

      Future<bool> carolIn() async => GroupList.fromJson(
        (await b.api.call(Routes.myGroups, bearer: carol.bearer)).json,
      ).groups.any((x) => x.groupId == g.groupId);

      test('cannot add people here without a legitimate adder', () async {
        for (final event in [
          null,
          change(RosterChangeKind.stateChanged, onA(alice)),
          change(RosterChangeKind.added, null),
          change(RosterChangeKind.added, carol.accountId),
          change(RosterChangeKind.added, '${Uuid.v7()}@${a.domain}'),
        ]) {
          final answer = await push(event);
          expect(answer.rejected, [
            carol.accountId,
          ], reason: '${event?.toJson()}');
          expect(await carolIn(), isFalse);
        }
        expect(await envelopes(b, carol, EnvelopeKind.rosterChange), isEmpty);

        // The owner adding Carol, whose privacy allows it, is accepted.
        final answer = await push(change(RosterChangeKind.added, onA(alice)));
        expect(answer.rejected, isEmpty);
        expect(await carolIn(), isTrue);
      });

      Future<void> fanOut(String sender) => a.federation.client.call(
        b.domain,
        'POST',
        Routes.s2sGroupMessages.expand({'group_id': g.groupId}),
        body: S2SGroupMessage(
          id: Uuid.v7(),
          sender: sender,
          senderDevice: Uuid.v7(),
          payload: bytes(40),
          devices: [bob.id],
          distributions: [DevicePayload(device: bob.id, payload: bytes(30))],
        ).toJson(),
      );

      test('cannot send in the name of people here or non-members', () async {
        for (final sender in [
          carol.accountId,
          onB(carol),
          '${Uuid.v7()}@${a.domain}',
        ]) {
          await expectLater(
            fanOut(sender),
            throwsA(predicate((e) => '$e'.contains('forbidden'))),
            reason: sender,
          );
        }
        Future<List<Envelope>> messages() async => [
          for (final e in (await mailbox(b, bob)).envelopes)
            if (e.kind != EnvelopeKind.rosterChange) e,
        ];
        expect(await messages(), isEmpty);

        await fanOut(onA(alice));
        final got = await messages();
        expect(got.map((e) => (e.kind, e.from!.account)), [
          (EnvelopeKind.message, onA(alice)),
          (EnvelopeKind.groupMessage, onA(alice)),
        ]);
      });
    });

    test('member servers cannot claim other people\'s devices', () async {
      final g = await create([onB(bob)]);
      final result = S2SGroupActionResult.fromJson(
        (await b.federation.client.call(
          a.domain,
          'POST',
          Routes.s2sGroupActions.expand({'group_id': g.groupId}),
          body: S2SGroupAction(
            actor: onB(bob),
            action: 'devices',
            body: {
              'devices': [bob.id, alice.id],
            },
          ).toJson(),
        ))!,
      );
      expect(result.status, 400);
      // Bob's devices are unchanged and Alice's stays hers.
      final sent = await sendGroup(a, alice, g.groupId, {
        alice.accountId: [],
        onB(bob): [bob.id],
      });
      expect(sent.status, 200, reason: sent.body);
    });

    /// A member's server names the device a remote member acts from. It may
    /// not name a device of the home server, or one already reported for
    /// another account (AUD-4c-4).
    test(
      'an action cannot name a device that belongs to someone else',
      () async {
        final g = await create([onB(bob)]);
        Future<S2SGroupActionResult> act(String? device) async =>
            S2SGroupActionResult.fromJson(
              (await b.federation.client.call(
                a.domain,
                'POST',
                Routes.s2sGroupActions.expand({'group_id': g.groupId}),
                body: S2SGroupAction(
                  actor: onB(bob),
                  actorDevice: device,
                  action: 'devices',
                  body: {
                    'devices': [bob.id],
                  },
                ).toJson(),
              ))!,
            );
        expect((await act(alice.id)).status, 403, reason: 'a home device');
        expect((await act('not a uuid')).status, 403);
        expect((await act(bob.id)).status, 204, reason: 'the actor own device');
        expect((await act(null)).status, 204);
      },
    );

    /// A group's deletion forgets the devices a remote member's server
    /// reported for it, when that member is in no other group here
    /// (AUD-4c-2).
    test(
      'deleting a group forgets the devices of its remote members',
      () async {
        final g = await create([onB(bob)]);
        final devices = '${a.env.platform.schemas.of('groups')}.remote_devices';
        Future<int> rows() async => (await a.env.platform.db.queryOne(
          'SELECT count(*)::int8 AS n FROM $devices WHERE account = @a:text',
          {'a': onB(bob)},
        ))!.integer('n');
        expect(await rows(), greaterThan(0));
        final r = await a.api.call(
          Routes.deleteGroup,
          params: {'group_id': g.groupId},
          bearer: alice.bearer,
        );
        expect(r.status, 204, reason: r.body);
        expect(await rows(), 0);
      },
    );

    /// Syncs of one group are applied one at a time, so the cache ends at the
    /// newest version whatever order they arrive in (AUD-4c-1). Carol is
    /// "removed" in the newest snapshot; an older one that lands last must not
    /// bring her back.
    test('overlapping syncs never leave an older roster cached', () async {
      final g = await create([onB(bob), onB(carol)]);
      final cache = '${b.env.platform.schemas.of('groups')}.remote_groups';
      Future<void> sync(int version, {required bool withCarol}) async {
        final snapshot = Group(
          groupId: g.groupId,
          epoch: 0,
          stateVersion: 1,
          encryptedState: bytes(4),
          settings: const GroupSettings(),
          members: [
            GroupMember(
              account: onA(alice),
              role: GroupRole.owner,
              joinedAt: DateTime.utc(2026),
            ),
            GroupMember(
              account: bob.accountId,
              role: GroupRole.member,
              joinedAt: DateTime.utc(2026),
            ),
            if (withCarol)
              GroupMember(
                account: carol.accountId,
                role: GroupRole.member,
                joinedAt: DateTime.utc(2026),
              ),
          ],
          createdAt: DateTime.utc(2026),
          homeServer: a.domain,
        );
        await a.federation.client.call(
          b.domain,
          'POST',
          Routes.s2sGroupSync.expand({'group_id': g.groupId}),
          body: S2SGroupSync(
            rosterVersion: version,
            group: snapshot,
            notify: const [],
          ).toJson(),
        );
      }

      await Future.wait([
        for (var v = 1; v <= 12; v++) sync(1000 + v, withCarol: v != 12),
      ]);
      final row = (await b.env.platform.db.queryOne(
        'SELECT roster_version FROM $cache WHERE group_id = @g:uuid',
        {'g': g.groupId},
      ))!;
      expect(row.integer('roster_version'), 1012);
      final members = GroupList.fromJson(
        (await b.api.call(Routes.myGroups, bearer: carol.bearer)).json,
      );
      expect(
        members.groups.any((x) => x.groupId == g.groupId),
        isFalse,
        reason: 'the newest roster has no Carol',
      );
    });

    test('only the home server may push a group', () async {
      final g = await create([onB(bob)]);
      // A third server claiming the same group is refused by B.
      final c = await federated();
      try {
        final response = await c.federation.client.call(
          b.domain,
          'POST',
          Routes.s2sGroupSync.expand({'group_id': g.groupId}),
          body: S2SGroupSync(
            rosterVersion: 99,
            group: Group(
              groupId: g.groupId,
              epoch: 0,
              stateVersion: 1,
              encryptedState: bytes(4),
              settings: const GroupSettings(),
              members: const [],
              createdAt: DateTime.utc(2026),
            ),
          ).toJson(),
        );
        fail('expected a refusal, got $response');
      } on Object catch (e) {
        expect('$e', contains('forbidden'));
      } finally {
        await c.stop();
      }
      expect((await viewOn(b, bob, g.groupId)).members, hasLength(2));
    });
  });
}
