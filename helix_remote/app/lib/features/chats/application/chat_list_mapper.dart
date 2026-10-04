import 'package:helix_remote/core/chat/chat_naming.dart';
import 'package:helix_remote/core/chat/chat_people.dart';
import 'package:helix_remote/core/chat/message_semantics.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// One chat-list row from a database row.
///
/// [now] is the injected clock: a label like "Yesterday" depends on it, and a
/// widget must not.
HelixChatListItem chatListItemOf(
  ConversationListItem row, {
  required ChatPeople people,
  required String? selfId,
  required DateTime now,
}) {
  final chat = row.conversation;
  final peer = peerOfConversation(chat.id);
  final title = chatTitleOf(chat, people);
  return HelixChatListItem(
    id: chat.id,
    title: title,
    avatar: chatAvatarOf(chat, people),
    preview: _previewOf(row, people: people, selfId: selfId),
    timeLabel: formatChatTime(chat.lastMessageAt, now),
    unreadCount: chat.unreadCount,
    hasMention: chat.mentionCount > 0,
    pinned: chat.pinnedAt != null,
    muted: chat.mutedUntil?.isAfter(now) ?? false,
    archived: chat.archived,
    verified: peer != null && people.isVerified(peer),
  );
}

HelixChatPreview? _previewOf(
  ConversationListItem row, {
  required ChatPeople people,
  required String? selfId,
}) {
  final draft = row.conversation.draft?.trim();
  if (draft != null && draft.isNotEmpty) {
    return HelixChatPreview(text: draft, isDraft: true);
  }
  final last = row.lastMessage;
  if (last == null) return null;
  final isGroup = peerOfConversation(row.conversation.id) == null;
  final notice = systemNoticeText(last, selfId: selfId, people: people);
  if (isNoticeKind(last.kind)) {
    // Notices have no author and no tick: they are the chat talking.
    return HelixChatPreview(
      text: notice ?? '',
      kind: last.kind == 'call_log'
          ? HelixPreviewKind.call
          : HelixPreviewKind.text,
    );
  }
  final String? prefix;
  if (last.outgoing) {
    prefix = 'You';
  } else if (isGroup) {
    prefix = people.firstNameOf(last.sender);
  } else {
    prefix = null;
  }
  return HelixChatPreview(
    text: previewTextOf(last),
    kind: previewKindOf(last),
    senderPrefix: prefix,
    status: deliveryStatusOf(last),
  );
}
