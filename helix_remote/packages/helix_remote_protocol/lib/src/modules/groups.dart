import 'dart:typed_data';

import 'package:helix_remote_protocol/src/json.dart';

enum GroupRole implements WireEnum {
  owner('owner'),
  admin('admin'),
  member('member');

  const GroupRole(this.wire);

  @override
  final String wire;

  bool get canAdminister => this != member;
}

enum GroupPermission implements WireEnum {
  everyone('everyone'),
  admins('admins');

  const GroupPermission(this.wire);

  @override
  final String wire;
}

/// Who may do what in a group. The server enforces these; the group's name,
/// picture and description are E2EE ([Group.encryptedState]).
final class GroupSettings {
  const GroupSettings({
    this.addMembers = GroupPermission.admins,
    this.editInfo = GroupPermission.admins,
    this.sendMessages = GroupPermission.everyone,
  });

  final GroupPermission addMembers;
  final GroupPermission editInfo;
  final GroupPermission sendMessages;

  JsonMap toJson() => {
    'add_members': addMembers.wire,
    'edit_info': editInfo.wire,
    'send_messages': sendMessages.wire,
  };

  factory GroupSettings.fromJson(JsonReader json) => GroupSettings(
    addMembers: json.enumValue('add_members', GroupPermission.values),
    editInfo: json.enumValue('edit_info', GroupPermission.values),
    sendMessages: json.enumValue('send_messages', GroupPermission.values),
  );
}

final class GroupMember {
  const GroupMember({
    required this.account,
    required this.role,
    required this.joinedAt,
  });

  final String account;
  final GroupRole role;
  final DateTime joinedAt;

  JsonMap toJson() => {
    'account': account,
    'role': role.wire,
    'joined_at': toWireTime(joinedAt),
  };

  factory GroupMember.fromJson(JsonReader json) => GroupMember(
    account: json.nonEmpty('account'),
    role: json.enumValue('role', GroupRole.values),
    joinedAt: json.time('joined_at'),
  );
}

/// `GET /v1/groups/{group_id}` (members only).
final class Group {
  const Group({
    required this.groupId,
    required this.epoch,
    required this.stateVersion,
    required this.encryptedState,
    required this.settings,
    required this.members,
    required this.createdAt,
    this.homeServer,
  });

  static const maxMembers = 1024;
  static const maxStateBytes = 64 * 1024;

  final String groupId;

  /// Increases on every membership removal (CRYPTO_V2.md §9).
  final int epoch;

  /// Increases on every [encryptedState] change.
  final int stateVersion;

  /// Group state sealed with the epoch's group master key.
  final Uint8List encryptedState;
  final GroupSettings settings;
  final List<GroupMember> members;
  final DateTime createdAt;

  /// The authoritative server's domain, for federated groups.
  final String? homeServer;

  JsonMap toJson() => compact({
    'group_id': groupId,
    'epoch': epoch,
    'state_version': stateVersion,
    'encrypted_state': encodeBytes(encryptedState),
    'settings': settings.toJson(),
    'members': [for (final m in members) m.toJson()],
    'created_at': toWireTime(createdAt),
    'home_server': homeServer,
  });

  factory Group.fromJson(JsonReader json) => Group(
    groupId: json.nonEmpty('group_id'),
    epoch: json.integer('epoch'),
    stateVersion: json.integer('state_version'),
    encryptedState: json.bytes('encrypted_state'),
    settings: GroupSettings.fromJson(json.object('settings')),
    members: json.objects('members', GroupMember.fromJson),
    createdAt: json.time('created_at'),
    homeServer: json.optString('home_server'),
  );
}

/// The decrypted group state (inside [Group.encryptedState]).
final class GroupStateContent {
  const GroupStateContent({required this.name, this.description, this.avatar});

  static const maxNameLength = 100;

  final String name;
  final String? description;

  /// A `MediaPointer` JSON object (persistent media).
  final JsonMap? avatar;

  JsonMap toJson() =>
      compact({'name': name, 'description': description, 'avatar': avatar});

  factory GroupStateContent.fromJson(JsonReader json) => GroupStateContent(
    name: json.string('name'),
    description: json.optString('description'),
    avatar: json.optObject('avatar')?.json,
  );
}

/// `POST /v1/groups`. The creator becomes the owner.
final class CreateGroupRequest {
  const CreateGroupRequest({
    required this.groupId,
    required this.encryptedState,
    required this.members,
    this.settings = const GroupSettings(),
  });

  final String groupId;
  final Uint8List encryptedState;

  /// Initial members besides the creator.
  final List<String> members;
  final GroupSettings settings;

  JsonMap toJson() => {
    'group_id': groupId,
    'encrypted_state': encodeBytes(encryptedState),
    'members': members,
    'settings': settings.toJson(),
  };

