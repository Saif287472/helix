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
