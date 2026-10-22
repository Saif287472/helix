import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:helix_remote/features/chats/application/chat_actions.dart';
import 'package:helix_remote/features/chats/application/chat_list_provider.dart';
import 'package:orbit_ui/models.dart';
import 'package:helix_remote/shared/widgets/mute_choice.dart' as app_mute;
import 'package:orbit_ui/orbit_ui.dart' as orbit;

class ArchivedChatsScreen extends ConsumerWidget {
  const ArchivedChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archivedAsync = ref.watch(archivedChatListProvider);
    final typing = ref.watch(chatTypingProvider).value ?? const {};
    final raw = archivedAsync.value ?? const <HelixChatListItem>[];
    final chats = [
      for (final c in raw)
        HelixChatListItem(
          id: c.id,
          title: c.title,
          avatar: c.avatar,
          preview: c.preview,
          timeLabel: c.timeLabel,
          unreadCount: c.unreadCount,
          hasMention: c.hasMention,
          markedUnread: c.markedUnread,
          pinned: c.pinned,
          muted: c.muted,
          archived: true,
          typingLabel: typing[c.id] ?? c.typingLabel,
          online: c.online,
          verified: c.verified,
        ),
    ];
    final status = archivedAsync.isLoading
        ? orbit.ListStatus.loading
        : archivedAsync.hasError
        ? orbit.ListStatus.failed
        : orbit.ListStatus.ready;

    final actions = ref.read(chatActionsProvider);
    final orbitActions = orbit.ArchivedChatsActions(
      onOpenChat: (id) => context.push('/chat/${Uri.encodeComponent(id)}'),
      onSetArchived: (ids, {required archived}) =>
          actions.archive(ids, archived: archived),
      onMute: (ids, length) => actions.mute(ids, _mapMute(length)),
      onMarkRead: (ids) => actions.markRead(ids),
      onDelete: (ids) => actions.delete(ids),
      onBack: () => Navigator.maybePop(context),
    );

    return orbit.ArchivedChatsScreen(
      model: orbit.ArchivedChatsModel(chats: chats, status: status),
      actions: orbitActions,
    );
  }
}

app_mute.MuteFor? _mapMute(orbit.MuteFor? length) {
  if (length == null) return null;
  switch (length) {
    case orbit.MuteFor.eightHours:
      return app_mute.MuteFor.eightHours;
    case orbit.MuteFor.week:
      return app_mute.MuteFor.oneWeek;
    case orbit.MuteFor.always:
      return app_mute.MuteFor.always;
  }
}
