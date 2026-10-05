import 'dart:convert';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart' hide GroupRole;
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/errors.dart';
import 'package:helix_remote_engine/src/groups/group_ids.dart';
import 'package:helix_remote_engine/src/groups/group_invite_links.dart';
import 'package:helix_remote_engine/src/groups/group_keyring.dart';
import 'package:helix_remote_engine/src/groups/group_rekey.dart';
import 'package:helix_remote_engine/src/groups/group_roster.dart';
import 'package:helix_remote_engine/src/groups/group_trust.dart';
import 'package:helix_remote_engine/src/groups/sender_key_store.dart';
import 'package:helix_remote_engine/src/messaging/outbox.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// A group as the UI shows it: the row, the roster and what only members can
/// read.
final class GroupDetails {
  const GroupDetails({
    required this.group,
    required this.members,
    required this.meta,
  });

  final GroupRow group;

  /// The roster with roles (`GroupMemberRow.role` is a [GroupRole] wire
  /// name) and the member devices this device knows of.
  final List<GroupMemberRow> members;

  /// Settings, description and picture pointer.
  final GroupMeta meta;

  String get id => group.id;

  /// The group's name; empty until the group key has reached this device.
  String get title => group.title;

  /// This account's role.
  GroupRole get role => GroupRole.values.firstWhere(
    (r) => r.wire == group.role,
    orElse: () => GroupRole.member,
  );

  bool get canAdminister => role.canAdminister;

  /// Whether this account may add people (the group's setting, or an admin).
  bool get canAddMembers =>
      canAdminister || meta.settings.addMembers == GroupPermission.everyone;

  bool get canEditInfo =>
      canAdminister || meta.settings.editInfo == GroupPermission.everyone;

  bool get canSend =>
      canAdminister || meta.settings.sendMessages == GroupPermission.everyone;

  GroupSettings get settings => meta.settings;
}

/// The result of creating a group.
final class CreatedGroup {
  const CreatedGroup({required this.conversation, required this.rejected});

  /// The group chat.
  final ConversationRow conversation;

  /// People asked for who are not in the group (their privacy settings do
  /// not allow being added, or they do not exist): send them an invite link.
  final List<String> rejected;

  String get groupId => GroupIds.groupIdOf(conversation.id);
}

/// A link to share, made by [GroupsService.createInviteLink].
final class GroupInviteLink {
  const GroupInviteLink({
    required this.linkId,
    required this.link,
    required this.requiresApproval,
    this.expiresAt,
  });

  /// For revoking it.
  final String linkId;

  /// The URL to share (`https://<server>/open#HLX-GRP-…`).
  final String link;
  final bool requiresApproval;
  final DateTime? expiresAt;

  @override
  String toString() => 'GroupInviteLink($linkId, <redacted>)';
}

/// What an invite link shows before joining.
final class GroupInvitePreview {
  const GroupInvitePreview({
    required this.groupId,
    required this.memberCount,
    required this.requiresApproval,
    required this.name,
    this.description,
    this.avatar,
  });

  final String groupId;
  final int memberCount;
  final bool requiresApproval;
  final String name;
  final String? description;

  /// The picture's `MediaPointer` JSON.
  final JsonMap? avatar;
}

/// The result of joining through a link: [JoinStatus.joined], or
/// [JoinStatus.pending] when an admin has to approve.
final class JoinResult {
  const JoinResult({required this.groupId, required this.status});

  final String groupId;
  final JoinStatus status;

  bool get joined => status == JoinStatus.joined;
}

/// Groups end to end (Phase C4-G): create, rename, picture, settings,
/// members, roles, leaving, bans, invite links and join requests, kept
/// consistent with the server's roster in `groups`, `group_members` and
/// `group_bans`.
///
/// Every call talks to the server first and updates the local copy from the
/// answer (`GroupRosterSync`). The group's name, description and picture are
/// an encrypted state blob sealed with the group master key (CRYPTO_V2.md
/// §9); changing it is an optimistic write that retries on
/// `version_conflict`. Messages in a group are sent with
/// `ChatsService` on the chat `group:<id>`.
///
/// **Chat list.** The group chat is a row in `conversations` (title,
/// avatar, members, summary, unread and mention counts); the `groups`
/// table's own summary columns stay unused, so the chat list reads one
/// table (`ChatsService.watchChats`). A chat whose `groups` row is gone is a
/// group this account left or was removed from: history only.
///
/// **Keys.** Whoever adds a member hands them the group key, and a removal
/// rotates it (`GroupKeyDistributor`); sender keys for messages rotate on
/// their own (CRYPTO_V2.md §7).
final class GroupsService {
  GroupsService(
    this._ctx,
    this._roster,
    this._keyring,
    this._keys,
    this._senderKeys,
    this._outbox,
    this._trust,
  );

