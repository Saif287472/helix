import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/chats/application/chat_list_provider.dart';
import 'package:helix_remote/features/chats/application/chat_selection.dart';
import 'package:helix_remote/features/chats/presentation/chat_list_view.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The archived chats: the same rows as the Chats tab, swiped to unarchive.
class ArchivedChatsScreen extends ConsumerWidget {
  const ArchivedChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = ref.watch(archivedChatListProvider);
    final selecting = ref.watch(chatSelectionProvider).isNotEmpty;
    final items = archived.value ?? const <HelixChatListItem>[];
    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(chatSelectionProvider.notifier).clear();
      },
      child: Scaffold(
        appBar: selecting
            ? ChatSelectionBar(items: items, archivedList: true)
            : AppBar(title: const Text('Archived chats')),
        body: archived.value != null && items.isEmpty
            ? const HelixEmptyState(
                icon: Icons.archive_outlined,
                title: 'No archived chats',
                message:
                    'Chats you archive stay here until you unarchive them.',
              )
            : ChatListStates(
                chats: archived,
                builder: (items) =>
                    ChatListView(items: items, archivedList: true),
              ),
      ),
    );
  }
}
