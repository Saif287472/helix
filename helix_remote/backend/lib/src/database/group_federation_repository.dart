part of '../database.dart';

/// Which server is authoritative for a given group, from the perspective of
/// the server this database belongs to.
///
/// A group's home server is whichever server processed its `POST
/// /groups/create` call — the single source of truth for membership/roles.
/// Every other server hosting a member is a participant, holding a synced
/// read-model populated via `/api/v1/s2s/groups/sync`.
class GroupAuthority {
  const GroupAuthority({
    required this.isHome,
    required this.isParticipant,
    this.homeServerId,
    this.homeDomain,
  });

  final bool isHome;
  final bool isParticipant;
  final String? homeServerId;
  final String? homeDomain;

  bool get exists => isHome || isParticipant;
}

extension BackendGroupFederationRepository on BackendDatabase {
  GroupAuthority resolveGroupAuthority(String groupId) {
    if (getGroup(groupId) != null) {
      return const GroupAuthority(isHome: true, isParticipant: false);
    }
    final federated = getFederatedGroup(groupId);
    if (federated != null) {
      return GroupAuthority(
        isHome: false,
        isParticipant: true,
        homeServerId: federated['home_server_id'] as String,
        homeDomain: federated['home_domain'] as String,
      );
    }
    return const GroupAuthority(isHome: false, isParticipant: false);
  }

  /// Ensures a `conversations` row exists for a federated group on a
  /// participant server -- `federated_groups`, `conversation_members`, and
  /// `federated_conversation_members` all carry (or, for the latter two,
  /// conceptually assume) a FK to `conversations(conversation_id)`, but a
  /// participant never runs the home-only `createGroup`/`createConversation`
  /// paths that normally create that row.
  void ensureConversationShell(String groupId, String? name, int createdAt) {
    final stmt = _db.prepare('''
      INSERT INTO conversations (conversation_id, type, title, created_at, last_sequence)
      VALUES (?, 'GROUP', ?, ?, 0)
      ON CONFLICT(conversation_id) DO UPDATE SET title = excluded.title;
    ''');
    stmt.execute([groupId, name, createdAt]);
    stmt.close();
  }