  final EngineContext _ctx;
  final GroupRosterSync _roster;
  final GroupKeyring _keyring;
  final GroupKeyDistributor _keys;
  final DbSenderKeyStore _senderKeys;
  final OutboxService _outbox;
  final GroupTrust _trust;

  HelixDb get _db => _ctx.db;

  // ------------------------------------------------- unconfirmed members

  /// Members the server's roster gained that no admin's action explains, by
  /// account, with the reason (`unattributed` or `link_join`). This device
  /// hands them neither its sender key nor the group key until
  /// [confirmMember]; everything sent here stays unreadable to them.
  Future<Map<String, String>> pendingMembers(String groupId) =>
      _trust.pending(groupId);

  Stream<Map<String, String>> watchPendingMembers(String groupId) =>
      _trust.watchPending(groupId);

  /// The user accepts [account]: from the next message on it gets this
  /// device's sender key, and it gets the group key now. Returns false when
  /// [account] was not waiting. (Removing a member the user does not know is
  /// `removeMember`, for admins.)
  Future<bool> confirmMember(String groupId, String account) async {
    await _require(groupId);
    final confirmed = await _trust.confirm(groupId, account);
    if (confirmed) {
      // Confirmed before the roster read that lists them has run: that read
      // must not hold them back again.
      if (await _db.groupsDao.member(groupId, account) == null) {
        await _trust.explain(groupId, [account]);
      }
      await _keys.share(groupId, [account]);
    }
    return confirmed;
  }

  // -------------------------------------------------------------- reading

  /// Every group this account is in, newest activity first.
  Stream<List<GroupRow>> watchGroups({bool archived = false}) =>
      _db.groupsDao.watchAll(archived: archived);

  Stream<GroupRow?> watchGroup(String groupId) => _db.groupsDao.watch(groupId);

  /// The roster of [groupId], live.
  Stream<List<GroupMemberRow>> watchMembers(String groupId) =>
      _db.groupsDao.watchMembers(groupId);

  /// The group's details, or null when this account is not in it.
  Future<GroupDetails?> details(String groupId) async {
    final group = await _db.groupsDao.byId(groupId);
    if (group == null) return null;
    return GroupDetails(
      group: group,
      members: await _db.groupsDao.members(groupId),
      meta: await _keyring.meta(groupId),
    );
  }

  /// This account's role, or null when it is not in the group.
  Future<GroupRole?> role(String groupId) async {
    final row = await _db.groupsDao.selfMembership(groupId);
    if (row == null) return null;
    return GroupRole.values.firstWhere(
      (r) => r.wire == row.role,
      orElse: () => GroupRole.member,
    );
  }

  /// Accounts banned from the group *by this account*. The server has no
  /// ban list to read, so bans made on other devices are not known here.
  Future<List<GroupBanRow>> bans(String groupId) => _db.groupsDao.bans(groupId);

  // ------------------------------------------------------------ lifecycle

  /// Makes a group named [name] with [members] besides this account, who
  /// becomes the owner. Returns the group chat; people whose privacy
  /// settings keep them out are in [CreatedGroup.rejected].
  Future<CreatedGroup> create({
    required String name,
    Iterable<String> members = const [],
    String? description,
    JsonMap? avatar,
    GroupSettings settings = const GroupSettings(),
  }) async {
    final title = _validName(name);
    final self = _ctx.identity.accountId;
    final groupId = _ctx.ids.next();
    final key = newSymmetricKey(_ctx.random);
    final state = GroupStateContent(
      name: title,
      description: description,
      avatar: avatar,
    );
    // The first epoch is 0 (the server starts there and a removal bumps it).
    final sealed = await _keyring.sealState(
      groupId,
      0,
      GroupLimits.initialStateVersion,
      key,
      state,
    );
    await _keyring.put(groupId, 0, key);
    final wanted = members.where((m) => m != self).toSet().toList();
    final Group created;
    try {
      created = await _ctx.api.groups.create(
        CreateGroupRequest(
          groupId: groupId,
          encryptedState: sealed,
          members: wanted,
          settings: settings,
        ),
      );
    } on Object {
      await _keyring.forget(groupId);
      rethrow;
    }
    await _roster.apply(created);
    final inGroup = {for (final m in created.members) m.account};
    // Everyone in the group (and this account's other devices) needs the key
    // to read the name.
    await _keys.share(groupId, inGroup, epoch: 0);
    final conversation = (await _db.conversationsDao.byId(
      GroupIds.conversationId(groupId),
    ))!;
    return CreatedGroup(
      conversation: conversation,
      rejected: [
        for (final m in wanted)
          if (!inGroup.contains(m)) m,
      ],
    );
  }

