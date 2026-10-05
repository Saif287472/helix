import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/platform/phone_numbers.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote/features/groups/application/group_picture.dart';
import 'package:helix_remote_db/helix_remote_db.dart' show PersonRow;
import 'package:helix_remote_engine/helix_remote_engine.dart' as engine;
import 'package:helix_remote_protocol/helix_remote_protocol.dart' as wire;

/// The engine's groups service as the group screens use it.
///
/// An interface so every screen's flow, and the errors it shows, run in widget
/// tests against a fake; [EngineGroupsPort] is the real thing. Everything here
/// talks to the server first and updates the local copy from the answer, so a
/// call that throws changed nothing locally.
abstract interface class GroupsPort {
  /// The group and its roster, live; null once this account is no longer in it.
  Stream<GroupSnapshot?> watch(String groupId);

  /// People this device knows, for the member pickers (live).
  Stream<List<GroupCandidate>> watchCandidates();

  /// Finds somebody by phone number or `~Helix name` who this device does not
  /// know yet; null when there is no such account.
  Future<GroupCandidate?> lookup(String query);

  Future<CreatedGroupInfo> create({
    required String name,
    required Iterable<String> members,
    String? description,
    Uint8List? picture,
  });

  Future<void> rename(String groupId, String name);
  Future<void> setDescription(String groupId, String? description);

  /// Uploads [picture] (already scaled) and sets it as the group's picture;
  /// null removes the picture.
  Future<void> setPicture(String groupId, Uint8List? picture);
  Future<void> setPermissions(String groupId, GroupPermissions permissions);
  Future<void> setDisappearing(String groupId, int? seconds);

  Future<AddMembersOutcome> addMembers(
    String groupId,
    Iterable<String> accounts,
  );
  Future<void> removeMember(String groupId, String account);
  Future<void> leave(String groupId);
  Future<void> setRole(String groupId, String account, GroupMemberRole role);
  Future<void> ban(String groupId, String account);
  Future<void> unban(String groupId, String account);
  Future<void> deleteGroup(String groupId);

  /// Accounts this device banned (the server keeps no ban list to read).
  Future<List<BannedInfo>> bans(String groupId);

  Future<InviteLinkInfo> createInviteLink(
    String groupId, {
    required bool requiresApproval,
    DateTime? expiresAt,
  });
  Future<void> revokeInviteLink(String groupId, String linkId);

  Future<InvitePreviewInfo> previewInvite(String link);
  Future<JoinResultInfo> joinWithLink(String link);

  Future<List<JoinRequestInfo>> joinRequests(String groupId);
  Future<void> approveJoinRequest(String groupId, String requestId);
  Future<void> rejectJoinRequest(String groupId, String requestId);

  /// Reads the group from the server again.
  Future<void> refresh(String groupId);

  /// Things that happen to [groupId] that a screen reacts to.
  Stream<GroupSignal> signals(String groupId);
}

/// [GroupsPort] over the engine.
final class EngineGroupsPort implements GroupsPort {
  EngineGroupsPort(this._engine, this._pictures, this._country);

  final engine.Engine _engine;
  final GroupPictureStore _pictures;
  final PhoneCountry _country;

  engine.GroupsService get _groups => _engine.groups;

  @override
  Stream<GroupSnapshot?> watch(String groupId) {
    final conversation = engine.GroupIds.conversationId(groupId);
    late final StreamController<GroupSnapshot?> out;
    final subs = <StreamSubscription<Object?>>[];
    int? disappearing;
    var running = false;
    var dirty = false;
    var closed = false;

    Future<void> recompute() async {
      if (running) {
        dirty = true;
        return;
      }
      running = true;
      try {
        do {
          dirty = false;
          final details = await _groups.details(groupId);
          if (closed) return;
          out.add(details == null ? null : _snapshotOf(details, disappearing));
        } while (dirty && !closed);
      } on Object catch (error, stack) {
        if (!closed) out.addError(error, stack);
      } finally {
        running = false;
      }
    }

    out = StreamController<GroupSnapshot?>(
      onListen: () {
        subs
          ..add(
            _groups.watchGroup(groupId).listen((_) => unawaited(recompute())),
          )
          ..add(
            _groups.watchMembers(groupId).listen((_) => unawaited(recompute())),
          )
          ..add(
            _engine.chats.watchChat(conversation).listen((chat) {
              disappearing = chat?.disappearingSeconds;
              unawaited(recompute());
            }),
          );
      },
      onCancel: () async {
        closed = true;
        for (final sub in subs) {
          await sub.cancel();
        }
      },
    );
    return out.stream;
  }