  factory CreateGroupRequest.fromJson(JsonReader json) => CreateGroupRequest(
    groupId: json.nonEmpty('group_id'),
    encryptedState: json.bytes('encrypted_state'),
    members: json.strings('members'),
    settings: json.has('settings')
        ? GroupSettings.fromJson(json.object('settings'))
        : const GroupSettings(),
  );
}

/// One entry of `GET /v1/groups`.
final class GroupSummary {
  const GroupSummary({
    required this.groupId,
    required this.epoch,
    required this.stateVersion,
  });

  final String groupId;
  final int epoch;
  final int stateVersion;

  JsonMap toJson() => {
    'group_id': groupId,
    'epoch': epoch,
    'state_version': stateVersion,
  };

  factory GroupSummary.fromJson(JsonReader json) => GroupSummary(
    groupId: json.nonEmpty('group_id'),
    epoch: json.integer('epoch'),
    stateVersion: json.integer('state_version'),
  );
}

final class GroupList {
  const GroupList({required this.groups});

  final List<GroupSummary> groups;

  JsonMap toJson() => {
    'groups': [for (final g in groups) g.toJson()],
  };

  factory GroupList.fromJson(JsonReader json) =>
      GroupList(groups: json.objects('groups', GroupSummary.fromJson));
}

/// `PUT /v1/groups/{group_id}/state`, optimistic: fails with
/// `version_conflict` if [expectedVersion] is not current.
final class SetGroupStateRequest {
  const SetGroupStateRequest({
    required this.encryptedState,
    required this.expectedVersion,
  });

  final Uint8List encryptedState;
  final int expectedVersion;

  JsonMap toJson() => {
    'encrypted_state': encodeBytes(encryptedState),
    'expected_version': expectedVersion,
  };

  factory SetGroupStateRequest.fromJson(JsonReader json) =>
      SetGroupStateRequest(
        encryptedState: json.bytes('encrypted_state'),
        expectedVersion: json.integer('expected_version'),
      );
}

final class GroupVersionResponse {
  const GroupVersionResponse({required this.epoch, required this.stateVersion});

  final int epoch;
  final int stateVersion;

  JsonMap toJson() => {'epoch': epoch, 'state_version': stateVersion};

  factory GroupVersionResponse.fromJson(JsonReader json) =>
      GroupVersionResponse(
        epoch: json.integer('epoch'),
        stateVersion: json.integer('state_version'),
      );
}

/// `POST /v1/groups/{group_id}/members`.
final class AddMembersRequest {
  const AddMembersRequest({required this.accounts});

  final List<String> accounts;

  JsonMap toJson() => {'accounts': accounts};

  factory AddMembersRequest.fromJson(JsonReader json) =>
      AddMembersRequest(accounts: json.strings('accounts'));
}

enum AddMemberRejection implements WireEnum {
  /// The person's privacy settings do not allow being added; send them an
  /// invite link instead.
  privacy('privacy'),
  banned('banned'),
  notFound('not_found'),
  alreadyMember('already_member'),
  unknown('unknown');

  const AddMemberRejection(this.wire);

  @override
  final String wire;
}

final class AddMembersResponse {
  const AddMembersResponse({
    required this.added,
    required this.rejected,
    required this.epoch,
  });

  final List<String> added;
  final Map<String, AddMemberRejection> rejected;
  final int epoch;

  JsonMap toJson() => {
    'added': added,
    'rejected': {for (final e in rejected.entries) e.key: e.value.wire},
    'epoch': epoch,
  };

  factory AddMembersResponse.fromJson(JsonReader json) {
    final rejected = json.object('rejected');
    return AddMembersResponse(
      added: json.strings('added'),
      rejected: {
        for (final key in rejected.json.keys)
          key: rejected.enumValue(
            key,
            AddMemberRejection.values,
            orElse: AddMemberRejection.unknown,
          ),
      },
      epoch: json.integer('epoch'),
    );
  }
}

/// `PUT /v1/groups/{group_id}/members/{account}/role`. Ownership moves by
/// setting another member to [GroupRole.owner] (the old owner becomes admin).
final class SetRoleRequest {
  const SetRoleRequest({required this.role});

  final GroupRole role;

  JsonMap toJson() => {'role': role.wire};

  factory SetRoleRequest.fromJson(JsonReader json) =>
      SetRoleRequest(role: json.enumValue('role', GroupRole.values));
}

/// `POST /v1/groups/{group_id}/invite-links`. The link URL carries a secret
/// key in its fragment (`https://<host>/open#HLX-GRP-...`) that decrypts
/// [encryptedPreview] (name and picture) for people not yet in the group.
final class CreateInviteLinkRequest {
  const CreateInviteLinkRequest({
    required this.encryptedPreview,
    this.requiresApproval = false,
    this.expiresAt,
  });

