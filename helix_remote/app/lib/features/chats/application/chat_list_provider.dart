import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/chat/chat_naming.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/features/chats/application/chat_list_mapper.dart';
import 'package:orbit_ui/models.dart';

/// The chat list, as the components want it.
///
/// Every list in this app is a [StreamProvider] over a drift watch query
/// (plan §6.4): the engine owns the query, this maps rows into the plain value
/// objects in `orbit_ui` with the people-naming rule applied, and the
/// widgets never see a row, a column or a clock.
///
/// It waits for the people table once, so the first frame shows names rather
/// than "Orbit user ..." placeholders that then change.
final chatListProvider = StreamProvider<List<HelixChatListItem>>((ref) async* {
  final gateway = await ref.watch(chatGatewayProvider.future);
  final people = await ref.watch(peopleDirectoryProvider.future);
  final now = ref.watch(clockProvider);
  final self = gateway.selfAccountId;
  yield* gateway.watchChats().map(
    (rows) => [
      for (final row in rows)
        chatListItemOf(row, people: people, selfId: self, now: now()),
    ],
  );
});

/// The archived chats, in the same shape.
final archivedChatListProvider = StreamProvider<List<HelixChatListItem>>((
  ref,
) async* {
  final gateway = await ref.watch(chatGatewayProvider.future);
  final people = await ref.watch(peopleDirectoryProvider.future);
  final now = ref.watch(clockProvider);
  final self = gateway.selfAccountId;
  yield* gateway
      .watchChats(archived: true)
      .map(
        (rows) => [
          for (final row in rows)
            chatListItemOf(row, people: people, selfId: self, now: now()),
        ],
      );
});

/// The locked chats, in the same shape. Read only by the Locked chats screen
/// (behind the unlock) and for the count that decides whether the menu offers
/// it.
final lockedChatListProvider = StreamProvider<List<HelixChatListItem>>((
  ref,
) async* {
  final gateway = await ref.watch(chatGatewayProvider.future);
  final people = await ref.watch(peopleDirectoryProvider.future);
  final now = ref.watch(clockProvider);
  final self = gateway.selfAccountId;
  yield* gateway.watchLockedChats().map(
    (rows) => [
      for (final row in rows)
        chatListItemOf(row, people: people, selfId: self, now: now()),
    ],
  );
});

/// Who is typing where, as the finished label a row shows. Kept apart from
/// [chatListProvider] so a typing indicator never rebuilds 5,000 rows; each
/// visible row selects its own entry.
final chatTypingProvider = StreamProvider<Map<String, String>>((ref) async* {
  final gateway = await ref.watch(chatGatewayProvider.future);
  final people = await ref.watch(peopleDirectoryProvider.future);
  yield* gateway.watchAllTyping().map(
    (typing) => {
      for (final entry in typing.entries)
        entry.key: typingLabelFor(entry.key, entry.value, people),
    },
  );
});

/// One row's typing label, or null.
final chatTypingLabelProvider = Provider.family<String?, String>(
  (ref, conversationId) =>
      ref.watch(chatTypingProvider.select((m) => m.value?[conversationId])),
);

/// The person's own lists, as the chips of the Chats tab.
final chatListsProvider = StreamProvider<List<HelixChatList>>((ref) async* {
  final gateway = await ref.watch(chatGatewayProvider.future);
  yield* gateway.watchChatLists().map(
    (rows) => [for (final r in rows) HelixChatList(id: r.id, name: r.name)],
  );
});

/// For each chat, the ids of the lists it is on.
final chatListMembershipProvider = StreamProvider<Map<String, List<String>>>((
  ref,
) async* {
  final gateway = await ref.watch(chatGatewayProvider.future);
  yield* gateway.watchChatListMembers().map((rows) {
    final byChat = <String, List<String>>{};
    for (final r in rows) {
      (byChat[r.conversationId] ??= []).add(r.listId);
    }
    return byChat;
  });
});
