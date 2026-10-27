import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/conversation/application/starred_messages.dart';
import 'package:helix_remote/shared/navigation/chat_locations.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: the messages you starred, drawn by `orbit_ui`'s
/// [orbit.StarredMessagesScreen]. A row opens its chat at that message.
class StarredScreen extends ConsumerWidget {
  const StarredScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starred = ref.watch(starredItemsProvider);
    return orbit.StarredMessagesScreen(
      model: orbit.StarredModel(
        items: starred.value ?? const [],
        status: starred.hasError
            ? orbit.ListStatus.failed
            : starred.hasValue
            ? orbit.ListStatus.ready
            : orbit.ListStatus.loading,
      ),
      actions: orbit.StarredActions(
        onOpen: (chatId, messageId) =>
            context.push(chatLocation(chatId, messageId: messageId)),
        onRetry: () => ref.invalidate(starredItemsProvider),
      ),
    );
  }
}
