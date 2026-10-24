import 'dart:async';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/groups/module.dart';
import 'package:test/test.dart';

import '../support/flows.dart';
import '../support/harness.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';

const carolNumber = '+8801711000003';

void main() {
  group('groups', skip: databaseTestSkipReason, () {
    late Harness h;
    late TestDevice alice;
    late TestDevice bob;
    late TestDevice carol;

    setUp(() async {
      h = await Harness.start();
      alice = await h.registerGlobal(aliceNumber);
      bob = await h.registerGlobal(bobNumber);
      carol = await h.registerGlobal(carolNumber);
    });

    tearDown(() async => h.stop());

    Future<Group> create(
      List<String> members, {
      GroupSettings settings = const GroupSettings(),
    }) async {
      final r = await h.api.call(
        Routes.createGroup,
        bearer: alice.bearer,
        body: CreateGroupRequest(
          groupId: Uuid.v7(),
          encryptedState: bytes(40),
          members: members,
          settings: settings,
        ).toJson(),
      );
      expect(r.status, 201, reason: r.body);
      return Group.fromJson(r.json);
    }

    Future<List<RosterChangeEvent>> roster(TestDevice d) async => [
      for (final e in (await mailbox(h, d)).envelopes)
        if (e.kind == EnvelopeKind.rosterChange)
          RosterChangeEvent.fromJson(JsonReader(e.data!)),
    ];

    test(
      'creating respects each person\'s group-add privacy and announces the roster',
      () async {
        await h.api.call(
          Routes.setPrivacy,
          bearer: carol.bearer,
          body: const PrivacySettings(groupAdd: Audience.nobody).toJson(),
        );
        final g = await create([bob.accountId, carol.accountId]);
        expect(g.members.map((m) => (m.account, m.role)), [
          (alice.accountId, GroupRole.owner),
          (bob.accountId, GroupRole.member),
        ]);
        final events = await roster(bob);
        expect(events.single.change, RosterChangeKind.created);
        expect(events.single.members, [bob.accountId]);
        expect(await roster(carol), isEmpty);
        expect(
          (await h.api.call(
            Routes.group,
            params: {'group_id': g.groupId},
            bearer: carol.bearer,
          )).status,
          404,
          reason: 'non-members cannot see that the group exists',
        );
        final mine = GroupList.fromJson(
          (await h.api.call(Routes.myGroups, bearer: bob.bearer)).json,
        );
        expect(mine.groups.single.groupId, g.groupId);
      },
    );

    test(
      'a group message is one ciphertext fanned out; distributions arrive first',
      () async {
        final g = await create([bob.accountId, carol.accountId]);
        final digest = membersDigest({
          alice.accountId: <String>[],
          bob.accountId: [bob.id],
          carol.accountId: [carol.id],
        });
        final id = Uuid.v7();
        final ok = await h.api.call(
          Routes.sendGroupMessage,
          params: {'group_id': g.groupId},
          bearer: alice.bearer,
          body: GroupMessageRequest(
            id: id,
            payload: bytes(200, 5),
            devicesDigest: digest,
            distributions: [
              Recipient(
                account: bob.accountId,
                devices: [DevicePayload(device: bob.id, payload: bytes(90, 6))],
              ),
            ],
          ).toJson(),
        );
        expect(ok.status, 200, reason: ok.body);
        final bobBox = (await mailbox(
          h,
          bob,
        )).envelopes.where((e) => e.kind != EnvelopeKind.rosterChange).toList();
        expect(bobBox.map((e) => e.kind), [
          EnvelopeKind.message,
          EnvelopeKind.groupMessage,
        ]);
        expect(bobBox[1].groupId, g.groupId);
        expect(bobBox[1].payload, bytes(200, 5));
        expect(bobBox[1].id, id);
        final carolBox = (await mailbox(
          h,
          carol,
        )).envelopes.where((e) => e.kind == EnvelopeKind.groupMessage);
        expect(carolBox.single.payload, bytes(200, 5));
      },
    );

    test('a stale device digest returns every member device', () async {
      final g = await create([bob.accountId]);
      final stale = await h.api.call(
        Routes.sendGroupMessage,
        params: {'group_id': g.groupId},
        bearer: alice.bearer,
        body: GroupMessageRequest(
          id: Uuid.v7(),
          payload: bytes(10),
          devicesDigest: bytes(32),
        ).toJson(),
      );
      expect(stale.status, 409);
      final details = StaleDevices.fromJson(
        stale.json.object('error').object('details'),
      );
      final bobs = details.accounts.firstWhere(
        (a) => a.account == bob.accountId,
      );
      expect(bobs.missing, [bob.id]);
    });

    test('the same group message id sent twice stores it once', () async {
      final g = await create([bob.accountId, carol.accountId]);
      final digest = membersDigest({
        alice.accountId: <String>[],
        bob.accountId: [bob.id],
        carol.accountId: [carol.id],
      });
      final id = Uuid.v7();
      Future<TestResponse> send() => h.api.call(
        Routes.sendGroupMessage,
        params: {'group_id': g.groupId},
        bearer: alice.bearer,
        body: GroupMessageRequest(
          id: id,
          payload: bytes(200, 5),
          devicesDigest: digest,
        ).toJson(),
      );
      expect((await send()).status, 200);
      // A retry whose answer was lost: no Idempotency-Key, just the id.
      final retry = await send();
      expect(retry.status, 200, reason: retry.body);
      expect(
        SendMessageResponse.fromJson(retry.json).replayed,
        isTrue,
        reason: 'a group send is idempotent by message id, like a direct one',
      );
      for (final d in [bob, carol]) {
        expect(
          (await mailbox(h, d)).envelopes.where((e) => e.id == id),
          hasLength(1),
          reason: '${d.id} holds one copy of the retried message',
        );
      }
    });

    test('a member list longer than the group can hold is refused', () async {
      final g = await create([bob.accountId]);
      final tooMany = await h.api.call(
        Routes.addGroupMembers,
        params: {'group_id': g.groupId},
        bearer: alice.bearer,
        body: AddMembersRequest(
          accounts: [for (var i = 0; i <= Group.maxMembers; i++) Uuid.v7()],
        ).toJson(),
      );
      expect(tooMany.errorCode, 'invalid_field');
      expect(
        tooMany.json.object('error').object('details').string('field'),
        'accounts',
        reason: 'refused before any id is resolved under the group lock',
      );
    });

    test(
      'a member removed while a send is in flight receives nothing',
      () async {
        final g = await create([bob.accountId, carol.accountId]);
        final digest = membersDigest({
          alice.accountId: <String>[],
          bob.accountId: [bob.id],
          carol.accountId: [carol.id],
        });
        Future<TestResponse> send(String id) => h.api.call(
          Routes.sendGroupMessage,
          params: {'group_id': g.groupId},
          bearer: alice.bearer,
          body: GroupMessageRequest(
            id: id,
            payload: bytes(200, 5),
            devicesDigest: digest,
          ).toJson(),
        );
        // One send first, so the group's rate bucket exists: it is what the
        // gate below locks.
        expect((await send(Uuid.v7())).status, 200);

        final parked = Completer<void>();
        final release = Completer<void>();
        unawaited(
          h.env.platform.db.tx((tx) async {
            // A send stops on this bucket after reading the roster and
            // before storing anything, which is the window the finding is
            // about: hold it, change the roster inside it, then let go.
            final row = await tx.queryOne(
              'SELECT key FROM ${h.env.platform.schemas.platform}.rate_buckets '
              'WHERE key = @k:text FOR UPDATE',
              {'k': '${GroupsModule.fanOutPerGroup.name}:${g.groupId}'},
            );
            if (row == null) return;
            parked.complete();
            await release.future;
          }),
        );
        await parked.future.timeout(const Duration(seconds: 5));

        final id = Uuid.v7();
        final inFlight = send(id);
        expect(
          await Future.any([
            inFlight.then((_) => false),
            Future.delayed(const Duration(milliseconds: 400), () => true),
          ]),
          isTrue,
          reason: 'the send is parked on the locked budget',
        );
        final removed = await h.api.call(
          Routes.removeGroupMember,
          params: {'group_id': g.groupId, 'account': carol.accountId},
          bearer: alice.bearer,
        );
        expect(removed.status, 200, reason: removed.body);
        release.complete();

        final answer = await inFlight;
        expect(answer.status, 200, reason: 'the sender is still a member');
        final seen = Future.wait([mailbox(h, bob), mailbox(h, carol)]);
        final boxes = await seen;
        expect(
          boxes[0].envelopes.where((e) => e.id == id),
          hasLength(1),
          reason: 'the members left in the group get it',
        );
        expect(
          boxes[1].envelopes.where((e) => e.id == id),
          isEmpty,
          reason: 'the removal committed before the message was stored',
        );
      },
    );

    test(
      'roles: members cannot administer; owners transfer ownership',
      () async {
        final g = await create([bob.accountId, carol.accountId]);
        final forbidden = await h.api.call(
          Routes.setGroupSettings,
          params: {'group_id': g.groupId},
          bearer: bob.bearer,
          body: const GroupSettings(
            addMembers: GroupPermission.everyone,
          ).toJson(),
        );
        expect(forbidden.errorCode, 'forbidden');
        await h.api.call(
          Routes.setGroupRole,
          params: {'group_id': g.groupId, 'account': bob.accountId},
          bearer: alice.bearer,
          body: const SetRoleRequest(role: GroupRole.owner).toJson(),
        );
        final view = Group.fromJson(
          (await h.api.call(
            Routes.group,
            params: {'group_id': g.groupId},
            bearer: carol.bearer,
          )).json,
        );
        final roles = {for (final m in view.members) m.account: m.role};
        expect(roles[bob.accountId], GroupRole.owner);
        expect(roles[alice.accountId], GroupRole.admin);
      },
    );

    test(
      'removal bumps the epoch, tells the removed member, and ends their access',
      () async {
        final g = await create([bob.accountId, carol.accountId]);
        final removed = await h.api.call(
          Routes.removeGroupMember,
          params: {'group_id': g.groupId, 'account': carol.accountId},
          bearer: alice.bearer,
        );
        expect(GroupVersionResponse.fromJson(removed.json).epoch, g.epoch + 1);
        expect(
          (await roster(carol)).map((e) => e.change),
          contains(RosterChangeKind.removed),
        );
        final carolSend = await h.api.call(
          Routes.sendGroupMessage,
          params: {'group_id': g.groupId},
          bearer: carol.bearer,
          body: GroupMessageRequest(
            id: Uuid.v7(),
            payload: bytes(10),
            devicesDigest: bytes(32),
          ).toJson(),
        );
        expect(carolSend.status, 404);
      },
    );

    test(
      'when the owner leaves, an admin (or the oldest member) takes over',
      () async {
        final g = await create([bob.accountId, carol.accountId]);
        await h.api.call(
          Routes.removeGroupMember,
          params: {'group_id': g.groupId, 'account': alice.accountId},
          bearer: alice.bearer,
        );
        final view = Group.fromJson(
          (await h.api.call(
            Routes.group,
            params: {'group_id': g.groupId},
            bearer: bob.bearer,
          )).json,
        );
        expect(
          view.members.firstWhere((m) => m.role == GroupRole.owner).account,
          bob.accountId,
        );
        expect((await roster(bob)).last.change, RosterChangeKind.left);
      },
    );

    test('absurd times and sizes in a request are a clean 4xx, not a 500, '
        'and the server keeps working', () async {
      final g = await create([bob.accountId]);
      for (final huge in [
        9223372036854775807,
        -9223372036854775808,
        8640000000000001,
        253402300800000,
      ]) {
        final r = await h.api.call(
          Routes.createInviteLink,
          params: {'group_id': g.groupId},
          bearer: alice.bearer,
          body: {
            'encrypted_preview': encodeBytes(bytes(30, 9)),
            'expires_at': huge,
          },
        );
        expect(
          r.status,
          inInclusiveRange(400, 499),
          reason: '$huge: ${r.body}',
        );
      }
      final fine = await h.api.call(
        Routes.createInviteLink,
        params: {'group_id': g.groupId},
        bearer: alice.bearer,
        body: CreateInviteLinkRequest(encryptedPreview: bytes(30, 9)).toJson(),
      );
      expect(fine.status, inInclusiveRange(200, 299));
    });

    test('invite links: preview, join, approval flow, bans', () async {
      final g = await create([bob.accountId]);
      final open = InviteLink.fromJson(
        (await h.api.call(
          Routes.createInviteLink,
          params: {'group_id': g.groupId},
          bearer: alice.bearer,
          body: CreateInviteLinkRequest(
            encryptedPreview: bytes(30, 9),
          ).toJson(),
        )).json,
      );
      final preview = InvitePreview.fromJson(
        (await h.api.call(
          Routes.previewInviteLink,
          bearer: carol.bearer,
          body: InviteTokenRequest(token: open.token).toJson(),
        )).json,
      );
      expect(preview.memberCount, 2);
      expect(preview.encryptedPreview, bytes(30, 9));

      final joined = JoinGroupResponse.fromJson(
        (await h.api.call(
          Routes.joinGroup,
          bearer: carol.bearer,
          body: InviteTokenRequest(token: open.token).toJson(),
        )).json,
      );
      expect(joined.status, JoinStatus.joined);

      await h.api.call(
        Routes.banFromGroup,
        params: {'group_id': g.groupId, 'account': carol.accountId},
        bearer: alice.bearer,
      );
      final banned = await h.api.call(
        Routes.joinGroup,
        bearer: carol.bearer,
        body: InviteTokenRequest(token: open.token).toJson(),
      );
      expect(banned.errorCode, 'forbidden');

      final dave = await h.registerGlobal('+8801711000004');
      final approval = InviteLink.fromJson(
        (await h.api.call(
          Routes.createInviteLink,
          params: {'group_id': g.groupId},
          bearer: alice.bearer,
          body: CreateInviteLinkRequest(
            encryptedPreview: bytes(30),
            requiresApproval: true,
          ).toJson(),
        )).json,
      );
      final pending = JoinGroupResponse.fromJson(
        (await h.api.call(
          Routes.joinGroup,
          bearer: dave.bearer,
          body: InviteTokenRequest(token: approval.token).toJson(),
        )).json,
      );
      expect(pending.status, JoinStatus.pending);
      expect(
        (await roster(alice)).map((e) => e.change),
        contains(RosterChangeKind.joinRequested),
      );
      expect(
        (await roster(bob)).map((e) => e.change),
        isNot(contains(RosterChangeKind.joinRequested)),
        reason: 'only admins hear about requests',
      );
      final requests = JoinRequestList.fromJson(
        (await h.api.call(
          Routes.joinRequests,
          params: {'group_id': g.groupId},
          bearer: alice.bearer,
        )).json,
      );
      await h.api.call(
        Routes.resolveJoinRequest,
        params: {
          'group_id': g.groupId,
          'request_id': requests.requests.single.requestId,
        },
        bearer: alice.bearer,
        body: const ResolveJoinRequest(approve: true).toJson(),
      );
      final view = Group.fromJson(
        (await h.api.call(
          Routes.group,
          params: {'group_id': g.groupId},
          bearer: dave.bearer,
        )).json,
      );
      expect(view.members.map((m) => m.account), contains(dave.accountId));

      await h.api.call(
        Routes.revokeInviteLink,
        params: {'group_id': g.groupId, 'link_id': open.linkId},
        bearer: alice.bearer,
      );
      expect(
        (await h.api.call(
          Routes.previewInviteLink,
          bearer: dave.bearer,
          body: InviteTokenRequest(token: open.token).toJson(),
        )).errorCode,
        'expired',
      );
    });

    test('admins list the live invite links, never their tokens', () async {
      final g = await create([bob.accountId]);
      Future<InviteLink> make({bool approval = false}) async =>
          InviteLink.fromJson(
            (await h.api.call(
              Routes.createInviteLink,
              params: {'group_id': g.groupId},
              bearer: alice.bearer,
              body: CreateInviteLinkRequest(
                encryptedPreview: bytes(30),
                requiresApproval: approval,
              ).toJson(),
            )).json,
          );
      final first = await make();
      final second = await make(approval: true);

      Future<TestResponse> list(TestDevice d) => h.api.call(
        Routes.listInviteLinks,
        params: {'group_id': g.groupId},
        bearer: d.bearer,
      );
      final listed = await list(alice);
      expect(listed.status, 200, reason: listed.body);
      expect(listed.body, isNot(contains(first.token)));
      expect(listed.body, isNot(contains(second.token)));
      final links = InviteLinkList.fromJson(listed.json).links;
      expect(links.map((l) => l.linkId), [second.linkId, first.linkId]);
      expect(links.map((l) => l.requiresApproval), [true, false]);
      expect(links.map((l) => l.createdBy), everyElement(alice.accountId));

      await h.api.call(
        Routes.revokeInviteLink,
        params: {'group_id': g.groupId, 'link_id': second.linkId},
        bearer: alice.bearer,
      );
      expect(
        InviteLinkList.fromJson(
          (await list(alice)).json,
        ).links.map((l) => l.linkId),
        [first.linkId],
      );

      // A member who is not an admin may not see them; a stranger cannot
      // tell the group exists.
      expect((await list(bob)).errorCode, 'forbidden');
      expect((await list(carol)).status, 404);
    });

    test('group state updates are optimistic', () async {
      final g = await create([bob.accountId]);
      Future<TestResponse> set(int expected) => h.api.call(
        Routes.setGroupState,
        params: {'group_id': g.groupId},
        bearer: alice.bearer,
        body: SetGroupStateRequest(
          encryptedState: bytes(50, expected),
          expectedVersion: expected,
        ).toJson(),
      );
      expect(
        GroupVersionResponse.fromJson(
          (await set(g.stateVersion)).json,
        ).stateVersion,
        g.stateVersion + 1,
      );
      expect((await set(g.stateVersion)).errorCode, 'version_conflict');
    });
  });
}
