import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/chats/application/chat_actions.dart';
import 'package:helix_remote/features/chats/application/chat_list_provider.dart';
import 'package:helix_remote/features/chats/application/chat_selection.dart';
import 'package:helix_remote/shared/widgets/mute_choice.dart';
import 'package:helix_remote/shared/navigation/chat_locations.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The chat rows: fixed height, lazily built, with swipe actions and
/// selection. Used by the Chats tab and by the archived chats screen.
///
/// The rows are sliver items of one fixed extent, so scrolling 5,000 chats
/// never measures a row, and only the rows on screen exist.
class ChatListView extends ConsumerWidget {
  const ChatListView({
    super.key,
    required this.items,
    this.headers = const [],
    this.archivedList = false,
    this.activeChatId,
    this.onOpenChat,
  });

  final List<HelixChatListItem> items;

  /// Slivers shown above the rows (the search pill, the Archived row).
  final List<Widget> headers;

  /// This is the archived list: the swipe is "Unarchive", not "Archive".
  final bool archivedList;

  /// The chat open beside the list on a wide window; its row stays tinted.
  final String? activeChatId;

  /// Opens a chat in place (the wide layout). Null pushes its page.
  final ValueChanged<String>? onOpenChat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(chatSelectionProvider);
    final selecting = selection.isNotEmpty;
    final extent = HelixChatListTile.extentFor(
      MediaQuery.textScalerOf(context),
    );
    final actions = ref.read(chatActionsProvider);
    final notifier = ref.read(chatSelectionProvider.notifier);

    void open(HelixChatListItem item) {
      if (selecting) {
        notifier.toggle(item.id);
      } else if (onOpenChat != null) {
        onOpenChat!(item.id);
      } else {
        context.push(chatLocation(item.id));
      }
    }

    return CustomScrollView(
      slivers: [
        ...headers,
        SliverFixedExtentList(
          itemExtent: extent,
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final item = items[index];
              return _ChatRow(
                key: ValueKey(item.id),
                item: item,
                selected:
                    selection.contains(item.id) || item.id == activeChatId,
                selecting: selecting,
                onOpen: () => open(item),
                onSelect: () => selecting
                    ? notifier.toggle(item.id)
                    : notifier.start(item.id),
                startAction: archivedList
                    ? null
                    : HelixSwipeAction(
                        icon: item.pinned
                            ? Icons.push_pin_outlined
                            : Icons.push_pin,
                        label: item.pinned ? 'Unpin' : 'Pin',
                        onTriggered: () =>
                            actions.pin([item.id], pinned: !item.pinned),
                      ),
                endAction: HelixSwipeAction(
                  icon: archivedList ? Icons.unarchive : Icons.archive,
                  label: archivedList ? 'Unarchive' : 'Archive',
                  onTriggered: () async {
                    await actions.archive([item.id], archived: !archivedList);
                    if (!context.mounted) return;
                    showHelixSnackBar(
                      context,
                      archivedList ? 'Chat unarchived' : 'Chat archived',
                      actionLabel: 'Undo',
                      onAction: () =>
                          actions.archive([item.id], archived: archivedList),
                    );
                  },
                ),
              );
            },
            childCount: items.length,
            addAutomaticKeepAlives: false,
            findChildIndexCallback: (key) {
              if (key is ValueKey<String>) {
                final i = items.indexWhere((e) => e.id == key.value);
                return i < 0 ? null : i;
              }
              return null;
            },
          ),
        ),
      ],
    );
  }
}

/// One row: reads its own typing label so a typing indicator rebuilds one
/// tile, not the list.
class _ChatRow extends ConsumerWidget {
  const _ChatRow({
    super.key,
    required this.item,
    required this.selected,
    required this.selecting,
    required this.onOpen,
    required this.onSelect,
    required this.startAction,
    required this.endAction,
  });

