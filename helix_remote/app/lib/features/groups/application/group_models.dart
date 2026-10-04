import 'package:flutter/foundation.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// A member's role in a group.
enum GroupMemberRole {
  owner('Owner'),
  admin('Admin'),
  member('Member');

  const GroupMemberRole(this.label);

  final String label;

  bool get canAdminister => this != member;
}

/// Who may do something in a group.
enum GroupWho {
  everyone('Everyone'),
  admins('Only admins');

  const GroupWho(this.label);

  final String label;
}

/// The group's three permission settings (admins can always do all of them).
@immutable
final class GroupPermissions {
  const GroupPermissions({
    this.addMembers = GroupWho.admins,
    this.editInfo = GroupWho.admins,
    this.sendMessages = GroupWho.everyone,
  });

  final GroupWho addMembers;
  final GroupWho editInfo;
  final GroupWho sendMessages;

  GroupPermissions copyWith({
    GroupWho? addMembers,
    GroupWho? editInfo,
    GroupWho? sendMessages,
  }) => GroupPermissions(
    addMembers: addMembers ?? this.addMembers,
    editInfo: editInfo ?? this.editInfo,
    sendMessages: sendMessages ?? this.sendMessages,
  );

  @override
  bool operator ==(Object other) =>
      other is GroupPermissions &&
      other.addMembers == addMembers &&
      other.editInfo == editInfo &&
      other.sendMessages == sendMessages;

  @override
  int get hashCode => Object.hash(addMembers, editInfo, sendMessages);
}

/// One member as the engine's roster has them.
@immutable
final class GroupMemberInfo {
  const GroupMemberInfo({
    required this.account,
    required this.role,
    this.isSelf = false,
    this.nameHint,
  });

  /// Account id: a bare uuid for this server, `uuid@domain` for a member on
  /// another server.
  final String account;
  final GroupMemberRole role;
  final bool isSelf;

  /// The roster's own name for the member, used only when this device has no
  /// people row for them.
  final String? nameHint;

  /// The member's server when it is not this one; null for a local member.
  String? get server {
    final at = account.indexOf('@');
    return at < 0 || at == account.length - 1
        ? null
        : account.substring(at + 1);
  }

  @override
  bool operator ==(Object other) =>
      other is GroupMemberInfo &&
      other.account == account &&
      other.role == role &&
      other.isSelf == isSelf &&
      other.nameHint == nameHint;

  @override
  int get hashCode => Object.hash(account, role, isSelf, nameHint);
}

/// A group as the engine has it: what the screens read before they add names.
@immutable
final class GroupSnapshot {
  const GroupSnapshot({
    required this.id,
    required this.title,
    required this.selfRole,
    required this.members,
    this.description,
    this.avatarPointer,
    this.permissions = const GroupPermissions(),
    this.disappearingSeconds,
    this.homeServer,
  });

  final String id;

  /// The group's name; empty until the group key has reached this device.
  final String title;
  final String? description;

  /// The picture's `MediaPointer` JSON, when the group has one.
  final Map<String, Object?>? avatarPointer;
  final GroupMemberRole selfRole;
  final List<GroupMemberInfo> members;
  final GroupPermissions permissions;

  /// The default disappearing-message timer, null when off.
  final int? disappearingSeconds;

  /// The authoritative server's domain for a group that lives on another
  /// server.
  final String? homeServer;

  /// The name has not arrived yet (the key is on its way).
  bool get nameUnavailable => title.isEmpty;

  bool get canAdminister => selfRole.canAdminister;
  bool get isOwner => selfRole == GroupMemberRole.owner;
  bool get canEditInfo =>
      canAdminister || permissions.editInfo == GroupWho.everyone;
  bool get canAddMembers =>
      canAdminister || permissions.addMembers == GroupWho.everyone;

  @override
  bool operator ==(Object other) =>
      other is GroupSnapshot &&
      other.id == id &&
      other.title == title &&
      other.description == description &&
      mapEquals(other.avatarPointer, avatarPointer) &&
      other.selfRole == selfRole &&
      listEquals(other.members, members) &&
      other.permissions == permissions &&
      other.disappearingSeconds == disappearingSeconds &&
      other.homeServer == homeServer;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    description,
    selfRole,
    Object.hashAll(members),
    permissions,
    disappearingSeconds,
  );
}

/// Why an add was refused.
enum AddRejection {
  /// Their privacy settings do not allow being added: send an invite link.
  privacy,
  banned,
  notFound,
  alreadyMember,
  unknown,
}

/// The result of adding people.
@immutable
final class AddMembersOutcome {
  const AddMembersOutcome({required this.added, required this.rejected});

  final List<String> added;
  final Map<String, AddRejection> rejected;
}

/// A group just created.
@immutable
final class CreatedGroupInfo {
  const CreatedGroupInfo({
    required this.groupId,
    required this.conversationId,
    this.rejected = const [],
  });

  final String groupId;
  final String conversationId;

  /// People who could not be added (their privacy settings): they need a link.
  final List<String> rejected;
}

/// An invite link to share.
@immutable
final class InviteLinkInfo {
  const InviteLinkInfo({
    required this.linkId,
    required this.link,
    required this.requiresApproval,
    this.expiresAt,
  });

  final String linkId;

  /// The URL to share. A secret: never logged or shown in a notification.
  final String link;
  final bool requiresApproval;
  final DateTime? expiresAt;

  @override
  String toString() => 'InviteLinkInfo($linkId, <redacted>)';
}

/// What an invite link shows before joining.
@immutable
final class InvitePreviewInfo {
  const InvitePreviewInfo({
    required this.groupId,
    required this.memberCount,
    required this.requiresApproval,
    required this.name,
    this.description,
    this.avatarPointer,
  });

  final String groupId;
  final int memberCount;
  final bool requiresApproval;

  /// Empty when the link's key did not open the preview.
  final String name;
  final String? description;
  final Map<String, Object?>? avatarPointer;
}

/// How joining went.
enum JoinOutcome { joined, pending }

/// The result of joining through a link.
@immutable
final class JoinResultInfo {
  const JoinResultInfo({required this.groupId, required this.outcome});

  final String groupId;
  final JoinOutcome outcome;
}

/// Someone waiting for an admin's approval.
@immutable
final class JoinRequestInfo {
  const JoinRequestInfo({
    required this.requestId,
    required this.account,
    required this.createdAt,
  });

  final String requestId;
  final String account;
  final DateTime createdAt;
}

/// Someone this device banned from a group.
@immutable
final class BannedInfo {
  const BannedInfo({required this.account, required this.bannedAt});

  final String account;
  final DateTime bannedAt;
}

/// A person who can be put in a group.
@immutable
final class GroupCandidate {
  const GroupCandidate({
    required this.account,
    required this.names,
    this.blocked = false,
  });

  final String account;
  final HelixPersonNames names;
  final bool blocked;
}

/// Something that happened to a group that a screen should react to.
sealed class GroupSignal {
  const GroupSignal(this.groupId);

  final String groupId;
}

/// This device is no longer in the group: [reason] is `removed`, `left` or
/// `deleted`.
final class GroupMembershipEnded extends GroupSignal {
  const GroupMembershipEnded(super.groupId, this.reason);

  final String reason;
}

/// Someone asked to join through an approval link.
final class GroupJoinRequestArrived extends GroupSignal {
  const GroupJoinRequestArrived(super.groupId, this.account);

  final String account;
}
