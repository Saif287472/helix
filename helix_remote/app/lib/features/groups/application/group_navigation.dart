import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote/features/groups/application/groups_port.dart';
import 'package:helix_remote/shared/navigation/chat_locations.dart';

/// Where a group's **chat** opens, as a router location, or null when there
/// is none.
///
/// The group *conversation* belongs to the conversation feature, and features
/// never import each other, so the group screens ask this for "open the chat
/// of conversation `group:<id>`". It resolves to the conversation route
/// (`shared/navigation/chat_locations.dart`). A test overrides it with a
/// function returning null to see the fallback: the screens that would open
/// the chat (a new group, a finished join) open the group's info page
/// instead, so nothing is a dead end.
typedef GroupChatLocation = String? Function(String conversationId);

final groupChatLocationProvider = Provider<GroupChatLocation>(
  (ref) => chatLocation,
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
