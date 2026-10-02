part of '../helix_remote_ui.dart';

/// A rounded search field with a leading magnifier and a clear button.
///
/// The text lives in [controller]; the clear button appears only while there
/// is text. Used standalone (Chats and Calls people search) and inside
/// [HelixSearchAppBar].
class HelixSearchField extends StatelessWidget {
  const HelixSearchField({
    super.key,
    required this.controller,
    this.hint = 'Search',
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.focusNode,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: HelixChatMetrics.minTarget),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.all(Radius.circular(24)),
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsetsDirectional.only(start: HelixSpace.sm),
              child: ExcludeSemantics(child: Icon(Icons.search)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: HelixSpace.xs),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: autofocus,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    hintText: hint,
                    hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => value.text.isEmpty
                  ? const SizedBox(width: HelixSpace.sm)
                  : IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Clear search',
                      onPressed: () {
                        controller.clear();
                        onChanged?.call('');
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// An app bar that is either a title with a search button or, while
/// [searching], a search field with a back button.
class HelixSearchAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HelixSearchAppBar({
    super.key,
    required this.title,
    required this.searching,
    required this.onSearchChanged,
    required this.controller,
    this.searchHint = 'Search',
    this.onQueryChanged,
    this.actions = const [],
  });

  final String title;
  final bool searching;

  /// Called with the new `searching` value (the search button, the back
  /// button).
  final ValueChanged<bool> onSearchChanged;
  final TextEditingController controller;
  final String searchHint;
  final ValueChanged<String>? onQueryChanged;

  /// Shown after the search button when not searching.
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    if (searching) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Close search',
          onPressed: () {
            controller.clear();
            onQueryChanged?.call('');
            onSearchChanged(false);
          },
        ),
        title: HelixSearchField(
          controller: controller,
          hint: searchHint,
          autofocus: true,
          onChanged: onQueryChanged,
        ),
      );
    }
    return AppBar(
      title: Text(title),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search',
          onPressed: () => onSearchChanged(true),
        ),
        ...actions,
      ],
    );
  }
}

/// Text with [HelixHighlightedText.ranges] emphasised. Ranges that fall
/// outside the text are ignored.
class HelixHighlightedTextView extends StatelessWidget {
  const HelixHighlightedTextView({
    super.key,
    required this.text,
    this.style,
    this.maxLines = 1,
  });

