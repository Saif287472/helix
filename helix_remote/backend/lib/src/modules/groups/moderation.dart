part of '../groups.dart';

/// Admin actions against content and people rather than the group's own
/// settings: deleting someone else's message, blocking a member.
mixin GroupsModerationHandlers on GroupsModuleBase {
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

      final authority = db.resolveGroupAuthority(groupId);
      if (authority.isParticipant) {
        return _proxyToHome(
          authority,
          groupId,
          'admin_delete_message',
          accountId,
          body,
        );
      }
      if (!authority.isHome) {
        return Response.notFound(jsonEncode({'error': 'Group not found'}));
      }

      if (!_isAdmin(groupId, accountId)) {
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
      final moderatePayload = {
        'type': 'group_admin_event',
        'group_id': groupId,
        'action': 'message_moderated',
        'message_id': messageId,
        'actor_id': accountId,
        'timestamp': now,
      };
      _relayToGroupMembers(groupId, moderatePayload);
      await _broadcastGroupSync(
        groupId,
        db.getParticipatingDomains(groupId),
        event: moderatePayload,
      );
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

      final authority = db.resolveGroupAuthority(groupId);
      if (authority.isParticipant) {
        return _proxyToHome(
          authority,
          groupId,
          'block_member',
          accountId,
          body,
        );
      }
      if (!authority.isHome) {
        return Response.notFound(jsonEncode({'error': 'Group not found'}));
      }

      if (!_isAdmin(groupId, accountId)) {
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
      if (db.isGroupMemberIncludingFederated(groupId, targetId)) {
        final domainsBefore = db.getParticipatingDomains(groupId);
        db.removeGroupMember(groupId, targetId);
        final blockPayload = {
          'type': 'membership_changed',
          'group_id': groupId,
          'conversation_id': groupId,
          'account_id': targetId,
          'action': 'removed',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        _relayToGroupMembers(groupId, blockPayload);
        await _broadcastGroupSync(groupId, {
          ...domainsBefore,
          ...db.getParticipatingDomains(groupId),
        }, event: blockPayload);
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
  // Milestone 4.2: Sender Key epoch distribution
  // -------------------------------------------------------------------------
}
