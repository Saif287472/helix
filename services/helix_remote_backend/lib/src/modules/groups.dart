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
        body: jsonEncode({'error': 'Group creation quota exceeded (5 per day)'}),
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

      db.logAudit(accountId, deviceId, 'GROUP_CREATED',
          request.context['client_ip'] as String?, null);

      return Response.ok(
        jsonEncode({'group_id': groupId, 'name': name, 'members': members}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
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
          body: jsonEncode({'error': 'Missing invite_id, group_id, or invitee_id'}),
        );
      }

      if (!db.isGroupAdmin(groupId, accountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Only admins can invite members'}),
        );
      }

      if (db.hasOpenGroupInvite(groupId, inviteeId)) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Open invite already exists for this user'}),
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
      final invitePayload = {
        'type': 'group_invite',
        'invite_id': inviteId,
        'group_id': groupId,
        'inviter_id': accountId,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      };
      for (final dev in inviteeDevices) {
        final devId = dev['device_id'] as String;
        wsRelay.sendToDevice(devId, invitePayload);
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
        body: jsonEncode({'error': e.toString()}),
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
        _relayToGroupMembers(groupId, memberPayload, excludeAccountId: accountId);
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
        body: jsonEncode({'error': e.toString()}),
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

      // Relay admin event to all member devices.
      _relayToGroupMembers(groupId, {
        'type': 'group_admin_event',
        'group_id': groupId,
        'action': 'update',
        if (name != null) 'name': name,
        'actor_id': accountId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      return Response.ok(
        jsonEncode({'group_id': groupId, 'updated': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
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
        body: jsonEncode({'error': e.toString()}),
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

      db.removeGroupMember(groupId, accountId);

      _relayToGroupMembers(groupId, {
        'type': 'membership_changed',
        'group_id': groupId,
        'conversation_id': groupId,
        'account_id': accountId,
        'action': 'removed',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      return Response.ok(
        jsonEncode({'group_id': groupId, 'left': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
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

      db.removeGroupMember(groupId, targetId);

      // P16-005 signal: trigger key epoch update by broadcasting
      // group_key_updated to remaining members (key material is app-layer).
      _relayToGroupMembers(groupId, {
        'type': 'group_key_updated',
        'group_id': groupId,
        'reason': 'member_removed',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      _relayToGroupMembers(groupId, {
        'type': 'membership_changed',
        'group_id': groupId,
        'conversation_id': groupId,
        'account_id': targetId,
        'action': 'removed',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      return Response.ok(
        jsonEncode({'group_id': groupId, 'removed': targetId}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
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

      db.logAudit(accountId, auth['device_id'] as String?,
          'GROUP_DELETED', request.context['client_ip'] as String?, null);

      return Response.ok(
        jsonEncode({'group_id': groupId, 'deleted': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
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
    final members = db.getConversationMembers(groupId);
    for (final memberId in members) {
      if (memberId == excludeAccountId) continue;
      final devices = db.getDevices(memberId);
      for (final dev in devices) {
        final devId = dev['device_id'] as String;
        if (devId == excludeDeviceId) continue;
        wsRelay.sendToDevice(devId, payload);
      }
    }
  }

  Response _unauthorized() => Response(
        401,
        body: jsonEncode({'error': 'Unauthorized'}),
        headers: {'Content-Type': 'application/json'},
      );
}
