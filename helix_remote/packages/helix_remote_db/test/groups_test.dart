import 'dart:typed_data';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show membersDigest;
import 'package:test/test.dart';

import 'support.dart';

GroupsCompanion newGroup(
  String id, {
  String title = 'Team',
  String role = 'member',
  int epoch = 0,
  DateTime? lastMessageAt,
  bool archived = false,
}) => GroupsCompanion.insert(
  id: id,
  title: title,
  role: role,
  epoch: Value(epoch),
  archived: Value(archived),
  lastMessageAt: Value(lastMessageAt),
  createdAt: t0,
);

GroupMemberRow member(
  String groupId,
  String account, {
  String role = 'member',
  bool isSelf = false,
  String devices = '[]',
}) => GroupMemberRow(
  groupId: groupId,
  accountId: account,
  qualifiedId: account,
  role: role,
  isSelf: isSelf,
  devicesJson: devices,
);

void main() {
  late HelixDb db;
  late GroupsDao groups;

  setUp(() async {
    db = memoryDb();
    groups = db.groupsDao;
    await groups.upsert(newGroup('g1', role: 'owner'));
  });

  group('the group row', () {
    test(
      'upsert replaces, byId reads, flags and the state blob persist',
      () async {
        await groups.upsert(newGroup('g1', title: 'Renamed', role: 'admin'));
        final row = (await groups.byId('g1'))!;
        expect((row.title, row.role), ('Renamed', 'admin'));
        expect((row.archived, row.muted, row.epoch), (false, false, 0));

        await groups.setMuted('g1', muted: true);
        await groups.setArchived('g1', archived: true);
        await groups.saveState(
          'g1',
          state: Uint8List.fromList([1, 2, 3]),
          version: 4,
        );
        final after = (await groups.byId('g1'))!;
        expect((after.muted, after.archived), (true, true));
        expect(after.state, [1, 2, 3]);
        expect(after.stateVersion, 4);
        expect(await groups.byId('nope'), isNull);
      },
    );

    test('the list is newest activity first and split by archived', () async {
      await groups.upsert(newGroup('old', lastMessageAt: at(1)));
      await groups.upsert(newGroup('new', lastMessageAt: at(9)));
      await groups.upsert(newGroup('hidden', archived: true));
      expect((await groups.all()).map((g) => g.id), ['new', 'old', 'g1']);
      expect((await groups.all(archived: true)).map((g) => g.id), ['hidden']);

      final stream = collect(groups.watchAll());
      await eventually(() => stream.isNotEmpty);
      await groups.upsert(newGroup('newest', lastMessageAt: at(20)));
      await eventually(() => stream.last.first.id == 'newest');
    });

    test('summary columns round-trip for the chat list', () async {
      await groups.upsert(
        GroupsCompanion.insert(
          id: 'g2',
          title: 'Chatty',
          role: 'member',
          lastMessageRowid: const Value(7),
          lastMessageSortKey: Value(SortKey.of(at(5), 'm7')),
          lastMessageAt: Value(at(5)),
          lastMessagePreview: const Value('see you at 5'),
          unreadCount: const Value(3),
          mentionCount: const Value(1),
          createdAt: t0,
        ),
      );
      final row = (await groups.byId('g2'))!;
      expect(row.lastMessageRowid, 7);
      expect(row.lastMessageSortKey, SortKey.of(at(5), 'm7'));
      expect(row.lastMessageAt, at(5));
      expect(row.lastMessagePreview, 'see you at 5');
      expect((row.unreadCount, row.mentionCount), (3, 1));
      // A fresh group starts with nothing.
      final fresh = (await groups.byId('g1'))!;
      expect(fresh.lastMessageAt, isNull);
      expect((fresh.unreadCount, fresh.mentionCount), (0, 0));
    });
  });

  group('the roster', () {
    test(
      'replaceRoster writes the whole roster and moves the epoch forward',
      () async {
        final ok = await groups.replaceRoster('g1', [
          member('g1', 'alice', role: 'owner', isSelf: true),
          member('g1', 'bob'),
        ], epoch: 3);
        expect(ok, isTrue);
        expect((await groups.members('g1')).map((m) => m.accountId), [
          'alice',
          'bob',
        ]);
        expect((await groups.byId('g1'))!.epoch, 3);

        // A newer roster replaces, it does not merge: bob is gone, carol is in.
        await groups.replaceRoster('g1', [
          member('g1', 'alice', role: 'owner', isSelf: true),
          member('g1', 'carol'),
        ], epoch: 4);
        expect((await groups.members('g1')).map((m) => m.accountId), [
          'alice',
          'carol',
        ]);
        expect((await groups.byId('g1'))!.epoch, 4);
      },
    );

    test('a stale roster is refused and changes nothing', () async {
      await groups.replaceRoster('g1', [member('g1', 'alice')], epoch: 5);
      final ok = await groups.replaceRoster('g1', [
        member('g1', 'alice'),
        member('g1', 'removed-long-ago'),
      ], epoch: 4);
      expect(ok, isFalse);
      expect((await groups.members('g1')).map((m) => m.accountId), ['alice']);
      expect((await groups.byId('g1'))!.epoch, 5);
      // The same epoch is a refresh and is applied.
      expect(
        await groups.replaceRoster('g1', [member('g1', 'dave')], epoch: 5),
        isTrue,
      );
      expect((await groups.members('g1')).single.accountId, 'dave');
    });

    test('a failing replace rolls back the old roster', () async {
      await groups.replaceRoster('g1', [member('g1', 'alice')], epoch: 1);
      await expectLater(
        groups.replaceRoster('g1', [
          member('g1', 'bob'),
          member('g1', 'bob'), // duplicate primary key
        ], epoch: 2),
        throwsA(anything),
      );
      expect((await groups.members('g1')).map((m) => m.accountId), ['alice']);
      expect((await groups.byId('g1'))!.epoch, 1);
    });

    test('self membership decides the role; unknown means member', () async {
      expect(await groups.selfRole('g1'), GroupRole.member);
      await groups.replaceRoster('g1', [
        member('g1', 'alice', role: 'admin', isSelf: true),
        member('g1', 'bob', role: 'owner'),
      ], epoch: 1);
      expect((await groups.selfMembership('g1'))!.accountId, 'alice');
      expect(await groups.selfRole('g1'), GroupRole.admin);
      expect((await groups.member('g1', 'bob'))!.role, 'owner');
      expect(await groups.member('g1', 'zed'), isNull);

      // A role this build does not know never grants more than member.
      await groups.replaceRoster('g1', [
        member('g1', 'alice', role: 'superuser', isSelf: true),
      ], epoch: 2);
      expect(await groups.selfRole('g1'), GroupRole.member);
    });

    test('watchMembers follows roster changes', () async {
      final stream = collect(groups.watchMembers('g1'));
      await eventually(() => stream.isNotEmpty);
      await groups.replaceRoster('g1', [member('g1', 'alice')], epoch: 1);
      await eventually(() => stream.last.length == 1);
    });
  });

  group('device lists', () {
    test('are stored as JSON and read back per member and per group', () async {
      await groups.replaceRoster('g1', [
        member('g1', 'alice', isSelf: true),
        member('g1', 'bob'),
        member('g1', 'carol'),
      ], epoch: 1);
      await groups.saveMemberDevices(
        'g1',
        'alice',
        deviceIds: ['a1', 'a2'],
        now: at(1),
      );
      await groups.saveMemberDevices(
        'g1',
        'bob',
        deviceIds: ['b1'],
        now: at(2),
      );

      final stored = (await groups.member('g1', 'alice'))!;
      expect(stored.devicesJson, '["a1","a2"]');
      expect(stored.devicesFetchedAt, at(1));
      expect(await groups.memberDevices('g1', 'alice'), ['a1', 'a2']);
      expect(await groups.memberDevices('g1', 'nobody'), isEmpty);
      // carol was never fetched: no devices, not an error.
      expect(await groups.devicesByAccount('g1'), {
        'alice': ['a1', 'a2'],
        'bob': ['b1'],
        'carol': <String>[],
      });

      final roster = await groups.rosterDevices('g1');
      expect(roster.map((r) => r.accountId), ['alice', 'bob', 'carol']);
      expect(roster.first.deviceIds, ['a1', 'a2']);
      expect(roster.first.fetchedAt, at(1));
      expect(roster.last.fetchedAt, isNull);
    });

    test(
      'the roster digest is the protocol digest over the stored devices',
      () async {
        await groups.replaceRoster('g1', [
          member('g1', 'bob'),
          member('g1', 'alice'),
        ], epoch: 1);
        await groups.saveMemberDevices(
          'g1',
          'alice',
          deviceIds: ['a2', 'a1'],
          now: t0,
        );
        await groups.saveMemberDevices('g1', 'bob', deviceIds: ['b1'], now: t0);
        final digest = await groups.rosterDigest('g1');
        expect(
          digest,
          membersDigest({
            'alice': ['a1', 'a2'],
            'bob': ['b1'],
          }),
        );
        // A new device changes it; that is what makes a stale send detectable.
        await groups.saveMemberDevices(
          'g1',
          'bob',
          deviceIds: ['b1', 'b2'],
          now: t0,
        );
        expect(await groups.rosterDigest('g1'), isNot(digest));
      },
    );

    test('unreadable stored lists are no devices, never more devices', () {
      expect(decodeDeviceIds('["a","b"]'), ['a', 'b']);
      expect(decodeDeviceIds('not json'), isEmpty);
      expect(decodeDeviceIds('{"a":1}'), isEmpty);
      expect(decodeDeviceIds('["a", 7, null, "", "b"]'), ['a', 'b']);
    });

    test('a federated member is told apart by its qualified id', () async {
      await groups.replaceRoster('g1', [
        const GroupMemberRow(
          groupId: 'g1',
          accountId: 'uuid-1',
          qualifiedId: 'uuid-1@other.example',
          role: 'member',
          isSelf: false,
          devicesJson: '[]',
        ),
        member('g1', 'local'),
      ], epoch: 1);
      final roster = await groups.rosterDevices('g1');
      expect(
        {for (final r in roster) r.accountId: r.isFederated},
        {'local': false, 'uuid-1': true},
      );
    });
  });

  group('bans', () {
    test('a ban is recorded, idempotent and removable', () async {
      expect(await groups.isBanned('g1', 'mallory'), isFalse);
      await groups.addBan('g1', 'mallory', now: at(1));
      await groups.addBan('g1', 'mallory', now: at(2));
      expect(await groups.isBanned('g1', 'mallory'), isTrue);
      expect(await groups.isBanned('g1', 'someone-else'), isFalse);
      final bans = await groups.bans('g1');
      expect(bans, hasLength(1));
      expect(bans.single.bannedAt, at(2));

      await groups.removeBan('g1', 'mallory');
      expect(await groups.isBanned('g1', 'mallory'), isFalse);
    });

    test('bans are per group', () async {
      await groups.upsert(newGroup('g2'));
      await groups.addBan('g1', 'mallory', now: t0);
      expect(await groups.isBanned('g2', 'mallory'), isFalse);
    });
  });

  group('forget', () {
    test(
      'drops the group, its roster and its bans, and no other group',
      () async {
        await groups.upsert(newGroup('g2'));
        for (final id in ['g1', 'g2']) {
          await groups.replaceRoster(id, [member(id, 'alice')], epoch: 1);
          await groups.addBan(id, 'mallory', now: t0);
        }
        await groups.forget('g1');
        expect(await groups.byId('g1'), isNull);
        expect(await groups.members('g1'), isEmpty);
        expect(await groups.bans('g1'), isEmpty);
        expect(await groups.byId('g2'), isNotNull);
        expect(await groups.members('g2'), hasLength(1));
        expect(await groups.bans('g2'), hasLength(1));
      },
    );
  });
}
