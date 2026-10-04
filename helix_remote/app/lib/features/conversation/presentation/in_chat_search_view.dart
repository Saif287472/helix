import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/conversation/application/conversation_search.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The results of searching inside one conversation. Picking one closes the
/// search and jumps to the message.
class InChatSearchView extends ConsumerWidget {
  const InChatSearchView({
    super.key,
    required this.conversationId,
    required this.onPick,
  });

  final String conversationId;

  /// Called with the content id of the chosen message.
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(inChatSearchQueryProvider(conversationId)).trim();
    if (query.isEmpty) {
      return const HelixEmptyState(
        icon: Icons.search,
        title: 'Search this chat',
        message: 'Type a word to find messages that contain it.',
      );
    }
    final results = ref.watch(inChatSearchResultsProvider(conversationId));
    final hits = results.value;
    if (hits == null) {
      return results.hasError
          ? const HelixErrorState(message: 'The search could not be run.')
          : const Center(child: CircularProgressIndicator());
    }
    if (hits.isEmpty) return HelixNoResults(query: query);
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: hits.length,
      itemExtent: HelixChatListTile.extentFor(MediaQuery.textScalerOf(context)),
      itemBuilder: (context, index) {
        final hit = hits[index];
        return HelixMessageSearchTile(
          key: ValueKey('hit:${hit.result.id}'),
          result: hit.result,
          onTap: () => onPick(hit.messageId),
        );
      },
    );
  }
}
