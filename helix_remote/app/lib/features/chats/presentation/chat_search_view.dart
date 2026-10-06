import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/chats/application/chat_search.dart';
import 'package:helix_remote/shared/navigation/chat_locations.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Builds the people section of the search: who matches the query, and a way
/// to start a chat with them.
///
/// **This is the seam to the people feature.** The widget it returns must not
/// scroll (a `Column` of rows with its own header): it is placed between the
/// chat and message results. It is supplied by the router, because a feature
/// may not import another feature.
typedef PeopleSearchBuilder =
    Widget Function(BuildContext context, String query);

/// The Chats tab while the person is searching: chats by name, people (the
/// seam), and messages by their text.
class ChatSearchView extends ConsumerWidget {
  const ChatSearchView({super.key, this.peopleResults});

  final PeopleSearchBuilder? peopleResults;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(chatSearchQueryProvider).trim();
    if (query.isEmpty) {
      return const HelixEmptyState(
        icon: Icons.search,
        title: 'Search',
        message: 'Find chats, messages and people.',
      );
    }
    final results = ref.watch(chatSearchResultsProvider);
    final value = results.value;
    if (results.hasError && value == null) {
      return const HelixErrorState(message: 'The search could not be run.');
    }
    final people = peopleResults?.call(context, query);
    if (value == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (value.isEmpty && people == null) {
      return HelixNoResults(query: query);
    }
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (value.chats.isNotEmpty) ...[
          const HelixSectionHeader(title: 'Chats'),
          for (final chat in value.chats)
            HelixChatListTile(
              key: ValueKey('chat:${chat.id}'),
              item: chat,
              onTap: () => context.push(chatLocation(chat.id)),
            ),
        ],
        ?people,
        if (value.messages.isNotEmpty) ...[
          const HelixSectionHeader(title: 'Messages'),
          for (final hit in value.messages)
            HelixMessageSearchTile(
              key: ValueKey('hit:${hit.result.id}'),
              result: hit.result,
              onTap: () => context.push(
                chatLocation(hit.conversationId, messageId: hit.messageId),
              ),
            ),
        ],
      ],
    );
  }
}
