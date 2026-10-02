/// Group chats live in `conversations` under `group:<group id>`, the group
/// twin of `direct:<peer account>`.
abstract final class GroupIds {
  static const _prefix = 'group:';

  /// The conversation id of group [groupId].
  static String conversationId(String groupId) => '$_prefix$groupId';

  static bool isGroupConversation(String conversationId) =>
      conversationId.startsWith(_prefix);

  /// The group id of a group conversation. Throws [ArgumentError] for any
  /// other conversation.
  static String groupIdOf(String conversationId) {
    if (!isGroupConversation(conversationId)) {
      throw ArgumentError.value(
        conversationId,
        'conversationId',
        'is not a group chat',
      );
    }
    return conversationId.substring(_prefix.length);
  }
}

/// Bounds the group code applies.
abstract final class GroupLimits {
  /// Groups with more members than this send no delivered or read receipts
  /// (every member would otherwise send one to the author per message).
  static const receiptsMaxMembers = 64;

  /// Epoch keys kept per group (the state blob is sealed under the epoch it
  /// was last written in, which can lag the group's epoch).
  static const keptEpochKeys = 4;

  /// Received sender keys kept per sending device (late messages of the
  /// previous key still arrive after a rotation).
  static const keptReceivedSenderKeys = 3;

  /// Versions conflicts retried when writing the group state.
  static const stateRetries = 4;
}

/// `system` message kinds the engine writes locally into a group chat from
/// roster changes (CONTENT_V2.md §2), plus the one it sends.
abstract final class GroupNoticeKinds {
  static const created = 'group_created';
  static const added = 'member_added';
  static const joined = 'member_joined';
  static const removed = 'member_removed';
  static const left = 'member_left';
  static const roleChanged = 'role_changed';
  static const settingsChanged = 'group_settings_changed';
  static const renamed = 'group_renamed';
  static const pictureChanged = 'group_picture_changed';
  static const joinRequested = 'join_requested';

  /// This device was removed from the group.
  static const youWereRemoved = 'you_were_removed';

  /// This account left the group (on this or another device).
  static const youLeft = 'you_left';
  static const deleted = 'group_deleted';
}
