part of '../groups.dart';

/// Who is in the group and what they may do: invites and their responses,
/// role changes, leaving, removal, and ownership transfer.
///
/// This is the security-sensitive half of the module - see
/// `docs/ai/AI_GUARDRAILS.md` on group admin and trust rules before
/// changing an authorization check here.
mixin GroupsMembershipHandlers on GroupsModuleBase {
  Future<Response> _handleInvite(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();

    final accountId = auth['account_id'] as String;

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

      final authority = db.resolveGroupAuthority(groupId);
      if (authority.isParticipant) {
        return _proxyToHome(authority, groupId, 'invite', accountId, body);
      }
      if (!authority.isHome) {
        return Response.notFound(jsonEncode({'error': 'Group not found'}));
      }

      // P16-014: Invite rate limit.
      if (db.countGroupInvitesLastHour(accountId) >= _maxInvitesPerHour) {
        return Response(
          429,
          body: jsonEncode({'error': 'Invite quota exceeded (20 per hour)'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (!_isAdmin(groupId, accountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Only admins can invite members'}),
        );
      }

      if (_isExternal(inviteeId) && federationClient == null) {
        return Response(
          503,
          body: jsonEncode({'error': 'Federation is not configured'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      if (db.isGroupMemberBlocked(groupId, inviteeId)) {
        return Response.forbidden(
          jsonEncode({'error': 'User is blocked from this group'}),
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

      final now = DateTime.now().millisecondsSinceEpoch;
      if (_isExternal(inviteeId)) {
        // Milestone 4.1: invitee is hosted on another server — tell that
        // server about the pending invite so it can notify its local
        // devices. Only that one domain needs to know; the invitee isn't a
        // member yet so a full roster broadcast isn't needed.
        await _sendGroupSync(groupId, FederationClient.domainOf(inviteeId)!, {
          'group_id': groupId,
          'home_server_id': federationClient!.identity.serverId,
          'home_domain': localDomain,
          'pending_invites': [
            {
              'invite_id': inviteId,
              'group_id': groupId,
              'home_server_id': federationClient!.identity.serverId,
              'home_domain': localDomain,
              'inviter_id': _qualify(accountId),
              'invitee_id': inviteeId,
              'status': 'PENDING',
              'created_at': now,
            },
          ],
        });
      } else {
        // P16-011: Relay invite event to online devices of the invitee.
        _notifyInviteeDevices(
          inviteId: inviteId,
          groupId: groupId,
          inviterId: accountId,
          inviteeId: inviteeId,
          createdAt: now,
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

  void _notifyInviteeDevices({
    required String inviteId,
    required String groupId,
    required String inviterId,
    required String inviteeId,
    required int createdAt,
  }) {
    final inviteeDevices = db.getDevices(inviteeId);
    final bodyPayload = {
      'invite_id': inviteId,
      'group_id': groupId,
      'inviter_id': inviterId,
      'created_at': createdAt,
    };
    for (final dev in inviteeDevices) {
      final devId = dev['device_id'] as String;
      final envelope = BackendDatabase.buildEnvelope(
        eventId: 'group_invite_${inviteId}_$devId',
        type: 'group_invite',
        payload: bodyPayload,
        timestamp: createdAt,
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
        // Milestone 4.1: not a home-local invite record. If this server is
        // a participant mirroring it (because the invitee is local here
        // but the group's home is elsewhere), proxy the response to home.
        final fedInvite = db.getFederatedGroupInvite(inviteId);
        if (fedInvite == null) {
          return Response.notFound(jsonEncode({'error': 'Invite not found'}));
        }
        if (fedInvite['invitee_id'] != accountId) {
          return Response.forbidden(
            jsonEncode({'error': 'Not the invitee for this invite'}),
          );
        }
        final authority = GroupAuthority(
          isHome: false,
          isParticipant: true,
          homeServerId: fedInvite['home_server_id'] as String,
          homeDomain: fedInvite['home_domain'] as String,
        );
        return _proxyToHome(
          authority,
          fedInvite['group_id'] as String,
          'invite_respond',
          accountId,
          body,
        );
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

      final domainsBefore = db.getParticipatingDomains(groupId);
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
        await _broadcastGroupSync(groupId, {
          ...domainsBefore,
          ...db.getParticipatingDomains(groupId),
        }, event: memberPayload);
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

      final authority = db.resolveGroupAuthority(groupId);
      if (authority.isParticipant) {
        return _proxyToHome(authority, groupId, 'member_role', accountId, body);
      }
      if (!authority.isHome) {
        return Response.notFound(jsonEncode({'error': 'Group not found'}));
      }

      if (!_isAdmin(groupId, accountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Only admins can change member roles'}),
        );
      }
      // F6: Creator protection — cannot demote the protected creator.
      if (role == 'MEMBER' && db.isGroupCreatorProtected(groupId, targetId)) {
        return Response(
          409,
          body: jsonEncode({
            'error':
                'Cannot demote the original creator; transfer ownership first',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (role != 'ADMIN' && role != 'MEMBER') {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid group role'}),
        );
      }
      if (!db.isGroupMemberIncludingFederated(groupId, targetId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Target account is not a group member'}),
        );
      }
      if (role == 'MEMBER' &&
          db.getGroupMemberRoleIncludingFederated(groupId, targetId) ==
              'ADMIN' &&
          db.countGroupAdminsIncludingFederated(groupId) == 1) {
        return Response(
          409,
          body: jsonEncode({'error': 'Cannot demote the final admin'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      db.changeGroupMemberRole(groupId, targetId, role);

      final rolePayload = {
        'type': 'membership_changed',
        'group_id': groupId,
        'conversation_id': groupId,
        'account_id': targetId,
        'action': 'role_changed',
        'role': role,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      _relayToGroupMembers(groupId, rolePayload);
      await _broadcastGroupSync(
        groupId,
        db.getParticipatingDomains(groupId),
        event: rolePayload,
      );

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

      final authority = db.resolveGroupAuthority(groupId);
      if (authority.isParticipant) {
        return _proxyToHome(authority, groupId, 'leave', accountId, body);
      }
      if (!authority.isHome) {
        return Response.notFound(jsonEncode({'error': 'Group not found'}));
      }

      if (!db.isGroupMemberIncludingFederated(groupId, accountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Not a member of this group'}),
        );
      }

      final domainsBefore = db.getParticipatingDomains(groupId);
      final wasAdmin = _isAdmin(groupId, accountId);
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
        'account_id': _qualify(accountId),
        'action': 'left',
        'timestamp': now,
      };
      if (promotedAdmin != null) {
        adminPayload['promoted_admin_id'] = promotedAdmin;
      }
      _relayToGroupAdmins(groupId, adminPayload);
      await _broadcastGroupSync(groupId, {
        ...domainsBefore,
        ...db.getParticipatingDomains(groupId),
      }, event: adminPayload);

      if (!db.hasAnyGroupMembersIncludingFederated(groupId)) {
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

      final authority = db.resolveGroupAuthority(groupId);
      if (authority.isParticipant) {
        return _proxyToHome(authority, groupId, 'remove', accountId, body);
      }
      if (!authority.isHome) {
        return Response.notFound(jsonEncode({'error': 'Group not found'}));
      }

      if (!_isAdmin(groupId, accountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Only admins can remove members'}),
        );
      }
      if (!db.isGroupMemberIncludingFederated(groupId, targetId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Target account is not a group member'}),
        );
      }
      // F6: Cannot remove the protected creator.
      if (db.isGroupCreatorProtected(groupId, targetId)) {
        return Response(
          409,
          body: jsonEncode({
            'error':
                'Cannot remove the original creator; transfer ownership first',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final domainsBefore = db.getParticipatingDomains(groupId);
      final wasAdmin =
          db.getGroupMemberRoleIncludingFederated(groupId, targetId) == 'ADMIN';
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
      await _broadcastGroupSync(groupId, {
        ...domainsBefore,
        ...db.getParticipatingDomains(groupId),
      }, event: membershipPayload);

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

      final authority = db.resolveGroupAuthority(groupId);
      if (authority.isParticipant) {
        return _proxyToHome(
          authority,
          groupId,
          'transfer_ownership',
          accountId,
          body,
        );
      }
      if (!authority.isHome) {
        return Response.notFound(jsonEncode({'error': 'Group not found'}));
      }
      final group = db.getGroup(groupId)!;
      if (group['creator_id'] != accountId) {
        return Response.forbidden(
          jsonEncode({
            'error': 'Only the original creator can transfer ownership',
          }),
        );
      }
      if (!db.isGroupMemberIncludingFederated(groupId, newOwnerId)) {
        return Response.forbidden(
          jsonEncode({'error': 'New owner must be a current group member'}),
        );
      }
      // Ensure new owner is admin before transferring.
      if (!_isAdmin(groupId, newOwnerId)) {
        db.changeGroupMemberRole(groupId, newOwnerId, 'ADMIN');
      }
      db.transferGroupOwnership(groupId, newOwnerId);
      final transferPayload = {
        'type': 'group_admin_event',
        'group_id': groupId,
        'action': 'ownership_transferred',
        'actor_id': accountId,
        'new_owner_id': newOwnerId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      _relayToGroupMembers(groupId, transferPayload);
      await _broadcastGroupSync(
        groupId,
        db.getParticipatingDomains(groupId),
        event: transferPayload,
      );
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
}
