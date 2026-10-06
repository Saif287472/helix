import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart' hide GroupRole;
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/crypto/peer_directory.dart';
import 'package:helix_remote_engine/src/errors.dart';
import 'package:helix_remote_engine/src/events.dart';
import 'package:helix_remote_engine/src/groups/group_ids.dart';
import 'package:helix_remote_engine/src/groups/group_keyring.dart';
import 'package:helix_remote_engine/src/groups/group_notices.dart';
import 'package:helix_remote_engine/src/groups/group_trust.dart';
import 'package:helix_remote_engine/src/groups/sender_key_store.dart';
import 'package:helix_remote_engine/src/util/keyed_lock.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// What a roster refresh found, for the notices and duties that follow it.
final class RosterUpdate {
  const RosterUpdate({
    required this.group,
    required this.applied,
    required this.previousTitle,
    required this.added,
    required this.removed,
    this.stateRolledBack = false,
  });

  /// The `groups` row after the refresh.
  final GroupRow group;

  /// False when the server's copy was older than the stored epoch and was
  /// ignored (`replaceRoster` refuses a stale roster).
  final bool applied;

  /// The title before the refresh (null for a group new to this device).
  final String? previousTitle;

  /// Members that are new, and members that are gone, since the last roster.
  final Set<String> added;
  final Set<String> removed;

  /// The server offered an older state version than the stored one: the
  /// stored state was kept (a state is never replaced by an older one).
  final bool stateRolledBack;
}

/// The member devices a group send addresses.
final class GroupSendRoster {
  GroupSendRoster({
    required this.groupId,
    required this.members,
    required this.devicesByAccount,
    this.withheld = const {},
  }) : crypto = GroupRoster(
         groupId: groupId,
         members: members.difference(withheld),
         devices: [
           for (final e in devicesByAccount.entries)
             if (!withheld.contains(e.key))
               for (final d in e.value) ?_address(e.key, d),
         ],
       ),
       digest = membersDigest(devicesByAccount);

  final String groupId;

  /// Every member account, this one included.
  final Set<String> members;

  /// Member devices by account, this device left out.
  final Map<String, List<String>> devicesByAccount;

  /// Members this account has not confirmed (see [GroupTrust]): they are
  /// left out of [crypto], so no sender key is handed to them, but they stay
  /// in [digest], which the server checks against everyone it delivers to.
  final Set<String> withheld;

  /// The roster in the form the sender-key protocol takes.
  final GroupRoster crypto;

  /// `membersDigest` the server compares (REST_V2.md, groups).
  final Uint8List digest;

  static DeviceAddress? _address(String account, String device) {
    try {
      return DeviceAddress(account, device);
    } on ArgumentError {
      return null; // A corrupt cache entry must never widen an audience.
    }
  }
}

/// This device's copy of a group's roster, state and per-member device
/// lists, kept consistent with the server's.
///
/// The server is the authority: [refresh] reads `GET /v1/groups/{id}` and
/// replaces the stored roster in one transaction (`replaceRoster` refuses
/// an epoch older than the stored one, so a late answer cannot put a removed
/// member back). Member device lists cannot be read from the group (the
/// route lists accounts only); they come from the server's
/// `device_list_stale` answer to a group send ([adoptStale]), which lists
/// every member device, and they are what the send digest is taken over.
///
/// Everything per group runs under one lock, so a refresh and a stale
/// adoption never interleave.
final class GroupRosterSync {
  GroupRosterSync(
    this._ctx,
    this._keyring,
    this._peers,
    this._senderKeys,
    this._trust,
  ) : _notices = GroupNotices(_ctx);

  final EngineContext _ctx;
  final GroupKeyring _keyring;
  final PeerDirectory _peers;
  final DbSenderKeyStore _senderKeys;
  final GroupTrust _trust;
  final GroupNotices _notices;
  final KeyedLock<String> _locks = KeyedLock();

  HelixDb get _db => _ctx.db;

