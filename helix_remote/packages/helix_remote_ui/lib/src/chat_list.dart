part of '../helix_remote_ui.dart';

/// One row of the chat list.
///
/// **Sizing contract.** The row is exactly [extentFor] tall for the current
/// text scale and never measures its content (every line is single-line and
/// ellipsised), so a list can pass `itemExtent: HelixChatListTile.extentFor(
/// MediaQuery.textScalerOf(context))` to `ListView.builder` and scroll 5,000
/// rows without layout per row.
///
/// The tile is stateless and `const`-constructible; it does no work in
/// `build` beyond reading the theme and assembling one semantics label.
class HelixChatListTile extends StatelessWidget {
  const HelixChatListTile({
    super.key,
    required this.item,
    this.selected = false,
    this.selectionMode = false,
    this.onTap,
    this.onLongPress,
    this.onAvatarTap,
    this.semanticActions,
  });

  final HelixChatListItem item;

  /// This row is selected (selection mode).
  final bool selected;

  /// A selection is in progress; the avatar then shows the check and tapping
  /// toggles instead of opening.
  final bool selectionMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Tapping the avatar (profile quick view). Not offered in selection mode.
  final VoidCallback? onAvatarTap;

  /// Extra screen-reader actions (the swipe actions, for example).
  final Map<CustomSemanticsAction, VoidCallback>? semanticActions;

  static const _titleHeight = 20.0;
  static const _previewHeight = 18.0;
  static const _titleGap = 2.0;
  static const _verticalPadding = 16.0;

  /// The exact row height for [scaler].
  static double extentFor(TextScaler scaler) => math.max(
    HelixChatMetrics.chatTileHeight,
    2 * _verticalPadding +
        scaler.scale(_titleHeight) +
        _titleGap +
        scaler.scale(_previewHeight),
  );

  Widget _tappable(Widget avatar) => onAvatarTap == null || selectionMode
      ? avatar
      : GestureDetector(onTap: onAvatarTap, child: avatar);

  String _semanticLabel() {
    final b = StringBuffer(item.title);
    if (item.unreadCount > 0) {
      b.write(', ${item.unreadCount} unread');
    } else if (item.markedUnread) {
      b.write(', marked unread');
    }
    if (item.hasMention) b.write(', you were mentioned');
    if (item.pinned) b.write(', pinned');
    if (item.muted) b.write(', muted');
    if (item.archived) b.write(', archived');
    if (item.typingLabel != null) {
      b.write(', ${item.typingLabel}');
    } else if (item.preview != null) {
      b.write(', ${_previewSpoken(item.preview!)}');
    }
    if (item.timeLabel.isNotEmpty) b.write(', ${item.timeLabel}');
    return b.toString();
  }

  static String _previewSpoken(HelixChatPreview p) {
    final label = helixPreviewLabel(p.kind);
    final text = p.text.isEmpty ? label : p.text;
    final who = p.senderPrefix == null ? '' : '${p.senderPrefix}: ';
    final draft = p.isDraft ? 'Draft: ' : '';
    return '$draft$who$text';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final unread = item.hasUnread;
    final titleStyle = theme.textTheme.titleMedium!.copyWith(
      height: _titleHeight / 16,
      fontSize: 16,
      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
    );
    final timeStyle = theme.textTheme.labelSmall!.copyWith(
      height: _titleHeight / 12,
      color: unread && !item.muted ? scheme.primary : scheme.onSurfaceVariant,
      fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
    );
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: _semanticLabel(),
      onTap: onTap,
      onLongPress: onLongPress,
      customSemanticsActions: semanticActions,
      child: ExcludeSemantics(
        child: SizedBox(
          height: extentFor(scaler),
          child: Material(
            color: selected
                ? scheme.secondaryContainer
                : Theme.of(context).scaffoldBackgroundColor,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: HelixSpace.md,
                  vertical: _verticalPadding / 2,
                ),
                child: Row(
                  children: [
                    _tappable(
                      HelixAvatar(
                        model: item.avatar,
                        size: HelixAvatarSize.lg,
                        online: item.online,
                        selected: selected && selectionMode,
                      ),
                    ),
                    const SizedBox(width: HelixSpace.sm),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: titleStyle,
                                ),
                              ),
                              if (item.verified)
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
                              const SizedBox(width: HelixSpace.xs),
                              Text(
                                item.timeLabel,
                                maxLines: 1,
                                style: timeStyle,
                              ),
                            ],
                          ),
                          const SizedBox(height: _titleGap),
                          SizedBox(
                            height: scaler.scale(_previewHeight),
                            child: Row(
                              children: [
                                Expanded(
                                  child: item.typingLabel != null
                                      ? Text(
                                          item.typingLabel!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            height: _previewHeight / 14,
                                            color: scheme.primary,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        )
                                      : _PreviewLine(
                                          preview: item.preview,
                                          unread: unread,
                                        ),
                                ),
                                _TileIndicators(item: item),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.preview, required this.unread});
  final HelixChatPreview? preview;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final p = preview;
    if (p == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final color = unread ? scheme.onSurface : scheme.onSurfaceVariant;
    final base = TextStyle(
      fontSize: 14,
      height: HelixChatListTile._previewHeight / 14,
      color: color,
      fontWeight: unread ? FontWeight.w500 : FontWeight.w400,
    );
    final icon = helixPreviewIcon(p.kind);
    final label = helixPreviewLabel(p.kind);
    final body = p.text.isNotEmpty ? p.text : label;
    // A deleted or undecryptable message reads as a notice, not as text.
    final italic =
        p.kind == HelixPreviewKind.deleted ||
        p.kind == HelixPreviewKind.undecryptable ||
        p.kind == HelixPreviewKind.unsupported;
    return Row(
      children: [
        if (p.status != null && !p.isDraft)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 2),
            child: HelixStatusTicks(status: p.status!, size: 16),
          ),
        if (icon != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 2),
            child: Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          ),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                if (p.isDraft)
                  TextSpan(
                    text: 'Draft: ',
                    style: TextStyle(color: scheme.error),
                  ),
                if (p.senderPrefix != null && !p.isDraft)
                  TextSpan(text: '${p.senderPrefix}: '),
                TextSpan(
                  text: body,
                  style: italic
                      ? const TextStyle(fontStyle: FontStyle.italic)
                      : null,
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: base,
          ),
        ),
      ],
    );
  }
}