  Future<void> rename(String groupId, String name) {
    final title = _validName(name);
    return _updateState(
      groupId,
      (s) => GroupStateContent(
        name: title,
        description: s.description,
        avatar: s.avatar,
      ),
    );
  }

  /// Sets or clears (null or empty) the group's description.
  Future<void> setDescription(String groupId, String? description) =>
      _updateState(
        groupId,
        (s) => GroupStateContent(
          name: s.name,
          description: description == null || description.trim().isEmpty
              ? null
              : description,
          avatar: s.avatar,
        ),
      );

  /// Sets or clears the group picture, a `MediaPointer` JSON to an uploaded
  /// image (the transfer queue uploads it first).
  Future<void> setAvatar(String groupId, JsonMap? avatar) => _updateState(
    groupId,
    (s) => GroupStateContent(
      name: s.name,
      description: s.description,
      avatar: avatar,
    ),
  );

  /// Who may add members, edit the group info and send messages (admins
  /// change it).
  Future<void> setSettings(String groupId, GroupSettings settings) async {
    await _requireAdmin(groupId);
    await _ctx.api.groups.setSettings(groupId, settings);
    await _roster.refresh(groupId);
  }

  /// Adds [accounts]. Those whose privacy settings do not allow it come
  /// back in `rejected`; they can be invited with a link instead. The new
  /// members get the group key.
  Future<AddMembersResponse> addMembers(
    String groupId,
    Iterable<String> accounts,
  ) async {
    final details = await _require(groupId);
    if (!details.canAddMembers) {
      throw const GroupException(GroupFailure.notAllowed);
    }
    final result = await _ctx.api.groups.addMembers(
      groupId,
      accounts.toSet().toList(),
    );
    // Added by this account: explained, not "added by the server roster".
    await _roster.explainOwnAdds(groupId, result.added);
    final update = await _roster.refresh(groupId);
    if (update != null && result.added.isNotEmpty) {
      await _keys.share(groupId, result.added, epoch: update.group.epoch);
    }
    return result;
  }

  /// Removes [account] (an admin's action). Removing this account is
  /// leaving. The epoch changes: the group key is rotated so the removed
  /// member cannot read what is written after, and every member's sender
  /// key rotates with their next message (CRYPTO_V2.md §7).
  Future<void> removeMember(String groupId, String account) async {
    if (account == _ctx.identity.accountId) return leave(groupId);
    await _requireAdmin(groupId);
    await _ctx.api.groups.removeMember(groupId, account);
    await _afterRemoval(groupId, account);
  }

  /// Leaves the group. The chat stays as history.
  Future<void> leave(String groupId) async {
    await _require(groupId);
    await _ctx.api.groups.removeMember(groupId, _ctx.identity.accountId);
    await _roster.lose(groupId, 'left');
  }

  /// Makes [account] an admin or a member; only the owner passes ownership
  /// on (the previous owner becomes an admin).
  Future<void> setRole(String groupId, String account, GroupRole role) async {
    await _requireAdmin(groupId);
    await _ctx.api.groups.setRole(groupId, account, role);
    await _roster.refresh(groupId);
  }

  /// Removes [account] and keeps it from joining again through a link.
  Future<void> ban(String groupId, String account) async {
    await _requireAdmin(groupId);
    final wasMember = await _db.groupsDao.member(groupId, account) != null;
    await _ctx.api.groups.ban(groupId, account);
    await _db.groupsDao.addBan(groupId, account, now: _ctx.now());
    if (wasMember) await _afterRemoval(groupId, account);
  }

  Future<void> unban(String groupId, String account) async {
    await _requireAdmin(groupId);
    await _ctx.api.groups.unban(groupId, account);
    await _db.groupsDao.removeBan(groupId, account);
  }

  /// Deletes the group for everyone (the owner's action).
  Future<void> deleteGroup(String groupId) async {
    final details = await _require(groupId);
    if (details.role != GroupRole.owner) {
      throw const GroupException(GroupFailure.notAllowed);
    }
    await _ctx.api.groups.delete(groupId);
    await _roster.lose(groupId, 'deleted');
  }

