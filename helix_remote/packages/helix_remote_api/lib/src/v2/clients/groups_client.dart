import 'package:helix_remote_api/src/v2/transport/transport.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// The `groups` module: roster authority, settings, roles, bans, invite
/// links, join requests and sender-key group sends.
final class GroupsClient {
  const GroupsClient(this._t);

  final HelixTransport _t;

  Future<Group> create(CreateGroupRequest request) =>
      _t.call(Routes.createGroup, Group.fromJson, json: request.toJson());

  Future<GroupList> list() => _t.call(Routes.myGroups, GroupList.fromJson);

  Future<Group> get(String groupId) =>
      _t.call(Routes.group, Group.fromJson, params: {'group_id': groupId});

  /// Owner only.
  Future<void> delete(String groupId) =>
      _t.empty(Routes.deleteGroup, params: {'group_id': groupId});

  /// Replaces the encrypted state at `expected_version` (optimistic).
  Future<GroupVersionResponse> setState(
    String groupId,
    SetGroupStateRequest request,
  ) => _t.call(
    Routes.setGroupState,
    GroupVersionResponse.fromJson,
    params: {'group_id': groupId},
    json: request.toJson(),
  );

  Future<void> setSettings(String groupId, GroupSettings settings) => _t.empty(
    Routes.setGroupSettings,
    params: {'group_id': groupId},
    json: settings.toJson(),
  );

  Future<AddMembersResponse> addMembers(
    String groupId,
    List<String> accounts,
  ) => _t.call(
    Routes.addGroupMembers,
    AddMembersResponse.fromJson,
    params: {'group_id': groupId},
    json: AddMembersRequest(accounts: accounts).toJson(),
  );

  /// Removes [account]; removing yourself leaves the group.
  Future<GroupVersionResponse> removeMember(String groupId, String account) =>
      _t.call(
        Routes.removeGroupMember,
        GroupVersionResponse.fromJson,
        params: {'group_id': groupId, 'account': account},
      );

  Future<void> setRole(String groupId, String account, GroupRole role) =>
      _t.empty(
        Routes.setGroupRole,
        params: {'group_id': groupId, 'account': account},
        json: SetRoleRequest(role: role).toJson(),
      );

  Future<void> ban(String groupId, String account) => _t.empty(
    Routes.banFromGroup,
    params: {'group_id': groupId, 'account': account},
  );

  Future<void> unban(String groupId, String account) => _t.empty(
    Routes.unbanFromGroup,
    params: {'group_id': groupId, 'account': account},
  );

  /// The returned [InviteLink.token] is shown once.
  Future<InviteLink> createInviteLink(
    String groupId,
    CreateInviteLinkRequest request,
  ) => _t.call(
    Routes.createInviteLink,
    InviteLink.fromJson,
    params: {'group_id': groupId},
    json: request.toJson(),
  );

  Future<void> revokeInviteLink(String groupId, String linkId) => _t.empty(
    Routes.revokeInviteLink,
    params: {'group_id': groupId, 'link_id': linkId},
  );

  Future<InvitePreview> previewInviteLink(String token) => _t.call(
    Routes.previewInviteLink,
    InvitePreview.fromJson,
    json: InviteTokenRequest(token: token).toJson(),
  );

  Future<JoinGroupResponse> join(String token) => _t.call(
    Routes.joinGroup,
    JoinGroupResponse.fromJson,
    json: InviteTokenRequest(token: token).toJson(),
  );

  Future<JoinRequestList> joinRequests(String groupId) => _t.call(
    Routes.joinRequests,
    JoinRequestList.fromJson,
    params: {'group_id': groupId},
  );

  Future<void> resolveJoinRequest(
    String groupId,
    String requestId, {
    required bool approve,
  }) => _t.empty(
    Routes.resolveJoinRequest,
    params: {'group_id': groupId, 'request_id': requestId},
    json: ResolveJoinRequest(approve: approve).toJson(),
  );

  /// Fans one sender-key message out to every member device. The message id
  /// is the idempotency key. A digest that does not match the server's
  /// member devices throws `device_list_stale` listing every member device.
  Future<SendMessageResponse> sendMessage(
    String groupId,
    GroupMessageRequest request,
  ) => _t.call(
    Routes.sendGroupMessage,
    SendMessageResponse.fromJson,
    params: {'group_id': groupId},
    json: request.toJson(),
    idempotencyKey: request.id,
  );
}