  void upsertFederatedGroup({
    required String groupId,
    required String homeServerId,
    required String homeDomain,
    required String creatorId,
    String? name,
    required String encryptionKeyId,
    required String status,
    required String addPolicy,
    required int createdAt,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO federated_groups (
        group_id, home_server_id, home_domain, creator_id, name,
        encryption_key_id, status, add_policy, created_at, synced_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(group_id) DO UPDATE SET
        home_server_id = excluded.home_server_id,
        home_domain = excluded.home_domain,
        creator_id = excluded.creator_id,
        name = excluded.name,
        encryption_key_id = excluded.encryption_key_id,
        status = excluded.status,
        add_policy = excluded.add_policy,
        synced_at = excluded.synced_at;
    ''');
    stmt.execute([
      groupId,
      homeServerId,
      homeDomain,
      creatorId,
      name,
      encryptionKeyId,
      status,
      addPolicy,
      createdAt,
      now,
    ]);
    stmt.close();
  }

  Map<String, dynamic>? getFederatedGroup(String groupId) {
    final stmt = _db.prepare(
      'SELECT * FROM federated_groups WHERE group_id = ?;',
    );
    final res = stmt.select([groupId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'group_id': row['group_id'],
      'home_server_id': row['home_server_id'],
      'home_domain': row['home_domain'],
      'creator_id': row['creator_id'],
      'name': row['name'],
      'encryption_key_id': row['encryption_key_id'],
      'status': row['status'],
      'add_policy': row['add_policy'],
      'created_at': row['created_at'],
      'synced_at': row['synced_at'],
    };
  }

  /// Replaces this participant server's local read-model of a group's full
  /// roster. `members` entries carry fully-qualified account ids (even for
  /// members local to THIS server) so the split below can tell local from
  /// federated purely from the domain suffix, mirroring
  /// [BackendMessagingRepository.upsertConversationMemberRow].
  void applyFederatedGroupRoster({
    required String groupId,
    required List<Map<String, dynamic>> members,
    String? localDomain,
  }) {
    _db.execute('BEGIN TRANSACTION;');
    try {
      final clearLocal = _db.prepare(
        'DELETE FROM conversation_members WHERE conversation_id = ?;',
      );
      clearLocal.execute([groupId]);
      clearLocal.close();
      final clearFed = _db.prepare(
        'DELETE FROM federated_conversation_members WHERE conversation_id = ?;',
      );
      clearFed.execute([groupId]);
      clearFed.close();

      final normalizedLocalDomain = localDomain?.toLowerCase();
      for (final member in members) {
        final accountId = member['account_id'] as String;
        final role = member['role'] as String? ?? 'MEMBER';
        final at = accountId.lastIndexOf('@');
        final domain = (at > 0 && at < accountId.length - 1)
            ? accountId.substring(at + 1).toLowerCase()
            : null;
        if (domain == null) {
          upsertConversationMemberRow(groupId, accountId, role);
        } else if (normalizedLocalDomain != null &&
            domain == normalizedLocalDomain) {
          final bareId = accountId.substring(0, at);
          if (accountExists(bareId)) {
            upsertConversationMemberRow(groupId, bareId, role);
          }
        } else {
          final fedStmt = _db.prepare('''
            INSERT OR REPLACE INTO federated_conversation_members (
              conversation_id, account_id, domain, role
            )
            VALUES (?, ?, ?, ?);
          ''');
          fedStmt.execute([groupId, accountId, domain, role]);
          fedStmt.close();
        }
      }
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void upsertFederatedGroupInvite({
    required String inviteId,
    required String groupId,
    required String homeServerId,
    required String homeDomain,
    required String inviterId,
    required String inviteeId,
    required String status,
    required int createdAt,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO federated_group_invites (
        invite_id, group_id, home_server_id, home_domain,
        inviter_id, invitee_id, status, created_at, synced_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(invite_id) DO UPDATE SET
        status = excluded.status,
        synced_at = excluded.synced_at;
    ''');
    stmt.execute([
      inviteId,
      groupId,
      homeServerId,
      homeDomain,
      inviterId,
      inviteeId,
      status,
      createdAt,
      now,
    ]);
    stmt.close();
  }

  Map<String, dynamic>? getFederatedGroupInvite(String inviteId) {
    final stmt = _db.prepare(
      'SELECT * FROM federated_group_invites WHERE invite_id = ?;',
    );
    final res = stmt.select([inviteId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'invite_id': row['invite_id'],
      'group_id': row['group_id'],
      'home_server_id': row['home_server_id'],
      'home_domain': row['home_domain'],
      'inviter_id': row['inviter_id'],
      'invitee_id': row['invitee_id'],
      'status': row['status'],
      'created_at': row['created_at'],
    };
  }

  /// Domains currently hosting at least one federated member of this group,
  /// per this server's own view (either as home, or — for a participant
  /// self-healing — as recorded on its own mirror table).
  Set<String> getParticipatingDomains(String groupId) {
    return getFederatedConversationMembers(
      groupId,
    ).map((m) => m['domain'] as String).toSet();
  }

  // ---------------------------------------------------------------------
  // Membership/role checks that also see federated_conversation_members.
  // Only needed for *target*-account checks (e.g. "is the account being
  // removed a member"); the *actor* (authenticated local caller) is always
  // present in this server's own conversation_members once roster sync has
  // run, so existing isGroupAdmin/isConversationMember stay correct for
  // actor checks unchanged.
  // ---------------------------------------------------------------------

  bool isGroupMemberIncludingFederated(String groupId, String accountId) {
    if (isConversationMember(groupId, accountId)) return true;
    return isFederatedConversationMember(groupId, accountId);
  }

  String? getGroupMemberRoleIncludingFederated(
    String groupId,
    String accountId,
  ) {
    final local = getGroupMemberRole(groupId, accountId);
    if (local != null) return local;
    for (final member in getFederatedConversationMembers(groupId)) {
      if (member['account_id'] == accountId) return member['role'] as String;
    }
    return null;
  }

  int countGroupAdminsIncludingFederated(String groupId) {
    final federatedAdmins = getFederatedConversationMembers(
      groupId,
    ).where((m) => m['role'] == 'ADMIN').length;
    return countGroupAdmins(groupId) + federatedAdmins;
  }

  bool hasAnyGroupMembersIncludingFederated(String groupId) {
    if (getConversationMembers(groupId).isNotEmpty) return true;
    return getFederatedConversationMembers(groupId).isNotEmpty;
  }

  List<Map<String, dynamic>> getCombinedGroupMembers(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) {
    final local = getGroupMembersPaginated(
      groupId,
      limit: limit,
      offset: offset,
    );
    final federated = getFederatedConversationMembers(
      groupId,
    ).map((m) => {'account_id': m['account_id'], 'role': m['role']}).toList();
    return [...local, ...federated];
  }
}
