import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:helix_remote_db/src/database.dart';
import 'package:helix_remote_db/src/tables/groups.dart';
import 'package:helix_remote_db/src/values.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show membersDigest;

part 'groups_dao.g.dart';

/// Groups, their rosters and their bans.
///
/// The roster is the **server's**, cached here so a send can name the exact
/// devices to encrypt to and the sender-key fan-out can tell who is missing the
/// key. Every write is one transaction, because a half-applied roster would
/// encrypt to the wrong audience.
@DriftAccessor(tables: [Groups, GroupMembers, GroupBans])
class GroupsDao extends DatabaseAccessor<HelixDb> with _$GroupsDaoMixin {
  GroupsDao(super.attachedDatabase);

  // ------------------------------------------------------------- the group

  Future<GroupRow?> byId(String groupId) =>
      (select(groups)..where((g) => g.id.equals(groupId))).getSingleOrNull();

  Future<List<GroupRow>> all({bool archived = false}) =>
      (select(groups)
            ..where((g) => g.archived.equals(archived))
            ..orderBy([(g) => OrderingTerm.desc(g.lastMessageAt)]))
          .get();

  Stream<List<GroupRow>> watchAll({bool archived = false}) =>
      (select(groups)
            ..where((g) => g.archived.equals(archived))
            ..orderBy([(g) => OrderingTerm.desc(g.lastMessageAt)]))
          .watch();

  Stream<GroupRow?> watch(String groupId) =>
      (select(groups)..where((g) => g.id.equals(groupId))).watchSingleOrNull();

  Future<void> upsert(GroupsCompanion group) =>
      into(groups).insertOnConflictUpdate(group);

  Future<void> setArchived(String groupId, {required bool archived}) =>
      (update(groups)..where((g) => g.id.equals(groupId))).write(
        GroupsCompanion(archived: Value(archived)),
      );

  Future<void> setMuted(String groupId, {required bool muted}) =>
      (update(groups)..where((g) => g.id.equals(groupId))).write(
        GroupsCompanion(muted: Value(muted)),
      );

  /// The group's encrypted state blob, as the server last sent it.
  Future<void> saveState(
    String groupId, {
    required Uint8List state,
    required int version,
  }) => (update(groups)..where((g) => g.id.equals(groupId))).write(
    GroupsCompanion(state: Value(state), stateVersion: Value(version)),
  );

  // ----------------------------------------------------------- the roster

  Future<List<GroupMemberRow>> members(String groupId) =>
      (select(groupMembers)
            ..where((m) => m.groupId.equals(groupId))
            ..orderBy([(m) => OrderingTerm.asc(m.accountId)]))
          .get();

  Stream<List<GroupMemberRow>> watchMembers(String groupId) =>
      (select(groupMembers)
            ..where((m) => m.groupId.equals(groupId))
            ..orderBy([(m) => OrderingTerm.asc(m.accountId)]))
          .watch();

  /// The groups [account] is in, by the roster stored here.
  Future<List<String>> groupIdsOf(String account) async => [
    for (final m in await (select(
      groupMembers,
    )..where((m) => m.accountId.equals(account))).get())
      m.groupId,
  ];

  Future<GroupMemberRow?> member(String groupId, String account) =>
      (select(groupMembers)..where(
            (m) => m.groupId.equals(groupId) & m.accountId.equals(account),
          ))
          .getSingleOrNull();

  /// This device's own membership, which is what decides whether it may read
  /// the roster at all.
  Future<GroupMemberRow?> selfMembership(String groupId) =>
      (select(groupMembers)
            ..where((m) => m.groupId.equals(groupId) & m.isSelf.equals(true)))
          .getSingleOrNull();

  Future<GroupRole> selfRole(String groupId) async {
    final row = await selfMembership(groupId);
    if (row == null) return GroupRole.member;
    return GroupRole.values.firstWhere(
      (role) => role.name == row.role,
      orElse: () => GroupRole.member,
    );
  }

  /// Replaces the whole roster in one transaction.
  ///
  /// A roster is only ever valid as a whole: encrypting to a partly-applied one
  /// would either miss a member or send to somebody who has left. [members] is
  /// therefore written wholesale. A roster older than the one already stored is
  /// refused (returns false, nothing written), so a late response cannot put a
  /// removed member back; the same epoch is a refresh and is applied.
  Future<bool> replaceRoster(
    String groupId,
    List<GroupMemberRow> members, {
    required int epoch,
  }) => transaction(() async {
    final group = await byId(groupId);
    if (group != null && epoch < group.epoch) return false;
    await (delete(groupMembers)..where((m) => m.groupId.equals(groupId))).go();
    for (final member in members) {
      await into(groupMembers).insert(member);
    }
    if (group != null && epoch > group.epoch) {
      await (update(groups)..where((g) => g.id.equals(groupId))).write(
        GroupsCompanion(epoch: Value(epoch)),
      );
    }
    return true;
  });

