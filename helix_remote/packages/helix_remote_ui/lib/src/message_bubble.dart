part of '../helix_remote_ui.dart';

/// Every callback a bubble can raise. All optional: a bubble with none is a
/// read-only rendering (the gallery, goldens).
///
/// Quote and reaction taps are exposed to assistive technology as custom
/// semantics actions on the bubble rather than as 24 px buttons, so a screen
/// reader gets the same reach as a finger without breaking the 48 px rule.
class HelixBubbleActions {
  const HelixBubbleActions({
    this.onTap,
    this.onLongPress,
    this.onReply,
    this.onQuoteTap,
    this.onReactionsTap,
    this.onRetry,
    this.onLinkTap,
    this.onMediaTap,
    this.onTransferTap,
    this.onAudioToggle,
    this.onAudioSpeed,
    this.onAudioSeek,
    this.onPlaceholderAction,
    this.onAuthorTap,
    this.onViewOnceTap,
    this.onLocationTap,
    this.onContactTap,
  });

  final VoidCallback? onTap;

  /// Opens the message action menu.
  final VoidCallback? onLongPress;

  /// Swipe-to-reply (and the "Reply" screen-reader action).
  final VoidCallback? onReply;

  /// Jump to the quoted message.
  final VoidCallback? onQuoteTap;

  /// Show who reacted.
  final VoidCallback? onReactionsTap;

  /// Resend a failed message.
  final VoidCallback? onRetry;
  final ValueChanged<String>? onLinkTap;

  /// Open media item [index] in the viewer.
  final ValueChanged<int>? onMediaTap;

  /// Start or cancel the transfer of media item [index].
  final ValueChanged<int>? onTransferTap;
  final VoidCallback? onAudioToggle;

  /// Cycle the playback speed.
  final VoidCallback? onAudioSpeed;

  /// Seek to a fraction 0..1 of the voice note.
  final ValueChanged<double>? onAudioSeek;

  /// "Ask to resend" (undecryptable) or "Update Helix" (unsupported).
  final VoidCallback? onPlaceholderAction;
  final VoidCallback? onAuthorTap;
  final VoidCallback? onViewOnceTap;
  final VoidCallback? onLocationTap;
  final VoidCallback? onContactTap;
}

/// The first strong-direction letter of [text] decides its direction, as in
/// every messenger: an Arabic message in an English UI reads right to left.
/// Null when [text] has no letters (digits, emoji only).
TextDirection? helixTextDirectionOf(String text) {
  for (final rune in text.runes) {
    final rtl =
        (rune >= 0x0590 && rune <= 0x08FF) ||
        (rune >= 0xFB1D && rune <= 0xFDFF) ||
        (rune >= 0xFE70 && rune <= 0xFEFF) ||
        (rune >= 0x10800 && rune <= 0x10FFF) ||
        (rune >= 0x1E800 && rune <= 0x1EFFF);
    if (rtl) return TextDirection.rtl;
    final isLatinLetter =
        (rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A) ||
        (rune >= 0xC0 && rune <= 0x058F) ||
        (rune >= 0x0900 && rune <= 0x1FFF) ||
        (rune >= 0x2C00 && rune <= 0xD7FF);
    if (isLatinLetter) return TextDirection.ltr;
  }
  return null;
}

/// One message bubble: incoming or outgoing, grouped into runs, with its
/// reply quote, forwarded/edited labels, reactions, ticks and content.
///
/// Stateless and cheap to build. Height is content-dependent, so conversation
/// lists should not set `itemExtent`; give each row a `ValueKey(item.id)` and
/// `findChildIndexCallback` instead, and set `addAutomaticKeepAlives: false`.
class HelixMessageBubble extends StatelessWidget {
  const HelixMessageBubble({
    super.key,
    required this.message,
    this.position = HelixRunPosition.single,
    this.selected = false,
    this.actions = const HelixBubbleActions(),
  });

  final HelixMessage message;
  final HelixRunPosition position;
  final bool selected;
  final HelixBubbleActions actions;

  bool get _tail =>
      position == HelixRunPosition.first || position == HelixRunPosition.single;