  // ------------------------------------------------------------ refreshing

  /// The group's row, fetching the group from the server when this device
  /// does not know it yet (a message or key can arrive before the roster
  /// envelope is processed). Null if the server says this account is not a
  /// member. Network trouble throws [TransientEngineException].
  Future<GroupRow?> ensureKnown(String groupId) async {
    final known = await _db.groupsDao.byId(groupId);
    if (known != null) return known;
    final update = await refreshForInbound(groupId);
    return update?.group;
  }

  /// [refresh] for the inbound pipeline: only a network failure is
  /// transient there (it holds the stream back and retries).
  Future<RosterUpdate?> refreshForInbound(String groupId) async {
    try {
      return await refresh(groupId);
    } on NetworkException catch (e) {
      throw TransientEngineException('could not read a group', cause: e);
    } on ApiException catch (e) {
      if (e.isRetryable) {
        throw TransientEngineException('could not read a group', cause: e);
      }
      rethrow;
    }
  }

  /// Reads the group from the server and stores it. Returns null when the
  /// server does not know this account as a member (the group is forgotten
  /// locally).
  Future<RosterUpdate?> refresh(String groupId) =>
      _locks.run(groupId, () async {
        final Group group;
        try {
          group = await _ctx.api.groups.get(groupId);
        } on ApiException catch (e) {
          if (e.code == ErrorCode.notFound) {
            if (await _db.groupsDao.byId(groupId) != null) {
              await _lose(groupId, 'removed');
            }
            return null;
          }
          rethrow;
        }
        return _apply(group);
      });

  /// Stores a group the server returned (create, join). Same rules as
  /// [refresh].
  Future<RosterUpdate?> apply(Group group) =>
      _locks.run(group.groupId, () => _apply(group));

