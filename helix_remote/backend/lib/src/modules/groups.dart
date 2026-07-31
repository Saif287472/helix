import 'dart:async';
import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
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
class GroupsModule {
  GroupsModule(
    this.db,
    this.wsRelay, {
    this.federationClient,
    this.localDomain,
  });

  final BackendDatabase db;
  final MessageRelay wsRelay;
  final FederationClient? federationClient;
  final String? localDomain;

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
    // Milestone 4.2: group Sender Key epoch distribution.
    r.post('/epoch-key/deliver', _handleDeliverEpochKey);
    return r;
  }

  // -------------------------------------------------------------------------
  // Milestone 4.1: federation helpers
  // -------------------------------------------------------------------------

  bool _isExternal(String accountId) {
    final at = accountId.lastIndexOf('@');
    if (at <= 0 || at == accountId.length - 1) return false;
    final domain = accountId.substring(at + 1).toLowerCase();
    return localDomain == null || domain != localDomain!.toLowerCase();
  }

  String _qualify(String accountId) {
    if (accountId.contains('@') ||
        localDomain == null ||
        localDomain!.isEmpty) {
      return accountId;
    }
    return '$accountId@${localDomain!.toLowerCase()}';
  }

  /// Federation-aware admin check: true if `accountId` is ADMIN either in
  /// this server's local `conversation_members` or (once roster sync has
  /// run) in `federated_conversation_members`. Used for every actor check
  /// in this module instead of `db.isGroupAdmin` directly, since an action
  /// proxied from a participant server carries a qualified acting-account
  /// id that only ever appears in the federated table.
  bool _isAdmin(String groupId, String accountId) =>
      db.getGroupMemberRoleIncludingFederated(groupId, accountId) == 'ADMIN';

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
      return Response.badRequest(
        body: jsonEncode({'error': 'Unknown group action: $action'}),
      );
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

  /// Forwards a mutating action to the group's home server and translates
  /// its response (including error status/body) back verbatim.
  Future<Response> _proxyToHome(
    GroupAuthority authority,
    String groupId,
    String action,
    String actingAccountId,
    Map<String, dynamic> payload,
  ) async {
    if (federationClient == null) {
      return Response(
        503,
        body: jsonEncode({'error': 'Federation is not configured'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    try {
      final result = await federationClient!.proxyGroupAction(
        homeDomain: authority.homeDomain!,
        groupId: groupId,
        action: action,
        actingAccountId: _qualify(actingAccountId),
        payload: payload,
      );
      return Response.ok(
        jsonEncode(result),
        headers: {'Content-Type': 'application/json'},
      );
    } on FederationHttpException catch (e) {
      return Response(
        e.statusCode,
        body: e.body.isNotEmpty
            ? e.body
            : jsonEncode({'error': 'Group home server rejected the request'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (_) {
      return Response(
        502,
        body: jsonEncode({'error': 'Failed to reach group home server'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Guard for handlers not yet supported cross-server (join-link
  /// management, Phase 4.1 v1 scope cut): null if this server is home for
  /// `groupId` (proceed normally); an explicit error Response otherwise.
  Response? _requireHomeOnly(String groupId) {
    final authority = db.resolveGroupAuthority(groupId);
    if (authority.isHome) return null;
    if (authority.isParticipant) {
      return Response(
        409,
        body: jsonEncode({
          'error':
              'Join-link management must be performed on the group\'s home server (${authority.homeDomain}).',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return Response.notFound(jsonEncode({'error': 'Group not found'}));
  }

  /// Pushes the current group snapshot (metadata + full roster) to every
  /// domain in `domains` (fire-and-forget; failures fall back to the
  /// outbox for retry). Callers must pass the union of participating
  /// domains from *before* and *after* their mutation, so both newly-added
  /// and fully-departed domains get notified.
  /// Awaited (bounded by the normal HTTP timeout to each participant) so
  /// that, on the happy path, a caller's response only arrives once every
  /// reachable participant has the update — matching how Milestone 3's
  /// federated message proxy already behaves. An unreachable/slow
  /// participant doesn't fail the whole request: its push falls back to
  /// the outbox for retry instead of propagating the error.
  Future<void> _broadcastGroupSync(
    String groupId,
    Set<String> domains, {
    Map<String, dynamic>? event,
  }) async {
    if (federationClient == null || domains.isEmpty) return;
    final snapshot = _buildGroupSyncSnapshot(groupId, event: event);
    await Future.wait(
      domains.map((domain) => _sendGroupSync(groupId, domain, snapshot)),
    );
  }

  Future<void> _sendGroupSync(
    String groupId,
    String domain,
    Map<String, dynamic> snapshot,
  ) async {
    try {
      await federationClient!.syncGroupState(domain: domain, body: snapshot);
    } catch (_) {
      db.enqueueOutbox(
        's2s_grpsync_${groupId}_${domain}_${DateTime.now().millisecondsSinceEpoch}',
        'S2S_GROUP_SYNC',
        jsonEncode({'domain': domain, 'body': snapshot}),
      );
    }
  }

  Map<String, dynamic> _buildGroupSyncSnapshot(
    String groupId, {
    Map<String, dynamic>? event,
  }) {
    final group = db.getGroup(groupId);
    final members = <Map<String, dynamic>>[
      for (final id in db.getConversationMembers(groupId))
        {
          'account_id': _qualify(id),
          'role':
              db.getGroupMemberRoleIncludingFederated(groupId, id) ?? 'MEMBER',
        },
      for (final member in db.getFederatedConversationMembers(groupId))
        {'account_id': member['account_id'], 'role': member['role']},
    ];
    return {
      'group_id': groupId,
      'home_server_id': federationClient!.identity.serverId,
      'home_domain': localDomain,
      'name': group?['name'],
      'creator_id': _qualify(group?['creator_id'] as String? ?? ''),
      'encryption_key_id': group?['encryption_key_id'] ?? '',
      'status': group?['status'] ?? 'ACTIVE',
      'add_policy': group?['add_policy'] ?? 'EVERYONE',
      'created_at':
          group?['created_at'] ?? DateTime.now().millisecondsSinceEpoch,
      'members': members,
      if (event != null) 'event': event,
    };
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
        return Response.notFound(jsonEncode({'error': 'Group not found'}));
      }

      if (!_isAdmin(groupId, accountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Only admins can change group-add policy'}),
        );
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
      final homeOnlyError = _requireHomeOnly(groupId);
      if (homeOnlyError != null) return homeOnlyError;
      if (!_isAdmin(groupId, accountId)) {
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
      final homeOnlyError = _requireHomeOnly(link['group_id'] as String);
      if (homeOnlyError != null) return homeOnlyError;
      if (!_isAdmin(link['group_id'] as String, accountId)) {
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
      final homeOnlyError = _requireHomeOnly(groupId);
      if (homeOnlyError != null) return homeOnlyError;
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
    final homeOnlyError = _requireHomeOnly(groupId);
    if (homeOnlyError != null) return homeOnlyError;
    if (!_isAdmin(groupId, accountId)) {
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
      final homeOnlyError = _requireHomeOnly(groupId);
      if (homeOnlyError != null) return homeOnlyError;
      if (!_isAdmin(groupId, accountId)) {
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

  /// Batched delivery of pairwise-wrapped group epoch keys (see
  /// `packages/helix_remote_groups`' `RemoteGroupService`). Any current
  /// admin — home or federated participant — may rotate and redistribute
  /// keys; this is deliberately not gated to the group's home server the
  /// way membership/role mutations are, since key material distribution
  /// doesn't require a single mutation authority, only that the sender is
  /// a legitimate admin (checked via [_isAdmin], which already sees
  /// federated admins once roster sync has run).
  Future<Response> _handleDeliverEpochKey(Request request) async {
    final auth = request.context['auth'] as Map<String, dynamic>?;
    if (auth == null) return _unauthorized();
    final accountId = auth['account_id'] as String;
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final groupId = body['group_id'] as String?;
      final epoch = body['epoch'] as int?;
      final keyId = body['key_id'] as String?;
      final rawDeliveries = body['deliveries'] as List?;
      if (groupId == null ||
          epoch == null ||
          keyId == null ||
          rawDeliveries == null) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'Missing group_id, epoch, key_id, or deliveries',
          }),
        );
      }
      if (!db.resolveGroupAuthority(groupId).exists) {
        return Response.notFound(jsonEncode({'error': 'Group not found'}));
      }
      if (!_isAdmin(groupId, accountId)) {
        return Response.forbidden(
          jsonEncode({'error': 'Only admins can distribute group keys'}),
        );
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final byDomain = <String, List<Map<String, dynamic>>>{};
      var localCount = 0;
      for (final raw in rawDeliveries) {
        final delivery = raw as Map<String, dynamic>;
        final recipientAccountId = delivery['recipient_account_id'] as String?;
        final recipientDeviceId = delivery['recipient_device_id'] as String?;
        final wrappedKey = delivery['wrapped_key'] as String?;
        if (recipientAccountId == null ||
            recipientDeviceId == null ||
            wrappedKey == null) {
          continue;
        }
        if (_isExternal(recipientAccountId)) {
          final domain = FederationClient.domainOf(recipientAccountId)!;
          (byDomain[domain] ??= []).add({
            'group_id': groupId,
            'epoch': epoch,
            'key_id': keyId,
            'sender_account_id': _qualify(accountId),
            'recipient_account_id': recipientAccountId,
            'recipient_device_id': recipientDeviceId,
            'wrapped_key': wrappedKey,
          });
          continue;
        }
        if (!db.isDeviceActive(recipientAccountId, recipientDeviceId)) continue;
        localCount++;
        final eventId = 'grp_epoch_${groupId}_${epoch}_$recipientDeviceId';
        final deviceSeq = db.writeDeviceEvent(
          eventId: eventId,
          recipientDeviceId: recipientDeviceId,
          eventType: 'group_epoch_key',
          payload: jsonEncode({
            'group_id': groupId,
            'epoch': epoch,
            'key_id': keyId,
            'sender_account_id': _qualify(accountId),
            'wrapped_key': wrappedKey,
          }),
        );
        wsRelay.sendToDevice(recipientDeviceId, {
          'event_id': eventId,
          'schema_version': 1,
          'timestamp': now,
          'type': 'group_epoch_key',
          'payload': {
            'group_id': groupId,
            'epoch': epoch,
            'key_id': keyId,
            'sender_account_id': _qualify(accountId),
            'wrapped_key': wrappedKey,
          },
          'server_sequence': deviceSeq,
        });
      }

      var federatedDomainCount = 0;
      if (byDomain.isNotEmpty) {
        if (federationClient == null) {
          return Response(
            503,
            body: jsonEncode({'error': 'Federation is not configured'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
        federatedDomainCount = byDomain.length;
        await Future.wait(
          byDomain.entries.map((entry) async {
            try {
              await federationClient!.deliverEpochKeyBatch(
                domain: entry.key,
                deliveries: entry.value,
              );
            } catch (_) {
              db.enqueueOutbox(
                's2s_epochkey_${groupId}_${epoch}_${entry.key}_${DateTime.now().millisecondsSinceEpoch}',
                'S2S_EPOCH_KEY',
                jsonEncode({'domain': entry.key, 'deliveries': entry.value}),
              );
            }
          }),
        );
      }

      return Response.ok(
        jsonEncode({
          'group_id': groupId,
          'epoch': epoch,
          'local_deliveries': localCount,
          'federated_domains': federatedDomainCount,
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
    if (!db.hasAnyGroupMembersIncludingFederated(groupId)) return null;
    if (db.countGroupAdminsIncludingFederated(groupId) > 0) return null;
    if (db.getConversationMembers(groupId).isNotEmpty) {
      return db.promoteFirstRemainingGroupMemberToAdmin(groupId);
    }
    // No local members remain (federation-only group as seen from home) —
    // promote the alphabetically-first federated member instead.
    final federatedMembers = db.getFederatedConversationMembers(groupId);
    if (federatedMembers.isEmpty) return null;
    final sorted = [...federatedMembers]
      ..sort(
        (a, b) =>
            (a['account_id'] as String).compareTo(b['account_id'] as String),
      );
    final promoted = sorted.first['account_id'] as String;
    db.changeGroupMemberRole(groupId, promoted, 'ADMIN');
    return promoted;
  }

  Response _unauthorized() => Response(
    401,
    body: jsonEncode({'error': 'Unauthorized'}),
    headers: {'Content-Type': 'application/json'},
  );
}
