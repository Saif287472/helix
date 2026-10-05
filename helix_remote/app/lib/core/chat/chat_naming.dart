import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The conversation id prefix of a direct chat; the rest is the peer's
/// account id.
const _directPrefix = 'direct:';

/// The peer of a direct chat, or null for a group chat.
String? peerOfConversation(String conversationId) =>
    conversationId.startsWith(_directPrefix)
    ? conversationId.substring(_directPrefix.length)
    : null;

/// The title of a chat row or a conversation header: a person by the naming
/// rule, a group by its name.
String chatTitleOf(ConversationRow chat, PeopleDirectory people) {
  final peer = peerOfConversation(chat.id);
  if (peer != null) return people.displayOf(peer);
  final title = chat.title?.trim();
  return title == null || title.isEmpty ? 'Group' : title;
}

/// The avatar of a chat: a person's picture or initials, a group's glyph.
HelixAvatarModel chatAvatarOf(ConversationRow chat, PeopleDirectory people) {
  final peer = peerOfConversation(chat.id);
  if (peer != null) return people.avatarOf(peer);
  return HelixAvatarModel(
    name: chatTitleOf(chat, people),
    isGroup: true,
    colorIndex: HelixAvatarModel.colorIndexFor(chat.id),
  );
}

/// "typing..." in a direct chat; "Sam is typing..." in a group.
String typingLabelFor(
  String conversationId,
  Set<String> accounts,
  PeopleDirectory people,
) {
  if (peerOfConversation(conversationId) != null || accounts.isEmpty) {
    return 'typing...';
  }
  final names = [for (final a in accounts) people.firstNameOf(a)];
  if (names.length == 1) return '${names.first} is typing...';
  if (names.length == 2) return '${names[0]} and ${names[1]} are typing...';
  return '${names.length} people are typing...';
}