  /// Hands the group key of the current epoch to [accounts] again (a member
  /// reports that the name does not show; the key normally goes with adding
  /// someone). Returns false when this device does not hold the key.
  Future<bool> shareKey(String groupId, Iterable<String> accounts) async {
    await _require(groupId);
    return _keys.share(groupId, accounts);
  }

  /// Rotates the group master key now (an admin's action; a removal does it
  /// by itself).
  Future<void> rotateKey(String groupId) async {
    await _requireAdmin(groupId);
    await _outbox.enqueueRekey(groupId);
  }

  // ------------------------------------------------------------ invites

  /// Makes an invite link. With [requiresApproval] joining only asks, and
  /// an admin has to approve ([approveJoinRequest]).
  Future<GroupInviteLink> createInviteLink(
    String groupId, {
    bool requiresApproval = false,
    DateTime? expiresAt,
  }) async {
    final details = await _require(groupId);
    if (!details.canAdminister) {
      throw const GroupException(GroupFailure.notAllowed);
    }
    final previewKey = newSymmetricKey(_ctx.random);
    final preview = jsonEncode(
      GroupStateContent(
        name: details.title,
        description: details.meta.description,
        avatar: details.meta.avatar,
      ).toJson(),
    );
    // The preview is sealed with the link's own random key, bound to the
    // group (epoch and version 0 in the AAD: a preview carries neither).
    final sealed = await SealedBlobCipher.groupState.seal(
      secret: previewKey,
      plaintext: utf8.encode(preview),
      aad: SealedBlobCipher.groupStateAad(groupId, 0, 0),
      random: _ctx.random,
    );
    final link = await _ctx.api.groups.createInviteLink(
      groupId,
      CreateInviteLinkRequest(
        encryptedPreview: sealed,
        requiresApproval: requiresApproval,
        expiresAt: expiresAt,
      ),
    );
    return GroupInviteLink(
      linkId: link.linkId,
      link: GroupInviteLinks.encode(
        _ctx.api.transport.baseUrl.origin,
        link.token,
        previewKey,
      ),
      requiresApproval: link.requiresApproval,
      expiresAt: link.expiresAt,
    );
  }

  Future<void> revokeInviteLink(String groupId, String linkId) async {
    await _requireAdmin(groupId);
    await _ctx.api.groups.revokeInviteLink(groupId, linkId);
  }

  /// What a link leads to: the member count and, when the link's key opens
  /// it, the group's name, description and picture.
  Future<GroupInvitePreview> previewInvite(String link) async {
    final parsed = _parse(link);
    final preview = await _ctx.api.groups.previewInviteLink(parsed.token);
    GroupStateContent? content;
    try {
      final plain = await SealedBlobCipher.groupState.open(
        secret: parsed.previewKey,
        blob: preview.encryptedPreview,
        aad: SealedBlobCipher.groupStateAad(preview.groupId, 0, 0),
      );
      content = GroupStateContent.fromJson(
        JsonReader.decode(utf8.decode(plain)),
      );
    } on CryptoV2Exception {
      content = null;
    } on FormatException {
      content = null;
    }
    return GroupInvitePreview(
      groupId: preview.groupId,
      memberCount: preview.memberCount,
      requiresApproval: preview.requiresApproval,
      name: content?.name ?? '',
      description: content?.description,
      avatar: content?.avatar,
    );
  }

  /// Joins through [link]. Banned accounts are refused by the server. With
  /// an approval link the result is [JoinStatus.pending].
  Future<JoinResult> joinWithLink(String link) async {
    final parsed = _parse(link);
    final result = await _ctx.api.groups.join(parsed.token);
    if (result.status == JoinStatus.joined) {
      await _roster.refresh(result.groupId);
    }
    return JoinResult(groupId: result.groupId, status: result.status);
  }

  /// The people waiting for approval (admins).
  Future<List<JoinRequest>> joinRequests(String groupId) async {
    await _requireAdmin(groupId);
    return (await _ctx.api.groups.joinRequests(groupId)).requests;
  }

  /// Lets a join request in; the new member gets the group key.
  Future<void> approveJoinRequest(String groupId, String requestId) async {
    await _requireAdmin(groupId);
    final account = (await _ctx.api.groups.joinRequests(
      groupId,
    )).requests.where((r) => r.requestId == requestId).firstOrNull?.account;
    await _ctx.api.groups.resolveJoinRequest(groupId, requestId, approve: true);
    if (account != null) await _roster.explainOwnAdds(groupId, [account]);
    final update = await _roster.refresh(groupId);
    if (account != null && update != null) {
      await _keys.share(groupId, [account], epoch: update.group.epoch);
    }
  }