class _TileIndicators extends StatelessWidget {
  const _TileIndicators({required this.item});
  final HelixChatListItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final badgeColor = item.muted ? scheme.outline : scheme.primary;
    final children = <Widget>[
      if (item.muted)
        Icon(Icons.volume_off, size: 16, color: scheme.onSurfaceVariant),
      if (item.pinned)
        Icon(Icons.push_pin, size: 16, color: scheme.onSurfaceVariant),
      if (item.archived)
        Icon(Icons.archive_outlined, size: 16, color: scheme.onSurfaceVariant),
      if (item.hasMention && item.unreadCount > 0)
        HelixCountBadge.mention(color: badgeColor),
      if (item.unreadCount > 0)
        HelixCountBadge(count: item.unreadCount, color: badgeColor)
      else if (item.markedUnread)
        HelixCountBadge.dot(color: badgeColor),
    ];
    if (children.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: HelixSpace.xs),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: HelixSpace.xxs),
          children[i],
        ],
      ],
    );
  }
}

/// The pill with an unread count, the "@" mention circle, or a plain dot.
///
/// Decorative: the row's semantics label already says "3 unread".
class HelixCountBadge extends StatelessWidget {
  const HelixCountBadge({super.key, required this.count, required this.color})
    : _kind = 0;
  const HelixCountBadge.mention({super.key, required this.color})
    : count = 0,
      _kind = 1;
  const HelixCountBadge.dot({super.key, required this.color})
    : count = 0,
      _kind = 2;

  final int count;
  final Color color;
  final int _kind;

  @override
  Widget build(BuildContext context) {
    final onColor = Theme.of(context).colorScheme.onPrimary;
    if (_kind == 2) {
      return Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }
    final text = _kind == 1 ? '@' : (count > 99 ? '99+' : '$count');
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Text(
        text,
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontSize: 12,
          height: 1.2,
          fontWeight: FontWeight.w700,
          color: onColor,
        ),
      ),
    );
  }
}

/// A swipe action revealed behind a chat row.
class HelixSwipeAction {
  const HelixSwipeAction({
    required this.icon,
    required this.label,
    required this.onTriggered,
    this.destructive = false,
  });
  final IconData icon;

  /// Also the screen-reader action name ("Archive", "Pin", "Mark as read").
  final String label;
  final VoidCallback onTriggered;
  final bool destructive;
}

/// A [HelixChatListTile] with swipe actions: swipe towards the end for
/// [endAction] (archive), towards the start for [startAction] (pin / read).
/// The row snaps back after the action fires; the app removes or updates it.
///
/// Screen readers get the same actions as custom semantics actions, and the
/// long-press menu remains the keyboard route.
class HelixSwipeableChatListTile extends StatelessWidget {
  const HelixSwipeableChatListTile({
    super.key,
    required this.item,
    this.startAction,
    this.endAction,
    this.selected = false,
    this.selectionMode = false,
    this.onTap,
    this.onLongPress,
    this.onAvatarTap,
  });