  final HelixHighlightedText text;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = style ?? DefaultTextStyle.of(context).style;
    final value = text.text;
    final ranges = [
      for (final r in text.ranges)
        if (r.start >= 0 && r.length > 0 && r.end <= value.length) r,
    ]..sort((a, b) => a.start.compareTo(b.start));
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final r in ranges) {
      if (r.start < cursor) continue;
      if (r.start > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, r.start)));
      }
      spans.add(
        TextSpan(
          text: value.substring(r.start, r.end),
          style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary),
        ),
      );
      cursor = r.end;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor)));
    }
    return Text.rich(
      TextSpan(children: spans),
      style: base,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// A two-line list row shared by people, call-log and message-search rows:
/// avatar, a title line with an optional trailing label, a subtitle line, and
/// an optional trailing widget. Exactly [HelixChatListTile.extentFor] tall,
/// so these lists share the chat list's `itemExtent` contract.
class _TwoLineRow extends StatelessWidget {
  const _TwoLineRow({
    required this.avatar,
    required this.title,
    required this.subtitle,
    this.titleColor,
    this.topTrailing,
    this.trailing,
    this.semanticLabel,
    this.onTap,
    this.onLongPress,
  });

  final Widget avatar;
  final String title;
  final Widget subtitle;
  final Color? titleColor;
  final String? topTrailing;
  final Widget? trailing;
  final String? semanticLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    return Semantics(
      container: true,
      button: onTap != null,
      label: semanticLabel ?? title,
      onTap: onTap,
      onLongPress: onLongPress,
      child: ExcludeSemantics(
        child: SizedBox(
          height: HelixChatListTile.extentFor(scaler),
          child: Material(
            color: theme.scaffoldBackgroundColor,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: HelixSpace.md,
                  end: HelixSpace.xs,
                ),
                child: Row(
                  children: [
                    avatar,
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
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium!.copyWith(
                                    fontSize: 16,
                                    height: HelixChatListTile._titleHeight / 16,
                                    fontWeight: FontWeight.w500,
                                    color: titleColor,
                                  ),
                                ),
                              ),
                              if (topTrailing != null)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    start: HelixSpace.xs,
                                  ),
                                  child: Text(
                                    topTrailing!,
                                    maxLines: 1,
                                    style: theme.textTheme.labelSmall!.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: HelixChatListTile._titleGap),
                          SizedBox(
                            height: scaler.scale(
                              HelixChatListTile._previewHeight,
                            ),
                            child: DefaultTextStyle.merge(
                              style: TextStyle(
                                fontSize: 14,
                                height: HelixChatListTile._previewHeight / 14,
                                color: scheme.onSurfaceVariant,
                              ),
                              child: subtitle,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ?trailing,
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

/// A person in a people list or a people search result. The name follows the
/// product's naming order (phone-book name, nickname, number, `~Helix name`)
/// and the line under it is the number or the `~Helix name`.
class HelixPersonTile extends StatelessWidget {
  const HelixPersonTile({
    super.key,
    required this.person,
    this.onTap,
    this.onLongPress,
    this.trailing,
    this.highlight,
  });

  final HelixPersonItem person;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  /// A search hit to emphasise inside the name.
  final HelixHighlightedText? highlight;

  @override
  Widget build(BuildContext context) {
    final names = person.names;
    final secondary = person.blocked
        ? 'Blocked'
        : (names.secondary ?? person.about);
    return _TwoLineRow(
      avatar: HelixAvatar(
        model: person.avatar,
        size: HelixAvatarSize.lg,
        online: person.online,
      ),
      title: names.display,
      semanticLabel: [
        names.display,
        ?secondary,
        if (person.online) 'online',
      ].join(', '),
      subtitle: Text(
        secondary ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// A message hit: chat name and date on top, the snippet with the match
/// emphasised below.
class HelixMessageSearchTile extends StatelessWidget {
  const HelixMessageSearchTile({super.key, required this.result, this.onTap});

  final HelixMessageSearchResult result;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final who = r.senderLabel == null ? '' : '${r.senderLabel}: ';
    return _TwoLineRow(
      avatar: HelixAvatar(model: r.avatar, size: HelixAvatarSize.lg),
      title: r.chatTitle,
      topTrailing: r.timeLabel,
      semanticLabel: '${r.chatTitle}, $who${r.snippet.text}, ${r.timeLabel}',
      subtitle: Row(
        children: [
          if (who.isNotEmpty) Text(who),
          Expanded(child: HelixHighlightedTextView(text: r.snippet)),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// One row of the call log: who, how it went (red when missed) and when, and a
/// button to call back.
class HelixCallLogTile extends StatelessWidget {
  const HelixCallLogTile({
    super.key,
    required this.item,
    this.onTap,
    this.onCallBack,
    this.onLongPress,
  });

  final HelixCallLogItem item;

  /// Open the call details.
  final VoidCallback? onTap;

  /// Start the same kind of call again.
  final VoidCallback? onCallBack;
  final VoidCallback? onLongPress;

  static String directionLabel(HelixCallDirection d) => switch (d) {
    HelixCallDirection.incoming => 'Incoming',
    HelixCallDirection.outgoing => 'Outgoing',
    HelixCallDirection.missed => 'Missed',
    HelixCallDirection.declined => 'Declined',
    HelixCallDirection.failed => 'Failed',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final i = item;
    final bad =
        i.direction == HelixCallDirection.missed ||
        i.direction == HelixCallDirection.failed;
    final arrow = switch (i.direction) {
      HelixCallDirection.incoming => Icons.call_received,
      HelixCallDirection.outgoing => Icons.call_made,
      HelixCallDirection.missed => Icons.call_missed,
      HelixCallDirection.declined => Icons.call_end,
      HelixCallDirection.failed => Icons.error_outline,
    };
    final arrowColor = bad
        ? scheme.error
        : (i.direction == HelixCallDirection.declined
              ? scheme.onSurfaceVariant
              : HelixStatusColors.positive);
    final kind = i.video ? 'video call' : 'voice call';
    final title = i.count > 1 ? '${i.title} (${i.count})' : i.title;
    return _TwoLineRow(
      avatar: HelixAvatar(model: i.avatar, size: HelixAvatarSize.lg),
      title: title,
      titleColor: bad ? scheme.error : null,
      semanticLabel:
          '$title, ${directionLabel(i.direction)} $kind, ${i.timeLabel}'
          '${i.durationLabel == null ? '' : ', ${i.durationLabel}'}',
      subtitle: Row(
        children: [
          Icon(arrow, size: 16, color: arrowColor),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              i.timeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: onCallBack == null
          ? null
          : IconButton(
              icon: Icon(i.video ? Icons.videocam_outlined : Icons.call),
              color: scheme.primary,
              tooltip: i.video ? 'Video call' : 'Voice call',
              onPressed: onCallBack,
            ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

/// "No results for 'x'" for a search that found nothing.
class HelixNoResults extends StatelessWidget {
  const HelixNoResults({super.key, required this.query});
  final String query;

  @override
  Widget build(BuildContext context) => HelixEmptyState(
    icon: Icons.search_off,
    title: 'No results',
    message: query.isEmpty
        ? 'Try a different name or number.'
        : 'Nothing matches "$query".',
  );
}
