import 'dart:convert';

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
    this.encryptionKeyProvider,
  });

  final HelixRemoteDatabase db;

  /// Injectable ID generator — allows deterministic IDs in tests.
  final String Function() generateId;

  /// P16-004: Injectable encryption key provider. Returns an opaque key
  /// identifier for the group at the given epoch. In production this would
  /// call into helix_remote_crypto (GroupSenderChain). In tests a stub is
  /// supplied. Never generates production crypto internally.
  final String Function(String groupId, int epoch)? encryptionKeyProvider;

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
    final encKeyId =
        encryptionKeyProvider?.call(groupId, 0) ?? 'key_${groupId}_epoch_0';
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

    final payload = {
      'group_id': groupId,
      'name': name,
      'creator_id': creatorId,
      'encryption_key_id': encKeyId,
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

    db.enqueueOperation(
      generateId(),
      kGroupOpLeave,
      jsonEncode({'group_id': groupId, 'account_id': selfAccountId}),
      idempotencyKey: 'group_leave_${groupId}_$selfAccountId',
    );
  }

  /// Admin removes [accountId] from [groupId].
  /// P16-005: Triggers key epoch increment so remaining members can rotate.
  void removeMember({required String groupId, required String accountId}) {
    db.removeConversationMember(groupId, accountId);

    // P16-005: Membership change requires a key epoch bump so the removed
    // member loses forward access. Production key material is rotated by
    // the server and delivered to remaining devices via group_key_updated.
    _bumpEpoch(groupId);

    db.enqueueOperation(
      generateId(),
      kGroupOpRemoveMember,
      jsonEncode({'group_id': groupId, 'account_id': accountId}),
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

  void _bumpEpoch(String groupId) {
    db.updateGroupEpoch(groupId, getGroupEpoch(groupId) + 1);
  }
}
