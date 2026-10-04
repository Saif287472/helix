import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/people/name_lookup.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote/features/groups/application/groups_port.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// What a group admin can do to one member.
enum MemberAction {
  makeAdmin('Make admin'),
  removeAdmin('Remove admin'),
  makeOwner('Make owner'),
  remove('Remove from group'),
  ban('Remove and ban');

  const MemberAction(this.label);

  final String label;
}

/// One row of the members list.
@immutable
final class GroupMemberView {
  const GroupMemberView({
    required this.account,
    required this.names,
    required this.role,
    required this.isSelf,
    required this.actions,
    this.server,
  });

  final String account;

  /// By the people-naming order; for the signed-in person the screen says
  /// "You".
  final HelixPersonNames names;
  final GroupMemberRole role;
  final bool isSelf;

  /// What the viewer may do to this member, in menu order.
  final List<MemberAction> actions;

  /// The member's server when it is not this one ("example.org"): shown beside
  /// the name so a federated member is recognisable.
  final String? server;

  String get title => isSelf ? 'You' : names.display;

  /// The line under the name: the role, the server and the number or
  /// `~Helix name`.
  String get subtitle => [
    if (role != GroupMemberRole.member) role.label,
    ?server,
    if (!isSelf) ?names.secondary,
  ].join(' · ');

  HelixAvatarModel get avatar => HelixAvatarModel(
    name: names.display,
    colorIndex: HelixAvatarModel.colorIndexFor(account),
  );

  @override
  bool operator ==(Object other) =>
      other is GroupMemberView &&
      other.account == account &&
      other.names == names &&
      other.role == role &&
      other.isSelf == isSelf &&
      listEquals(other.actions, actions) &&
      other.server == server;

  @override
  int get hashCode => Object.hash(account, names, role, isSelf, server);
}

/// A group, ready to draw.
@immutable
final class GroupInfoView {
  const GroupInfoView({
    required this.snapshot,
    required this.members,
    required this.pictureKey,
  });

  final GroupSnapshot snapshot;
  final List<GroupMemberView> members;

  /// The group picture's pointer, JSON-encoded to key `groupPictureProvider`;
  /// null when the group has no picture.
  final String? pictureKey;

  String get id => snapshot.id;

  /// The name, or a placeholder until the group's key arrives.
  String get title => snapshot.nameUnavailable ? 'New group' : snapshot.title;

  HelixAvatarModel get avatar => HelixAvatarModel(
    name: title,
    colorIndex: HelixAvatarModel.colorIndexFor(id),
    isGroup: true,
  );

  String get memberCountLabel {
    final count = members.length;
    return count == 1 ? '1 member' : '$count members';
  }

  /// The group lives on another server.
  bool get isFederated => snapshot.homeServer != null;
}

List<MemberAction> _actionsFor(GroupMemberRole viewer, GroupMemberInfo target) {
  if (target.isSelf || target.role == GroupMemberRole.owner) return const [];
  switch (viewer) {
    case GroupMemberRole.owner:
      return [
        if (target.role == GroupMemberRole.admin)
          MemberAction.removeAdmin
        else
          MemberAction.makeAdmin,
        MemberAction.makeOwner,
        MemberAction.remove,
        MemberAction.ban,
      ];
    case GroupMemberRole.admin:
      // Admins manage ordinary members; the owner manages admins.
      if (target.role != GroupMemberRole.member) return const [];
      return const [
        MemberAction.makeAdmin,
        MemberAction.remove,
        MemberAction.ban,
      ];
    case GroupMemberRole.member:
      return const [];
  }
}

/// Builds the screen's view of [snapshot]: members named by the
/// people-naming order, owner first, then admins, then everyone else by name.
GroupInfoView buildGroupInfo(GroupSnapshot snapshot, PeopleNames names) {
  final members = [
    for (final m in snapshot.members)
      GroupMemberView(
        account: m.account,
        names: names.of(m.account, fallbackName: m.nameHint),
        role: m.role,
        isSelf: m.isSelf,
        actions: _actionsFor(snapshot.selfRole, m),
        server: m.server,
      ),
  ];
  int rank(GroupMemberView m) => switch (m.role) {
    GroupMemberRole.owner => 0,
    GroupMemberRole.admin => 1,
    GroupMemberRole.member => 2,
  };
  members.sort((a, b) {
    final byRole = rank(a).compareTo(rank(b));
    if (byRole != 0) return byRole;
    if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
    return a.names.display.toLowerCase().compareTo(
      b.names.display.toLowerCase(),
    );
  });
  final pointer = snapshot.avatarPointer;
  return GroupInfoView(
    snapshot: snapshot,
    members: members,
    pictureKey: pointer == null ? null : jsonEncode(pointer),
  );
}

/// A group's roster and state, live; null once this account is no longer in
/// the group.
final groupSnapshotProvider = StreamProvider.family<GroupSnapshot?, String>((
  ref,
  groupId,
) async* {
  final port = await ref.watch(groupsPortProvider.future);
  yield* port.watch(groupId);
});

/// The group screens' view of a group.
final groupInfoProvider = Provider.family<AsyncValue<GroupInfoView?>, String>((
  ref,
  groupId,
) {
  final snapshot = ref.watch(groupSnapshotProvider(groupId));
  final names = ref.watch(peopleNamesProvider).value ?? PeopleNames.empty;
  return snapshot.whenData(
    (value) => value == null ? null : buildGroupInfo(value, names),
  );
});
