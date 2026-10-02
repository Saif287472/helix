part of '../helix_remote_ui.dart';

/// "Today", "Yesterday", "12 September 2026" in a floating pill.
class HelixDateSeparator extends StatelessWidget {
  const HelixDateSeparator({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: HelixSpace.xs),
    child: Center(
      child: Semantics(
        header: true,
        child: _NoticePill(child: Text(label, style: _noticeStyle)),
      ),
    ),
  );
}

const _noticeStyle = TextStyle(
  fontSize: 12.5,
  height: 1.3,
  color: HelixChatColors.metaText,
);

class _NoticePill extends StatelessWidget {
  const _NoticePill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: HelixChatColors.notice,
      borderRadius: BorderRadius.all(Radius.circular(10)),
      boxShadow: [
        BoxShadow(
          color: HelixScrimColors.shadowSoft,
          blurRadius: 1,
          offset: Offset(0, 1),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: child,
    ),
  );
}

/// A centred notice: "Sam added Lee", "Disappearing messages are on (1 day)",
/// "Missed voice call". Text only; calls in the log are not tappable here.
class HelixSystemNotice extends StatelessWidget {
  const HelixSystemNotice({super.key, required this.text, this.icon});
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      vertical: HelixSpace.xs,
      horizontal: HelixSpace.lg,
    ),
    child: Center(
      child: Semantics(
        label: text,
        child: ExcludeSemantics(
          child: _NoticePill(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: HelixChatColors.metaText),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: _noticeStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// "3 unread messages", a full-width band between read and unread messages.
class HelixUnreadDivider extends StatelessWidget {
  const HelixUnreadDivider({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = count == 1 ? '1 unread message' : '$count unread messages';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HelixSpace.xs),
      child: Semantics(
        header: true,
        label: label,
        child: ExcludeSemantics(
          child: ColoredBox(
            color: HelixChatColors.notice,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three bouncing dots in an incoming bubble: someone is typing.
///
/// Stops animating under reduced motion, and when [animate] is false.
class HelixTypingIndicator extends StatefulWidget {
  const HelixTypingIndicator({
    super.key,
    this.label = 'Typing',
    this.animate = true,
  });

  /// Spoken, "Sam is typing".
  final String label;
  final bool animate;

  @override
  State<HelixTypingIndicator> createState() => _HelixTypingIndicatorState();
}

class _HelixTypingIndicatorState extends State<HelixTypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(HelixTypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final run = widget.animate && !MediaQuery.disableAnimationsOf(context);
    if (run && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!run && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(
      start: 8 + HelixChatMetrics.bubbleTail,
      top: HelixChatMetrics.bubbleGapNewRun,
    ),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Semantics(
        liveRegion: true,
        label: widget.label,
        child: ExcludeSemantics(
          child: DecoratedBox(
            decoration: const ShapeDecoration(
              color: HelixChatColors.incoming,
              shape: _BubbleBorder(outgoing: false, tail: true),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                        child: Transform.translate(
                          offset: Offset(0, -3 * _bounce(i)),
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: HelixChatColors.metaText,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  double _bounce(int i) {
    final t = (_controller.value - i * .15) % 1.0;
    return t < .5 ? math.sin(t * 2 * math.pi) : 0;
  }
}

/// The round "jump to latest" button with an unread count.
class HelixScrollToBottomButton extends StatelessWidget {
  const HelixScrollToBottomButton({
    super.key,
    required this.visible,
    required this.onPressed,
    this.unreadCount = 0,
  });

  final bool visible;
  final VoidCallback onPressed;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedScale(
      scale: visible ? 1 : 0,
      duration: const Duration(milliseconds: 150),
      child: IgnorePointer(
        ignoring: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: scheme.surface,
                elevation: HelixElevation.floating,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down),
                  tooltip: unreadCount > 0
                      ? 'Scroll to latest message, $unreadCount unread'
                      : 'Scroll to latest message',
                  onPressed: onPressed,
                ),
              ),
              if (unreadCount > 0)
                PositionedDirectional(
                  top: -6,
                  end: -2,
                  child: HelixCountBadge(
                    count: unreadCount,
                    color: scheme.primary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders one [HelixTimelineItem] with the right component. [actionsFor]
/// builds the callbacks for a message (called in `build`; keep it cheap).
class HelixTimelineRow extends StatelessWidget {
  const HelixTimelineRow({super.key, required this.item, this.actionsFor});

  final HelixTimelineItem item;
  final HelixBubbleActions Function(HelixMessage message)? actionsFor;

  @override
  Widget build(BuildContext context) => switch (item) {
    final HelixMessageItem i => HelixMessageBubble(
      message: i.message,
      position: i.position,
      selected: i.selected,
      actions: actionsFor?.call(i.message) ?? const HelixBubbleActions(),
    ),
    final HelixDateSeparatorItem i => HelixDateSeparator(label: i.label),
    final HelixUnreadDividerItem i => HelixUnreadDivider(count: i.count),
    final HelixSystemNoticeItem i => HelixSystemNotice(
      text: i.text,
      icon: i.icon,
    ),
  };
}

/// A conversation as a list: the page colour, bottom-anchored (`reverse`),
/// with stable keys and no per-row keep-alives. Pass newest-first items.
///
/// This is the reference for how to build a long conversation cheaply: rows
/// are built lazily, keyed by [HelixTimelineItem.id], and `findChild`
/// lookups use an id->index map built once per list change by the caller.
class HelixConversationList extends StatelessWidget {
  const HelixConversationList({
    super.key,
    required this.itemsNewestFirst,
    this.actionsFor,
    this.controller,
    this.footer,
    this.indexOfId,
  });

  final List<HelixTimelineItem> itemsNewestFirst;
  final HelixBubbleActions Function(HelixMessage message)? actionsFor;
  final ScrollController? controller;

  /// Shown at the bottom (newest end), e.g. [HelixTypingIndicator].
  final Widget? footer;

  /// id -> index in [itemsNewestFirst], to keep scroll position stable when
  /// items are inserted. Build it when the list changes, not in `build`.
  final Map<String, int>? indexOfId;

  @override
  Widget build(BuildContext context) {
    final extra = footer == null ? 0 : 1;
    return ColoredBox(
      color: HelixChatColors.page,
      child: ListView.builder(
        reverse: true,
        controller: controller,
        addAutomaticKeepAlives: false,
        padding: const EdgeInsets.symmetric(vertical: HelixSpace.xs),
        itemCount: itemsNewestFirst.length + extra,
        findChildIndexCallback: indexOfId == null
            ? null
            : (key) {
                if (key is ValueKey<String>) {
                  final i = indexOfId![key.value];
                  return i == null ? null : i + extra;
                }
                return null;
              },
        itemBuilder: (context, index) {
          if (footer != null && index == 0) return footer;
          final item = itemsNewestFirst[index - extra];
          return HelixTimelineRow(
            key: ValueKey(item.id),
            item: item,
            actionsFor: actionsFor,
          );
        },
      ),
    );
  }
}