  final Uint8List encryptedPreview;
  final bool requiresApproval;
  final DateTime? expiresAt;

  JsonMap toJson() => compact({
    'encrypted_preview': encodeBytes(encryptedPreview),
    'requires_approval': requiresApproval,
    'expires_at': expiresAt == null ? null : toWireTime(expiresAt!),
  });

  factory CreateInviteLinkRequest.fromJson(JsonReader json) =>
      CreateInviteLinkRequest(
        encryptedPreview: json.bytes('encrypted_preview'),
        requiresApproval: json.flag('requires_approval'),
        expiresAt: json.optTime('expires_at'),
      );
}

final class InviteLink {
  const InviteLink({
    required this.linkId,
    required this.token,
    required this.requiresApproval,
    required this.createdAt,
    this.expiresAt,
  });

  final String linkId;

  /// Goes in the link URL; the server stores only its hash.
  final String token;
  final bool requiresApproval;
  final DateTime createdAt;
  final DateTime? expiresAt;

  JsonMap toJson() => compact({
    'link_id': linkId,
    'token': token,
    'requires_approval': requiresApproval,
    'created_at': toWireTime(createdAt),
    'expires_at': expiresAt == null ? null : toWireTime(expiresAt!),
  });

  factory InviteLink.fromJson(JsonReader json) => InviteLink(
    linkId: json.nonEmpty('link_id'),
    token: json.nonEmpty('token'),
    requiresApproval: json.boolean('requires_approval'),
    createdAt: json.time('created_at'),
    expiresAt: json.optTime('expires_at'),
  );
}

/// Body of `POST /v1/groups/invite-links/preview` and `POST /v1/groups/join`.
final class InviteTokenRequest {
  const InviteTokenRequest({required this.token});

  final String token;

  JsonMap toJson() => {'token': token};

  factory InviteTokenRequest.fromJson(JsonReader json) =>
      InviteTokenRequest(token: json.nonEmpty('token'));

  @override
  String toString() => 'InviteTokenRequest(redacted)';
}

final class InvitePreview {
  const InvitePreview({
    required this.groupId,
    required this.memberCount,
    required this.requiresApproval,
    required this.encryptedPreview,
  });

  final String groupId;
  final int memberCount;
  final bool requiresApproval;
  final Uint8List encryptedPreview;

  JsonMap toJson() => {
    'group_id': groupId,
    'member_count': memberCount,
    'requires_approval': requiresApproval,
    'encrypted_preview': encodeBytes(encryptedPreview),
  };

  factory InvitePreview.fromJson(JsonReader json) => InvitePreview(
    groupId: json.nonEmpty('group_id'),
    memberCount: json.integer('member_count'),
    requiresApproval: json.boolean('requires_approval'),
    encryptedPreview: json.bytes('encrypted_preview'),
  );
}

enum JoinStatus implements WireEnum {
  joined('joined'),
  pending('pending');

  const JoinStatus(this.wire);

  @override
  final String wire;
}

final class JoinGroupResponse {
  const JoinGroupResponse({required this.groupId, required this.status});

  final String groupId;
  final JoinStatus status;

  JsonMap toJson() => {'group_id': groupId, 'status': status.wire};

  factory JoinGroupResponse.fromJson(JsonReader json) => JoinGroupResponse(
    groupId: json.nonEmpty('group_id'),
    status: json.enumValue('status', JoinStatus.values),
  );
}

final class JoinRequest {
  const JoinRequest({
    required this.requestId,
    required this.account,
    required this.createdAt,
  });

  final String requestId;
  final String account;
  final DateTime createdAt;

  JsonMap toJson() => {
    'request_id': requestId,
    'account': account,
    'created_at': toWireTime(createdAt),
  };

  factory JoinRequest.fromJson(JsonReader json) => JoinRequest(
    requestId: json.nonEmpty('request_id'),
    account: json.nonEmpty('account'),
    createdAt: json.time('created_at'),
  );
}

final class JoinRequestList {
  const JoinRequestList({required this.requests});

  final List<JoinRequest> requests;

  JsonMap toJson() => {
    'requests': [for (final r in requests) r.toJson()],
  };

  factory JoinRequestList.fromJson(JsonReader json) =>
      JoinRequestList(requests: json.objects('requests', JoinRequest.fromJson));
}

/// `POST /v1/groups/{group_id}/join-requests/{request_id}`.
final class ResolveJoinRequest {
  const ResolveJoinRequest({required this.approve});

  final bool approve;

  JsonMap toJson() => {'approve': approve};

  factory ResolveJoinRequest.fromJson(JsonReader json) =>
      ResolveJoinRequest(approve: json.boolean('approve'));
}
