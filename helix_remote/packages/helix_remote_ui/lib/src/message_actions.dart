part of '../helix_remote_ui.dart';

/// Well-known ids for [HelixMessageAction], so the app switches on constants.
abstract final class HelixMessageActionIds {
  static const reply = 'reply';
  static const forward = 'forward';
  static const copy = 'copy';
  static const edit = 'edit';
  static const star = 'star';
  static const info = 'info';
  static const select = 'select';
  static const deleteForMe = 'delete_for_me';
  static const deleteForEveryone = 'delete_for_everyone';
}

/// One row of the message action menu.
class HelixMessageAction {
  const HelixMessageAction({
    required this.id,
    required this.label,
    required this.icon,
    this.destructive = false,
  });
  final String id;
  final String label;
  final IconData icon;
  final bool destructive;
}

/// The actions that apply to a message, in menu order. [canEdit] and
/// [canDeleteForEveryone] come from the content rules (15 minutes and 2 days
/// from the message time, author only); the UI does not know the clock.
List<HelixMessageAction> helixDefaultMessageActions({
  required bool outgoing,
  bool hasText = true,
  bool canEdit = false,
  bool canDeleteForEveryone = false,
  bool starred = false,
}) => [
  const HelixMessageAction(
    id: HelixMessageActionIds.reply,
    label: 'Reply',
    icon: Icons.reply,
  ),
  if (hasText)
    const HelixMessageAction(
      id: HelixMessageActionIds.copy,
      label: 'Copy',
      icon: Icons.content_copy,
    ),
  const HelixMessageAction(
    id: HelixMessageActionIds.forward,
    label: 'Forward',
    icon: Icons.forward,
  ),
  HelixMessageAction(
    id: HelixMessageActionIds.star,
    label: starred ? 'Unstar' : 'Star',
    icon: starred ? Icons.star : Icons.star_border,
  ),
  if (canEdit)
    const HelixMessageAction(
      id: HelixMessageActionIds.edit,
      label: 'Edit',
      icon: Icons.edit_outlined,
    ),
  if (outgoing)
    const HelixMessageAction(
      id: HelixMessageActionIds.info,
      label: 'Message info',
      icon: Icons.info_outline,
    ),
  const HelixMessageAction(
    id: HelixMessageActionIds.select,
    label: 'Select',
    icon: Icons.check_circle_outline,
  ),
  const HelixMessageAction(
    id: HelixMessageActionIds.deleteForMe,
    label: 'Delete for me',
    icon: Icons.delete_outline,
    destructive: true,
  ),
  if (canDeleteForEveryone)
    const HelixMessageAction(
      id: HelixMessageActionIds.deleteForEveryone,
      label: 'Delete for everyone',
      icon: Icons.delete_forever_outlined,
      destructive: true,
    ),
];

/// The quick reactions offered first.
const helixQuickReactions = <String>['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// A row of quick reactions plus a "more" button. Your current reaction (if
/// any) is ringed; tapping it again takes it back (the app decides).
class HelixReactionPicker extends StatelessWidget {
  const HelixReactionPicker({
    super.key,
    required this.onPick,
    this.emojis = helixQuickReactions,
    this.current,
    this.onMore,
  });

  final ValueChanged<String> onPick;
  final List<String> emojis;
  final String? current;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final emoji in emojis)
              Semantics(
                button: true,
                selected: emoji == current,
                label: emoji == current
                    ? 'Remove your $emoji reaction'
                    : 'React with $emoji',
                onTap: () => onPick(emoji),
                child: ExcludeSemantics(
                  child: InkResponse(
                    onTap: () => onPick(emoji),
                    radius: 24,
                    child: SizedBox.square(
                      dimension: HelixChatMetrics.minTarget,
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: emoji == current
                                ? scheme.primaryContainer
                                : null,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text(
                              emoji,
                              textScaler: TextScaler.noScaling,
                              style: const TextStyle(fontSize: 24, height: 1.2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (onMore != null)
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'More reactions',
                onPressed: onMore,
              ),
          ],
        ),
      ),
    );
  }
}

/// The content of the long-press sheet: reaction picker on top, the action
/// list under it.
class HelixMessageActionMenu extends StatelessWidget {
  const HelixMessageActionMenu({
    super.key,
    required this.actions,
    required this.onAction,
    this.onReaction,
    this.currentReaction,
    this.onMoreReactions,
  });

  final List<HelixMessageAction> actions;
  final ValueChanged<String> onAction;

  /// Null hides the reaction picker (a deleted or undecryptable message).
  final ValueChanged<String>? onReaction;
  final String? currentReaction;
  final VoidCallback? onMoreReactions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onReaction != null)
          Padding(
            padding: const EdgeInsets.only(bottom: HelixSpace.xs),
            child: HelixReactionPicker(
              onPick: onReaction!,
              current: currentReaction,
              onMore: onMoreReactions,
            ),
          ),
        for (final action in actions)
          ListTile(
            leading: Icon(
              action.icon,
              color: action.destructive ? scheme.error : null,
            ),
            title: Text(
              action.label,
              style: action.destructive ? TextStyle(color: scheme.error) : null,
            ),
            onTap: () => onAction(action.id),
          ),
      ],
    );
  }
}

/// Shows [HelixMessageActionMenu] in a bottom sheet and returns the chosen
/// action id (or null). Reactions are returned as `react:<emoji>`, and
/// `react:more` for the "more reactions" button.
Future<String?> showHelixMessageActionMenu(
  BuildContext context, {
  required List<HelixMessageAction> actions,
  bool allowReactions = true,
  String? currentReaction,
}) => showHelixBottomSheet<String>(
  context,
  builder: (sheetContext) => HelixMessageActionMenu(
    actions: actions,
    currentReaction: currentReaction,
    onAction: (id) => Navigator.pop(sheetContext, id),
    onReaction: allowReactions
        ? (emoji) => Navigator.pop(sheetContext, 'react:$emoji')
        : null,
    onMoreReactions: allowReactions
        ? () => Navigator.pop(sheetContext, 'react:more')
        : null,
  ),
);
