import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote/features/groups/application/groups_port.dart';

/// Where a group's **chat** opens, as a router location, or null when the
/// conversation feature has not registered one.
///
/// **The seam for the conversation screen.** The group *conversation* belongs
/// to the chats feature, and features never import each other, so the group
/// screens ask this for "open the chat of conversation `group:<id>`". The
/// composition root overrides it with the conversation route, for example
/// `groupChatLocationProvider.overrideWithValue((id) => '/home/chat/$id')`.
/// Until it does, the screens that would open the chat (a new group, a
/// finished join) open the group's info page instead, so nothing is a dead
/// end.
typedef GroupChatLocation = String? Function(String conversationId);

final groupChatLocationProvider = Provider<GroupChatLocation>(
  (ref) =>
      (conversationId) => null,
);

/// The conversation id of group [groupId] (`group:<id>`), the id the chats
/// feature uses.
String groupConversationId(String groupId) => 'group:$groupId';

/// Something happened to [groupId] that the open screen should say: this
/// device was removed, left, or the group was deleted; or someone asked to
/// join. Stays open for as long as a screen listens.
final groupSignalsProvider = StreamProvider.autoDispose
    .family<GroupSignal, String>((ref, groupId) async* {
      final port = await ref.watch(groupsPortProvider.future);
      yield* port.signals(groupId);
    });
