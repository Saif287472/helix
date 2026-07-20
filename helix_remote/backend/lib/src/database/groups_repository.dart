part of '../database.dart';

extension BackendGroupsRepository on BackendDatabase {
  // Group operations (P16-001 to P16-014)
  // ---------------------------------------------------------------------------

  /// Creates a GROUP conversation, group metadata row, and sets creator to
  /// ADMIN. This server becomes the group's home (authoritative) server;
  /// `homeDomain` is recorded so participant servers can be told where to
  /// proxy future admin actions. Member ids may be qualified (user@domain)
  /// for federated members — see [BackendMessagingRepository.upsertConversationMemberRow].
  void createGroup({
    required String groupId,
    required String name,
    required String creatorId,
    required String encryptionKeyId,
    required List<String> initialMemberIds,
    String? homeDomain,
  }) {
    _db.execute('BEGIN TRANSACTION;');
    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      final convStmt = _db.prepare('''
        INSERT OR REPLACE INTO conversations (conversation_id, type, title, created_at, last_sequence)
        VALUES (?, 'GROUP', ?, ?, 0);
      ''');
      convStmt.execute([groupId, name, now]);
      convStmt.close();

      final clearStmt = _db.prepare(
        'DELETE FROM conversation_members WHERE conversation_id = ?;',
      );
      clearStmt.execute([groupId]);
      clearStmt.close();
      final clearFedStmt = _db.prepare(
        'DELETE FROM federated_conversation_members WHERE conversation_id = ?;',
      );
      clearFedStmt.execute([groupId]);
      clearFedStmt.close();

      final allMembers = [
        ...initialMemberIds,
        if (!initialMemberIds.contains(creatorId)) creatorId,
      ];
      for (final memberId in allMembers) {
        final role = memberId == creatorId ? 'ADMIN' : 'MEMBER';
        upsertConversationMemberRow(groupId, memberId, role);
      }

      final grpStmt = _db.prepare('''
        INSERT OR REPLACE INTO groups (group_id, creator_id, encryption_key_id, status, created_at, home_domain)
        VALUES (?, ?, ?, 'ACTIVE', ?, ?);
      ''');
      grpStmt.execute([groupId, creatorId, encryptionKeyId, now, homeDomain]);
      grpStmt.close();

      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Map<String, dynamic>? getGroup(String groupId) {
    final stmt = _db.prepare('''
      SELECT g.*, c.title AS name FROM groups g
      JOIN conversations c ON c.conversation_id = g.group_id
      WHERE g.group_id = ?;
    ''');
    final res = stmt.select([groupId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'group_id': row['group_id'],
      'name': row['name'],
      'creator_id': row['creator_id'],
      'encryption_key_id': row['encryption_key_id'],
      'status': row['status'],
      'created_at': row['created_at'],
      'home_domain': row['home_domain'],
      'add_policy': row['add_policy'],
    };
  }

  bool isGroupAdmin(String groupId, String accountId) {
    final stmt = _db.prepare('''
      SELECT 1 FROM conversation_members
      WHERE conversation_id = ? AND account_id = ? AND role = 'ADMIN';
    ''');
    final res = stmt.select([groupId, accountId]);
    stmt.close();
    return res.isNotEmpty;
  }

  String? getGroupMemberRole(String groupId, String accountId) {
    final stmt = _db.prepare('''
      SELECT role FROM conversation_members
      WHERE conversation_id = ? AND account_id = ?;
    ''');
    final res = stmt.select([groupId, accountId]);
    stmt.close();
    if (res.isEmpty) return null;
    return res.first['role'] as String;
  }

  /// P16-013: Paginated member list.
  List<Map<String, dynamic>> getGroupMembersPaginated(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) {
    final stmt = _db.prepare('''
      SELECT account_id, role FROM conversation_members
      WHERE conversation_id = ?
      ORDER BY role DESC, account_id ASC
      LIMIT ? OFFSET ?;
    ''');
    final res = stmt.select([groupId, limit, offset]);
    stmt.close();
    return res
        .map((row) => {'account_id': row['account_id'], 'role': row['role']})
        .toList();
  }

  // P16-003: Invite lifecycle

  void createGroupInvite({
    required String inviteId,
    required String groupId,
    required String inviterId,
    required String inviteeId,
    int? createdAt,
  }) {
    final now = createdAt ?? DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO group_invites (invite_id, group_id, inviter_id, invitee_id, status, created_at)
      VALUES (?, ?, ?, ?, 'PENDING', ?);
    ''');
    stmt.execute([inviteId, groupId, inviterId, inviteeId, now]);
    stmt.close();
  }

  Map<String, dynamic>? getGroupInvite(String inviteId) {
    final stmt = _db.prepare(
      'SELECT * FROM group_invites WHERE invite_id = ?;',
    );
    final res = stmt.select([inviteId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'invite_id': row['invite_id'],
      'group_id': row['group_id'],
      'inviter_id': row['inviter_id'],
      'invitee_id': row['invitee_id'],
      'status': row['status'],
      'created_at': row['created_at'],
    };
  }

  bool hasOpenGroupInvite(String groupId, String inviteeId) {
    final stmt = _db.prepare('''
      SELECT 1 FROM group_invites
      WHERE group_id = ? AND invitee_id = ? AND status = 'PENDING';
    ''');
    final res = stmt.select([groupId, inviteeId]);
    stmt.close();
    return res.isNotEmpty;
  }

  /// Accepts invite: sets status=ACCEPTED, adds invitee as MEMBER.
  void acceptGroupInvite(String inviteId) {
    _db.execute('BEGIN TRANSACTION;');
    try {
      final invite = getGroupInvite(inviteId);
      if (invite == null) throw StateError('Invite not found: $inviteId');

      final updStmt = _db.prepare(
        "UPDATE group_invites SET status = 'ACCEPTED' WHERE invite_id = ?;",
      );
      updStmt.execute([inviteId]);
      updStmt.close();

      upsertConversationMemberRow(
        invite['group_id'] as String,
        invite['invitee_id'] as String,
        'MEMBER',
      );

      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void rejectGroupInvite(String inviteId) {
    final stmt = _db.prepare(
      "UPDATE group_invites SET status = 'REJECTED' WHERE invite_id = ?;",
    );
    stmt.execute([inviteId]);
    stmt.close();
  }

  void updateGroupInfo(String groupId, {String? name}) {
    if (name != null) {
      final stmt = _db.prepare(
        'UPDATE conversations SET title = ? WHERE conversation_id = ?;',
      );
      stmt.execute([name, groupId]);
      stmt.close();
    }
  }

  void changeGroupMemberRole(String groupId, String accountId, String role) {
    upsertConversationMemberRow(groupId, accountId, role);
  }

  void removeGroupMember(String groupId, String accountId) {
    removeConversationMemberRow(groupId, accountId);
  }

  int countGroupAdmins(String groupId) {
    final stmt = _db.prepare('''
      SELECT COUNT(*) FROM conversation_members
      WHERE conversation_id = ? AND role = 'ADMIN';
    ''');
    final res = stmt.select([groupId]);
    stmt.close();
    return res.first.columnAt(0) as int;
  }

  String? promoteFirstRemainingGroupMemberToAdmin(String groupId) {
    final stmt = _db.prepare('''
      SELECT account_id FROM conversation_members
      WHERE conversation_id = ?
      ORDER BY account_id ASC
      LIMIT 1;
    ''');
    final res = stmt.select([groupId]);
    stmt.close();
    if (res.isEmpty) return null;
    final promoted = res.first['account_id'] as String;
    changeGroupMemberRole(groupId, promoted, 'ADMIN');
    return promoted;
  }

  void expireGroupInvite(String inviteId) {
    final stmt = _db.prepare(
      "UPDATE group_invites SET status = 'EXPIRED' WHERE invite_id = ?;",
    );
    stmt.execute([inviteId]);
    stmt.close();
  }

  /// P16-010: Mark group DELETED and tombstone it.
  void deleteGroup(String groupId) {
    _db.execute('BEGIN TRANSACTION;');
    try {
      final updStmt = _db.prepare(
        "UPDATE groups SET status = 'DELETED' WHERE group_id = ?;",
      );
      updStmt.execute([groupId]);
      updStmt.close();

      saveTombstone(groupId, 'GROUP');

      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  // P16-014: Rate limits

  void logGroupCreation(String logId, String accountId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO group_creation_log (log_id, account_id, created_at)
      VALUES (?, ?, ?);
    ''');
    stmt.execute([logId, accountId, now]);
    stmt.close();
  }

  int countGroupCreationsLastDay(String accountId) {
    final since = DateTime.now().millisecondsSinceEpoch - 86400000;
    final stmt = _db.prepare('''
      SELECT COUNT(*) FROM group_creation_log
      WHERE account_id = ? AND created_at >= ?;
    ''');
    final res = stmt.select([accountId, since]);
    stmt.close();
    if (res.isEmpty) return 0;
    return res.first.columnAt(0) as int;
  }

  /// Returns the number of group invites sent by an inviter in the last hour.
  int countGroupInvitesLastHour(String inviterId) {
    final since = DateTime.now().millisecondsSinceEpoch - 3600000;
    final stmt = _db.prepare('''
      SELECT COUNT(*) FROM group_invites
      WHERE inviter_id = ? AND created_at >= ?;
    ''');
    final res = stmt.select([inviterId, since]);
    stmt.close();
    if (res.isEmpty) return 0;
    return res.first.columnAt(0) as int;
  }

  // ---------------------------------------------------------------------------
  // F6: Group-add privacy
  // ---------------------------------------------------------------------------

  void setGroupAddPolicy(String groupId, String policy) {
    final stmt = _db.prepare(
      "UPDATE groups SET add_policy = ? WHERE group_id = ?;",
    );
    stmt.execute([policy, groupId]);
    stmt.close();
  }

  String getGroupAddPolicy(String groupId) {
    final stmt = _db.prepare(
      'SELECT add_policy FROM groups WHERE group_id = ?;',
    );
    final res = stmt.select([groupId]);
    stmt.close();
    if (res.isEmpty) return 'EVERYONE';
    return res.first['add_policy'] as String? ?? 'EVERYONE';
  }

  // ---------------------------------------------------------------------------
  // F6: Creator protection and ownership transfer
  // ---------------------------------------------------------------------------

  bool isGroupCreatorProtected(String groupId, String accountId) {
    final stmt = _db.prepare('''
      SELECT creator_protected FROM groups
      WHERE group_id = ? AND creator_id = ?;
    ''');
    final res = stmt.select([groupId, accountId]);
    stmt.close();
    if (res.isEmpty) return false;
    return (res.first['creator_protected'] as int) == 1;
  }

  void transferGroupOwnership(String groupId, String newOwnerId) {
    _db.execute('BEGIN TRANSACTION;');
    try {
      // Update creator_id and clear creator_protected on the group.
      final updStmt = _db.prepare('''
        UPDATE groups SET creator_id = ?, creator_protected = 1
        WHERE group_id = ?;
      ''');
      updStmt.execute([newOwnerId, groupId]);
      updStmt.close();
      // New owner must be ADMIN.
      upsertConversationMemberRow(groupId, newOwnerId, 'ADMIN');
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // F6: Add member directly (for join-via-link without approval)
  // ---------------------------------------------------------------------------

  void addGroupMember(String groupId, String accountId) {
    upsertConversationMemberRow(groupId, accountId, 'MEMBER');
  }

  // ---------------------------------------------------------------------------
  // F6: Join links
  // ---------------------------------------------------------------------------

  void createGroupJoinLink({
    required String linkId,
    required String groupId,
    required String creatorId,
    required String token,
    required bool requiresApproval,
    required int expiresAt,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO group_join_links
        (link_id, group_id, creator_id, token, requires_approval, expires_at, revoked_at, created_at)
      VALUES (?, ?, ?, ?, ?, ?, 0, ?);
    ''');
    stmt.execute([
      linkId,
      groupId,
      creatorId,
      token,
      requiresApproval ? 1 : 0,
      expiresAt,
      DateTime.now().millisecondsSinceEpoch,
    ]);
    stmt.close();
  }

  Map<String, dynamic>? getGroupJoinLink(String linkId) {
    final stmt = _db.prepare(
      'SELECT * FROM group_join_links WHERE link_id = ?;',
    );
    final res = stmt.select([linkId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'link_id': row['link_id'],
      'group_id': row['group_id'],
      'creator_id': row['creator_id'],
      'token': row['token'],
      'requires_approval': row['requires_approval'],
      'expires_at': row['expires_at'],
      'revoked_at': row['revoked_at'],
      'created_at': row['created_at'],
    };
  }

  Map<String, dynamic>? getGroupJoinLinkByToken(String token) {
    final stmt = _db.prepare(
      'SELECT * FROM group_join_links WHERE token = ?;',
    );
    final res = stmt.select([token]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'link_id': row['link_id'],
      'group_id': row['group_id'],
      'token': row['token'],
      'requires_approval': row['requires_approval'],
      'expires_at': row['expires_at'],
      'revoked_at': row['revoked_at'],
    };
  }

  void revokeGroupJoinLink(String linkId) {
    final stmt = _db.prepare(
      'UPDATE group_join_links SET revoked_at = ? WHERE link_id = ?;',
    );
    stmt.execute([DateTime.now().millisecondsSinceEpoch, linkId]);
    stmt.close();
  }

  int countJoinLinksLastDay(String groupId, String creatorId) {
    final since = DateTime.now().millisecondsSinceEpoch - 86400000;
    final stmt = _db.prepare('''
      SELECT COUNT(*) FROM group_join_links
      WHERE group_id = ? AND creator_id = ? AND created_at >= ?;
    ''');
    final res = stmt.select([groupId, creatorId, since]);
    stmt.close();
    if (res.isEmpty) return 0;
    return res.first.columnAt(0) as int;
  }

  // ---------------------------------------------------------------------------
  // F6: Join requests
  // ---------------------------------------------------------------------------

  void createGroupJoinRequest({
    required String requestId,
    required String groupId,
    required String requesterId,
    required String linkId,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO group_join_requests
        (request_id, group_id, requester_id, link_id, status, created_at, updated_at)
      VALUES (?, ?, ?, ?, 'PENDING', ?, ?);
    ''');
    stmt.execute([requestId, groupId, requesterId, linkId, now, now]);
    stmt.close();
  }

  Map<String, dynamic>? getGroupJoinRequest(String requestId) {
    final stmt = _db.prepare(
      'SELECT * FROM group_join_requests WHERE request_id = ?;',
    );
    final res = stmt.select([requestId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'request_id': row['request_id'],
      'group_id': row['group_id'],
      'requester_id': row['requester_id'],
      'link_id': row['link_id'],
      'status': row['status'],
      'created_at': row['created_at'],
    };
  }

  List<Map<String, dynamic>> getPendingGroupJoinRequests(String groupId) {
    final stmt = _db.prepare('''
      SELECT * FROM group_join_requests
      WHERE group_id = ? AND status = 'PENDING'
      ORDER BY created_at ASC;
    ''');
    final res = stmt.select([groupId]);
    stmt.close();
    return res
        .map(
          (row) => {
            'request_id': row['request_id'],
            'group_id': row['group_id'],
            'requester_id': row['requester_id'],
            'link_id': row['link_id'],
            'status': row['status'],
            'created_at': row['created_at'],
          },
        )
        .toList();
  }

  void updateGroupJoinRequestStatus(String requestId, String status) {
    final stmt = _db.prepare('''
      UPDATE group_join_requests
      SET status = ?, updated_at = ?
      WHERE request_id = ?;
    ''');
    stmt.execute([status, DateTime.now().millisecondsSinceEpoch, requestId]);
    stmt.close();
  }

  int countJoinRequestsLastHour(String linkId) {
    final since = DateTime.now().millisecondsSinceEpoch - 3600000;
    final stmt = _db.prepare('''
      SELECT COUNT(*) FROM group_join_requests
      WHERE link_id = ? AND created_at >= ?;
    ''');
    final res = stmt.select([linkId, since]);
    stmt.close();
    if (res.isEmpty) return 0;
    return res.first.columnAt(0) as int;
  }

  // ---------------------------------------------------------------------------
  // F6: Blocked members
  // ---------------------------------------------------------------------------

  void addGroupBlockedMember({
    required String groupId,
    required String accountId,
    required String createdBy,
  }) {
    final stmt = _db.prepare('''
      INSERT OR IGNORE INTO group_blocked_members
        (group_id, account_id, created_by, created_at)
      VALUES (?, ?, ?, ?);
    ''');
    stmt.execute([groupId, accountId, createdBy, DateTime.now().millisecondsSinceEpoch]);
    stmt.close();
  }

  bool isGroupMemberBlocked(String groupId, String accountId) {
    final stmt = _db.prepare('''
      SELECT 1 FROM group_blocked_members
      WHERE group_id = ? AND account_id = ?;
    ''');
    final res = stmt.select([groupId, accountId]);
    stmt.close();
    return res.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // F6: Moderated messages
  // ---------------------------------------------------------------------------

  void saveGroupModeratedMessage({
    required String messageId,
    required String groupId,
    required String moderatedBy,
    required int moderatedAt,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO group_moderated_messages
        (message_id, group_id, moderated_by, moderated_at)
      VALUES (?, ?, ?, ?);
    ''');
    stmt.execute([messageId, groupId, moderatedBy, moderatedAt]);
    stmt.close();
  }

  bool isGroupMessageModerated(String groupId, String messageId) {
    final stmt = _db.prepare(
      'SELECT 1 FROM group_moderated_messages WHERE group_id = ? AND message_id = ?;',
    );
    final rows = stmt.select([groupId, messageId]);
    stmt.close();
    return rows.isNotEmpty;
  }
}
