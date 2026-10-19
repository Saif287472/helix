import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/conversation/application/forward_targets.dart';
import 'package:helix_remote/features/conversation/application/message_actions.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: pick the chats (and people) to forward messages to, then send,
/// drawn by `orbit_ui`'s forward page (`contracts/conversation.md`). The
/// messages are the database ids in [rowids], from the conversation
/// [conversationId].
class ForwardScreen extends ConsumerWidget {
  const ForwardScreen({
    super.key,
    required this.conversationId,
    required this.rowids,
  });

  final String conversationId;
  final List<int> rowids;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = ref.watch(forwardTargetsProvider);
    final all = targets.value;

    Future<void> send(Set<String> picked) async {
      final chosen = [
        for (final t in all ?? const <ForwardTarget>[])
          if (picked.contains(t.id)) t,
      ];
      final failed = await ref
          .read(conversationActionsProvider(conversationId))
          .forward(
            rowids,
            [
              for (final t in chosen)
                if (t.newPeer == null) t.id,
            ],
            peersToOpen: [
              for (final t in chosen)
                if (t.newPeer != null) t.newPeer!,
            ],
          );
      // Shown over the chat: the page closes once this returns.
      if (context.mounted) {
        orbit.showOrbitToast(
          context,
          failed == 0 ? 'Forwarded' : 'Some messages could not be forwarded',
          error: failed != 0,
        );
      }
    }

    return orbit.ForwardScreen(
      model: orbit.ForwardModel(
        messageCount: rowids.length,
        loadState: all != null
            ? orbit.LoadState.ready
            : targets.hasError
            ? orbit.LoadState.error
            : orbit.LoadState.loading,
        targets: [
          for (final t in all ?? const <ForwardTarget>[])
            orbit.ForwardTargetItem(
              id: t.id,
              title: t.title,
              avatar: t.avatar,
              isNewChat: t.newPeer != null,
            ),
        ],
      ),
      actions: orbit.ForwardActions(
        onSend: send,
        onRetry: () => ref.invalidate(forwardTargetsProvider),
      ),
    );
  }
}