  static String summaryLabel(HelixMessage m) {
    final b = StringBuffer();
    b.write(m.outgoing ? 'You' : (m.authorName ?? ''));
    if (b.isNotEmpty) b.write(': ');
    if (m.forwarded) b.write('Forwarded. ');
    final r = m.reply;
    if (r != null) {
      b.write(
        'Reply to ${r.authorName}: '
        '${r.text.isEmpty ? helixPreviewLabel(r.kind) : r.text}. ',
      );
    }
    final c = m.content;
    switch (c) {
      case HelixTextContent():
        b.write(c.text);
        if (c.linkPreview?.title != null) {
          b.write('. Link: ${c.linkPreview!.title}');
        }
      case HelixMediaContent():
        b.write(
          c.items.length == 1
              ? (c.items.first.isVideo ? 'Video' : 'Photo')
              : '${c.items.length} photos and videos',
        );
        if (c.caption.isNotEmpty) b.write(', ${c.caption}');
      case HelixAudioContent():
        b.write(c.isVoiceNote ? 'Voice message' : 'Audio');
        b.write(', ${c.durationLabel}');
      case HelixDocumentContent():
        b.write('Document ${c.name}');
        if (c.sizeLabel.isNotEmpty) b.write(', ${c.sizeLabel}');
        if (c.caption.isNotEmpty) b.write(', ${c.caption}');
      case HelixLocationContent():
        b.write('Location');
        if (c.label.isNotEmpty) b.write(', ${c.label}');
      case HelixContactContent():
        b.write('Contact ${c.name}');
      case HelixPlaceholderContent():
        b.write(_placeholderText(c.kind, m.outgoing));
      case HelixViewOnceContent():
        b.write(
          c.opened
              ? 'View once ${c.isVideo ? 'video' : 'photo'}, opened'
              : 'View once ${c.isVideo ? 'video' : 'photo'}',
        );
    }
    if (m.edited) b.write(', edited');
    if (m.expiresLabel != null) b.write(', disappears after ${m.expiresLabel}');
    b.write(', ${m.timeLabel}');
    if (m.outgoing) b.write(', ${HelixStatusTicks.labelFor(m.status)}');
    if (m.reactions.isNotEmpty) {
      b.write(
        ', reactions ${m.reactions.map((r) => '${r.emoji} ${r.count}').join(', ')}',
      );
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = message;
    final base = m.outgoing
        ? HelixChatColors.outgoing
        : HelixChatColors.incoming;
    final color = m.highlighted
        ? Color.alphaBlend(scheme.primary.withValues(alpha: .25), base)
        : base;
    final content = m.content;
    final mediaOnly =
        content is HelixMediaContent &&
        content.caption.isEmpty &&
        m.reply == null &&
        !m.forwarded &&
        (m.authorName == null || m.outgoing || !_tail);

    final semanticActions = <CustomSemanticsAction, VoidCallback>{
      if (actions.onReply != null)
        const CustomSemanticsAction(label: 'Reply'): actions.onReply!,
      if (m.reply != null && actions.onQuoteTap != null)
        const CustomSemanticsAction(label: 'Go to replied message'):
            actions.onQuoteTap!,
      if (m.reactions.isNotEmpty && actions.onReactionsTap != null)
        const CustomSemanticsAction(label: 'Show reactions'):
            actions.onReactionsTap!,
    };

    final body = _BubbleBody(
      message: m,
      tail: _tail,
      actions: actions,
      mediaOnly: mediaOnly,
    );

    final bubble = DecoratedBox(
      decoration: ShapeDecoration(
        color: color,
        shape: _BubbleBorder(outgoing: m.outgoing, tail: _tail),
      ),
      child: Padding(
        padding: mediaOnly
            ? const EdgeInsets.all(3)
            : const EdgeInsets.fromLTRB(9, 6, 9, 6),
        child: body,
      ),
    );

    final interactive =
        content is HelixMediaContent ||
        content is HelixAudioContent ||
        content is HelixViewOnceContent ||
        (content is HelixPlaceholderContent &&
            actions.onPlaceholderAction != null) ||
        content is HelixContactContent ||
        content is HelixLocationContent ||
        (content is HelixTextContent && content.linkPreview != null);

    Widget bubbleNode = Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: actions.onTap,
        onLongPress: actions.onLongPress,
        excludeFromSemantics: true,
        child: bubble,
      ),
    );
    bubbleNode = Semantics(
      container: true,
      explicitChildNodes: interactive,
      // A bubble with interactive content (media, play button) keeps its
      // children addressable; a text bubble is one node with the whole story.
      label: interactive ? null : summaryLabel(m),
      selected: selected,
      onTap: actions.onTap,
      onLongPress: actions.onLongPress,
      customSemanticsActions: semanticActions.isEmpty ? null : semanticActions,
      child: interactive ? bubbleNode : ExcludeSemantics(child: bubbleNode),
    );