  Future<void> rejectJoinRequest(String groupId, String requestId) async {
    await _requireAdmin(groupId);
    await _ctx.api.groups.resolveJoinRequest(
      groupId,
      requestId,
      approve: false,
    );
  }

  // ----------------------------------------------------------------- sync

  /// Reads one group from the server (roster, state, settings).
  Future<void> refresh(String groupId) async {
    await _roster.refresh(groupId);
  }

  /// Reads every group this account is in from the server and forgets the
  /// ones it is no longer in. A freshly linked or signed-in device calls
  /// this once; afterwards `roster_change` envelopes keep it current.
  Future<void> refreshAll() async {
    final list = await _ctx.api.groups.list();
    final listed = {for (final g in list.groups) g.groupId};
    for (final id in listed) {
      try {
        await _roster.refresh(id);
      } on ApiException {
        // One group failing must not hide the others; it is read again at
        // the next refresh or roster envelope.
      }
    }
    for (final archived in [false, true]) {
      for (final group in await _db.groupsDao.all(archived: archived)) {
        if (!listed.contains(group.id)) {
          await _roster.lose(group.id, 'removed');
        }
      }
    }
  }

  // ------------------------------------------------------------ internals

  Future<void> _afterRemoval(String groupId, String account) async {
    await _roster.refresh(groupId);
    await _senderKeys.forgetMember(groupId, account);
    // The server bumped the epoch: the group key changes with it.
    await _outbox.enqueueRekey(groupId);
  }

  Future<GroupDetails> _require(String groupId) async {
    final details = await this.details(groupId);
    if (details == null) throw const GroupException(GroupFailure.notAMember);
    return details;
  }

  Future<GroupDetails> _requireAdmin(String groupId) async {
    final details = await _require(groupId);
    if (!details.canAdminister) {
      throw const GroupException(GroupFailure.notAllowed);
    }
    return details;
  }

  ({String token, List<int> previewKey}) _parse(String link) {
    final parsed = GroupInviteLinks.parse(link);
    if (parsed == null) throw const GroupException(GroupFailure.badLink);
    return parsed;
  }

  String _validName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > GroupStateContent.maxNameLength) {
      throw ArgumentError.value(name, 'name', 'must be 1-100 characters');
    }
    return trimmed;
  }

  /// Writes a new state (optimistic: `expected_version`). On
  /// `version_conflict` the group is read again and the change is made on
  /// top of the newer state.
  Future<void> _updateState(
    String groupId,
    GroupStateContent Function(GroupStateContent current) change,
  ) async {
    for (var attempt = 0; attempt < GroupLimits.stateRetries; attempt++) {
      final details = await _require(groupId);
      if (!details.canEditInfo) {
        throw const GroupException(GroupFailure.notAllowed);
      }
      final group = details.group;
      final key = await _keyring.keyFor(groupId, group.epoch);
      if (key == null) throw const GroupException(GroupFailure.noGroupKey);
      final blob = group.state;
      final current =
          (blob == null
              ? null
              : await _keyring.openState(
                  groupId,
                  blob,
                  epoch: group.epoch,
                  version: group.stateVersion,
                )) ??
          GroupStateContent(name: group.title);
      // A write over version v becomes v + 1, and the blob is sealed for it.
      final next = group.stateVersion + 1;
      final sealed = await _keyring.sealState(
        groupId,
        group.epoch,
        next,
        key,
        change(current),
      );
      try {
        final result = await _ctx.api.groups.setState(
          groupId,
          SetGroupStateRequest(
            encryptedState: sealed,
            expectedVersion: group.stateVersion,
          ),
        );
        if (result.stateVersion != next) {
          // The server numbered the write differently: nobody could open
          // the blob. Read the group again and retry on top of it.
          await _roster.refresh(groupId);
          continue;
        }
        await _db.groupsDao.saveState(
          groupId,
          state: sealed,
          version: result.stateVersion,
        );
        await _roster.reopenState(groupId);
        return;
      } on ApiException catch (e) {
        if (e.code != ErrorCode.versionConflict) rethrow;
        await _roster.refresh(groupId);
      }
    }
    throw const GroupException(GroupFailure.versionConflict);
  }
}
