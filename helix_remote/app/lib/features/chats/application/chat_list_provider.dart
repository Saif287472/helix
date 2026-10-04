import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/chat/chat_naming.dart';
import 'package:helix_remote/core/chat/chat_people.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/features/chats/application/chat_list_mapper.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The chat list, as the components want it.
///
/// Every list in this app is a [StreamProvider] over a drift watch query
/// (plan §6.4): the engine owns the query, this maps rows into the plain value
/// objects in `helix_remote_ui` with the people-naming rule applied, and the
/// widgets never see a row, a column or a clock.
///
/// It waits for the people table once, so the first frame shows names rather
/// than "Helix user ..." placeholders that then change.
final chatListProvider = StreamProvider<List<HelixChatListItem>>((ref) async* {
  final gateway = await ref.watch(chatGatewayProvider.future);
  final people = await ref.watch(chatPeopleProvider.future);
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
  final people = await ref.watch(chatPeopleProvider.future);
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

/// Who is typing where, as the finished label a row shows. Kept apart from
/// [chatListProvider] so a typing indicator never rebuilds 5,000 rows; each
/// visible row selects its own entry.
final chatTypingProvider = StreamProvider<Map<String, String>>((ref) async* {
  final gateway = await ref.watch(chatGatewayProvider.future);
  final people = await ref.watch(chatPeopleProvider.future);
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