  final HelixChatListItem item;
  final HelixSwipeAction? startAction;
  final HelixSwipeAction? endAction;
  final bool selected;
  final bool selectionMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final actions = <CustomSemanticsAction, VoidCallback>{
      if (startAction != null)
        CustomSemanticsAction(label: startAction!.label):
            startAction!.onTriggered,
      if (endAction != null)
        CustomSemanticsAction(label: endAction!.label): endAction!.onTriggered,
    };
    final tile = HelixChatListTile(
      item: item,
      selected: selected,
      selectionMode: selectionMode,
      onTap: onTap,
      onLongPress: onLongPress,
      onAvatarTap: onAvatarTap,
      semanticActions: actions.isEmpty ? null : actions,
    );
    if (selectionMode || (startAction == null && endAction == null)) {
      return tile;
    }
    return Dismissible(
      key: ValueKey('swipe:${item.id}'),
      direction: startAction != null && endAction != null
          ? DismissDirection.horizontal
          : startAction != null
          ? DismissDirection.startToEnd
          : DismissDirection.endToStart,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.3,
        DismissDirection.endToStart: 0.3,
      },
      background: startAction == null
          ? null
          : _SwipeBackground(action: startAction!, atStart: true),
      secondaryBackground: endAction == null
          ? null
          : _SwipeBackground(action: endAction!, atStart: false),
      confirmDismiss: (direction) async {
        final action = direction == DismissDirection.startToEnd
            ? startAction
            : endAction;
        action?.onTriggered();
        return false;
      },
      child: tile,
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({required this.action, required this.atStart});
  final HelixSwipeAction action;
  final bool atStart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = action.destructive ? scheme.error : scheme.primary;
    final fg = action.destructive ? scheme.onError : scheme.onPrimary;
    return ExcludeSemantics(
      child: Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: HelixSpace.lg),
        alignment: atStart
            ? AlignmentDirectional.centerStart
            : AlignmentDirectional.centerEnd,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(action.icon, color: fg),
            Text(
              action.label,
              style: TextStyle(color: fg, fontSize: 12),
              textScaler: TextScaler.noScaling,
            ),
          ],
        ),
      ),
    );
  }
}

/// A fixed-height section header for a list ("Pinned", "Archived").
class HelixSectionHeader extends StatelessWidget {
  const HelixSectionHeader({super.key, required this.title, this.trailing});

  /// The exact height; use it for `itemExtent` or a prototype extent.
  static const height = 40.0;

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: HelixSpace.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// The "Archived (3)" row at the top of the chat list.
class HelixArchivedRow extends StatelessWidget {
  const HelixArchivedRow({super.key, required this.count, this.onTap});
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Archived chats, $count',
      onTap: onTap,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: HelixChatMetrics.minTarget,
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: HelixSpace.md,
                vertical: HelixSpace.xs,
              ),
              child: Row(
                children: [
                  Icon(Icons.archive_outlined, color: scheme.onSurfaceVariant),
                  const SizedBox(width: HelixSpace.md),
                  const Expanded(child: Text('Archived')),
                  Text(
                    '$count',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The chat list when there is nothing in it.
class HelixChatListEmpty extends StatelessWidget {
  const HelixChatListEmpty({super.key, this.onFindPeople});
  final VoidCallback? onFindPeople;

  @override
  Widget build(BuildContext context) => HelixEmptyState(
    icon: Icons.chat_bubble_outline,
    title: 'No chats yet',
    message:
        'Search for a name or a number to start a secure conversation. '
        'Anyone on Helix can message you unless you block them.',
    action: onFindPeople == null
        ? null
        : FilledButton.icon(
            onPressed: onFindPeople,
            icon: const Icon(Icons.search),
            label: const Text('Find people'),
          ),
  );
}

/// Placeholder rows while the chat list loads. Not scrollable; announces
/// "Loading chats" once.
class HelixChatListSkeleton extends StatelessWidget {
  const HelixChatListSkeleton({super.key, this.count = 8, this.animate = true});

  final int count;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final extent = HelixChatListTile.extentFor(
      MediaQuery.textScalerOf(context),
    );
    return Semantics(
      label: 'Loading chats',
      liveRegion: true,
      child: ExcludeSemantics(
        child: HelixShimmer(
          animate: animate,
          child: ListView.builder(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: count,
            itemExtent: extent,
            itemBuilder: (context, index) => const _SkeletonRow(),
          ),
        ),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsetsDirectional.symmetric(horizontal: HelixSpace.md),
    child: Row(
      children: [
        HelixSkeleton(width: 52, height: 52, radius: Radius.circular(26)),
        SizedBox(width: HelixSpace.sm),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HelixSkeleton(width: 160, height: 14),
              SizedBox(height: HelixSpace.xs),
              HelixSkeleton(height: 12),
            ],
          ),
        ),
      ],
    ),
  );
}

/// One action in a selection or contextual bar.
class HelixBarAction {
  const HelixBarAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });
  final IconData icon;

  /// Required: it is the accessible name of the icon button.
  final String tooltip;
  final VoidCallback? onPressed;
}

/// The app bar shown while chats or messages are selected: close, "3
/// selected", and the actions that apply.
class HelixSelectionBar extends StatelessWidget implements PreferredSizeWidget {
  const HelixSelectionBar({
    super.key,
    required this.count,
    required this.onClose,
    this.actions = const [],
  });

  final int count;
  final VoidCallback onClose;
  final List<HelixBarAction> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Cancel selection',
        onPressed: onClose,
      ),
      title: Semantics(liveRegion: true, child: Text('$count selected')),
      actions: [
        for (final action in actions)
          IconButton(
            icon: Icon(action.icon),
            tooltip: action.tooltip,
            onPressed: action.onPressed,
          ),
      ],
    );
  }
}