  final HelixChatListItem item;
  final bool selected;
  final bool selecting;
  final VoidCallback onOpen;
  final VoidCallback onSelect;
  final HelixSwipeAction? startAction;
  final HelixSwipeAction endAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typing = ref.watch(chatTypingLabelProvider(item.id));
    final shown = typing == null
        ? item
        : HelixChatListItem(
            id: item.id,
            title: item.title,
            avatar: item.avatar,
            preview: item.preview,
            timeLabel: item.timeLabel,
            unreadCount: item.unreadCount,
            hasMention: item.hasMention,
            markedUnread: item.markedUnread,
            pinned: item.pinned,
            muted: item.muted,
            archived: item.archived,
            typingLabel: typing,
            online: item.online,
            verified: item.verified,
          );
    return HelixSwipeableChatListTile(
      item: shown,
      selected: selected,
      selectionMode: selecting,
      startAction: startAction,
      endAction: endAction,
      onTap: onOpen,
      onLongPress: onSelect,
    );
  }
}

/// The selection bar: the actions that apply to the ticked chats.
class ChatSelectionBar extends ConsumerWidget implements PreferredSizeWidget {
  const ChatSelectionBar({
    super.key,
    required this.items,
    this.archivedList = false,
  });

  /// Every chat in the list the selection is over.
  final List<HelixChatListItem> items;
  final bool archivedList;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(chatSelectionProvider);
    final selected = [
      for (final item in items)
        if (ids.contains(item.id)) item,
    ];
    final actions = ref.read(chatActionsProvider);
    final notifier = ref.read(chatSelectionProvider.notifier);
    final allPinned = selected.isNotEmpty && selected.every((c) => c.pinned);
    final anyMuted = selected.any((c) => c.muted);
    final anyUnread = selected.any((c) => c.hasUnread);

    Future<void> done(Future<void> work) async {
      await work;
      notifier.clear();
    }

    return HelixSelectionBar(
      count: ids.length,
      onClose: notifier.clear,
      actions: [
        if (!archivedList)
          HelixBarAction(
            icon: allPinned ? Icons.push_pin_outlined : Icons.push_pin,
            tooltip: allPinned ? 'Unpin chats' : 'Pin chats',
            onPressed: () => done(actions.pin(ids, pinned: !allPinned)),
          ),
        HelixBarAction(
          icon: anyMuted ? Icons.volume_up : Icons.volume_off,
          tooltip: anyMuted ? 'Unmute or mute chats' : 'Mute chats',
          onPressed: () async {
            final choice = await showMuteSheet(context, offerUnmute: anyMuted);
            switch (choice) {
              case MuteLengthChoice(:final length):
                await done(actions.mute(ids, length));
              case UnmuteChoice():
                await done(actions.mute(ids, null));
              case null:
                break;
            }
          },
        ),
        HelixBarAction(
          icon: archivedList ? Icons.unarchive : Icons.archive,
          tooltip: archivedList ? 'Unarchive chats' : 'Archive chats',
          onPressed: () => done(actions.archive(ids, archived: !archivedList)),
        ),
        if (anyUnread)
          HelixBarAction(
            icon: Icons.mark_chat_read_outlined,
            tooltip: 'Mark as read',
            onPressed: () => done(actions.markRead(ids)),
          ),
        HelixBarAction(
          icon: Icons.delete_outline,
          tooltip: 'Delete chats',
          onPressed: () async {
            final count = ids.length;
            final confirmed = await showHelixDestructiveDialog(
              context,
              title: count == 1 ? 'Delete this chat?' : 'Delete $count chats?',
              message:
                  'The messages are removed from this device. People you '
                  'chatted with keep their copies.',
              action: 'Delete',
            );
            if (confirmed) await done(actions.delete(ids));
          },
        ),
      ],
    );
  }
}

/// What the tab and the archived screen show for the list's load state.
class ChatListStates extends ConsumerWidget {
  const ChatListStates({
    super.key,
    required this.chats,
    required this.builder,
    this.empty,
  });

  final AsyncValue<List<HelixChatListItem>> chats;
  final Widget Function(List<HelixChatListItem> items) builder;
  final Widget? empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = chats.value;
    if (value != null) {
      if (value.isEmpty && empty != null) return empty!;
      return builder(value);
    }
    if (chats.hasError) {
      return HelixErrorState(
        message: 'Your chats could not be loaded.',
        onRetry: () => ref.invalidate(chatListProvider),
      );
    }
    return const HelixChatListSkeleton();
  }
}
