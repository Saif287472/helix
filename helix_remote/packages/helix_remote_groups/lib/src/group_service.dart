import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:helix_remote_domain/models.dart';
import 'package:helix_remote_storage/helix_remote_storage.dart';

// P16-002: Persistent member roles.
const String kRoleAdmin = 'ADMIN';
const String kRoleMember = 'MEMBER';

// Invite lifecycle statuses.
const String kInviteStatusPending = 'PENDING';
const String kInviteStatusAccepted = 'ACCEPTED';
const String kInviteStatusRejected = 'REJECTED';

// Pending-operation type constants used by RemoteSyncEngine outbound queue.
const String kGroupOpCreate = 'group_create';
const String kGroupOpInvite = 'group_invite';
const String kGroupOpInviteRespond = 'group_invite_respond';
const String kGroupOpUpdate = 'group_update';
const String kGroupOpMemberRole = 'group_member_role';
const String kGroupOpLeave = 'group_leave';
const String kGroupOpRemoveMember = 'group_remove_member';
const String kGroupOpDelete = 'group_delete';
// F6 operation types.
const String kGroupOpSetAddPolicy = 'group_set_add_policy';
const String kGroupOpCreateJoinLink = 'group_create_join_link';
const String kGroupOpRevokeJoinLink = 'group_revoke_join_link';
const String kGroupOpJoinViaLink = 'group_join_via_link';
const String kGroupOpApproveJoinRequest = 'group_approve_join_request';
const String kGroupOpTransferOwnership = 'group_transfer_ownership';
const String kGroupOpAdminDeleteMessage = 'group_admin_delete_message';
const String kGroupOpBlockMember = 'group_block_member';

// Group-add privacy policy values.
const String kGroupAddPolicyEveryone = 'EVERYONE';
const String kGroupAddPolicyContacts = 'CONTACTS';
const String kGroupAddPolicyContactsExcept = 'CONTACTS_EXCEPT';
const String kGroupAddPolicyNobody = 'NOBODY';

// Group notification policy values.
const String kGroupNotificationAll = 'ALL';
const String kGroupNotificationMentionsOnly = 'MENTIONS_ONLY';
const String kGroupNotificationAdminOnly = 'ADMIN_ONLY';
const String kGroupNotificationMuted = 'MUTED';

/// Orchestrates Remote group lifecycle: create, invite, membership management,
/// admin events, leave/remove, and deletion.
///
/// P16-016: Remote group authority is the creator/ADMIN role stored in the
/// conversation_members table. Local LAN host-election (helix_local_groups)
/// is NOT imported or referenced here. All group decisions go through the
/// Remote backend and are propagated via the sync event stream.
class RemoteGroupService {
  const RemoteGroupService({
    required this.db,
    required this.generateId,
    required this.encryptionKeyProvider,
  });

  final HelixRemoteDatabase db;

  /// Injectable ID generator — allows deterministic IDs in tests.
  final String Function() generateId;

  /// P16-004: Injectable encryption key provider. Returns an opaque key
  /// identifier for the group at the given epoch. In production this would
  /// call into helix_remote_crypto (GroupSenderChain). In tests a stub is
  /// supplied. Required — no fallback (P16-004 closure).
  final String Function(String groupId, int epoch) encryptionKeyProvider;

  // ---------------------------------------------------------------------------
  // P16-001: Persistent group identity
  // ---------------------------------------------------------------------------

