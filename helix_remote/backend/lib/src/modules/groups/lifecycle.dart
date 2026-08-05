part of '../groups.dart';

/// The group itself: create it, read it back, rename it, delete it.
/// Membership changes live in [GroupsMembershipHandlers].
mixin GroupsLifecycleHandlers on GroupsModuleBase {
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

      if (initialMemberIds.any(_isExternal) && federationClient == null) {
        return Response(
          503,
          body: jsonEncode({'error': 'Federation is not configured'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      db.createGroup(
        groupId: groupId,
        name: name,
        creatorId: accountId,
        encryptionKeyId: encryptionKeyId,
        initialMemberIds: initialMemberIds,
        homeDomain: localDomain,
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

      // Milestone 4.1: if any initial members are federated, tell their
      // home servers about the new group right away.
      await _broadcastGroupSync(
        groupId,
        db.getParticipatingDomains(groupId),
        event: {
          'type': 'group_created',
          'action': 'created',
          'actor_id': _qualify(accountId),
        },
      );

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
    if (group != null) {
      return Response.ok(
        jsonEncode(group),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Milestone 4.1: this server is a participant for this group — serve
    // its synced read-model instead.
    final federated = db.getFederatedGroup(groupId);
    if (federated == null) {
      return Response.notFound(jsonEncode({'error': 'Group not found'}));
    }
    return Response.ok(
      jsonEncode({
        'group_id': federated['group_id'],
        'name': federated['name'],
        'creator_id': federated['creator_id'],
        'encryption_key_id': federated['encryption_key_id'],
        'status': federated['status'],
        'created_at': federated['created_at'],
        'add_policy': federated['add_policy'],
        'is_federated': true,
        'home_domain': federated['home_domain'],
      }),
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
    final members = db.getCombinedGroupMembers(
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

      final authority = db.resolveGroupAuthority(groupId);
      if (authority.isParticipant) {
        return _proxyToHome(authority, groupId, 'update', accountId, body);
      }
      if (!authority.isHome) {
        return Response.notFound(jsonEncode({'error': 'Group not found'}));
      }

      if (!_isAdmin(groupId, accountId)) {
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
      await _broadcastGroupSync(
        groupId,
        db.getParticipatingDomains(groupId),
        event: adminEvent,
      );

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

      final authority = db.resolveGroupAuthority(groupId);
      if (authority.isParticipant) {
        return _proxyToHome(authority, groupId, 'delete', accountId, body);
      }
      if (!authority.isHome) {
        return Response.notFound(jsonEncode({'error': 'Group not found'}));
      }

      if (!_isAdmin(groupId, accountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Only admins can delete a group'}),
        );
      }

      final domains = db.getParticipatingDomains(groupId);

      // Notify all members before deletion so they can clean up locally.
      final deletePayload = {
        'type': 'group_deleted',
        'group_id': groupId,
        'deleted_by': accountId,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      _relayToGroupMembers(groupId, deletePayload);
      await _broadcastGroupSync(groupId, domains, event: deletePayload);

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
}