  static GroupSnapshot _snapshotOf(
    engine.GroupDetails details,
    int? disappearing,
  ) {
    final settings = details.settings;
    GroupWho who(wire.GroupPermission p) => p == wire.GroupPermission.everyone
        ? GroupWho.everyone
        : GroupWho.admins;
    return GroupSnapshot(
      id: details.id,
      title: details.title,
      description: details.meta.description,
      avatarPointer: details.meta.avatar,
      selfRole: _roleOf(details.role),
      members: [
        for (final m in details.members)
          GroupMemberInfo(
            account: m.accountId,
            role: _roleOfWire(m.role),
            isSelf: m.isSelf,
            nameHint: m.displayName,
          ),
      ],
      permissions: GroupPermissions(
        addMembers: who(settings.addMembers),
        editInfo: who(settings.editInfo),
        sendMessages: who(settings.sendMessages),
      ),
      disappearingSeconds: disappearing,
      homeServer: details.meta.homeServer,
    );
  }

  static GroupMemberRole _roleOf(wire.GroupRole role) => switch (role) {
    wire.GroupRole.owner => GroupMemberRole.owner,
    wire.GroupRole.admin => GroupMemberRole.admin,
    wire.GroupRole.member => GroupMemberRole.member,
  };

  static GroupMemberRole _roleOfWire(String role) => switch (role) {
    'owner' => GroupMemberRole.owner,
    'admin' => GroupMemberRole.admin,
    _ => GroupMemberRole.member,
  };

  static wire.GroupRole _toWire(GroupMemberRole role) => switch (role) {
    GroupMemberRole.owner => wire.GroupRole.owner,
    GroupMemberRole.admin => wire.GroupRole.admin,
    GroupMemberRole.member => wire.GroupRole.member,
  };

  static wire.GroupPermission _permission(GroupWho who) =>
      who == GroupWho.everyone
      ? wire.GroupPermission.everyone
      : wire.GroupPermission.admins;

  @override
  Stream<List<GroupCandidate>> watchCandidates() =>
      _engine.people.watchAll().map(
        (rows) => [
          for (final row in rows)
            GroupCandidate(
              account: row.accountId,
              names: PersonName.fromRow(row).tileNames,
              blocked: row.blocked,
            ),
        ],
      );

  @override
  Future<GroupCandidate?> lookup(String query) async {
    final text = query.trim();
    if (text.isEmpty) return null;
    final PersonRow? row;
    if (text.startsWith('~')) {
      row = await _engine.people.findByHelixName(text.substring(1));
    } else {
      final number = PhoneNumbers.normalize(
        text,
        defaultCallingCode: _country.callingCode,
        guessNational: true,
      );
      row = number == null ? null : await _engine.people.findByNumber(number);
    }
    if (row == null) return null;
    return GroupCandidate(
      account: row.accountId,
      names: PersonName.fromRow(row).tileNames,
      blocked: row.blocked,
    );
  }

  @override
  Future<CreatedGroupInfo> create({
    required String name,
    required Iterable<String> members,
    String? description,
    Uint8List? picture,
  }) async {
    final avatar = picture == null ? null : await _pictures.upload(picture);
    final created = await _groups.create(
      name: name,
      members: members,
      description: description,
      avatar: avatar,
    );
    return CreatedGroupInfo(
      groupId: created.groupId,
      conversationId: created.conversation.id,
      rejected: created.rejected,
    );
  }

  @override
  Future<void> rename(String groupId, String name) =>
      _groups.rename(groupId, name);

  @override
  Future<void> setDescription(String groupId, String? description) =>
      _groups.setDescription(groupId, description);

  @override
  Future<void> setPicture(String groupId, Uint8List? picture) async {
    final pointer = picture == null ? null : await _pictures.upload(picture);
    await _groups.setAvatar(groupId, pointer);
  }

  @override
  Future<void> setPermissions(String groupId, GroupPermissions permissions) =>
      _groups.setSettings(
        groupId,
        wire.GroupSettings(
          addMembers: _permission(permissions.addMembers),
          editInfo: _permission(permissions.editInfo),
          sendMessages: _permission(permissions.sendMessages),
        ),
      );

  @override
  Future<void> setDisappearing(String groupId, int? seconds) => _engine.chats
      .setDisappearing(engine.GroupIds.conversationId(groupId), seconds);