  /// Records one member's device list, as the server returned it.
  Future<void> saveMemberDevices(
    String groupId,
    String account, {
    required List<String> deviceIds,
    required DateTime now,
  }) =>
      (update(groupMembers)..where(
            (m) => m.groupId.equals(groupId) & m.accountId.equals(account),
          ))
          .write(
            GroupMembersCompanion(
              devicesJson: Value(jsonEncode(deviceIds)),
              devicesFetchedAt: Value(now),
            ),
          );

  /// One member's cached device ids.
  Future<List<String>> memberDevices(String groupId, String account) async {
    final row = await member(groupId, account);
    if (row == null) return const [];
    return decodeDeviceIds(row.devicesJson);
  }

  /// Every member's device ids, keyed by account: the exact audience a group
  /// message is encrypted to, and what the roster digest is taken over.
  Future<Map<String, List<String>>> devicesByAccount(String groupId) async {
    final rows = await members(groupId);
    return {
      for (final row in rows) row.accountId: decodeDeviceIds(row.devicesJson),
    };
  }

  /// One member's devices, with the addressing the send path needs.
  Future<List<GroupMemberDevices>> rosterDevices(String groupId) async {
    final rows = await members(groupId);
    return [
      for (final row in rows)
        GroupMemberDevices(
          accountId: row.accountId,
          qualifiedId: row.qualifiedId,
          deviceIds: decodeDeviceIds(row.devicesJson),
          fetchedAt: row.devicesFetchedAt,
        ),
    ];
  }

  /// The digest the server compares to decide whether a fan-out is stale
  /// (CRYPTO_V2.md §7). It is over member device ids only: this device learns
  /// nothing else about anybody's devices.
  Future<Uint8List> rosterDigest(String groupId) async =>
      membersDigest(await devicesByAccount(groupId));

  // ----------------------------------------------------------------- bans

  Future<List<GroupBanRow>> bans(String groupId) =>
      (select(groupBans)..where((b) => b.groupId.equals(groupId))).get();

  Future<bool> isBanned(String groupId, String account) async =>
      (await (select(groupBans)..where(
            (b) => b.groupId.equals(groupId) & b.accountId.equals(account),
          ))
          .getSingleOrNull()) !=
      null;

  Future<void> addBan(
    String groupId,
    String account, {
    required DateTime now,
  }) => into(groupBans).insertOnConflictUpdate(
    GroupBansCompanion.insert(
      groupId: groupId,
      accountId: account,
      bannedAt: now,
    ),
  );

  Future<void> removeBan(String groupId, String account) =>
      (delete(groupBans)..where(
            (b) => b.groupId.equals(groupId) & b.accountId.equals(account),
          ))
          .go();

  /// Drops everything about a group. Used when this device leaves, and when an
  /// account is purged.
  Future<void> forget(String groupId) => transaction(() async {
    await (delete(groupMembers)..where((m) => m.groupId.equals(groupId))).go();
    await (delete(groupBans)..where((b) => b.groupId.equals(groupId))).go();
    await (delete(groups)..where((g) => g.id.equals(groupId))).go();
  });
}

/// One member's cached device list.
final class GroupMemberDevices {
  const GroupMemberDevices({
    required this.accountId,
    required this.qualifiedId,
    required this.deviceIds,
    this.fetchedAt,
  });

  final String accountId;

  /// `uuid@domain` when the member is on another server (S6c), else the
  /// account id itself.
  final String qualifiedId;

  final List<String> deviceIds;
  final DateTime? fetchedAt;

  bool get isFederated => qualifiedId.contains('@');
}

/// Decodes a stored device list, treating anything unreadable as no devices.
///
/// A corrupt row must not widen an audience, so this answers empty rather than
/// throwing: the next roster refresh fixes it, and an empty audience sends to
/// nobody rather than to everybody.
List<String> decodeDeviceIds(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return [
      for (final id in decoded)
        if (id is String && id.isNotEmpty) id,
    ];
  } on FormatException {
    return const [];
  }
}
