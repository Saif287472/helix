import 'package:helix_remote/core/chat/chat_naming.dart';
import 'package:helix_remote/features/conversation/application/conversation_header.dart';
import 'package:helix_remote/shared/navigation/group_paths.dart';
import 'package:helix_remote/shared/navigation/people_paths.dart';

/// Where the info page of a conversation is: the other person's contact info
/// for a direct chat, the group's info for a group chat. Both belong to other
/// features (people, groups), so only their shared paths are known here.
/// Null for anything that is neither.
String? infoLocationOf(String conversationId) {
  final peer = peerOfConversation(conversationId);
  if (peer != null) return PeoplePaths.person(peer);
  final group = groupIdOf(conversationId);
  return group == null ? null : GroupPaths.info(group);
}