  @override
  Future<AddMembersOutcome> addMembers(
    String groupId,
    Iterable<String> accounts,
  ) async {
    final result = await _groups.addMembers(groupId, accounts);
    return AddMembersOutcome(
      added: result.added,
      rejected: {
        for (final e in result.rejected.entries)
          e.key: switch (e.value) {
            wire.AddMemberRejection.privacy => AddRejection.privacy,
            wire.AddMemberRejection.banned => AddRejection.banned,
            wire.AddMemberRejection.notFound => AddRejection.notFound,
            wire.AddMemberRejection.alreadyMember => AddRejection.alreadyMember,
            wire.AddMemberRejection.unknown => AddRejection.unknown,
          },
      },
    );
  }

  @override
  Future<void> removeMember(String groupId, String account) =>
      _groups.removeMember(groupId, account);

  @override
  Future<void> leave(String groupId) => _groups.leave(groupId);

  @override
  Future<void> setRole(String groupId, String account, GroupMemberRole role) =>
      _groups.setRole(groupId, account, _toWire(role));

  @override
  Future<void> ban(String groupId, String account) =>
      _groups.ban(groupId, account);

  @override
  Future<void> unban(String groupId, String account) =>
      _groups.unban(groupId, account);

  @override
  Future<void> deleteGroup(String groupId) => _groups.deleteGroup(groupId);

  @override
  Future<List<BannedInfo>> bans(String groupId) async => [
    for (final ban in await _groups.bans(groupId))
      BannedInfo(account: ban.accountId, bannedAt: ban.bannedAt),
  ];

  @override
  Future<InviteLinkInfo> createInviteLink(
    String groupId, {
    required bool requiresApproval,
    DateTime? expiresAt,
  }) async {
    final link = await _groups.createInviteLink(
      groupId,
      requiresApproval: requiresApproval,
      expiresAt: expiresAt,
    );
    return InviteLinkInfo(
      linkId: link.linkId,
      link: link.link,
      requiresApproval: link.requiresApproval,
      expiresAt: link.expiresAt,
    );
  }

  @override
  Future<void> revokeInviteLink(String groupId, String linkId) =>
      _groups.revokeInviteLink(groupId, linkId);

  @override
  Future<InvitePreviewInfo> previewInvite(String link) async {
    final preview = await _groups.previewInvite(link);
    return InvitePreviewInfo(
      groupId: preview.groupId,
      memberCount: preview.memberCount,
      requiresApproval: preview.requiresApproval,
      name: preview.name,
      description: preview.description,
      avatarPointer: preview.avatar,
    );
  }

  @override
  Future<JoinResultInfo> joinWithLink(String link) async {
    final result = await _groups.joinWithLink(link);
    return JoinResultInfo(
      groupId: result.groupId,
      outcome: result.joined ? JoinOutcome.joined : JoinOutcome.pending,
    );
  }

  @override
  Future<List<JoinRequestInfo>> joinRequests(String groupId) async => [
    for (final r in await _groups.joinRequests(groupId))
      JoinRequestInfo(
        requestId: r.requestId,
        account: r.account,
        createdAt: r.createdAt,
      ),
  ];

  @override
  Future<void> approveJoinRequest(String groupId, String requestId) =>
      _groups.approveJoinRequest(groupId, requestId);

  @override
  Future<void> rejectJoinRequest(String groupId, String requestId) =>
      _groups.rejectJoinRequest(groupId, requestId);

  @override
  Future<void> refresh(String groupId) => _groups.refresh(groupId);

  @override
  Stream<GroupSignal> signals(String groupId) => _engine.events
      .where(
        (event) => switch (event) {
          engine.GroupMembershipLost(groupId: final id) => id == groupId,
          engine.GroupJoinRequested(groupId: final id) => id == groupId,
          _ => false,
        },
      )
      .map<GroupSignal>(
        (event) => switch (event) {
          engine.GroupMembershipLost() => GroupMembershipEnded(
            event.groupId,
            event.reason,
          ),
          engine.GroupJoinRequested() => GroupJoinRequestArrived(
            event.groupId,
            event.account,
          ),
          _ => throw StateError('filtered'),
        },
      );
}

/// The live groups service, with the picture store.
final groupsPortProvider = FutureProvider<GroupsPort>((ref) async {
  final runtime = await ref.watch(runtimeProvider.future);
  final pictures = await ref.watch(groupPictureStoreProvider.future);
  return EngineGroupsPort(
    runtime.engine,
    pictures,
    ref.watch(phoneCountryProvider),
  );
});