    final failed = m.outgoing && m.status == HelixDeliveryStatus.failed;
    final column = Column(
      crossAxisAlignment: m.outgoing
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SwipeToReply(
          onReply: actions.onReply,
          outgoing: m.outgoing,
          child: bubbleNode,
        ),
        if (failed) _FailedRow(onRetry: actions.onRetry),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = math.min(
          constraints.maxWidth * HelixChatMetrics.bubbleMaxWidthFactor,
          560.0,
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withValues(alpha: .18) : null,
          ),
          child: Padding(
            padding: EdgeInsetsDirectional.only(
              top: _tail
                  ? HelixChatMetrics.bubbleGapNewRun
                  : HelixChatMetrics.bubbleGapSameRun,
              start: m.outgoing ? 0 : 8,
              end: m.outgoing ? 8 : 0,
            ),
            child: Align(
              alignment: m.outgoing
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Padding(
                  // Every bubble reserves the tail's width so runs line up.
                  padding: EdgeInsetsDirectional.only(
                    start: m.outgoing ? 0 : HelixChatMetrics.bubbleTail,
                    end: m.outgoing ? HelixChatMetrics.bubbleTail : 0,
                  ),
                  child: column,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

String _placeholderText(HelixPlaceholderKind kind, bool outgoing) =>
    switch (kind) {
      HelixPlaceholderKind.deleted =>
        outgoing ? 'You deleted this message' : 'This message was deleted',
      HelixPlaceholderKind.undecryptable => "Couldn't decrypt this message",
      HelixPlaceholderKind.unsupported =>
        'This message needs a newer version of Helix',
      HelixPlaceholderKind.expired => 'This message has disappeared',
    };

class _BubbleBorder extends ShapeBorder {
  const _BubbleBorder({required this.outgoing, required this.tail});
  final bool outgoing;
  final bool tail;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    // "End" is the right in LTR; outgoing bubbles carry the tail at the end,
    // incoming ones at the start.
    final rtl = textDirection == TextDirection.rtl;
    final tailRight = outgoing != rtl;
    const r = Radius.circular(HelixChatMetrics.bubbleRadius);
    final rr = RRect.fromRectAndCorners(
      rect,
      topLeft: tail && !tailRight ? Radius.zero : r,
      topRight: tail && tailRight ? Radius.zero : r,
      bottomLeft: r,
      bottomRight: r,
    );
    final path = Path()..addRRect(rr);
    if (tail) {
      const w = HelixChatMetrics.bubbleTail;
      const h = 10.0;
      if (tailRight) {
        path.addPolygon([
          Offset(rect.right, rect.top),
          Offset(rect.right + w, rect.top),
          Offset(rect.right, rect.top + h),
        ], true);
      } else {
        path.addPolygon([
          Offset(rect.left, rect.top),
          Offset(rect.left - w, rect.top),
          Offset(rect.left, rect.top + h),
        ], true);
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;

  @override
  bool operator ==(Object other) =>
      other is _BubbleBorder &&
      other.outgoing == outgoing &&
      other.tail == tail;

  @override
  int get hashCode => Object.hash(outgoing, tail);
}

class _FailedRow extends StatelessWidget {
  const _FailedRow({this.onRetry});
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 16, color: scheme.error),
        const SizedBox(width: HelixSpace.xxs),
        Text('Not sent', style: TextStyle(color: scheme.error, fontSize: 12)),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Retry')),
      ],
    );
  }
}

/// Drag a bubble towards the centre to reply; a haptic-free, state-light
/// version of the messenger gesture. Inert when [onReply] is null.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({
    required this.child,
    required this.onReply,
    required this.outgoing,
  });
  final Widget child;
  final VoidCallback? onReply;
  final bool outgoing;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  static const _trigger = 56.0;
  double _dx = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.onReply == null) return widget.child;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // Drag towards the opposite edge from the one the bubble hugs.
    final towardsEnd = !rtl;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) => setState(() {
        final next = _dx + d.delta.dx * (towardsEnd ? 1 : -1);
        _dx = next.clamp(0.0, _trigger * 1.4);
      }),
      onHorizontalDragEnd: (_) {
        final fire = _dx >= _trigger;
        setState(() => _dx = 0);
        if (fire) widget.onReply!();
      },
      onHorizontalDragCancel: () => setState(() => _dx = 0),
      excludeFromSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_dx > 8)
            PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: Opacity(
                  opacity: (_dx / _trigger).clamp(0.0, 1.0),
                  child: ExcludeSemantics(
                    child: Icon(
                      Icons.reply,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_dx * (towardsEnd ? 1 : -1), 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// The inside of a bubble: author, forwarded label, quote, content, meta,
/// reactions.
class _BubbleBody extends StatelessWidget {
  const _BubbleBody({
    required this.message,
    required this.tail,
    required this.actions,
    required this.mediaOnly,
  });

  final HelixMessage message;
  final bool tail;
  final HelixBubbleActions actions;
  final bool mediaOnly;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final c = m.content;
    final children = <Widget>[];

    if (!m.outgoing && m.authorName != null && tail && !mediaOnly) {
      children.add(
        _AuthorName(
          name: m.authorName!,
          colorIndex: m.authorColorIndex,
          onTap: actions.onAuthorTap,
        ),
      );
    }
    if (m.forwarded) {
      children.add(
        const Padding(
          padding: EdgeInsets.only(bottom: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forward, size: 14, color: HelixChatColors.metaText),
              SizedBox(width: 4),
              Flexible(
                child: Text(
                  'Forwarded',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: HelixChatColors.metaText,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (m.reply != null) {
      children.add(
        _ReplyQuoteBlock(quote: m.reply!, onTap: actions.onQuoteTap),
      );
    }

    switch (c) {
      case HelixTextContent():
        children.add(_TextWithMeta(message: m, content: c, actions: actions));
        if (c.linkPreview != null) {
          children.insert(
            children.length - 1,
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: HelixLinkPreviewCard(
                preview: c.linkPreview!,
                onTap: actions.onLinkTap == null
                    ? null
                    : () => actions.onLinkTap!(c.linkPreview!.url),
              ),
            ),
          );
        }
      case HelixMediaContent():
        children.add(
          HelixMediaGrid(
            items: c.items,
            onTap: actions.onMediaTap,
            onTransferTap: actions.onTransferTap,
            overlay: mediaOnly ? _BubbleMeta(message: m, onMedia: true) : null,
          ),
        );
        if (c.caption.isNotEmpty) {
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
              child: _TextWithMeta(
                message: m,
                content: HelixTextContent(c.caption),
                actions: actions,
              ),
            ),
          );
        } else if (!mediaOnly) {
          children.add(_MetaRow(message: m));
        }
      case HelixAudioContent():
        children.add(
          HelixAudioBubbleBody(
            content: c,
            outgoing: m.outgoing,
            onToggle: actions.onAudioToggle,
            onSpeed: actions.onAudioSpeed,
            onSeek: actions.onAudioSeek,
            onTransferTap: actions.onTransferTap == null
                ? null
                : () => actions.onTransferTap!(0),
          ),
        );
        children.add(_MetaRow(message: m));
      case HelixDocumentContent():
        children.add(
          HelixDocumentTile(
            content: c,
            onTap: actions.onMediaTap == null
                ? null
                : () => actions.onMediaTap!(0),
            onTransferTap: actions.onTransferTap == null
                ? null
                : () => actions.onTransferTap!(0),
          ),
        );
        if (c.caption.isNotEmpty) {
          children.add(
            _TextWithMeta(
              message: m,
              content: HelixTextContent(c.caption),
              actions: actions,
            ),
          );
        } else {
          children.add(_MetaRow(message: m));
        }
      case HelixLocationContent():
        children.add(
          HelixLocationCard(content: c, onTap: actions.onLocationTap),
        );
        children.add(_MetaRow(message: m));
      case HelixContactContent():
        children.add(HelixContactCard(content: c, onTap: actions.onContactTap));
        children.add(_MetaRow(message: m));
      case HelixPlaceholderContent():
        children.add(
          HelixPlaceholderBody(
            kind: c.kind,
            outgoing: m.outgoing,
            onAction: actions.onPlaceholderAction,
          ),
        );
        children.add(_MetaRow(message: m));
      case HelixViewOnceContent():
        children.add(
          HelixViewOnceTile(
            content: c,
            outgoing: m.outgoing,
            onTap: actions.onViewOnceTap,
          ),
        );
        children.add(_MetaRow(message: m));
    }

    if (m.reactions.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: HelixReactionsRow(
            reactions: m.reactions,
            onTap: actions.onReactionsTap,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

class _AuthorName extends StatelessWidget {
  const _AuthorName({required this.name, required this.colorIndex, this.onTap});
  final String name;
  final int colorIndex;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = HelixColorTokens.avatarPalette;
    // The avatar palette is tuned for white initials; darken it so a name
    // reads at 4.5:1 on a white bubble.
    final color = Color.lerp(
      palette[colorIndex.abs() % palette.length],
      HelixScrimColors.backdrop,
      .45,
    )!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: GestureDetector(
        onTap: onTap,
        excludeFromSemantics: true,
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// The quoted message at the top of a reply bubble.
class _ReplyQuoteBlock extends StatelessWidget {
  const _ReplyQuoteBlock({required this.quote, this.onTap});
  final HelixReplyQuote quote;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = HelixColorTokens.avatarPalette;
    final bar = palette[quote.authorColorIndex.abs() % palette.length];
    final nameColor = Color.lerp(bar, HelixScrimColors.backdrop, .45)!;
    final label = quote.missing
        ? 'Original message not available'
        : (quote.text.isEmpty ? helixPreviewLabel(quote.kind) : quote.text);
    final icon = quote.missing ? null : helixPreviewIcon(quote.kind);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        onTap: onTap,
        excludeFromSemantics: true,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: HelixScrimColors.shadowSoft,
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: bar,
                    borderRadius: const BorderRadiusDirectional.horizontal(
                      start: Radius.circular(8),
                    ),
                  ),
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          quote.authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: nameColor,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (icon != null)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  end: 2,
                                ),
                                child: Icon(
                                  icon,
                                  size: 14,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            Flexible(
                              child: Text(
                                label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                  fontStyle: quote.missing
                                      ? FontStyle.italic
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (quote.thumbnail != null)
                  ClipRRect(
                    borderRadius: const BorderRadiusDirectional.horizontal(
                      end: Radius.circular(8),
                    ).resolve(Directionality.of(context)),
                    child: Image(
                      image: ResizeImage.resizeIfNeeded(
                        96,
                        null,
                        quote.thumbnail!,
                      ),
                      width: 48,
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => const SizedBox(width: 48),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Time, "Edited", the disappearing-timer marker, a star and the tick.
class _BubbleMeta extends StatelessWidget {
  const _BubbleMeta({required this.message, this.onMedia = false});
  final HelixMessage message;

  /// Drawn over a photo: white on a dark pill.
  final bool onMedia;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final color = onMedia
        ? HelixScrimColors.onBackdrop
        : HelixChatColors.metaText;
    final style = TextStyle(fontSize: 11, height: 1.2, color: color);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (m.starred) ...[
          Icon(Icons.star, size: 12, color: color),
          const SizedBox(width: 2),
        ],
        if (m.expiresLabel != null) ...[
          Icon(Icons.timer_outlined, size: 12, color: color),
          Text(m.expiresLabel!, style: style),
          const SizedBox(width: 4),
        ],
        if (m.edited) ...[
          Text('Edited', style: style),
          const SizedBox(width: 4),
        ],
        Text(m.timeLabel, style: style),
        if (m.outgoing) ...[
          const SizedBox(width: 3),
          HelixStatusTicks(
            status: m.status,
            size: 15,
            color: onMedia ? HelixScrimColors.onBackdrop : color,
          ),
        ],
      ],
    );
    if (!onMedia) return row;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: HelixScrimColors.barrier,
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: row,
      ),
    );
  }

  /// A conservative width for the meta row, used to leave room for it at the
  /// end of the last line of text without measuring.
  static double estimateWidth(HelixMessage m, TextScaler scaler) {
    final chars =
        m.timeLabel.length +
        (m.edited ? 7 : 0) +
        (m.expiresLabel == null ? 0 : m.expiresLabel!.length + 2) +
        (m.starred ? 2 : 0);
    final textW = scaler.scale(6.4) * chars;
    return textW + (m.outgoing ? 22 : 0) + 8;
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.message});
  final HelixMessage message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Align(
      alignment: AlignmentDirectional.centerEnd,
      child: _BubbleMeta(message: message),
    ),
  );
}

/// Message text with the meta row sharing the last line when it fits and
/// wrapping to its own line when it does not.
class _TextWithMeta extends StatelessWidget {
  const _TextWithMeta({
    required this.message,
    required this.content,
    required this.actions,
  });
  final HelixMessage message;
  final HelixTextContent content;
  final HelixBubbleActions actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final dir =
        helixTextDirectionOf(content.text) ?? Directionality.of(context);
    final style = TextStyle(fontSize: 16, height: 1.3, color: scheme.onSurface);
    final reserve = _BubbleMeta.estimateWidth(message, scaler);
    final plain =
        content.mentions.isEmpty &&
        !content.text.contains('http') &&
        !content.text.contains('www.');
    final Widget text = plain
        ? Text.rich(
            TextSpan(
              children: [
                TextSpan(text: content.text),
                WidgetSpan(child: SizedBox(width: reserve, height: 1)),
              ],
            ),
            style: style,
          )
        : _RichMessageText(
            text: content.text,
            mentions: content.mentions,
            style: style,
            linkColor: scheme.primary,
            mentionColor: scheme.primary,
            reserve: reserve,
            onLinkTap: actions.onLinkTap,
          );
    return Directionality(
      textDirection: dir,
      child: Stack(
        children: [
          text,
          PositionedDirectional(
            end: 0,
            bottom: 0,
            child: _BubbleMeta(message: message),
          ),
        ],
      ),
    );
  }
}

final _linkPattern = RegExp(r'(?:https?://|www\.)[^\s<>]+');

/// Text with bold mentions and tappable links. Stateful only to own the tap
/// recognizers; plain messages never reach it.
class _RichMessageText extends StatefulWidget {
  const _RichMessageText({
    required this.text,
    required this.mentions,
    required this.style,
    required this.linkColor,
    required this.mentionColor,
    required this.reserve,
    this.onLinkTap,
  });

  final String text;
  final List<HelixTextRange> mentions;
  final TextStyle style;
  final Color linkColor;
  final Color mentionColor;
  final double reserve;
  final ValueChanged<String>? onLinkTap;

  @override
  State<_RichMessageText> createState() => _RichMessageTextState();
}

class _RichMessageTextState extends State<_RichMessageText> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  List<InlineSpan> _spans() {
    _disposeRecognizers();
    final text = widget.text;
    // Mentions and links as (start, end, kind) intervals, mentions first.
    final marks = <(int, int, bool)>[
      for (final m in widget.mentions)
        if (m.start >= 0 && m.length > 0 && m.end <= text.length)
          (m.start, m.end, true),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    for (final match in _linkPattern.allMatches(text)) {
      final overlaps = marks.any((x) => match.start < x.$2 && x.$1 < match.end);
      if (!overlaps) marks.add((match.start, match.end, false));
    }
    marks.sort((a, b) => a.$1.compareTo(b.$1));
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final (start, end, isMention) in marks) {
      if (start < cursor) continue;
      if (start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, start)));
      }
      final piece = text.substring(start, end);
      if (isMention) {
        spans.add(
          TextSpan(
            text: piece,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: widget.mentionColor,
            ),
          ),
        );
      } else {
        final recognizer = TapGestureRecognizer()
          ..onTap = widget.onLinkTap == null
              ? null
              : () => widget.onLinkTap!(piece);
        _recognizers.add(recognizer);
        spans.add(
          TextSpan(
            text: piece,
            recognizer: recognizer,
            style: TextStyle(
              color: widget.linkColor,
              decoration: TextDecoration.underline,
            ),
          ),
        );
      }
      cursor = end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    spans.add(WidgetSpan(child: SizedBox(width: widget.reserve, height: 1)));
    return spans;
  }

  @override
  Widget build(BuildContext context) =>
      Text.rich(TextSpan(children: _spans()), style: widget.style);
}

/// The emoji chips under a message: each distinct emoji with its count; yours
/// is outlined. One tap target for the whole row (who reacted).
class HelixReactionsRow extends StatelessWidget {
  const HelixReactionsRow({super.key, required this.reactions, this.onTap});

  final List<HelixReaction> reactions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      excludeFromSemantics: true,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final r in reactions)
            DecoratedBox(
              decoration: BoxDecoration(
                color: HelixChatColors.notice,
                borderRadius: const BorderRadius.all(Radius.circular(12)),
                border: Border.all(
                  color: r.mine ? scheme.primary : scheme.outlineVariant,
                  width: r.mine ? 1.5 : 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  r.count > 1 ? '${r.emoji} ${r.count}' : r.emoji,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
