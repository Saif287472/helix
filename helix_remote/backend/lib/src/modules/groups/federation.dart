part of '../groups.dart';

/// Milestone 4.1 plumbing: deciding whether an account is ours, proxying a
/// mutating action to the group's home server, and pushing roster snapshots
/// back out to participant servers.
///
/// Every handler mixin below leans on this one, which is why its members are
/// declared on [GroupsModuleBase] rather than only here.
mixin GroupsFederationHelpers on GroupsModuleBase {
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
      'event': ?event,
    };
  }

  // -------------------------------------------------------------------------
  // P16-001: Create group
  // -------------------------------------------------------------------------
}