  Future<RosterUpdate?> _apply(Group group) async {
    final self = _ctx.identity.accountId;
    final groupId = group.groupId;
    final existing = await _db.groupsDao.byId(groupId);
    final me = group.members.where((m) => m.account == self).firstOrNull;
    if (me == null) {
      // The server's roster does not list this account: not a member.
      if (existing != null) await _lose(groupId, 'removed');
      return null;
    }
    final previous = {
      for (final m in await _db.groupsDao.members(groupId)) m.accountId: m,
    };
    if (existing != null && group.epoch < existing.epoch) {
      return RosterUpdate(
        group: existing,
        applied: false,
        previousTitle: existing.title,
        added: const {},
        removed: const {},
      );
    }
    // A state is never replaced by an older one: a lower version than the
    // stored one is the server replaying an old blob (CRYPTO_V2.md section 9).
    // The roster still applies; the stored state, title and picture stay.
    final rolledBack =
        existing != null && group.stateVersion < existing.stateVersion;
    final stateBlob = rolledBack ? existing.state : group.encryptedState;
    final stateVersion = rolledBack
        ? existing.stateVersion
        : group.stateVersion;
    final content = stateBlob == null
        ? null
        : await _keyring.openState(
            groupId,
            stateBlob,
            epoch: group.epoch,
            version: stateVersion,
          );
    final title = content?.name ?? existing?.title ?? '';
    final avatar = content == null
        ? existing?.avatar
        : _avatarBytes(content.avatar);
    final oldMeta = await _keyring.meta(groupId);
    final meta = GroupMeta(
      settings: group.settings,
      description: content == null ? oldMeta.description : content.description,
      homeServer: group.homeServer,
      avatar: content == null ? oldMeta.avatar : content.avatar,
    );
    final now = _ctx.now();
    final conversation = GroupIds.conversationId(groupId);
    final rows = [
      for (final m in group.members)
        GroupMemberRow(
          groupId: groupId,
          accountId: m.account,
          qualifiedId: m.account,
          displayName: previous[m.account]?.displayName,
          role: m.role.wire,
          isSelf: m.account == self,
          devicesJson: previous[m.account]?.devicesJson ?? '[]',
          devicesFetchedAt: previous[m.account]?.devicesFetchedAt,
          joinedAt: m.joinedAt,
        ),
    ];
    var applied = false;
    final unconfirmed = <String>[];
    await _db.transaction(() async {
      await _db.groupsDao.upsert(
        GroupsCompanion.insert(
          id: groupId,
          title: title,
          avatar: Value(avatar),
          role: me.role.wire,
          epoch: existing == null ? Value(group.epoch) : const Value.absent(),
          state: rolledBack
              ? const Value.absent()
              : Value(Uint8List.fromList(group.encryptedState)),
          stateVersion: rolledBack
              ? const Value.absent()
              : Value(group.stateVersion),
          createdAt: existing?.createdAt ?? group.createdAt,
        ),
      );
      applied = await _db.groupsDao.replaceRoster(
        groupId,
        rows,
        epoch: group.epoch,
      );
      if (!applied) return;
      await _db.conversationsDao.ensureGroup(
        conversation,
        title: title.isEmpty ? null : title,
        avatar: avatar,
        now: now,
      );
      await _db.conversationsDao.setMembers(conversation, [
        for (final m in group.members)
          if (m.account != self) m.account,
      ]);
      await _keyring.saveMeta(groupId, meta);
      // Members the server added that nothing explains are held back in the
      // same transaction as the roster: no send can run in between.
      if (existing != null && previous.isNotEmpty) {
        for (final m in group.members) {
          if (m.account == self || previous.containsKey(m.account)) continue;
          if (await _trust.takeExplained(groupId, m.account)) continue;
          if (await _trust.isPending(groupId, m.account)) continue;
          unconfirmed.add(m.account);
          await _holdBack(groupId, m.account, PendingReasons.unattributed);
        }
      }
      await _trust.retainOnly(groupId, {
        for (final m in group.members) m.account,
      });
    });
    for (final account in unconfirmed) {
      _ctx.emit(
        GroupMemberUnconfirmed(
          groupId: groupId,
          account: account,
          reason: PendingReasons.unattributed,
        ),
      );
    }
    final stored = (await _db.groupsDao.byId(groupId))!;
    final names = {for (final m in group.members) m.account};
    return RosterUpdate(
      group: stored,
      applied: applied,
      previousTitle: existing?.title,
      added: existing == null
          ? const {}
          : names.difference(previous.keys.toSet()),
      removed: previous.keys.toSet().difference(names),
      stateRolledBack: rolledBack,
    );
  }

  // ------------------------------------------------- server-driven members

  /// Marks [account] as waiting for confirmation and leaves the notice in
  /// the chat. Runs inside the caller's transaction.
  Future<void> _holdBack(String groupId, String account, String reason) async {
    await _trust.addPending(groupId, account, reason);
    await _notices.add(
      groupId: groupId,
      kind: GroupNoticeKinds.memberUnconfirmed,
      members: [account],
      fields: {'reason': reason},
    );
  }

  /// A `roster_change` of kind `added` names [actor] as the one who added
  /// [accounts]. Called before the roster is read (the read finds the new
  /// members and would hold them back otherwise); also fine after it.
  ///
  /// Explained: an actor who may add people (an admin, or any member when
  /// the group allows everyone), who is not one of the added. Everyone else
  /// waits for confirmation: a member joining by themselves through a link
  /// ([PendingReasons.linkJoin], unless `EngineConfig.trustLinkJoins`) or an
  /// addition by someone who may not add ([PendingReasons.unattributed]).
  Future<void> attributeAdded(
    String groupId, {
    required String? actor,
    required Iterable<String> accounts,
    DateTime? at,
  }) => _locks.run(groupId, () async {
    final self = _ctx.identity.accountId;
    if (await _db.groupsDao.byId(groupId) == null) return;
    final may = actor != null && await _mayAdd(groupId, actor);
    final emitted = <(String, String)>[];
    await _db.transaction(() async {
      for (final account in accounts) {
        if (account == self) continue;
        final known = await _db.groupsDao.member(groupId, account) != null;
        final waiting = await _trust.isPending(groupId, account);
        if (known && !waiting) continue; // Accepted before.
        final selfJoin = actor == account;
        if (selfJoin ? _ctx.config.trustLinkJoins : may) {
          await _trust.explain(groupId, [account]);
          continue;
        }
        final reason = selfJoin
            ? PendingReasons.linkJoin
            : PendingReasons.unattributed;
        if (waiting) {
          await _trust.addPending(groupId, account, reason); // relabel
        } else {
          await _holdBack(groupId, account, reason);
          emitted.add((account, reason));
        }
      }
    });
    for (final (account, reason) in emitted) {
      _ctx.emit(
        GroupMemberUnconfirmed(
          groupId: groupId,
          account: account,
          reason: reason,
        ),
      );
    }
  });

