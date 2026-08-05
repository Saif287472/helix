import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:helix_remote_backend/src/app_error.dart';
import 'package:helix_remote_backend/src/database.dart';
import 'package:helix_remote_backend/src/federation.dart';
import 'package:helix_remote_backend/src/modules/messaging.dart';

/// HTTP module for Remote group lifecycle.
///
/// P16-001  POST /create                — create group (creator becomes ADMIN)
/// P16-013  GET  /info                  — group info + members (paginated)
/// P16-013  GET  /members               — paginated member list
/// P16-003  POST /invite                — admin invites a member
/// P16-003  POST /invite/respond        — invitee accepts or rejects
/// P16-008  POST /update                — admin renames or changes avatar
/// P16-008  POST /member-role           — admin changes a member's role
/// P16-009  POST /leave                 — member exits the group
/// P16-009  POST /remove                — admin removes a member
/// P16-010  POST /delete                — admin deletes the group
///
/// Milestone 4.1: a group's home server (whichever server processed
/// /create) is authoritative for membership/roles. Other servers hosting a
/// member are participants: they proxy their local admins' mutating actions
/// to home via POST /api/v1/s2s/groups/action (see [applyRemoteAction]) and
/// receive roster/invite pushes via POST /api/v1/s2s/groups/sync.
part 'groups/federation.dart';
part 'groups/lifecycle.dart';
part 'groups/membership.dart';
part 'groups/join_links.dart';
part 'groups/moderation.dart';
part 'groups/epoch_keys.dart';
part 'groups/relay.dart';

// P16-014 and F6 rate limits. Top-level rather than class statics so every
// part file can read them without qualifying, the same way the constants
// each one guards are used.
const int _maxGroupsPerDay = 5;
const int _maxInvitesPerHour = 20;
const int _inviteExpiryMs = 7 * 24 * 60 * 60 * 1000;
const int _maxJoinLinksPerDay = 10;
const int _joinLinkExpiryMs = 7 * 24 * 60 * 60 * 1000;
const int _joinRequestsPerLinkPerHour = 10;

/// What every handler mixin in this module is allowed to assume exists.
///
/// The four fields are the module's collaborators. The methods below are
/// helpers implemented in one part file and called from others - Dart
/// mixins can only see members declared on their `on` type, so a helper
/// that crosses a part boundary has to be declared here even though
/// exactly one mixin implements it.
abstract class GroupsModuleBase {
  BackendDatabase get db;
  MessageRelay get wsRelay;
  FederationClient? get federationClient;
  String? get localDomain;

  // Implemented by GroupsFederationHelpers.
  bool _isExternal(String accountId);
  String _qualify(String accountId);
  bool _isAdmin(String groupId, String accountId);
  Future<Response> _proxyToHome(
    GroupAuthority authority,
    String groupId,
    String action,
    String actingAccountId,
    Map<String, dynamic> payload,
  );
  Response? _requireHomeOnly(String groupId);
  Future<void> _broadcastGroupSync(
    String groupId,
    Set<String> domains, {
    Map<String, dynamic>? event,
  });
  Future<void> _sendGroupSync(
    String groupId,
    String domain,
    Map<String, dynamic> snapshot,
  );

  // Implemented by GroupsRelayHelpers.
  void _relayToGroupMembers(
    String groupId,
    Map<String, dynamic> payload, {
    String? excludeDeviceId,
    String? excludeAccountId,
  });
  void _relayToGroupAdmins(String groupId, Map<String, dynamic> payload);
  String? _promoteAdminIfNeeded(String groupId);
  AppError _unauthorized();
}

class GroupsModule extends GroupsModuleBase
    with
        GroupsFederationHelpers,
        GroupsLifecycleHandlers,
        GroupsMembershipHandlers,
        GroupsJoinLinkHandlers,
        GroupsModerationHandlers,
        GroupsEpochKeyHandlers,
        GroupsRelayHelpers {
  GroupsModule(
    this.db,
    this.wsRelay, {
    this.federationClient,
    this.localDomain,
  });

  @override
  final BackendDatabase db;
  @override
  final MessageRelay wsRelay;
  @override
  final FederationClient? federationClient;
  @override
  final String? localDomain;

  Handler get router {
    final r = Router();
    r.post('/create', _handleCreate);
    r.get('/info', _handleGetInfo);
    r.get('/members', _handleGetMembers);
    r.post('/invite', _handleInvite);
    r.post('/invite/respond', _handleInviteRespond);
    r.post('/update', _handleUpdate);
    r.post('/member-role', _handleMemberRole);
    r.post('/leave', _handleLeave);
    r.post('/remove', _handleRemove);
    r.post('/delete', _handleDelete);
    // F6 endpoints.
    r.post('/set-add-policy', _handleSetAddPolicy);
    r.post('/create-join-link', _handleCreateJoinLink);
    r.post('/revoke-join-link', _handleRevokeJoinLink);
    r.post('/join-via-link', _handleJoinViaLink);
    r.get('/join-requests', _handleGetJoinRequests);
    r.post('/approve-join-request', _handleApproveJoinRequest);
    r.post('/transfer-ownership', _handleTransferOwnership);
    r.post('/admin-delete-message', _handleAdminDeleteMessage);
    r.post('/block-member', _handleBlockMember);
    // Milestone 4.2: group Sender Key epoch distribution.
    r.post('/epoch-key/deliver', _handleDeliverEpochKey);
    return withAppErrorHandling(r.call);
  }

  // -------------------------------------------------------------------------
  // Milestone 4.1: federation helpers
  // -------------------------------------------------------------------------

  /// Actions a participant server may proxy to this group's home server.
  /// Each maps onto the existing REST handler via a synthetic local
  /// [Request] so authorization/mutation logic is defined in exactly one
  /// place for both the direct-REST and S2S-proxied entry points.
  late final Map<String, Future<Response> Function(Request)>
  _remoteActionHandlers = {
    'invite': _handleInvite,
    'invite_respond': _handleInviteRespond,
    'update': _handleUpdate,
    'member_role': _handleMemberRole,
    'leave': _handleLeave,
    'remove': _handleRemove,
    'delete': _handleDelete,
    'set_add_policy': _handleSetAddPolicy,
    'transfer_ownership': _handleTransferOwnership,
    'admin_delete_message': _handleAdminDeleteMessage,
    'block_member': _handleBlockMember,
  };

  /// Entry point for `POST /api/v1/s2s/groups/action`: a participant server
  /// asking this (home) server to apply an action on behalf of one of its
  /// local admins.
  Future<Response> applyRemoteAction(
    String action,
    String groupId,
    String actingAccountId,
    Map<String, dynamic> payload,
  ) async {
    final handler = _remoteActionHandlers[action];
    if (handler == null) {
      throw AppError.badRequest('Unknown group action: $action');
    }
    final body = Map<String, dynamic>.from(payload)..['group_id'] = groupId;
    final syntheticRequest = Request(
      'POST',
      Uri.parse('http://s2s.internal/groups/$action'),
      body: jsonEncode(body),
      context: {
        'auth': <String, dynamic>{'account_id': actingAccountId},
      },
    );
    return handler(syntheticRequest);
  }
}
