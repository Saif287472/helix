import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/chats/application/chat_list_provider.dart';
import 'package:helix_remote/features/chats/application/chat_search.dart';
import 'package:helix_remote/features/chats/application/chat_selection.dart';
import 'package:helix_remote/features/chats/presentation/chat_list_view.dart';
import 'package:helix_remote/features/chats/presentation/chat_search_view.dart';
import 'package:helix_remote/shared/navigation/chat_locations.dart';
import 'package:helix_remote/shared/navigation/group_paths.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The Chats tab: the chat list, its selection mode, the archived row and the
/// search that finds chats, people and messages.
///
/// It is a whole `Scaffold` with its own app bar, because a selection or a
/// search replaces the bar and a tab that only filled the body could not.
///
/// [peopleResults] is the seam to the people feature (see
/// [PeopleSearchBuilder]); without it the search shows chats and messages.
///
/// [detailBuilder] is the seam to the conversation feature: on a window wide
/// enough for two panes the list sits on the left and the chosen chat opens
/// on the right instead of on a page of its own. Without it the chat always
/// opens as a page.
class ChatsTab extends ConsumerStatefulWidget {
  const ChatsTab({super.key, this.peopleResults, this.detailBuilder});

  final PeopleSearchBuilder? peopleResults;
  final Widget Function(BuildContext context, String conversationId)?
  detailBuilder;

  @override
  ConsumerState<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends ConsumerState<ChatsTab> {
  /// From this width the chat opens beside the list.
  static const _twoPanes = HelixBreakpoints.medium;

  /// The list's width in the two-pane layout.
  static const _listWidth = 380.0;

  final TextEditingController _query = TextEditingController();
  bool _searching = false;
  String? _active;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _setSearching(bool searching) {
    setState(() => _searching = searching);
    if (!searching) ref.read(chatSearchQueryProvider.notifier).set('');
  }

  @override
  Widget build(BuildContext context) {
    final twoPanes =
        widget.detailBuilder != null &&
        MediaQuery.sizeOf(context).width >= _twoPanes;
    final chats = ref.watch(chatListProvider);
    final selecting = ref.watch(chatSelectionProvider).isNotEmpty;
    final items = chats.value ?? const <HelixChatListItem>[];
    final hasArchived =
        ref.watch(archivedChatListProvider).value?.isNotEmpty ?? false;

    final PreferredSizeWidget appBar = selecting
        ? ChatSelectionBar(items: items)
        : HelixSearchAppBar(
            title: 'Chats',
            searching: _searching,
            onSearchChanged: _setSearching,
            controller: _query,
            searchHint: 'Search chats, messages and people',
            onQueryChanged: (value) =>
                ref.read(chatSearchQueryProvider.notifier).set(value),
            actions: [
              PopupMenuButton<_ChatsMenu>(
                tooltip: 'More options',
                onSelected: (choice) => context.push(switch (choice) {
                  _ChatsMenu.newGroup => GroupPaths.create,
                  _ChatsMenu.joinGroup => GroupPaths.join,
                }),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _ChatsMenu.newGroup,
                    child: Text('New group'),
                  ),
                  PopupMenuItem(
                    value: _ChatsMenu.joinGroup,
                    child: Text('Join a group with a link'),
                  ),
                ],
              ),
            ],
          );

    final list = PopScope(
      // Back closes a selection or a search before it leaves the app.
      canPop: !selecting && !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (selecting) {
          ref.read(chatSelectionProvider.notifier).clear();
        } else if (_searching) {
          _query.clear();
          _setSearching(false);
        }
      },
      child: Scaffold(
        appBar: appBar,
        body: _searching && !selecting
            ? ChatSearchView(peopleResults: widget.peopleResults)
            : ChatListStates(
                chats: chats,
                // With everything archived the list is empty but the Archived
                // row must stay, so the empty state is for "nothing at all".
                empty: hasArchived
                    ? null
                    : HelixChatListEmpty(
                        onFindPeople: () => _setSearching(true),
                      ),
                builder: (items) => _ChatsBody(
                  items: items,
                  activeChatId: twoPanes ? _active : null,
                  onOpenChat: twoPanes
                      ? (id) => setState(() => _active = id)
                      : null,
                ),
              ),
        floatingActionButton: selecting || _searching
            ? null
            : FloatingActionButton.small(
                heroTag: 'new_chat_fab',
                tooltip: 'New chat',
                onPressed: () => _setSearching(true),
                child: const Icon(Icons.add_comment),
              ),
      ),
    );
    if (!twoPanes) return list;
    final active = _active;
    return Row(
      children: [
        SizedBox(width: _listWidth, child: list),
        const VerticalDivider(width: 1),
        Expanded(
          child: active == null
              ? const HelixEmptyState(
                  icon: Icons.forum_outlined,
                  title: 'Select a chat',
                  message:
                      'Pick a conversation from the list, or tap the new chat '
                      'button to find someone.',
                )
              : KeyedSubtree(
                  key: ValueKey(active),
                  child: widget.detailBuilder!(context, active),
                ),
        ),
      ],
    );
  }
}

/// What the Chats app bar's menu opens: the group screens, which belong to the
/// groups feature (only their shared paths are known here).
enum _ChatsMenu { newGroup, joinGroup }

class _ChatsBody extends ConsumerWidget {
  const _ChatsBody({
    required this.items,
    required this.activeChatId,
    required this.onOpenChat,
  });

  final List<HelixChatListItem> items;
  final String? activeChatId;
  final ValueChanged<String>? onOpenChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = ref.watch(archivedChatListProvider).value ?? const [];
    return ChatListView(
      items: items,
      activeChatId: activeChatId,
      onOpenChat: onOpenChat,
      headers: [
        if (archived.isNotEmpty)
          SliverToBoxAdapter(
            child: HelixArchivedRow(
              count: archived.length,
              onTap: () => context.push(ChatRoutes.archived),
            ),
          ),
      ],
    );
  }
}
