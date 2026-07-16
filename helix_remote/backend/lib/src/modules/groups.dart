import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:helix_remote_backend/src/database.dart';
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
class GroupsModule {
  GroupsModule(this.db, this.wsRelay);

  final BackendDatabase db;
  final MessageRelay wsRelay;

  // P16-014: Rate limits.
  static const int _maxGroupsPerDay = 5;
  static const int _maxInvitesPerHour = 20;
  static const int _inviteExpiryMs = 7 * 24 * 60 * 60 * 1000;

  // F6 rate limits.
  static const int _maxJoinLinksPerDay = 10;
  static const int _joinLinkExpiryMs = 7 * 24 * 60 * 60 * 1000;
  static const int _joinRequestsPerLinkPerHour = 10;

  Router get router {
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
    return r;
  }

  // -------------------------------------------------------------------------
  // P16-001: Create group
  // -------------------------------------------------------------------------

  Future<Response> _handleCreate(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();

    final accountId = auth['account_id'] as String;
    final deviceId = auth['device_id'] as String?;

    // P16-014: Group creation rate limit.
    if (db.countGroupCreationsLastDay(accountId) >= _maxGroupsPerDay) {
      return Response(
        429,
        body: jsonEncode({
          'error': 'Group creation quota exceeded (5 per day)',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final groupId = body['group_id'] as String?;
      final name = body['name'] as String?;
      final encryptionKeyId = body['encryption_key_id'] as String? ?? '';
      final rawMembers = body['initial_member_ids'] as List? ?? [];
      final initialMemberIds = rawMembers.whereType<String>().toList();

      if (groupId == null || name == null || name.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing group_id or name'}),
        );
      }

      db.createGroup(
        groupId: groupId,
        name: name,
        creatorId: accountId,
        encryptionKeyId: encryptionKeyId,
        initialMemberIds: initialMemberIds,
      );

      // P16-014: Log creation for quota tracking.
      db.logGroupCreation('gclog_${groupId}_$accountId', accountId);

      // P16-012: Relay group_created event to all member devices now online.
      final members = db.getConversationMembers(groupId);
      final eventPayload = {
        'type': 'group_created',
        'group_id': groupId,
        'name': name,
        'creator_id': accountId,
        'member_ids': members,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      };
      _relayToGroupMembers(groupId, eventPayload, excludeDeviceId: null);

      db.logAudit(
        accountId,
        deviceId,
        'GROUP_CREATED',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(
        jsonEncode({'group_id': groupId, 'name': name, 'members': members}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  // -------------------------------------------------------------------------
  // P16-001: Get group info
  // -------------------------------------------------------------------------

  Future<Response> _handleGetInfo(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();

    final accountId = auth['account_id'] as String;
    final groupId = request.url.queryParameters['group_id'];
    if (groupId == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing group_id'}),
      );
    }

    if (!db.isConversationMember(groupId, accountId)) {
      return Response.forbidden(
        jsonEncode({'error': 'Not a member of this group'}),
      );
    }

    final group = db.getGroup(groupId);
    if (group == null) {
      return Response.notFound(jsonEncode({'error': 'Group not found'}));
    }

    return Response.ok(
      jsonEncode(group),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // -------------------------------------------------------------------------
  // P16-013: Paginated member list
  // -------------------------------------------------------------------------

  Future<Response> _handleGetMembers(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();

    final accountId = auth['account_id'] as String;
    final params = request.url.queryParameters;
    final groupId = params['group_id'];
    if (groupId == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing group_id'}),
      );
    }

    if (!db.isConversationMember(groupId, accountId)) {
      return Response.forbidden(
        jsonEncode({'error': 'Not a member of this group'}),
      );
    }

    final limit = int.tryParse(params['limit'] ?? '') ?? 50;
    final offset = int.tryParse(params['offset'] ?? '') ?? 0;
    final members = db.getGroupMembersPaginated(
      groupId,
      limit: limit,
      offset: offset,
    );

    return Response.ok(
      jsonEncode({'members': members, 'limit': limit, 'offset': offset}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // -------------------------------------------------------------------------
  // P16-003: Invite
  // -------------------------------------------------------------------------

  Future<Response> _handleInvite(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();

    final accountId = auth['account_id'] as String;

    // P16-014: Invite rate limit.
    if (db.countGroupInvitesLastHour(accountId) >= _maxInvitesPerHour) {
      return Response(
        429,
        body: jsonEncode({'error': 'Invite quota exceeded (20 per hour)'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final inviteId = body['invite_id'] as String?;
      final groupId = body['group_id'] as String?;
      final inviteeId = body['invitee_id'] as String?;

      if (inviteId == null || groupId == null || inviteeId == null) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'Missing invite_id, group_id, or invitee_id',
          }),
        );
      }

      if (!db.isGroupAdmin(groupId, accountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Only admins can invite members'}),
        );
      }

      if (db.hasOpenGroupInvite(groupId, inviteeId)) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'Open invite already exists for this user',
          }),
        );
      }

      db.createGroupInvite(
        inviteId: inviteId,
        groupId: groupId,
        inviterId: accountId,
        inviteeId: inviteeId,
      );

      // P16-011: Relay invite event to online devices of the invitee.
      final inviteeDevices = db.getDevices(inviteeId);
      final now = DateTime.now().millisecondsSinceEpoch;
      final bodyPayload = {
        'invite_id': inviteId,
        'group_id': groupId,
        'inviter_id': accountId,
        'created_at': now,
      };
      for (final dev in inviteeDevices) {
        final devId = dev['device_id'] as String;
        final envelope = BackendDatabase.buildEnvelope(
          eventId: 'group_invite_${inviteId}_$devId',
          type: 'group_invite',
          payload: bodyPayload,
          timestamp: now,
        );
        wsRelay.sendToDevice(devId, envelope);
        // Queue push for offline invitee devices.
        db.enqueueOutbox(
          'grp_invite_${inviteId}_$devId',
          'PUSH_NOTIFICATION',
          jsonEncode({
            'notification_type': 'group_invite',
            'recipient_device_id': devId,
          }),
        );
      }

      return Response.ok(
        jsonEncode({'invite_id': inviteId, 'status': 'PENDING'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  // -------------------------------------------------------------------------
  // P16-003: Respond to invite
  // -------------------------------------------------------------------------

  Future<Response> _handleInviteRespond(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();

    final accountId = auth['account_id'] as String;

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final inviteId = body['invite_id'] as String?;
      final accept = body['accept'] as bool?;

      if (inviteId == null || accept == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing invite_id or accept'}),
        );
      }

      final invite = db.getGroupInvite(inviteId);
      if (invite == null) {
        return Response.notFound(jsonEncode({'error': 'Invite not found'}));
      }

      if (invite['invitee_id'] != accountId) {
        return Response.forbidden(
          jsonEncode({'error': 'Not the invitee for this invite'}),
        );
      }

      final groupId = invite['group_id'] as String;
      if (invite['status'] != 'PENDING') {
        return Response(
          409,
          body: jsonEncode({'error': 'Invite is no longer pending'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final createdAt = invite['created_at'] as int;
      if (DateTime.now().millisecondsSinceEpoch - createdAt > _inviteExpiryMs) {
        db.expireGroupInvite(inviteId);
        return Response(
          410,
          body: jsonEncode({'error': 'Invite has expired'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (accept) {
        db.acceptGroupInvite(inviteId);

        // P16-012: Notify existing members that a new member joined.
        final memberPayload = {
          'type': 'membership_changed',
          'group_id': groupId,
          'conversation_id': groupId,
          'account_id': accountId,
          'action': 'added',
          'role': 'MEMBER',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        _relayToGroupMembers(
          groupId,
          memberPayload,
          excludeAccountId: accountId,
        );
      } else {
        db.rejectGroupInvite(inviteId);
      }

      return Response.ok(
        jsonEncode({
          'invite_id': inviteId,
          'status': accept ? 'ACCEPTED' : 'REJECTED',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  // -------------------------------------------------------------------------
  // P16-008: Admin events — rename/avatar
  // -------------------------------------------------------------------------

  Future<Response> _handleUpdate(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();

    final accountId = auth['account_id'] as String;

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final groupId = body['group_id'] as String?;
      final name = body['name'] as String?;

      if (groupId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing group_id'}),
        );
      }

      if (!db.isGroupAdmin(groupId, accountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Only admins can update group info'}),
        );
      }

      db.updateGroupInfo(groupId, name: name);

      final adminEvent = {
        'type': 'group_admin_event',
        'group_id': groupId,
        'action': 'update',
        'actor_id': accountId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      if (name != null) {
        adminEvent['name'] = name;
      }

      // Relay admin event to all member devices.
      _relayToGroupMembers(groupId, adminEvent);

      return Response.ok(
        jsonEncode({'group_id': groupId, 'updated': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  // -------------------------------------------------------------------------
  // P16-008: Change member role
  // -------------------------------------------------------------------------

  Future<Response> _handleMemberRole(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();

    final accountId = auth['account_id'] as String;

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final groupId = body['group_id'] as String?;
      final targetId = body['account_id'] as String?;
      final role = body['role'] as String?;

      if (groupId == null || targetId == null || role == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing group_id, account_id, or role'}),
        );
      }

      if (!db.isGroupAdmin(groupId, accountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Only admins can change member roles'}),
        );
      }
      // F6: Creator protection — cannot demote the protected creator.
      if (role == 'MEMBER' && db.isGroupCreatorProtected(groupId, targetId)) {
        return Response(
          409,
          body: jsonEncode({
            'error': 'Cannot demote the original creator; transfer ownership first',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (role != 'ADMIN' && role != 'MEMBER') {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid group role'}),
        );
      }
      if (!db.isConversationMember(groupId, targetId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Target account is not a group member'}),
        );
      }
      if (role == 'MEMBER' &&
          db.getGroupMemberRole(groupId, targetId) == 'ADMIN' &&
          db.countGroupAdmins(groupId) == 1) {
        return Response(
          409,
          body: jsonEncode({'error': 'Cannot demote the final admin'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      db.changeGroupMemberRole(groupId, targetId, role);

      _relayToGroupMembers(groupId, {
        'type': 'membership_changed',
        'group_id': groupId,
        'conversation_id': groupId,
        'account_id': targetId,
        'action': 'role_changed',
        'role': role,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      return Response.ok(
        jsonEncode({'account_id': targetId, 'role': role}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  // -------------------------------------------------------------------------
  // P16-009: Leave
  // -------------------------------------------------------------------------

  Future<Response> _handleLeave(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();

    final accountId = auth['account_id'] as String;

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final groupId = body['group_id'] as String?;

      if (groupId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing group_id'}),
        );
      }

      if (!db.isConversationMember(groupId, accountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Not a member of this group'}),
        );
      }

      final wasAdmin = db.isGroupAdmin(groupId, accountId);
      db.removeGroupMember(groupId, accountId);
      final promotedAdmin = wasAdmin ? _promoteAdminIfNeeded(groupId) : null;

      final now = DateTime.now().millisecondsSinceEpoch;
      // F6: Silent leave — non-admins receive a generic event without leaver id.
      _relayToGroupMembers(groupId, {
        'type': 'membership_changed',
        'group_id': groupId,
        'conversation_id': groupId,
        'action': 'left_silently',
        'timestamp': now,
      });
      // Admins receive the full identity for audit/key-rotation purposes.
      final adminPayload = <String, dynamic>{
        'type': 'membership_changed_admin',
        'group_id': groupId,
        'conversation_id': groupId,
        'account_id': accountId,
        'action': 'left',
        'timestamp': now,
      };
      if (promotedAdmin != null) {
        adminPayload['promoted_admin_id'] = promotedAdmin;
      }
      _relayToGroupAdmins(groupId, adminPayload);

      if (db.getConversationMembers(groupId).isEmpty) {
        db.deleteGroup(groupId);
      }

      return Response.ok(
        jsonEncode({'group_id': groupId, 'left': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  // -------------------------------------------------------------------------
  // P16-009: Remove member (admin only)
  // -------------------------------------------------------------------------

  Future<Response> _handleRemove(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();

    final accountId = auth['account_id'] as String;

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final groupId = body['group_id'] as String?;
      final targetId = body['account_id'] as String?;

      if (groupId == null || targetId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing group_id or account_id'}),
        );
      }

      if (!db.isGroupAdmin(groupId, accountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Only admins can remove members'}),
        );
      }
      if (!db.isConversationMember(groupId, targetId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Target account is not a group member'}),
        );
      }
      // F6: Cannot remove the protected creator.
      if (db.isGroupCreatorProtected(groupId, targetId)) {
        return Response(
          409,
          body: jsonEncode({
            'error': 'Cannot remove the original creator; transfer ownership first',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final wasAdmin = db.isGroupAdmin(groupId, targetId);
      db.removeGroupMember(groupId, targetId);
      final promotedAdmin = wasAdmin ? _promoteAdminIfNeeded(groupId) : null;
      final nextEpoch = body['epoch'] as int? ?? 0;
      final encryptionKeyId = body['encryption_key_id'] as String?;

      // P16-005 signal: trigger key epoch update by broadcasting
      // group_key_updated to remaining members (key material is app-layer).
      final keyUpdatePayload = {
        'type': 'group_key_updated',
        'group_id': groupId,
        'reason': 'member_removed',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      if (nextEpoch > 0) {
        keyUpdatePayload['epoch'] = nextEpoch;
      }
      if (encryptionKeyId != null) {
        keyUpdatePayload['encryption_key_id'] = encryptionKeyId;
      }
      _relayToGroupMembers(groupId, keyUpdatePayload);

      final membershipPayload = {
        'type': 'membership_changed',
        'group_id': groupId,
        'conversation_id': groupId,
        'account_id': targetId,
        'action': 'removed',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      if (promotedAdmin != null) {
        membershipPayload['promoted_admin_id'] = promotedAdmin;
      }
      _relayToGroupMembers(groupId, membershipPayload);

      return Response.ok(
        jsonEncode({'group_id': groupId, 'removed': targetId}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  // -------------------------------------------------------------------------
  // P16-010: Delete group
  // -------------------------------------------------------------------------

  Future<Response> _handleDelete(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();

    final accountId = auth['account_id'] as String;

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final groupId = body['group_id'] as String?;

      if (groupId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing group_id'}),
        );
      }

      if (!db.isGroupAdmin(groupId, accountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Only admins can delete a group'}),
        );
      }

      // Notify all members before deletion so they can clean up locally.
      _relayToGroupMembers(groupId, {
        'type': 'group_deleted',
        'group_id': groupId,
        'deleted_by': accountId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      db.deleteGroup(groupId);

      db.logAudit(
        accountId,
        auth['device_id'] as String?,
        'GROUP_DELETED',
        request.context['client_ip'] as String?,
        null,
      );

      return Response.ok(
        jsonEncode({'group_id': groupId, 'deleted': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  // -------------------------------------------------------------------------
  // F6: Set group-add privacy policy
  // -------------------------------------------------------------------------

  Future<Response> _handleSetAddPolicy(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();
    final accountId = auth['account_id'] as String;
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final groupId = body['group_id'] as String?;
      final policy = body['policy'] as String?;
      if (groupId == null || policy == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing group_id or policy'}),
        );
      }
      const validPolicies = {
        'EVERYONE',
        'CONTACTS',
        'CONTACTS_EXCEPT',
        'NOBODY',
      };
      if (!validPolicies.contains(policy)) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid policy value'}),
        );
      }
      if (!db.isGroupAdmin(groupId, accountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Only admins can change group-add policy'}),
        );
      }
      db.setGroupAddPolicy(groupId, policy);
      _relayToGroupMembers(groupId, {
        'type': 'group_add_policy_changed',
        'group_id': groupId,
        'policy': policy,
        'actor_id': accountId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      return Response.ok(
        jsonEncode({'group_id': groupId, 'policy': policy}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  // -------------------------------------------------------------------------
  // F6: Create join link
  // -------------------------------------------------------------------------

  Future<Response> _handleCreateJoinLink(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();
    final accountId = auth['account_id'] as String;
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final groupId = body['group_id'] as String?;
      final linkId = body['link_id'] as String?;
      final token = body['token'] as String?;
      final requiresApproval = body['requires_approval'] as bool? ?? false;
      final expiresAt =
          body['expires_at'] as int? ??
          DateTime.now().millisecondsSinceEpoch + _joinLinkExpiryMs;

      if (groupId == null || linkId == null || token == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing group_id, link_id, or token'}),
        );
      }
      if (!db.isGroupAdmin(groupId, accountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Only admins can create join links'}),
        );
      }
      if (db.countJoinLinksLastDay(groupId, accountId) >= _maxJoinLinksPerDay) {
        return Response(
          429,
          body: jsonEncode({'error': 'Join link creation quota exceeded'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      db.createGroupJoinLink(
        linkId: linkId,
        groupId: groupId,
        creatorId: accountId,
        token: token,
        requiresApproval: requiresApproval,
        expiresAt: expiresAt,
      );
      return Response.ok(
        jsonEncode({
          'link_id': linkId,
          'token': token,
          'expires_at': expiresAt,
          'requires_approval': requiresApproval,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  // -------------------------------------------------------------------------
  // F6: Revoke join link
  // -------------------------------------------------------------------------

  Future<Response> _handleRevokeJoinLink(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();
    final accountId = auth['account_id'] as String;
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final linkId = body['link_id'] as String?;
      if (linkId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing link_id'}),
        );
      }
      final link = db.getGroupJoinLink(linkId);
      if (link == null) {
        return Response.notFound(jsonEncode({'error': 'Link not found'}));
      }
      if (!db.isGroupAdmin(link['group_id'] as String, accountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Only admins can revoke join links'}),
        );
      }
      db.revokeGroupJoinLink(linkId);
      return Response.ok(
        jsonEncode({'link_id': linkId, 'revoked': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  // -------------------------------------------------------------------------
  // F6: Join via link
  // -------------------------------------------------------------------------

  Future<Response> _handleJoinViaLink(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();
    final accountId = auth['account_id'] as String;
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final token = body['token'] as String?;
      final requestId = body['request_id'] as String?;
      if (token == null || requestId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing token or request_id'}),
        );
      }
      final link = db.getGroupJoinLinkByToken(token);
      if (link == null || (link['revoked_at'] as int) > 0) {
        return Response(
          410,
          body: jsonEncode({'error': 'Join link is revoked or does not exist'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      if ((link['expires_at'] as int) < now) {
        return Response(
          410,
          body: jsonEncode({'error': 'Join link has expired'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final groupId = link['group_id'] as String;
      if (db.isConversationMember(groupId, accountId)) {
        return Response(
          409,
          body: jsonEncode({'error': 'Already a member'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (db.isGroupMemberBlocked(groupId, accountId)) {
        return Response(
          403,
          body: jsonEncode({'error': 'You cannot join this group'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (db.countJoinRequestsLastHour(link['link_id'] as String) >=
          _joinRequestsPerLinkPerHour) {
        return Response(
          429,
          body: jsonEncode({'error': 'Too many join requests for this link'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final requiresApproval = (link['requires_approval'] as int) == 1;
      if (requiresApproval) {
        db.createGroupJoinRequest(
          requestId: requestId,
          groupId: groupId,
          requesterId: accountId,
          linkId: link['link_id'] as String,
        );
        _relayToGroupAdmins(groupId, {
          'type': 'group_join_requested',
          'group_id': groupId,
          'request_id': requestId,
          'requester_id': accountId,
          'timestamp': now,
        });
        return Response.ok(
          jsonEncode({'request_id': requestId, 'status': 'PENDING'}),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        // Direct join: add as MEMBER and rotate epoch.
        db.addGroupMember(groupId, accountId);
        _relayToGroupMembers(groupId, {
          'type': 'membership_changed',
          'group_id': groupId,
          'conversation_id': groupId,
          'account_id': accountId,
          'action': 'added',
          'role': 'MEMBER',
          'timestamp': now,
        });
        return Response.ok(
          jsonEncode({'group_id': groupId, 'status': 'JOINED'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  // -------------------------------------------------------------------------
  // F6: Get pending join requests (admin only)
  // -------------------------------------------------------------------------

  Future<Response> _handleGetJoinRequests(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();
    final accountId = auth['account_id'] as String;
    final groupId = request.url.queryParameters['group_id'];
    if (groupId == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing group_id'}),
      );
    }
    if (!db.isGroupAdmin(groupId, accountId)) {
      return Response.forbidden(
        jsonEncode({'error': 'Only admins can view join requests'}),
      );
    }
    final requests = db.getPendingGroupJoinRequests(groupId);
    return Response.ok(
      jsonEncode({'requests': requests}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // -------------------------------------------------------------------------
  // F6: Approve or reject a join request
  // -------------------------------------------------------------------------

  Future<Response> _handleApproveJoinRequest(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();
    final accountId = auth['account_id'] as String;
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final requestId = body['request_id'] as String?;
      final approve = body['approve'] as bool?;
      if (requestId == null || approve == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing request_id or approve'}),
        );
      }
      final jr = db.getGroupJoinRequest(requestId);
      if (jr == null) {
        return Response.notFound(jsonEncode({'error': 'Request not found'}));
      }
      if (jr['status'] != 'PENDING') {
        return Response(
          409,
          body: jsonEncode({'error': 'Request is no longer pending'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final groupId = jr['group_id'] as String;
      if (!db.isGroupAdmin(groupId, accountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Only admins can approve join requests'}),
        );
      }
      final requesterId = jr['requester_id'] as String;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (approve) {
        db.updateGroupJoinRequestStatus(requestId, 'APPROVED');
        db.addGroupMember(groupId, requesterId);
        _relayToGroupMembers(groupId, {
          'type': 'membership_changed',
          'group_id': groupId,
          'conversation_id': groupId,
          'account_id': requesterId,
          'action': 'added',
          'role': 'MEMBER',
          'timestamp': now,
        });
      } else {
        db.updateGroupJoinRequestStatus(requestId, 'REJECTED');
      }
      // Notify the requester of the decision.
      final requesterDevices = db.getDevices(requesterId);
      for (final dev in requesterDevices) {
        final devId = dev['device_id'] as String;
        final envelope = BackendDatabase.buildEnvelope(
          eventId: 'join_request_${requestId}_$devId',
          type: 'group_join_request_resolved',
          payload: {
            'request_id': requestId,
            'group_id': groupId,
            'approved': approve,
          },
          timestamp: now,
        );
        wsRelay.sendToDevice(devId, envelope);
      }
      return Response.ok(
        jsonEncode({
          'request_id': requestId,
          'status': approve ? 'APPROVED' : 'REJECTED',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  // -------------------------------------------------------------------------
  // F6: Transfer group ownership (creator protection)
  // -------------------------------------------------------------------------

  Future<Response> _handleTransferOwnership(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();
    final accountId = auth['account_id'] as String;
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final groupId = body['group_id'] as String?;
      final newOwnerId = body['new_owner_id'] as String?;
      if (groupId == null || newOwnerId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing group_id or new_owner_id'}),
        );
      }
      final group = db.getGroup(groupId);
      if (group == null) {
        return Response.notFound(jsonEncode({'error': 'Group not found'}));
      }
      if (group['creator_id'] != accountId) {
        return Response.forbidden(
          jsonEncode({'error': 'Only the original creator can transfer ownership'}),
        );
      }
      if (!db.isConversationMember(groupId, newOwnerId)) {
        return Response.forbidden(
          jsonEncode({'error': 'New owner must be a current group member'}),
        );
      }
      // Ensure new owner is admin before transferring.
      if (!db.isGroupAdmin(groupId, newOwnerId)) {
        db.changeGroupMemberRole(groupId, newOwnerId, 'ADMIN');
      }
      db.transferGroupOwnership(groupId, newOwnerId);
      _relayToGroupMembers(groupId, {
        'type': 'group_admin_event',
        'group_id': groupId,
        'action': 'ownership_transferred',
        'actor_id': accountId,
        'new_owner_id': newOwnerId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      return Response.ok(
        jsonEncode({
          'group_id': groupId,
          'new_owner_id': newOwnerId,
          'transferred': true,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  // -------------------------------------------------------------------------
  // F6: Admin delete abusive message
  // -------------------------------------------------------------------------

  Future<Response> _handleAdminDeleteMessage(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();
    final accountId = auth['account_id'] as String;
    final deviceId = auth['device_id'] as String?;
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final groupId = body['group_id'] as String?;
      final messageId = body['message_id'] as String?;
      if (groupId == null || messageId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing group_id or message_id'}),
        );
      }
      if (!db.isGroupAdmin(groupId, accountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Only admins can delete group messages'}),
        );
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      db.saveGroupModeratedMessage(
        messageId: messageId,
        groupId: groupId,
        moderatedBy: accountId,
        moderatedAt: now,
      );
      db.logAudit(accountId, deviceId, 'GROUP_MESSAGE_MODERATED', null, null);
      _relayToGroupMembers(groupId, {
        'type': 'group_admin_event',
        'group_id': groupId,
        'action': 'message_moderated',
        'message_id': messageId,
        'actor_id': accountId,
        'timestamp': now,
      });
      return Response.ok(
        jsonEncode({'message_id': messageId, 'moderated': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  // -------------------------------------------------------------------------
  // F6: Block member from re-adding
  // -------------------------------------------------------------------------

  Future<Response> _handleBlockMember(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();
    final accountId = auth['account_id'] as String;
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final groupId = body['group_id'] as String?;
      final targetId = body['account_id'] as String?;
      if (groupId == null || targetId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing group_id or account_id'}),
        );
      }
      if (!db.isGroupAdmin(groupId, accountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Only admins can block members'}),
        );
      }
      db.addGroupBlockedMember(
        groupId: groupId,
        accountId: targetId,
        createdBy: accountId,
      );
      // Also remove from group if still a member.
      if (db.isConversationMember(groupId, targetId)) {
        db.removeGroupMember(groupId, targetId);
        _relayToGroupMembers(groupId, {
          'type': 'membership_changed',
          'group_id': groupId,
          'conversation_id': groupId,
          'account_id': targetId,
          'action': 'removed',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
      }
      return Response.ok(
        jsonEncode({'group_id': groupId, 'blocked': targetId}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error'}),
      );
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  void _relayToGroupMembers(
    String groupId,
    Map<String, dynamic> payload, {
    String? excludeDeviceId,
    String? excludeAccountId,
  }) {
    final eventType = payload['type'] as String?;
    if (eventType == null) return;
    final bodyPayload = Map<String, dynamic>.from(payload)..remove('type');

    final now = DateTime.now().millisecondsSinceEpoch;
    final members = db.getConversationMembers(groupId);
    for (final memberId in members) {
      if (memberId == excludeAccountId) continue;
      final devices = db.getDevices(memberId);
      for (final dev in devices) {
        final devId = dev['device_id'] as String;
        if (devId == excludeDeviceId) continue;
        final eventId = '${eventType}_${groupId}_${now}_$devId';
        final envelope = BackendDatabase.buildEnvelope(
          eventId: eventId,
          type: eventType,
          payload: bodyPayload,
          timestamp: now,
        );
        wsRelay.sendToDevice(devId, envelope);
      }
    }
  }

  void _relayToGroupAdmins(String groupId, Map<String, dynamic> payload) {
    final eventType = payload['type'] as String?;
    if (eventType == null) return;
    final bodyPayload = Map<String, dynamic>.from(payload)..remove('type');
    final now = DateTime.now().millisecondsSinceEpoch;
    final members = db.getGroupMembersPaginated(groupId, limit: 500, offset: 0);
    for (final member in members) {
      if (member['role'] != 'ADMIN') continue;
      final memberId = member['account_id'] as String;
      final devices = db.getDevices(memberId);
      for (final dev in devices) {
        final devId = dev['device_id'] as String;
        final envelope = BackendDatabase.buildEnvelope(
          eventId: '${eventType}_${groupId}_admin_${now}_$devId',
          type: eventType,
          payload: bodyPayload,
          timestamp: now,
        );
        wsRelay.sendToDevice(devId, envelope);
      }
    }
  }

  String? _promoteAdminIfNeeded(String groupId) {
    if (db.getConversationMembers(groupId).isEmpty) return null;
    if (db.countGroupAdmins(groupId) > 0) return null;
    return db.promoteFirstRemainingGroupMemberToAdmin(groupId);
  }

  Response _unauthorized() => Response(
    401,
    body: jsonEncode({'error': 'Unauthorized'}),
    headers: {'Content-Type': 'application/json'},
  );
}
