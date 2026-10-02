import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/home/application/chat_list_provider.dart';
import 'package:helix_remote/features/home/application/home_tab.dart';
import 'package:helix_remote/features/home/presentation/home_screen.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Chats: the list, straight off the engine's watch query.
///
/// A2 builds on this - selection, swipe actions, archiving, search and the
/// conversation itself. What A1 establishes is the shape everything else
/// follows: a [StreamProvider] over a drift watch query in the application
/// layer, mapped to plain value objects, and a widget that only draws.
class ChatsTab extends ConsumerWidget {
  const ChatsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(chatListProvider);
    return HomeTabScaffold(
      title: 'Chats',
      tab: HomeTab.chats,
      child: switch (chats) {
        AsyncError() => const HelixErrorState(
          message: 'Your chats could not be loaded. Open the app again to try.',
        ),
        AsyncData(:final value) when value.isEmpty =>
          const HelixChatListEmpty(),
        AsyncData(:final value) => ListView.builder(
          itemCount: value.length,
          itemExtent: HelixChatListTile.extentFor(
            MediaQuery.textScalerOf(context),
          ),
          itemBuilder: (context, index) => HelixChatListTile(
            key: ValueKey(value[index].id),
            item: value[index],
          ),
        ),
        _ => const HelixChatListSkeleton(),
      },
    );
  }
}
