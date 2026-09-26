part of '../database.dart';

mixin RemoteGroupsRepository on HelixRemoteDatabaseBase {
  // ---------------------------------------------------------------------------
  // Group metadata (P16-001, P16-008)
  // ---------------------------------------------------------------------------

  void upsertGroupMetadata({
    required String groupId,
    required String name,
    required String creatorId,
    String? avatarUri,
    int epoch = 0,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO groups (group_id, name, owner_id, status, avatar_uri, creator_id, epoch)
      VALUES (?, ?, ?, 'ACTIVE', ?, ?, ?)
      ON CONFLICT(group_id) DO UPDATE SET
        name = excluded.name,
        avatar_uri = excluded.avatar_uri,
        epoch = excluded.epoch;
    ''');
    stmt.execute([groupId, name, creatorId, avatarUri, creatorId, epoch]);
    stmt.close();
  }

  Map<String, dynamic>? getGroupMetadata(String groupId) {
    final stmt = _db.prepare('SELECT * FROM groups WHERE group_id = ?;');
    final res = stmt.select([groupId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'group_id': row['group_id'],
      'name': row['name'],
      'creator_id': row['creator_id'] ?? row['owner_id'],
      'avatar_uri': row['avatar_uri'],
      'epoch': row['epoch'] ?? 0,
      'status': row['status'],
    };
  }

  /// P16-005: Increment the key epoch after a membership change.
  void updateGroupEpoch(String groupId, int epoch) {
    final stmt = _db.prepare('UPDATE groups SET epoch = ? WHERE group_id = ?;');
    stmt.execute([epoch, groupId]);
    stmt.close();
  }

  void saveGroupEpochKey({
    required String groupId,
    required int epoch,
    required String keyId,
    required String keyMaterial,
    required int createdAt,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO group_epoch_keys
        (group_id, epoch, key_id, key_material, created_at)
      VALUES (?, ?, ?, ?, ?);
    ''');
    stmt.execute([groupId, epoch, keyId, keyMaterial, createdAt]);
    stmt.close();
  }

  void upsertGroupEpochKey({
    required String groupId,
    required int epoch,
    required String keyId,
    required String keyMaterial,
    required int createdAt,
  }) =>
      saveGroupEpochKey(
        groupId: groupId,
        epoch: epoch,
        keyId: keyId,
        keyMaterial: keyMaterial,
        createdAt: createdAt,
      );

  Map<String, dynamic>? getGroupEpochKey(String groupId, int epoch) {
    final stmt = _db.prepare('''
      SELECT * FROM group_epoch_keys
      WHERE group_id = ? AND epoch = ?;
    ''');
    final res = stmt.select([groupId, epoch]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'group_id': row['group_id'],
      'epoch': row['epoch'],
      'key_id': row['key_id'],
      'key_material': row['key_material'],
      'created_at': row['created_at'],
    };
  }

  List<Map<String, dynamic>> getGroupEpochKeys(String groupId) {
    final stmt = _db.prepare('''
      SELECT * FROM group_epoch_keys
      WHERE group_id = ?
      ORDER BY epoch ASC;
    ''');
    final res = stmt.select([groupId]);
    stmt.close();
    return res
        .map(
          (row) => {
            'group_id': row['group_id'],
            'epoch': row['epoch'],
            'key_id': row['key_id'],
            'key_material': row['key_material'],
            'created_at': row['created_at'],
          },
        )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Group invites (P16-003)
  // ---------------------------------------------------------------------------

  void upsertGroupInvite({
    required String inviteId,
    required String groupId,
    required String inviterId,
    required String status,
    required int createdAt,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO group_invites (invite_id, group_id, inviter_id, status, created_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(invite_id) DO UPDATE SET status = excluded.status;
    ''');
    stmt.execute([inviteId, groupId, inviterId, status, createdAt]);
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
      'status': row['status'],
      'created_at': row['created_at'],
    };
  }

  List<Map<String, dynamic>> getGroupInvites() {
    final stmt = _db.prepare(
      "SELECT * FROM group_invites WHERE status = 'PENDING' ORDER BY created_at DESC;",
    );
    final res = stmt.select();
    stmt.close();
    return res
        .map(
          (row) => {
            'invite_id': row['invite_id'],
            'group_id': row['group_id'],
            'inviter_id': row['inviter_id'],
            'status': row['status'],
            'created_at': row['created_at'],
          },
        )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Members with roles (P16-002)
  // ---------------------------------------------------------------------------

  List<Map<String, dynamic>> getGroupMembersWithRoles(String conversationId) {
    final stmt = _db.prepare(
      'SELECT account_id, role FROM members WHERE conversation_id = ?;',
    );
    final res = stmt.select([conversationId]);
    stmt.close();
    return res
        .map((row) => {'account_id': row['account_id'], 'role': row['role']})
        .toList();
  }

  // ---------------------------------------------------------------------------
  // F6: Group-add privacy (schema v19)
  // ---------------------------------------------------------------------------

  void upsertGroupAddPolicy({
    required String groupId,
    required String policy,
    String contactsExceptJson = '[]',
  }) {
    final stmt = _db.prepare('''
      INSERT INTO group_add_policy (group_id, policy, contacts_except_json, updated_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(group_id) DO UPDATE SET
        policy = excluded.policy,
        contacts_except_json = excluded.contacts_except_json,
        updated_at = excluded.updated_at;
    ''');
    stmt.execute([
      groupId,
      policy,
      contactsExceptJson,
      DateTime.now().millisecondsSinceEpoch,
    ]);
    stmt.close();
  }

  Map<String, dynamic>? getGroupAddPolicy(String groupId) {
    final stmt = _db.prepare(
      'SELECT * FROM group_add_policy WHERE group_id = ?;',
    );
    final res = stmt.select([groupId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'group_id': row['group_id'],
      'policy': row['policy'],
      'contacts_except_json': row['contacts_except_json'],
      'updated_at': row['updated_at'],
    };
  }

  // ---------------------------------------------------------------------------
  // F6: Join links (schema v19)
  // ---------------------------------------------------------------------------

  void upsertGroupJoinLink({
    required String linkId,
    required String groupId,
    required String token,
    required bool requiresApproval,
    required int expiresAt,
    int revokedAt = 0,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO group_join_links
        (link_id, group_id, token, requires_approval, expires_at, revoked_at, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(link_id) DO UPDATE SET
        revoked_at = excluded.revoked_at;
    ''');
    stmt.execute([
      linkId,
      groupId,
      token,
      requiresApproval ? 1 : 0,
      expiresAt,
      revokedAt,
      DateTime.now().millisecondsSinceEpoch,
    ]);
    stmt.close();
  }

  List<Map<String, dynamic>> getActiveGroupJoinLinks(String groupId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      SELECT * FROM group_join_links
      WHERE group_id = ? AND revoked_at = 0 AND expires_at > ?
      ORDER BY created_at DESC;
    ''');
    final res = stmt.select([groupId, now]);
    stmt.close();
    return res
        .map(
          (row) => {
            'link_id': row['link_id'],
            'group_id': row['group_id'],
            'token': row['token'],
            'requires_approval': (row['requires_approval'] as int) == 1,
            'expires_at': row['expires_at'],
            'created_at': row['created_at'],
          },
        )
        .toList();
  }

  void revokeGroupJoinLink(String linkId) {
    final stmt = _db.prepare(
      'UPDATE group_join_links SET revoked_at = ? WHERE link_id = ?;',
    );
    stmt.execute([DateTime.now().millisecondsSinceEpoch, linkId]);
    stmt.close();
  }

  // ---------------------------------------------------------------------------
  // F6: Join requests (schema v19)
  // ---------------------------------------------------------------------------

  void upsertGroupJoinRequest({
    required String requestId,
    required String groupId,
    required String requesterId,
    required String linkId,
    required String status,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO group_join_requests
        (request_id, group_id, requester_id, link_id, status, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(request_id) DO UPDATE SET
        status = excluded.status,
        updated_at = excluded.updated_at;
    ''');
    stmt.execute([requestId, groupId, requesterId, linkId, status, now, now]);
    stmt.close();
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

  /// Records the outcome of a join request an admin decided.
  ///
  /// The decision arrives as a `group_join_request_resolved` push, so without
  /// this the row stays `PENDING` locally and a decided request keeps showing
  /// in the "Join Requests" list. Only the status is written: the approval path
  /// also relays a `membership_changed`, which is what adds the member.
  void updateGroupJoinRequestStatus({
    required String requestId,
    required String status,
  }) {
    final stmt = _db.prepare('''
      UPDATE group_join_requests
      SET status = ?, updated_at = ?
      WHERE request_id = ?;
    ''');
    stmt.execute([
      status,
      DateTime.now().millisecondsSinceEpoch,
      requestId,
    ]);
    stmt.close();
  }

  // ---------------------------------------------------------------------------
  // F6: Blocked members (schema v19)
  // ---------------------------------------------------------------------------

  void addGroupBlockedMember({
    required String groupId,
    required String accountId,
  }) {
    final stmt = _db.prepare('''
      INSERT OR IGNORE INTO group_blocked_members (group_id, account_id, created_at)
      VALUES (?, ?, ?);
    ''');
    stmt.execute([groupId, accountId, DateTime.now().millisecondsSinceEpoch]);
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
  // F6: Epoch key deliveries (schema v19)
  // ---------------------------------------------------------------------------

  void saveGroupEpochKeyDelivery({
    required String deliveryId,
    required String groupId,
    required int epoch,
    required String keyId,
    required String recipientDeviceId,
    required String wrappedKey,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO group_epoch_key_deliveries
        (delivery_id, group_id, epoch, key_id, recipient_device_id, wrapped_key, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      deliveryId,
      groupId,
      epoch,
      keyId,
      recipientDeviceId,
      wrappedKey,
      DateTime.now().millisecondsSinceEpoch,
    ]);
    stmt.close();
  }

  List<Map<String, dynamic>> getPendingEpochKeyDeliveries(String groupId) {
    final stmt = _db.prepare('''
      SELECT * FROM group_epoch_key_deliveries
      WHERE group_id = ? AND delivered_at = 0
      ORDER BY epoch ASC;
    ''');
    final res = stmt.select([groupId]);
    stmt.close();
    return res
        .map(
          (row) => {
            'delivery_id': row['delivery_id'],
            'group_id': row['group_id'],
            'epoch': row['epoch'],
            'key_id': row['key_id'],
            'recipient_device_id': row['recipient_device_id'],
            'wrapped_key': row['wrapped_key'],
          },
        )
        .toList();
  }

  void markEpochKeyDelivered(String deliveryId) {
    final stmt = _db.prepare(
      'UPDATE group_epoch_key_deliveries SET delivered_at = ? WHERE delivery_id = ?;',
    );
    stmt.execute([DateTime.now().millisecondsSinceEpoch, deliveryId]);
    stmt.close();
  }

  // ---------------------------------------------------------------------------
  // F6: Mention index (schema v19)
  // ---------------------------------------------------------------------------

  void insertGroupMention({
    required String mentionId,
    required String conversationId,
    required String messageId,
    required String mentionedAccountId,
    required int serverSequence,
  }) {
    final stmt = _db.prepare('''
      INSERT OR IGNORE INTO group_mention_index
        (mention_id, conversation_id, message_id, mentioned_account_id, server_sequence)
      VALUES (?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      mentionId,
      conversationId,
      messageId,
      mentionedAccountId,
      serverSequence,
    ]);
    stmt.close();
  }

  List<Map<String, dynamic>> getUnreadMentions(
    String conversationId,
    String accountId,
  ) {
    final stmt = _db.prepare('''
      SELECT * FROM group_mention_index
      WHERE conversation_id = ? AND mentioned_account_id = ? AND read_at = 0
      ORDER BY server_sequence ASC;
    ''');
    final res = stmt.select([conversationId, accountId]);
    stmt.close();
    return res
        .map(
          (row) => {
            'mention_id': row['mention_id'],
            'conversation_id': row['conversation_id'],
            'message_id': row['message_id'],
            'server_sequence': row['server_sequence'],
          },
        )
        .toList();
  }

  void markMentionRead(String mentionId) {
    final stmt = _db.prepare(
      'UPDATE group_mention_index SET read_at = ? WHERE mention_id = ?;',
    );
    stmt.execute([DateTime.now().millisecondsSinceEpoch, mentionId]);
    stmt.close();
  }

  // ---------------------------------------------------------------------------
  // F6: Notification policy (schema v19)
  // ---------------------------------------------------------------------------

  void upsertGroupNotificationPolicy({
    required String groupId,
    required String policy,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO group_notification_policy (group_id, policy, updated_at)
      VALUES (?, ?, ?)
      ON CONFLICT(group_id) DO UPDATE SET
        policy = excluded.policy,
        updated_at = excluded.updated_at;
    ''');
    stmt.execute([groupId, policy, DateTime.now().millisecondsSinceEpoch]);
    stmt.close();
  }

  String getGroupNotificationPolicy(String groupId) {
    final stmt = _db.prepare(
      'SELECT policy FROM group_notification_policy WHERE group_id = ?;',
    );
    final res = stmt.select([groupId]);
    stmt.close();
    if (res.isEmpty) return 'ALL';
    return res.first['policy'] as String;
  }

  // ---------------------------------------------------------------------------
  // F6: Moderated messages (schema v19)
  // ---------------------------------------------------------------------------

  void saveGroupModeratedMessage({
    required String messageId,
    required String groupId,
    required String moderatedBy,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO group_moderated_messages
        (message_id, group_id, moderated_by, moderated_at)
      VALUES (?, ?, ?, ?);
    ''');
    stmt.execute([
      messageId,
      groupId,
      moderatedBy,
      DateTime.now().millisecondsSinceEpoch,
    ]);
    stmt.close();
  }

  bool isGroupMessageModerated(String messageId) {
    final stmt = _db.prepare(
      'SELECT 1 FROM group_moderated_messages WHERE message_id = ?;',
    );
    final res = stmt.select([messageId]);
    stmt.close();
    return res.isNotEmpty;
  }
}
