part of '../groups_screen.dart';

class _GroupRowData {
  const _GroupRowData({
    required this.conversationId,
    required this.title,
    required this.memberCount,
    required this.isAdmin,
    required this.notificationPolicy,
    required this.unreadMentionCount,
  });

  final String conversationId;
  final String title;
  final int memberCount;
  final bool isAdmin;
  final String notificationPolicy;
  final int unreadMentionCount;
}
