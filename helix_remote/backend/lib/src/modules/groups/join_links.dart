part of '../groups.dart';

/// F6: joining by link instead of by invite - the add policy that gates
/// it, link issue/revoke, and the approval queue a link can feed.
mixin GroupsJoinLinkHandlers on GroupsModuleBase {
  Future<Response> _handleSetAddPolicy(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) throw _unauthorized();
    final accountId = auth['account_id'] as String;
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final groupId = body['group_id'] as String?;
    final policy = body['policy'] as String?;
    if (groupId == null || policy == null) {
      throw AppError.badRequest('Missing group_id or policy');
    }
    const validPolicies = {'EVERYONE', 'CONTACTS', 'CONTACTS_EXCEPT', 'NOBODY'};
    if (!validPolicies.contains(policy)) {
      throw AppError.badRequest('Invalid policy value');
    }

    final authority = db.resolveGroupAuthority(groupId);
    if (authority.isParticipant) {
      return _proxyToHome(
        authority,
        groupId,
        'set_add_policy',
        accountId,
        body,
      );
    }
    if (!authority.isHome) {
      throw AppError.notFound('Group not found');
    }

    if (!_isAdmin(groupId, accountId)) {
      throw AppError.forbidden('Only admins can change group-add policy');
    }
    db.setGroupAddPolicy(groupId, policy);
    final policyPayload = {
      'type': 'group_add_policy_changed',
      'group_id': groupId,
      'policy': policy,
      'actor_id': accountId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    _relayToGroupMembers(groupId, policyPayload);
    await _broadcastGroupSync(
      groupId,
      db.getParticipatingDomains(groupId),
      event: policyPayload,
    );
    return Response.ok(
      jsonEncode({'group_id': groupId, 'policy': policy}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // -------------------------------------------------------------------------
  // F6: Create join link
  // -------------------------------------------------------------------------

  Future<Response> _handleCreateJoinLink(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) throw _unauthorized();
    final accountId = auth['account_id'] as String;
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
      throw AppError.badRequest('Missing group_id, link_id, or token');
    }
    final homeOnlyError = _requireHomeOnly(groupId);
    if (homeOnlyError != null) return homeOnlyError;
    if (!_isAdmin(groupId, accountId)) {
      throw AppError.forbidden('Only admins can create join links');
    }
    if (db.countJoinLinksLastDay(groupId, accountId) >= _maxJoinLinksPerDay) {
      throw AppError.tooManyRequests('Join link creation quota exceeded');
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
  }

  // -------------------------------------------------------------------------
  // F6: Revoke join link
  // -------------------------------------------------------------------------

  Future<Response> _handleRevokeJoinLink(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) throw _unauthorized();
    final accountId = auth['account_id'] as String;
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final linkId = body['link_id'] as String?;
    if (linkId == null) {
      throw AppError.badRequest('Missing link_id');
    }
    final link = db.getGroupJoinLink(linkId);
    if (link == null) {
      throw AppError.notFound('Link not found');
    }
    final homeOnlyError = _requireHomeOnly(link['group_id'] as String);
    if (homeOnlyError != null) return homeOnlyError;
    if (!_isAdmin(link['group_id'] as String, accountId)) {
      throw AppError.forbidden('Only admins can revoke join links');
    }
    db.revokeGroupJoinLink(linkId);
    return Response.ok(
      jsonEncode({'link_id': linkId, 'revoked': true}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // -------------------------------------------------------------------------
  // F6: Join via link
  // -------------------------------------------------------------------------

  Future<Response> _handleJoinViaLink(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) throw _unauthorized();
    final accountId = auth['account_id'] as String;
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final token = body['token'] as String?;
    final requestId = body['request_id'] as String?;
    if (token == null || requestId == null) {
      throw AppError.badRequest('Missing token or request_id');
    }
    final link = db.getGroupJoinLinkByToken(token);
    if (link == null || (link['revoked_at'] as int) > 0) {
      throw AppError(
        'Join link is revoked or does not exist',
        statusCode: 410,
        code: RemoteErrorCode.conflict,
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if ((link['expires_at'] as int) < now) {
      throw AppError(
        'Join link has expired',
        statusCode: 410,
        code: RemoteErrorCode.conflict,
      );
    }
    final groupId = link['group_id'] as String;
    final homeOnlyError = _requireHomeOnly(groupId);
    if (homeOnlyError != null) return homeOnlyError;
    if (db.isConversationMember(groupId, accountId)) {
      throw AppError.conflict('Already a member');
    }
    if (db.isGroupMemberBlocked(groupId, accountId)) {
      throw AppError.forbidden('You cannot join this group');
    }
    if (db.countJoinRequestsLastHour(link['link_id'] as String) >=
        _joinRequestsPerLinkPerHour) {
      throw AppError.tooManyRequests('Too many join requests for this link');
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
  }

  // -------------------------------------------------------------------------
  // F6: Get pending join requests (admin only)
  // -------------------------------------------------------------------------

  Future<Response> _handleGetJoinRequests(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) throw _unauthorized();
    final accountId = auth['account_id'] as String;
    final groupId = request.url.queryParameters['group_id'];
    if (groupId == null) {
      throw AppError.badRequest('Missing group_id');
    }
    final homeOnlyError = _requireHomeOnly(groupId);
    if (homeOnlyError != null) return homeOnlyError;
    if (!_isAdmin(groupId, accountId)) {
      throw AppError.forbidden('Only admins can view join requests');
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
    if (auth == null) throw _unauthorized();
    final accountId = auth['account_id'] as String;
    final body =
        jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final requestId = body['request_id'] as String?;
    final approve = body['approve'] as bool?;
    if (requestId == null || approve == null) {
      throw AppError.badRequest('Missing request_id or approve');
    }
    final jr = db.getGroupJoinRequest(requestId);
    if (jr == null) {
      throw AppError.notFound('Request not found');
    }
    if (jr['status'] != 'PENDING') {
      throw AppError.conflict('Request is no longer pending');
    }
    final groupId = jr['group_id'] as String;
    final homeOnlyError = _requireHomeOnly(groupId);
    if (homeOnlyError != null) return homeOnlyError;
    if (!_isAdmin(groupId, accountId)) {
      throw AppError.forbidden('Only admins can approve join requests');
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
  }

  // -------------------------------------------------------------------------
  // F6: Transfer group ownership (creator protection)
  // -------------------------------------------------------------------------
}