  Future<bool> _mayAdd(String groupId, String actor) async {
    final member = await _db.groupsDao.member(groupId, actor);
    if (member == null) return false;
    if (member.role == GroupRole.owner.wire ||
        member.role == GroupRole.admin.wire) {
      return true;
    }
    return (await _keyring.meta(groupId)).settings.addMembers ==
        GroupPermission.everyone;
  }

  /// This account added [accounts] itself (or approved their request): they
  /// are explained.
  Future<void> explainOwnAdds(String groupId, Iterable<String> accounts) =>
      _trust.explain(groupId, accounts);

  /// Re-reads the stored state blob with the keys held now (a group key
  /// just arrived): name, picture and description appear without a network
  /// round trip. Runs inside the caller's transaction when there is one.
  Future<void> reopenState(String groupId) async {
    final group = await _db.groupsDao.byId(groupId);
    final blob = group?.state;
    if (group == null || blob == null) return;
    final content = await _keyring.openState(
      groupId,
      blob,
      epoch: group.epoch,
      version: group.stateVersion,
    );
    if (content == null) return;
    final avatar = _avatarBytes(content.avatar);
    await _db.groupsDao.upsert(
      GroupsCompanion.insert(
        id: groupId,
        title: content.name,
        avatar: Value(avatar),
        role: group.role,
        createdAt: group.createdAt,
      ),
    );
    await _db.conversationsDao.ensureGroup(
      GroupIds.conversationId(groupId),
      title: content.name.isEmpty ? null : content.name,
      avatar: avatar,
      now: _ctx.now(),
    );
    final meta = await _keyring.meta(groupId);
    await _keyring.saveMeta(
      groupId,
      GroupMeta(
        settings: meta.settings,
        description: content.description,
        homeServer: meta.homeServer,
        avatar: content.avatar,
      ),
    );
  }

  /// The group picture's pointer as the bytes kept in `groups.avatar` and
  /// `conversations.avatar`: its JSON, until the transfer queue (C4-M) and
  /// the app resolve it to an image.
  static Uint8List? _avatarBytes(JsonMap? pointer) => pointer == null
      ? null
      : Uint8List.fromList(utf8.encode(jsonEncode(pointer)));

  // ---------------------------------------------------------- forgetting

  /// This device is no longer in [groupId] (removed, left, deleted): the
  /// roster, keys and group row go, the chat stays as history. [notice] is
  /// the system row to leave in it, with [actor] and the roster envelope's
  /// [at] time.
  Future<void> lose(
    String groupId,
    String reason, {
    String? actor,
    String? noticeId,
    DateTime? at,
  }) => _locks.run(
    groupId,
    () => _lose(groupId, reason, actor: actor, noticeId: noticeId, at: at),
  );