  /// Creates a new group with [creatorId] as the first ADMIN.
  void createGroup({
    required String groupId,
    required String name,
    required String creatorId,
    String? avatarUri,
    List<String> initialMemberIds = const [],
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;

    final allMembers = [
      ...initialMemberIds,
      if (!initialMemberIds.contains(creatorId)) creatorId,
    ];

    // Persist local conversation record (type=GROUP).
    db.upsertConversation(
      RemoteConversation(
        conversationId: groupId,
        title: name,
        type: 'GROUP',
        lastActivitySequence: 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(now),
      ),
      allMembers,
    );

    // P16-002: Creator is ADMIN; all others start as MEMBER.
    db.upsertConversationMember(groupId, creatorId, role: kRoleAdmin);

    // Persist group-specific metadata (name, creator, epoch).
    db.upsertGroupMetadata(
      groupId: groupId,
      name: name,
      creatorId: creatorId,
      avatarUri: avatarUri,
      epoch: 0,
    );
    final epochKey = _persistEpochKey(groupId, 0, now);

    final payload = {
      'group_id': groupId,
      'name': name,
      'creator_id': creatorId,
      'epoch': 0,
      'encryption_key_id': epochKey.keyId,
      'initial_member_ids': allMembers,
    };
    if (avatarUri != null) {
      payload['avatar_uri'] = avatarUri;
    }

    db.enqueueOperation(
      generateId(),
      kGroupOpCreate,
      jsonEncode(payload),
      idempotencyKey: 'group_create_$groupId',
    );
  }

  // ---------------------------------------------------------------------------
  // P16-003: Invite/join approval rules
  // ---------------------------------------------------------------------------

  /// Invites [inviteeId] to [groupId]. The invite is locally recorded as
  /// PENDING and queued for server delivery.
  void inviteMember({
    required String groupId,
    required String inviteId,
    required String inviterId,
    required String inviteeId,
  }) {
    db.upsertGroupInvite(
      inviteId: inviteId,
      groupId: groupId,
      inviterId: inviterId,
      status: kInviteStatusPending,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    db.enqueueOperation(
      generateId(),
      kGroupOpInvite,
      jsonEncode({
        'invite_id': inviteId,
        'group_id': groupId,
        'invitee_id': inviteeId,
      }),
      idempotencyKey: 'group_invite_$inviteId',
    );
  }

  /// Responds to an inbound invite. On [accept], the caller is optimistically
  /// added to the local member list pending server confirmation.
  void respondToInvite({
    required String inviteId,
    required String selfAccountId,
    required bool accept,
  }) {
    final invite = db.getGroupInvite(inviteId);
    if (invite == null) return;

    final groupId = invite['group_id'] as String;
    final newStatus = accept ? kInviteStatusAccepted : kInviteStatusRejected;

    db.upsertGroupInvite(
      inviteId: inviteId,
      groupId: groupId,
      inviterId: invite['inviter_id'] as String,
      status: newStatus,
      createdAt: invite['created_at'] as int,
    );

    if (accept) {
      db.upsertConversationMember(groupId, selfAccountId, role: kRoleMember);
      _rotateEpoch(groupId);
    }

    db.enqueueOperation(
      generateId(),
      kGroupOpInviteRespond,
      jsonEncode({'invite_id': inviteId, 'accept': accept}),
      idempotencyKey: 'group_invite_respond_$inviteId',
    );
  }

  // ---------------------------------------------------------------------------
  // P16-002: Persistent membership and roles
  // ---------------------------------------------------------------------------

  /// Returns all member account IDs for [groupId].
  List<String> getGroupMembers(String groupId) =>
      db.getConversationMembers(groupId);

  /// Returns members with their roles [{account_id, role}].
  List<Map<String, dynamic>> getGroupMembersWithRoles(String groupId) =>
      db.getGroupMembersWithRoles(groupId);

  // ---------------------------------------------------------------------------
  // P16-006 + P16-013: Persistent group message history with pagination
  // ---------------------------------------------------------------------------

  /// Fetches group messages. Ciphertext only — content never decrypted here.
  /// [limit] and [offset] implement large-group pagination (P16-013).
  List<Map<String, dynamic>> getGroupMessages(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) => db.getMessages(groupId, limit: limit, offset: offset);

  // ---------------------------------------------------------------------------
  // P16-008: Admin events
  // ---------------------------------------------------------------------------

  /// Updates group name or avatar (caller must be ADMIN).
  void updateGroupInfo({
    required String groupId,
    String? name,
    String? avatarUri,
  }) {
    final existing = db.getGroupMetadata(groupId);
    if (existing != null) {
      db.upsertGroupMetadata(
        groupId: groupId,
        name: name ?? existing['name'] as String,
        creatorId: existing['creator_id'] as String,
        avatarUri: avatarUri ?? existing['avatar_uri'] as String?,
        epoch: existing['epoch'] as int,
      );
    }

    final payload = {'group_id': groupId};
    if (name != null) {
      payload['name'] = name;
    }
    if (avatarUri != null) {
      payload['avatar_uri'] = avatarUri;
    }

    db.enqueueOperation(
      generateId(),
      kGroupOpUpdate,
      jsonEncode(payload),
      idempotencyKey:
          'group_update_${groupId}_${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  /// Promotes or demotes [accountId] in [groupId] (caller must be ADMIN).
  void changeMemberRole({
    required String groupId,
    required String accountId,
    required String role,
  }) {
    db.upsertConversationMember(groupId, accountId, role: role);

    db.enqueueOperation(
      generateId(),
      kGroupOpMemberRole,
      jsonEncode({'group_id': groupId, 'account_id': accountId, 'role': role}),
      idempotencyKey: 'group_role_${groupId}_$accountId',
    );
  }

  // ---------------------------------------------------------------------------
  // P16-009: Leave/remove/block behavior
  // ---------------------------------------------------------------------------

  /// The authenticated user leaves [groupId].
  void leaveGroup({required String groupId, required String selfAccountId}) {
    db.removeConversationMember(groupId, selfAccountId);
    final epochKey = _rotateEpoch(groupId);

    db.enqueueOperation(
      generateId(),
      kGroupOpLeave,
      jsonEncode({
        'group_id': groupId,
        'account_id': selfAccountId,
        'epoch': epochKey.epoch,
        'encryption_key_id': epochKey.keyId,
      }),
      idempotencyKey: 'group_leave_${groupId}_$selfAccountId',
    );
  }

  /// Admin removes [accountId] from [groupId].
  /// P16-005: Triggers key epoch increment so remaining members can rotate.
  void removeMember({required String groupId, required String accountId}) {
    db.removeConversationMember(groupId, accountId);

    final epochKey = _rotateEpoch(groupId);

    db.enqueueOperation(
      generateId(),
      kGroupOpRemoveMember,
      jsonEncode({
        'group_id': groupId,
        'account_id': accountId,
        'epoch': epochKey.epoch,
        'encryption_key_id': epochKey.keyId,
      }),
      idempotencyKey: 'group_remove_${groupId}_$accountId',
    );
  }

  // ---------------------------------------------------------------------------
  // P16-010: Group deletion
  // ---------------------------------------------------------------------------

  /// Admin deletes [groupId]. Tombstone written locally; server notifies
  /// all remaining members.
  void deleteGroup(String groupId) {
    db.saveTombstone(groupId, 'GROUP');

    db.enqueueOperation(
      generateId(),
      kGroupOpDelete,
      jsonEncode({'group_id': groupId}),
      idempotencyKey: 'group_delete_$groupId',
    );
  }

  // ---------------------------------------------------------------------------
  // P16-005: Membership-change key epoch
  // ---------------------------------------------------------------------------

  /// Returns the current key epoch for [groupId]. Epoch increments whenever
  /// a member is removed so remaining members know to re-key.
  int getGroupEpoch(String groupId) {
    final meta = db.getGroupMetadata(groupId);
    return meta?['epoch'] as int? ?? 0;
  }

  Map<String, dynamic>? getGroupEpochKey(String groupId, int epoch) =>
      db.getGroupEpochKey(groupId, epoch);

  _GroupEpochKey _rotateEpoch(String groupId) {
    final nextEpoch = getGroupEpoch(groupId) + 1;
    db.updateGroupEpoch(groupId, nextEpoch);
    return _persistEpochKey(
      groupId,
      nextEpoch,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  _GroupEpochKey _persistEpochKey(String groupId, int epoch, int createdAt) {
    final keyMaterial = encryptionKeyProvider(groupId, epoch);
    if (keyMaterial.isEmpty) {
      throw StateError('Group epoch key material must not be empty');
    }
    final keyId = _deriveKeyId(groupId, epoch, keyMaterial);
    db.saveGroupEpochKey(
      groupId: groupId,
      epoch: epoch,
      keyId: keyId,
      keyMaterial: keyMaterial,
      createdAt: createdAt,
    );
    return _GroupEpochKey(epoch: epoch, keyId: keyId);
  }

  String _deriveKeyId(String groupId, int epoch, String keyMaterial) {
    final digest = crypto.sha256.convert(
      utf8.encode('helix.remote.group.epoch.v1:$groupId:$epoch:$keyMaterial'),
    );
    return 'gk_${digest.toString().substring(0, 32)}';
  }

  // ---------------------------------------------------------------------------
  // F6: Group-add privacy
  // ---------------------------------------------------------------------------

  /// Sets the group-add privacy policy. Queues server update.
  void setGroupAddPolicy({
    required String groupId,
    required String policy,
    String contactsExceptJson = '[]',
  }) {
    db.upsertGroupAddPolicy(
      groupId: groupId,
      policy: policy,
      contactsExceptJson: contactsExceptJson,
    );
    db.enqueueOperation(
      generateId(),
      kGroupOpSetAddPolicy,
      jsonEncode({'group_id': groupId, 'policy': policy}),
      idempotencyKey: 'group_add_policy_$groupId',
    );
  }

  String getGroupAddPolicy(String groupId) {
    final meta = db.getGroupAddPolicy(groupId);
    return meta?['policy'] as String? ?? kGroupAddPolicyEveryone;
  }

  // ---------------------------------------------------------------------------
  // F6: Join links
  // ---------------------------------------------------------------------------

  /// Creates a join link. [token] must be 32 cryptographically-random bytes
  /// base64url-encoded (caller supplies it for testability).
  void createJoinLink({
    required String linkId,
    required String groupId,
    required String token,
    required bool requiresApproval,
    required int expiresAt,
  }) {
    db.upsertGroupJoinLink(
      linkId: linkId,
      groupId: groupId,
      token: token,
      requiresApproval: requiresApproval,
      expiresAt: expiresAt,
    );
    db.enqueueOperation(
      generateId(),
      kGroupOpCreateJoinLink,
      jsonEncode({
        'link_id': linkId,
        'group_id': groupId,
        'token': token,
        'requires_approval': requiresApproval,
        'expires_at': expiresAt,
      }),
      idempotencyKey: 'group_create_link_$linkId',
    );
  }

  void revokeJoinLink({required String groupId, required String linkId}) {
    db.revokeGroupJoinLink(linkId);
    db.enqueueOperation(
      generateId(),
      kGroupOpRevokeJoinLink,
      jsonEncode({'link_id': linkId, 'group_id': groupId}),
      idempotencyKey: 'group_revoke_link_$linkId',
    );
  }

  List<Map<String, dynamic>> getActiveJoinLinks(String groupId) =>
      db.getActiveGroupJoinLinks(groupId);

  // ---------------------------------------------------------------------------
  // F6: Join requests (received from server events)
  // ---------------------------------------------------------------------------

  void recordJoinRequest({
    required String requestId,
    required String groupId,
    required String requesterId,
    required String linkId,
    String status = 'PENDING',
  }) {
    db.upsertGroupJoinRequest(
      requestId: requestId,
      groupId: groupId,
      requesterId: requesterId,
      linkId: linkId,
      status: status,
    );
  }

  List<Map<String, dynamic>> getPendingJoinRequests(String groupId) =>
      db.getPendingGroupJoinRequests(groupId);

  void approveJoinRequest({
    required String requestId,
    required String groupId,
    required bool approve,
  }) {
    db.upsertGroupJoinRequest(
      requestId: requestId,
      groupId: groupId,
      requesterId: '',
      linkId: '',
      status: approve ? 'APPROVED' : 'REJECTED',
    );
    db.enqueueOperation(
      generateId(),
      kGroupOpApproveJoinRequest,
      jsonEncode({
        'request_id': requestId,
        'group_id': groupId,
        'approve': approve,
      }),
      idempotencyKey: 'group_approve_request_$requestId',
    );
  }

  // ---------------------------------------------------------------------------
  // F6: Ownership transfer
  // ---------------------------------------------------------------------------

  void transferOwnership({
    required String groupId,
    required String newOwnerId,
    required String selfAccountId,
  }) {
    // The server is the authoritative decision-maker; queue the operation.
    db.enqueueOperation(
      generateId(),
      kGroupOpTransferOwnership,
      jsonEncode({
        'group_id': groupId,
        'new_owner_id': newOwnerId,
        'current_owner_id': selfAccountId,
      }),
      idempotencyKey: 'group_transfer_ownership_$groupId',
    );
  }

  // ---------------------------------------------------------------------------
  // F6: Admin moderation deletion
  // ---------------------------------------------------------------------------

  void adminDeleteMessage({
    required String groupId,
    required String messageId,
    required String moderatorId,
  }) {
    db.saveGroupModeratedMessage(
      messageId: messageId,
      groupId: groupId,
      moderatedBy: moderatorId,
    );
    db.enqueueOperation(
      generateId(),
      kGroupOpAdminDeleteMessage,
      jsonEncode({'group_id': groupId, 'message_id': messageId}),
      idempotencyKey: 'group_admin_delete_${groupId}_$messageId',
    );
  }

  bool isMessageModerated(String messageId) =>
      db.isGroupMessageModerated(messageId);

  // ---------------------------------------------------------------------------
  // F6: Blocked member management
  // ---------------------------------------------------------------------------

  void blockMember({required String groupId, required String accountId}) {
    db.addGroupBlockedMember(groupId: groupId, accountId: accountId);
    db.enqueueOperation(
      generateId(),
      kGroupOpBlockMember,
      jsonEncode({'group_id': groupId, 'account_id': accountId}),
      idempotencyKey: 'group_block_${groupId}_$accountId',
    );
  }

  bool isMemberBlocked(String groupId, String accountId) =>
      db.isGroupMemberBlocked(groupId, accountId);

  // ---------------------------------------------------------------------------
  // F6: Mention index
  // ---------------------------------------------------------------------------

  void indexMention({
    required String mentionId,
    required String conversationId,
    required String messageId,
    required String mentionedAccountId,
    required int serverSequence,
  }) {
    db.insertGroupMention(
      mentionId: mentionId,
      conversationId: conversationId,
      messageId: messageId,
      mentionedAccountId: mentionedAccountId,
      serverSequence: serverSequence,
    );
  }

  List<Map<String, dynamic>> getUnreadMentions(
    String conversationId,
    String accountId,
  ) => db.getUnreadMentions(conversationId, accountId);

  void markMentionRead(String mentionId) => db.markMentionRead(mentionId);

  // ---------------------------------------------------------------------------
  // F6: Notification policy
  // ---------------------------------------------------------------------------

  void setGroupNotificationPolicy({
    required String groupId,
    required String policy,
  }) {
    db.upsertGroupNotificationPolicy(groupId: groupId, policy: policy);
  }

  String getGroupNotificationPolicy(String groupId) =>
      db.getGroupNotificationPolicy(groupId);

  // ---------------------------------------------------------------------------
  // F6: Epoch key deliveries (pairwise-wrapped distribution)
  // ---------------------------------------------------------------------------

  /// Records a wrapped epoch key delivery for [recipientDeviceId]. The
  /// [wrappedKey] is opaque ciphertext encrypted with the recipient device's
  /// agreement public key; only that device can unwrap it.
  void recordEpochKeyDelivery({
    required String deliveryId,
    required String groupId,
    required int epoch,
    required String keyId,
    required String recipientDeviceId,
    required String wrappedKey,
  }) {
    db.saveGroupEpochKeyDelivery(
      deliveryId: deliveryId,
      groupId: groupId,
      epoch: epoch,
      keyId: keyId,
      recipientDeviceId: recipientDeviceId,
      wrappedKey: wrappedKey,
    );
  }

  List<Map<String, dynamic>> getPendingEpochKeyDeliveries(String groupId) =>
      db.getPendingEpochKeyDeliveries(groupId);

  void markEpochKeyDelivered(String deliveryId) =>
      db.markEpochKeyDelivered(deliveryId);
}

class _GroupEpochKey {
  const _GroupEpochKey({required this.epoch, required this.keyId});

  final int epoch;
  final String keyId;
}
