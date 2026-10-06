import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/conversation/application/conversation_calls.dart';
import 'package:helix_remote/features/conversation/application/conversation_header.dart';
import 'package:helix_remote/features/conversation/application/conversation_links.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// What the app bar's menu can ask for.
enum ConversationMenuAction { search, info, media, settings }

/// The conversation's app bar: who it is with (name, avatar, presence or who
/// is typing), the call buttons and a menu.
///
/// Tapping the title opens the contact info (a direct chat) or the group info
/// (a group); the menu also reaches the shared media and the chat's settings.
/// The call buttons go through the calls seam (`conversationCallsProvider`); a
/// group has none (group calls are not part of this release).
class ConversationAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const ConversationAppBar({
    super.key,
    required this.conversationId,
    required this.onMenu,
  });

  final String conversationId;
  final ValueChanged<ConversationMenuAction> onMenu;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = ref.watch(conversationHeaderProvider(conversationId));
    final calls = ref.watch(conversationCallsProvider);
    final scheme = Theme.of(context).colorScheme;
    final peer = header?.peerAccount;

    Future<void> call({required bool video}) async {
      if (peer == null) return;
      if (!calls.isAvailable) {
        showHelixSnackBar(context, 'Calls are not available on this device.');
        return;
      }
      final failure = await calls.start(peer, video: video);
      if (failure != null && context.mounted) {
        showHelixSnackBar(context, failure);
      }
    }

    final info = infoLocationOf(conversationId);

    return AppBar(
      titleSpacing: 0,
      title: header == null
          ? const SizedBox.shrink()
          : Semantics(
              button: true,
              label:
                  '${header.title}, ${header.subtitle ?? ''}. '
                  '${header.isGroup ? 'Open group info' : 'Open contact info'}',
              child: InkWell(
                onTap: info == null ? null : () => context.push(info),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: HelixChatMetrics.minTarget,
                  ),
                  child: Row(
                    children: [
                      ExcludeSemantics(
                        child: HelixAvatar(
                          model: header.avatar,
                          size: HelixAvatarSize.sm,
                        ),
                      ),
                      const SizedBox(width: HelixSpace.sm),
                      Expanded(
                        child: ExcludeSemantics(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      header.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  if (header.verified)
                                    const Padding(
                                      padding: EdgeInsetsDirectional.only(
                                        start: HelixSpace.xxs,
                                      ),
                                      child: Icon(
                                        Icons.verified_user,
                                        size: 14,
                                        color: HelixStatusColors.positive,
                                      ),
                                    ),
                                ],
                              ),
                              if (header.subtitle != null)
                                Text(
                                  header.subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: header.typing
                                            ? scheme.primary
                                            : scheme.onSurfaceVariant,
                                      ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      actions: [
        if (peer != null && !(header?.blocked ?? false)) ...[
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            tooltip: 'Video call',
            onPressed: () => call(video: true),
          ),
          IconButton(
            icon: const Icon(Icons.call_outlined),
            tooltip: 'Voice call',
            onPressed: () => call(video: false),
          ),
        ],
        PopupMenuButton<ConversationMenuAction>(
          tooltip: 'More options',
          onSelected: onMenu,
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: ConversationMenuAction.search,
              child: Text('Search'),
            ),
            if (info != null)
              PopupMenuItem(
                value: ConversationMenuAction.info,
                child: Text(
                  header?.isGroup ?? false ? 'Group info' : 'Contact info',
                ),
              ),
            const PopupMenuItem(
              value: ConversationMenuAction.media,
              child: Text('Media, links and docs'),
            ),
            const PopupMenuItem(
              value: ConversationMenuAction.settings,
              child: Text('Chat settings'),
            ),
          ],
        ),
      ],
    );
  }
}