  Future<void> _lose(
    String groupId,
    String reason, {
    String? actor,
    String? noticeId,
    DateTime? at,
  }) async {
    final existed = await _db.groupsDao.byId(groupId) != null;
    await _db.transaction(() async {
      await _db.groupsDao.forget(groupId);
      await _senderKeys.forgetGroup(groupId);
      await _keyring.forget(groupId);
      await _trust.forget(groupId);
      final conversation = GroupIds.conversationId(groupId);
      if (await _db.conversationsDao.byId(conversation) != null) {
        await _db.conversationsDao.setMembers(conversation, const []);
        await _notices.add(
          groupId: groupId,
          kind: switch (reason) {
            'left' => GroupNoticeKinds.youLeft,
            'deleted' => GroupNoticeKinds.deleted,
            _ => GroupNoticeKinds.youWereRemoved,
          },
          actor: actor,
          messageId: noticeId,
          at: at,
        );
      }
    });
    if (existed) {
      _ctx.emit(GroupMembershipLost(groupId: groupId, reason: reason));
    }
  }

  // ------------------------------------------------------- sending roster

  /// The audience of a group send from the stored roster, or null when this
  /// device is not in the group.
  Future<GroupSendRoster?> rosterForSend(String groupId) async {
    if (await _db.groupsDao.byId(groupId) == null) return null;
    final own = _ctx.identity.deviceId;
    final rows = await _db.groupsDao.members(groupId);
    final waiting = await _trust.pending(groupId);
    return GroupSendRoster(
      groupId: groupId,
      withheld: waiting.keys.toSet(),
      members: {for (final r in rows) r.accountId},
      devicesByAccount: {
        for (final r in rows)
          r.accountId: [
            for (final d in decodeDeviceIds(r.devicesJson))
              if (d != own) d,
          ],
      },
    );
  }

  /// Takes the device lists of a `device_list_stale` answer: the server
  /// lists every member device. A different set of accounts means the
  /// roster changed too, so the group is read again first. Devices that are
  /// gone lose their cached keys and sessions.
  Future<void> adoptStale(String groupId, StaleDevices stale) async {
    final lists = {for (final a in stale.accounts) a.account: a.missing};
    final cached = {
      for (final m in await _db.groupsDao.members(groupId)) m.accountId,
    };
    if (!_sameSet(cached, lists.keys.toSet())) {
      await refresh(groupId);
    }
    await _locks.run(groupId, () async {
      final own = _ctx.identity.deviceId;
      final now = _ctx.now();
      final gone = <DeviceAddress>[];
      await _db.transaction(() async {
        for (final entry in lists.entries) {
          final row = await _db.groupsDao.member(groupId, entry.key);
          if (row == null) continue;
          final fresh = [
            for (final d in entry.value)
              if (d != own) d,
          ];
          for (final old in decodeDeviceIds(row.devicesJson)) {
            if (old != own && !fresh.contains(old)) {
              try {
                gone.add(DeviceAddress(entry.key, old));
              } on ArgumentError {
                // Not a valid address; nothing cached for it.
              }
            }
          }
          await _db.groupsDao.saveMemberDevices(
            groupId,
            entry.key,
            deviceIds: fresh,
            now: now,
          );
        }
      });
      for (final device in gone) {
        await _peers.dropDevice(device.account, device.device);
      }
    });
  }

  /// Removes devices the server no longer returns keys for from the cached
  /// roster (they were revoked between the stale answer and the key fetch).
  Future<void> dropDevices(String groupId, Iterable<DeviceAddress> devices) =>
      _locks.run(groupId, () async {
        final byAccount = <String, Set<String>>{};
        for (final d in devices) {
          (byAccount[d.account] ??= {}).add(d.device);
        }
        final now = _ctx.now();
        for (final entry in byAccount.entries) {
          final row = await _db.groupsDao.member(groupId, entry.key);
          if (row == null) continue;
          await _db.groupsDao.saveMemberDevices(
            groupId,
            entry.key,
            deviceIds: [
              for (final d in decodeDeviceIds(row.devicesJson))
                if (!entry.value.contains(d)) d,
            ],
            now: now,
          );
        }
        for (final d in devices) {
          await _peers.dropDevice(d.account, d.device);
        }
      });

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
}
