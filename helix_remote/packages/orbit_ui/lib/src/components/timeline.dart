import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:orbit_ui/src/components/avatar.dart';
import 'package:orbit_ui/src/components/chat_rows.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/theme/css_gradient.dart';
import 'package:orbit_ui/src/theme/effect_shapes.dart';
import 'package:orbit_ui/src/theme/motion.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// What the parts of a bubble do when touched, for every message of a
/// timeline: each callback names the message by [HelixMessage.id]. All are
/// optional; a bubble draws the same with or without them, and a part with
/// no callback takes no touches (the bubble's own tap and long press get
/// them).
class OrbitBubbleActions {
  const OrbitBubbleActions({
    this.onReply,
    this.onQuote,
    this.onReactions,
    this.onLink,
    this.onMedia,
    this.onViewOnce,
    this.onAudioToggle,
    this.onAudioSpeed,
    this.onAudioSeek,
    this.onAuthor,
  });

  /// Swiped 56px towards the middle (theirs right, yours left).
  final ValueChanged<String>? onReply;

  /// The quoted message was tapped.
  final ValueChanged<String>? onQuote;

  /// A reaction under the bubble was tapped.
  final ValueChanged<String>? onReactions;

  /// A link in the text, or the link card, was tapped (the address).
  final ValueChanged<String>? onLink;

  /// Picture [index] of a media grid, or a document's button, was tapped.
  final void Function(String id, int index)? onMedia;
  final ValueChanged<String>? onViewOnce;

  /// A voice message's play button.
  final ValueChanged<String>? onAudioToggle;

  /// A voice message's speed chip.
  final ValueChanged<String>? onAudioSpeed;

  /// The waveform was tapped or dragged, at a fraction 0..1 of the note.
  final void Function(String id, double fraction)? onAudioSeek;

  /// The author's picture beside a group bubble was tapped.
  final ValueChanged<String>? onAuthor;

  static const none = OrbitBubbleActions();
}

/// The message a bubble's parts belong to, and what touching them does.
class _BubbleTaps extends InheritedWidget {
  const _BubbleTaps({
    required this.id,
    required this.actions,
    required super.child,
  });

  final String id;
  final OrbitBubbleActions actions;

  static _BubbleTaps? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BubbleTaps>();

  @override
  bool updateShouldNotify(_BubbleTaps old) =>
      old.id != id || old.actions != actions;
}

/// [child], tappable when [onTap] is set (answering across 48px when
/// [target]); otherwise exactly [child].
Widget _tappable(VoidCallback? onTap, Widget child, {bool target = false}) {
  if (onTap == null) return child;
  final detector = GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: child,
  );
  return target ? OrbitTapArea(child: detector) : detector;
}

/// `.timeline`'s contents (`UI.timeline` in `js/ui.js`): [items] top to
/// bottom, 10px 12px 14px in. The chat background is the caller's (an
/// [OrbitPatternBackground]); a screen puts this in its scrolling list.
class OrbitTimeline extends StatelessWidget {
  const OrbitTimeline({
    super.key,
    required this.items,
    this.group = false,
    this.onRetry,
    this.onRetryAction,
    this.onTapMessage,
    this.onLongPressMessage,
    this.bubble = OrbitBubbleActions.none,
  });

  final List<HelixTimelineItem> items;

  /// A group chat: incoming messages show their author and picture.
  final bool group;
  final ValueChanged<String>? onRetry;

  /// Retries a failed action on a message, by message id.
  final ValueChanged<String>? onRetryAction;
  final ValueChanged<String>? onTapMessage;
  final ValueChanged<String>? onLongPressMessage;
  final OrbitBubbleActions bubble;

  /// The timeline's padding in a list [width] wide. A wide chat keeps its
  /// messages to the middle 860px:
  /// `padding-inline: max(12px, calc((100% - 860px) / 2))`.
  static EdgeInsets paddingFor(double width) {
    final side = width.isFinite
        ? ((width - 860) / 2).clamp(12.0, 9999.0)
        : 12.0;
    return EdgeInsets.fromLTRB(side, 10, side, 14);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => Padding(
      padding: paddingFor(c.maxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final it in items)
            OrbitTimelineEntry(
              item: it,
              group: group,
              onRetry: onRetry,
              onRetryAction: onRetryAction,
              onTapMessage: onTapMessage,
              onLongPressMessage: onLongPressMessage,
              bubble: bubble,
            ),
        ],
      ),
    ),
  );
}

/// One row of a timeline: a message, a date, the unread line, a notice, the
/// encryption card or the typing dots.
class OrbitTimelineEntry extends StatelessWidget {
  const OrbitTimelineEntry({
    super.key,
    required this.item,
    this.group = false,
    this.onRetry,
    this.onRetryAction,
    this.onTapMessage,
    this.onLongPressMessage,
    this.bubble = OrbitBubbleActions.none,
  });

  final HelixTimelineItem item;
  final bool group;
  final ValueChanged<String>? onRetry;
  final ValueChanged<String>? onRetryAction;
  final ValueChanged<String>? onTapMessage;
  final ValueChanged<String>? onLongPressMessage;
  final OrbitBubbleActions bubble;

  /// How many entries were built (a test hook): a burst of messages must
  /// rebuild the rows that changed, not every row on screen.
  @visibleForTesting
  static int debugBuilds = 0;

  @override
  Widget build(BuildContext context) {
    debugBuilds++;
    return _entry();
  }

  Widget _entry() => switch (item) {
    final HelixMessageItem m => OrbitMessageBubble(
      message: m.message,
      position: m.position,
      group: group,
      selected: m.selected,
      onRetry: onRetry == null ? null : () => onRetry!(m.message.id),
      onRetryAction: onRetryAction == null
          ? null
          : () => onRetryAction!(m.message.id),
      onTap: onTapMessage == null ? null : () => onTapMessage!(m.message.id),
      onLongPress: onLongPressMessage == null
          ? null
          : () => onLongPressMessage!(m.message.id),
      actions: bubble,
    ),
    final HelixDateSeparatorItem d => OrbitDaySeparator(d.label),
    final HelixUnreadDividerItem u => OrbitUnreadDivider(u.count),
    final HelixSystemNoticeItem n => OrbitTimelineNotice(n),
    HelixEncryptionNoticeItem() => const OrbitEncryptionCard(),
    HelixTypingItem() => const OrbitTypingBubble(),
  };
}

/// A hairline either side of a label: the date separator and the unread
/// line share it.
class _Ruled extends StatelessWidget {
  const _Ruled({required this.label, required this.rule, required this.margin});

  final Widget label;
  final Color rule;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: Row(
      children: [
        Expanded(child: Container(height: 1, color: rule)),
        const SizedBox(width: 10),
        label,
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: rule)),
      ],
    ),
  );
}

/// `.day` (`css/screens.css`): the date between `--line` hairlines, 16px
/// above and 10px below, 6px in; mono 10.5px tracked 0.1em, upper case, in
/// `--ink-3` on a `--chat-bg` patch. The theme's `day` ornaments go either
/// side (Papyrus's ❦, Terminal's brackets, Mochi's ✦), Arcade colours it
/// `--accent-ink`, and Bloom's `dayLabel` sets it in its display face,
/// italic, at 13px as written.
class OrbitDaySeparator extends StatelessWidget {
  const OrbitDaySeparator(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final bloom = t.meta.effect('dayLabel');
    final colourEffect = orbitEffectOn(t, 'eyebrowColour', '.day span');
    final token = colourEffect?.param<String>('token');
    final ink = token == null ? t.ink3 : t.value<Color>(token);
    final size = bloom == null
        ? 10.5
        : double.parse(
            (bloom.param<String>('size') ?? '13px').replaceAll('px', ''),
          );
    final style = bloom == null
        ? t.mono.style(size: size, color: ink, letterSpacingEm: 0.1)
        : t.fontDisplay
              .style(size: size, color: ink)
              .copyWith(fontStyle: FontStyle.italic);
    final marks = orbitOrnaments(t, 'day');
    String up(String s) => bloom == null ? s.toUpperCase() : s;
    TextSpan mark(OrbitEffect e) {
      final span = orbitOrnamentSpan(t, e, style);
      return TextSpan(text: up(span.text!), style: span.style);
    }

    return _Ruled(
      rule: t.line,
      margin: const EdgeInsets.fromLTRB(6, 16, 6, 10),
      label: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: t.chatBg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: OrbitText.rich(
          TextSpan(
            children: [
              ...marks.before.map(mark),
              TextSpan(text: up(label)),
              ...marks.after.map(mark),
            ],
          ),
          style: style,
        ),
      ),
    );
  }
}

/// `.unread-div` (`css/screens.css`): "2 unread messages" between
/// `--accent-line` hairlines, 14px above and 10px below; mono 10.5px at
/// weight 600, tracked 0.08em, upper case, in `--accent-ink`.
class OrbitUnreadDivider extends StatelessWidget {
  const OrbitUnreadDivider(this.count, {super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return _Ruled(
      rule: t.accentLine,
      margin: const EdgeInsets.only(top: 14, bottom: 10),
      label: OrbitText(
        '$count unread message${count == 1 ? '' : 's'}'.toUpperCase(),
        style: t.mono.style(
          size: 10.5,
          weight: 600,
          color: t.accentInk,
          letterSpacingEm: 0.08,
        ),
      ),
    );
  }
}

/// `.notice` (`css/screens.css`): a centred pill, 8px above and below, at
/// most 86% wide, 6px 12px in, corner 10, `--notice-bg` with a `--line-2`
/// edge; a 14px icon 7px before the text at `--t-caption` in `--ink-3`. A
/// warning is `--warning` on `--warning-soft`; a missed call's icon is filled
/// `--danger`.
class OrbitTimelineNotice extends StatelessWidget {
  const OrbitTimelineNotice(this.item, {super.key});

  final HelixSystemNoticeItem item;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final warn = item.tone == HelixNoticeTone.warn;
    final missed = item.tone == HelixNoticeTone.missedCall;
    final ink = warn ? t.warning : t.ink3;
    final icon = item.icon;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Center(
        child: LayoutBuilder(
          builder: (context, box) => ConstrainedBox(
            // 86% of the timeline, which the 16px margins sit inside.
            constraints: BoxConstraints(maxWidth: (box.maxWidth + 32) * 0.86),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: warn ? t.warningSoft : t.noticeBg,
                border: Border.all(color: warn ? t.warningLine : t.line2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    OrbitIcon(
                      icon,
                      weight: missed ? OrbitIconWeight.fill : null,
                      size: 14,
                      color: missed ? t.danger : ink,
                    ),
                    const SizedBox(width: 7),
                  ],
                  Flexible(
                    child: OrbitText(
                      item.text,
                      textAlign: TextAlign.center,
                      style: t.font.style(size: OrbitType.caption, color: ink),
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
}

/// `.e2e-card` (`css/screens.css`): the start of an empty chat. Centred, at
/// most 300 wide, 6px above and 14px below, 12px 14px in, `--surface` with a
/// `--line` edge, corner `--r-md`; a filled lock at 18px in `--accent` 10px
/// before the text at `--t-caption` in `--ink-2`, line height 1.5.
class OrbitEncryptionCard extends StatelessWidget {
  const OrbitEncryptionCard({super.key});

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: t.surface,
            border: Border.all(color: t.line),
            borderRadius: BorderRadius.circular(t.rMd),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: OrbitIcon(
                  OrbitIcons.lockSimple,
                  weight: OrbitIconWeight.fill,
                  size: 18,
                  color: t.accent,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: OrbitText(
                  'Messages are end-to-end encrypted. Say hello.',
                  style: t.font.style(
                    size: OrbitType.caption,
                    color: t.ink2,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The corner radii of a bubble: the theme's `--bubble-cut` on the first
/// bubble's top outer corner, 8px where bubbles of a run meet, and
/// `--bubble-r` elsewhere.
BorderRadius _corners(OrbitTokens t, bool out, HelixRunPosition p) {
  final r = Radius.circular(t.bubbleR);
  final cut = Radius.circular(t.bubbleCut);
  const joint = Radius.circular(8);
  final top = switch (p) {
    HelixRunPosition.single || HelixRunPosition.first => cut,
    _ => joint,
  };
  final bottom = switch (p) {
    HelixRunPosition.first || HelixRunPosition.middle => joint,
    _ => r,
  };
  return out
      ? BorderRadius.only(
          topLeft: r,
          bottomLeft: r,
          topRight: top,
          bottomRight: bottom,
        )
      : BorderRadius.only(
          topLeft: top,
          bottomLeft: bottom,
          topRight: r,
          bottomRight: r,
        );
}

/// A bubble's fill and edge, with a different width on each side (Field's
/// stripe) and an optional dashed edge (placeholders).
class _BubbleFrame extends CustomPainter {
  const _BubbleFrame({
    required this.radius,
    required this.fill,
    required this.edge,
    required this.widths,
    this.dashed = false,
    this.stripe,
    this.shadows = const [],
  });

  final BorderRadius radius;
  final Color? fill;
  final Color edge;
  final EdgeInsets widths;
  final bool dashed;

  /// The colour of a thicker side, when one side is a stripe.
  final Color? stripe;

  /// Outer shadows (Arcade's glow, the jump highlight), drawn only outside
  /// the bubble, as CSS draws a box-shadow: never under a clear fill.
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = radius.toRRect(Offset.zero & size);
    if (shadows.isNotEmpty) {
      canvas
        ..save()
        ..clipPath(
          Path.combine(
            PathOperation.difference,
            Path()..addRect((Offset.zero & size).inflate(64)),
            Path()..addRRect(outer),
          ),
        );
      for (final s in shadows) {
        canvas.drawRRect(
          outer.shift(s.offset).inflate(s.spreadRadius),
          s.toPaint(),
        );
      }
      canvas.restore();
    }
    final f = fill;
    if (f != null) canvas.drawRRect(outer, Paint()..color = f);
    if (dashed) {
      final paint = Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      final path = Path()..addRRect(outer.deflate(0.5));
      for (final m in path.computeMetrics()) {
        for (var d = 0.0; d < m.length; d += 6) {
          canvas.drawPath(m.extractPath(d, d + 3), paint);
        }
      }
      // Field's stripe wins over the dashes on its side (its rule is more
      // specific than `.bubble.placeholder`'s).
      if (stripe == null) return;
    }
    final inner = RRect.fromLTRBAndCorners(
      widths.left,
      widths.top,
      size.width - widths.right,
      size.height - widths.bottom,
      topLeft: _shrink(outer.tlRadius, widths.left, widths.top),
      topRight: _shrink(outer.trRadius, widths.right, widths.top),
      bottomLeft: _shrink(outer.blRadius, widths.left, widths.bottom),
      bottomRight: _shrink(outer.brRadius, widths.right, widths.bottom),
    );
    final ring = Path.combine(
      PathOperation.difference,
      Path()..addRRect(outer),
      Path()..addRRect(inner),
    );
    final s = stripe;
    if (s == null) {
      canvas.drawPath(ring, Paint()..color = edge);
      return;
    }
    // A stripe: the thick side in its colour, the rest in the edge colour.
    if (!dashed) canvas.drawPath(ring, Paint()..color = edge);
    final thickLeft = widths.left > widths.right;
    final band = thickLeft
        ? Rect.fromLTWH(0, 0, widths.left, size.height)
        : Rect.fromLTWH(
            size.width - widths.right,
            0,
            widths.right,
            size.height,
          );
    canvas
      ..save()
      ..clipRect(band)
      ..drawPath(ring, Paint()..color = s)
      ..restore();
  }

  static Radius _shrink(Radius r, double x, double y) =>
      Radius.elliptical(math.max(0, r.x - x), math.max(0, r.y - y));

  @override
  bool shouldRepaint(_BubbleFrame old) =>
      old.radius != radius ||
      old.fill != fill ||
      old.edge != edge ||
      old.widths != widths ||
      old.dashed != dashed ||
      old.stripe != stripe ||
      !listEquals(old.shadows, shadows);
}

/// The bubble's colours and the theme's bubble effects.
class _BubbleLook {
  _BubbleLook(this.t, this.out);

  final OrbitTokens t;
  final bool out;

  Color get fill => out ? t.out : t.inBubble;
  Color get edge => out ? t.outLine : t.inLine;
  Color get ink => out ? t.outInk : t.inInk;
  Color get meta => out ? t.outMeta : t.inMeta;

  /// Mochi's `bubbleWeight`: the bubble's text at its weight.
  int get weight =>
      t.meta.effect('bubbleWeight')?.param<num>('weight')?.toInt() ?? 400;

  /// Field's `bubbleStripe`: (side widths, stripe colour).
  (EdgeInsets, Color?) get stripe {
    final e = t.meta.effect('bubbleStripe');
    final spec = e?.params[out ? 'out' : 'in'];
    if (spec is! Map) return (const EdgeInsets.all(1), null);
    final w = (spec['width'] as num?)?.toDouble() ?? 1;
    final colour = orbitEffectColour(t, spec['colour']);
    return spec['edge'] == 'left'
        ? (EdgeInsets.fromLTRB(w, 1, 1, 1), colour)
        : (EdgeInsets.fromLTRB(1, 1, w, 1), colour);
  }

  /// Arcade's `bubbleGlow`.
  List<BoxShadow>? get glow {
    final e = t.meta.effect('bubbleGlow');
    final spec = e?.params[out ? 'out' : 'in'];
    if (spec is! Map) return null;
    return [
      BoxShadow(
        color: orbitEffectColour(t, spec['colour']),
        offset: Offset(
          (spec['dx'] as num? ?? 0).toDouble(),
          (spec['dy'] as num? ?? 0).toDouble(),
        ),
        blurRadius: orbitCssBlur((spec['blur'] as num? ?? 0).toDouble()),
      ),
    ];
  }
}

/// `UI.message` (`js/ui.js`; `.msg` and `.bubble` in `css/screens.css`): one
/// message in a timeline.
///
/// - Incoming on the left, yours on the right, 2px under the one before
///   (8px for the first of a run). In a group, an incoming run shows its
///   author over the first bubble and a 30px picture beside the last.
/// - The bubble: at most 80% wide (with a picture, 80% of what is left plus
///   10px), at least 64, 8px 12px 6px in, `--in` or `--out` with a 1px edge,
///   the theme's corners; text at `--t-body`, line height 1.42.
/// - The time and ticks sit at the end of the last line when they fit and
///   on a line of their own when not, as the prototype's float does.
class OrbitMessageBubble extends StatelessWidget {
  const OrbitMessageBubble({
    super.key,
    required this.message,
    this.position = HelixRunPosition.single,
    this.group = false,
    this.selected = false,
    this.onRetry,
    this.onRetryAction,
    this.onTap,
    this.onLongPress,
    this.actions = OrbitBubbleActions.none,
  });

  final HelixMessage message;
  final HelixRunPosition position;
  final bool group;
  final bool selected;
  final VoidCallback? onRetry;

  /// Retries a failed action on the message (a delete for everyone that did
  /// not reach the others).
  final VoidCallback? onRetryAction;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// What the bubble's parts do (quote, links, media, voice, reactions) and
  /// the swipe to reply.
  final OrbitBubbleActions actions;

  Widget _authorPicture(Widget picture, String? author) {
    final open = actions.onAuthor;
    if (open == null) return picture;
    return Semantics(
      button: true,
      label: author == null ? 'Open profile' : "Open $author's profile",
      excludeSemantics: true,
      child: _tappable(() => open(message.id), picture, target: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = message;
    final out = m.outgoing;
    final look = _BubbleLook(t, out);
    final withAv = group && !out;
    final opens =
        position == HelixRunPosition.single ||
        position == HelixRunPosition.first;
    final closes =
        position == HelixRunPosition.single ||
        position == HelixRunPosition.last;
    final (_, authorInk) = OrbitAvatar.palette(t, m.authorColorIndex);
    final author = m.authorName;

    final bubble = LayoutBuilder(
      builder: (context, box) {
        // A wide window caps it: `max-width: min(80%, 540px)` (550 with a
        // picture).
        final maxW = withAv
            ? (box.maxWidth * 0.8 + 10).clamp(0.0, 550.0)
            : (box.maxWidth * 0.8).clamp(0.0, 540.0);
        return ConstrainedBox(
          constraints: BoxConstraints(minWidth: 64, maxWidth: maxW),
          child: _Bubble(
            message: m,
            position: position,
            look: look,
            highlighted: m.highlighted,
          ),
        );
      },
    );

    final column = Column(
      crossAxisAlignment: out
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (withAv && opens && author != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 3),
            child: OrbitText(
              author,
              style: t.font.style(
                size: OrbitType.caption,
                weight: 620,
                color: authorInk,
              ),
            ),
          ),
        Align(
          alignment: out ? Alignment.centerRight : Alignment.centerLeft,
          child: actions.onReply == null
              ? bubble
              : _SwipeToReply(
                  outgoing: out,
                  onReply: () => actions.onReply!(m.id),
                  child: bubble,
                ),
        ),
        if (m.reactions.isNotEmpty)
          // `margin-top: -5px`: over the bubble's edge, and 5px less tall.
          _PullUp(by: 5, child: _Reactions(m.reactions)),
        if (out && m.status == HelixDeliveryStatus.failed)
          _FailedLine(onRetry: onRetry),
        if (m.failedAction != null)
          _FailedLine(
            label: m.failedAction!,
            semanticsLabel: 'Retry this action',
            onRetry: onRetryAction,
          ),
      ],
    );

    Widget row = withAv
        ? Stack(
            children: [
              Padding(padding: const EdgeInsets.only(left: 38), child: column),
              if (closes)
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: _authorPicture(
                    OrbitAvatar(
                      avatar:
                          m.authorAvatar ??
                          HelixAvatarModel(
                            name: author ?? '',
                            colorIndex: m.authorColorIndex,
                          ),
                      size: 30,
                    ),
                    author,
                  ),
                ),
            ],
          )
        : column;
    if (selected) {
      // `.msg.selected::before`: the accent at 12% across the timeline.
      row = Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -12,
            right: -12,
            top: -1,
            bottom: -1,
            child: ColoredBox(color: t.accent.withValues(alpha: 0.12)),
          ),
          row,
        ],
      );
    }
    Widget body = identical(actions, OrbitBubbleActions.none)
        ? row
        : _BubbleTaps(id: m.id, actions: actions, child: row);
    final touchable = onTap != null || onLongPress != null;
    if (touchable) {
      // One node a screen reader can read and act on: the whole story for a
      // bubble without controls; one that has them (play, download, a link
      // card, Retry) keeps them reachable.
      final c = m.content;
      final controls =
          c is HelixMediaContent ||
          c is HelixAudioContent ||
          c is HelixViewOnceContent ||
          c is HelixDocumentContent ||
          (c is HelixTextContent && c.linkPreview != null) ||
          (out && m.status == HelixDeliveryStatus.failed);
      final a = actions;
      body = Semantics(
        container: true,
        explicitChildNodes: controls,
        label: describe(m),
        selected: selected,
        onTap: onTap,
        onLongPress: onLongPress,
        customSemanticsActions: {
          if (a.onReply != null)
            const CustomSemanticsAction(label: 'Reply'): () => a.onReply!(m.id),
          if (m.reply != null && a.onQuote != null)
            const CustomSemanticsAction(label: 'Go to replied message'): () =>
                a.onQuote!(m.id),
          if (m.reactions.isNotEmpty && a.onReactions != null)
            const CustomSemanticsAction(label: 'Show reactions'): () =>
                a.onReactions!(m.id),
          if (withAv && a.onAuthor != null)
            const CustomSemanticsAction(label: 'Open profile'): () =>
                a.onAuthor!(m.id),
        },
        child: controls ? body : ExcludeSemantics(child: body),
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: opens ? 8 : 2),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
        onLongPress: onLongPress,
        onSecondaryTap: onLongPress,
        excludeFromSemantics: touchable,
        child: body,
      ),
    );
  }

  /// What a screen reader says for [m]: who, what, when and how far it got.
  static String describe(HelixMessage m) {
    final b = StringBuffer(m.outgoing ? 'You' : (m.authorName ?? ''));
    if (b.isNotEmpty) b.write(': ');
    if (m.forwarded) b.write('Forwarded. ');
    final r = m.reply;
    if (r != null) {
      final (_, kind) = orbitPreviewLabel(r.kind);
      b.write('Reply to ${r.authorName}: ${r.text.isEmpty ? kind : r.text}. ');
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
      case HelixPollContent():
        b.write('Poll ${c.question}');
      case HelixPlaceholderContent():
        b.write(_placeholderWords(c.kind, m.outgoing).$2);
      case HelixViewOnceContent():
        b.write(
          'View once ${c.isVideo ? 'video' : 'photo'}${c.opened ? ', opened' : ''}',
        );
    }
    if (m.edited) b.write(', edited');
    if (m.expiresLabel != null) b.write(', disappears after ${m.expiresLabel}');
    b.write(', ${m.timeLabel}');
    if (m.outgoing) {
      b.write(switch (m.status) {
        HelixDeliveryStatus.pending => ', sending',
        HelixDeliveryStatus.sent => ', sent',
        HelixDeliveryStatus.delivered => ', delivered',
        HelixDeliveryStatus.read => ', read',
        HelixDeliveryStatus.failed => ', not sent',
      });
    }
    if (m.reactions.isNotEmpty) {
      b.write(
        ', reactions '
        '${m.reactions.map((r) => '${r.emoji} ${r.count}').join(', ')}',
      );
    }
    return b.toString();
  }
}

/// The prototype's swipe to reply: the bubble follows the finger sideways,
/// up to 80px towards the middle of the chat, and springs back in 180ms; let
/// go past 56px and [onReply] runs.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({
    required this.outgoing,
    required this.onReply,
    required this.child,
  });

  final bool outgoing;
  final VoidCallback onReply;
  final Widget child;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  static const _trigger = 56.0;
  static const _most = 80.0;
  var _pull = 0.0;
  var _dragging = false;

  void _end() {
    final fire = _pull >= _trigger;
    setState(() {
      _pull = 0;
      _dragging = false;
    });
    if (fire) widget.onReply();
  }

  @override
  Widget build(BuildContext context) {
    final sign = widget.outgoing ? -1.0 : 1.0;
    final t = OrbitTokens.of(context);
    return GestureDetector(
      // Measured from where the finger went down, as the prototype's is.
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: (_) => setState(() => _dragging = true),
      onHorizontalDragUpdate: (d) =>
          setState(() => _pull = (_pull + d.delta.dx * sign).clamp(0.0, _most)),
      onHorizontalDragEnd: (_) => _end(),
      onHorizontalDragCancel: () => setState(() {
        _pull = 0;
        _dragging = false;
      }),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: _pull * sign),
        duration: _dragging || !OrbitMotion.allowed(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        curve: t.motion.curve,
        builder: (context, dx, child) =>
            Transform.translate(offset: Offset(dx, 0), child: child),
        child: widget.child,
      ),
    );
  }
}

/// The bubble itself: its frame, then what the content is.
class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.position,
    required this.look,
    required this.highlighted,
  });

  final HelixMessage message;
  final HelixRunPosition position;
  final _BubbleLook look;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final t = look.t;
    final m = message;
    final c = m.content;
    final radius = _corners(t, m.outgoing, position);
    final placeholder = c is HelixPlaceholderContent;
    final media = c is HelixMediaContent;
    final (widths, stripe) = look.stripe;
    final body = look.weight;
    final text = t.font.style(
      size: OrbitType.body,
      weight: body,
      color: look.ink,
      height: 1.42,
    );

    Widget content;
    var padding = EdgeInsets.fromLTRB(
      12 - widths.left + 1,
      8,
      12 - widths.right + 1,
      6,
    );
    if (placeholder) {
      content = _PlaceholderBody(message: m, look: look, text: text);
    } else if (media) {
      padding = const EdgeInsets.all(4);
      content = _MediaBody(message: m, look: look, text: text);
    } else {
      content = _BlockBody(message: m, look: look, text: text);
    }
    final warn =
        c is HelixPlaceholderContent &&
        c.kind == HelixPlaceholderKind.undecryptable;
    final edge = placeholder
        ? (warn
              ? t.warningLine
              : m.outgoing
              ? t.outLine
              : t.controlLine)
        : look.edge;
    final shadows = <BoxShadow>[
      ...?look.glow,
      if (highlighted) BoxShadow(color: t.accent, spreadRadius: 2),
    ];
    return CustomPaint(
      painter: _BubbleFrame(
        radius: radius,
        fill: placeholder ? null : look.fill,
        edge: edge,
        widths: widths,
        dashed: placeholder,
        stripe: stripe,
        shadows: shadows,
      ),
      child: Padding(padding: padding + widths, child: content),
    );
  }
}

/// `UI.meta(m)` (`js/ui.js`; `.bubble .meta`): the timer and its label, then
/// "Edited", the time and, for yours, the tick; mono 10.5px tracked 0.02em,
/// line height 1, 4px apart, in `--in-meta` or `--out-meta`, icons at 14px
/// (the timer at 12, 2px from its label).
class _Meta extends StatelessWidget {
  const _Meta({
    required this.message,
    required this.color,
    this.readColor,
    this.withEdited = true,
  });

  final HelixMessage message;
  final Color color;
  final Color? readColor;
  final bool withEdited;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final m = message;
    final style = t.mono.style(
      size: 10.5,
      color: color,
      letterSpacingEm: 0.02,
      height: 1,
    );
    final parts = <Widget>[
      if (m.expiresLabel != null)
        Semantics(
          label: 'Disappearing message',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OrbitIcon(OrbitIcons.timer, size: 12, color: color),
              const SizedBox(width: 2),
              Text(m.expiresLabel!, style: style),
            ],
          ),
        ),
      if (withEdited && m.edited) Text('Edited', style: style),
      Text(m.timeLabel, style: style),
      if (m.outgoing)
        _MetaTick(status: m.status, color: color, readColor: readColor),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, p) in parts.indexed) ...[
          if (i > 0) const SizedBox(width: 4),
          p,
        ],
      ],
    );
  }
}

class _MetaTick extends StatelessWidget {
  const _MetaTick({required this.status, required this.color, this.readColor});

  final HelixDeliveryStatus status;
  final Color color;
  final Color? readColor;

  @override
  Widget build(BuildContext context) {
    final rc = readColor;
    if (status == HelixDeliveryStatus.read && rc != null) {
      return Semantics(
        label: 'Read',
        child: OrbitIcon(
          OrbitIcons.checks,
          weight: OrbitIconWeight.bold,
          size: 14,
          color: rc,
        ),
      );
    }
    return OrbitTick(status, color: color, size: 14);
  }
}

/// A bubble that holds text or a card: its parts top to bottom (forwarded,
/// quote, link card or card, text) and the meta floated at the end.
class _BlockBody extends StatelessWidget {
  const _BlockBody({
    required this.message,
    required this.look,
    required this.text,
  });

  final HelixMessage message;
  final _BubbleLook look;
  final TextStyle text;

  @override
  Widget build(BuildContext context) {
    final t = look.t;
    final m = message;
    final c = m.content;
    final meta = _Meta(message: m, color: look.meta, readColor: t.readTick);
    final onLink = _BubbleTaps.of(context)?.actions.onLink;
    // Card contents push the bubble's 12px padding back with their own
    // negative margins; they are laid out from the inside of the padding by
    // undoing it here.
    Widget wide(Widget child, double into) => _Outset(by: into, child: child);
    final parts = <Widget>[
      if (m.forwarded) _Forwarded(look: look),
      if (m.reply != null) wide(_Quote(m.reply!, look: look), 6),
    ];
    switch (c) {
      case HelixTextContent(:final linkPreview):
        if (linkPreview != null) {
          parts.add(
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: wide(_LinkCard(linkPreview, look: look), 6),
            ),
          );
        }
        parts.add(
          _TextFlow(
            span: _rich(t, c, text),
            style: text,
            meta: meta,
            onLink: onLink,
          ),
        );
      case HelixPollContent(:final question, :final options):
        final s = ['Poll: $question', ...options.map((o) => '- $o')].join('\n');
        parts.add(
          _TextFlow(
            span: TextSpan(text: s, style: text),
            style: text,
            meta: meta,
          ),
        );
      case HelixAudioContent():
        parts
          ..add(_Voice(message: m, content: c, look: look))
          ..add(_FloatLine(meta: meta));
      case HelixDocumentContent():
        parts.add(_Document(content: c, look: look));
        if (c.caption.isNotEmpty) {
          parts.add(
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: OrbitText(c.caption, style: text),
            ),
          );
        }
        parts.add(_FloatLine(meta: meta));
      case HelixLocationContent():
        parts
          ..add(wide(_Location(content: c, look: look), 8))
          ..add(_FloatLine(meta: meta));
      case HelixContactContent():
        parts
          ..add(_Contact(content: c, look: look))
          ..add(_FloatLine(meta: meta));
      case HelixViewOnceContent():
        parts
          ..add(_ViewOnce(content: c, outgoing: m.outgoing, look: look))
          ..add(_FloatLine(meta: meta));
      default:
        parts.add(_FloatLine(meta: meta));
    }
    // A location card starts 4px above the padding (`margin: -4px`).
    final pullUp = c is HelixLocationContent && parts.length == 2;
    final column = IntrinsicWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: parts,
      ),
    );
    return pullUp ? _PullUp(by: 4, child: column) : column;
  }
}

/// [child] laid out [by] px wider on each side than its parent gives it, as
/// a negative CSS margin does.
class _Outset extends SingleChildRenderObjectWidget {
  const _Outset({required this.by, required super.child});

  final double by;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderOutset(by);

  @override
  void updateRenderObject(BuildContext context, _RenderOutset r) => r.by = by;
}

class _RenderOutset extends RenderProxyBox {
  _RenderOutset(this._by);

  double _by;
  set by(double v) {
    if (v == _by) return;
    _by = v;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.max(0, (child?.getMinIntrinsicWidth(height) ?? 0) - 2 * _by);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      math.max(0, (child?.getMaxIntrinsicWidth(height) ?? 0) - 2 * _by);

  @override
  void performLayout() {
    final c = child!;
    final w = constraints.maxWidth + 2 * _by;
    c.layout(
      BoxConstraints(
        minWidth: w.isFinite ? w : 0,
        maxWidth: w,
        maxHeight: constraints.maxHeight,
      ),
      parentUsesSize: true,
    );
    size = constraints.constrain(Size(constraints.maxWidth, c.size.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      context.paintChild(child!, offset - Offset(_by, 0));

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: Offset(-_by, 0),
        position: position,
        hitTest: (r, p) => child!.hitTest(r, position: p),
      );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.translateByDouble(-_by, 0, 0, 1);
}

/// [child] moved [by] px up into what is above it, taking that much less
/// room, as a negative top margin does.
class _PullUp extends SingleChildRenderObjectWidget {
  const _PullUp({required this.by, required super.child});

  final double by;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPullUp(by);
}

class _RenderPullUp extends RenderProxyBox {
  _RenderPullUp(this.by);

  final double by;

  @override
  void performLayout() {
    final c = child!..layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.constrain(
      Size(c.size.width, math.max(0, c.size.height - by)),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      context.paintChild(child!, offset - Offset(0, by));

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: Offset(0, -by),
        position: position,
        hitTest: (r, p) => child!.hitTest(r, position: p),
      );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.translateByDouble(0, -by, 0, 1);
}

/// The meta on a line of its own, after a block: floated right, 6px down
/// (`margin: 6px -2px -2px 10px`, `top: 4px`).
class _FloatLine extends StatelessWidget {
  const _FloatLine({required this.meta});

  final Widget meta;

  @override
  Widget build(BuildContext context) => _FloatBox(meta: meta);
}

class _FloatBox extends SingleChildRenderObjectWidget {
  const _FloatBox({required Widget meta}) : super(child: meta);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFloatBox();
}

/// Takes the meta's margin box (its width + 8, its height + 4) and paints
/// it 10px down and 2px past the right edge.
class _RenderFloatBox extends RenderProxyBox {
  @override
  double computeMinIntrinsicWidth(double height) =>
      (child?.getMaxIntrinsicWidth(height) ?? 0) + 8;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      (child?.getMaxIntrinsicWidth(height) ?? 0) + 8;

  @override
  void performLayout() {
    final c = child!..layout(const BoxConstraints(), parentUsesSize: true);
    size = constraints.constrain(
      Size(
        constraints.maxWidth.isFinite ? constraints.maxWidth : c.size.width + 8,
        c.size.height + 4,
      ),
    );
  }

  Offset get _at => Offset(size.width + 2 - child!.size.width, 10);

  @override
  void paint(PaintingContext context, Offset offset) =>
      context.paintChild(child!, offset + _at);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.translateByDouble(_at.dx, _at.dy, 0, 1);
}

/// Text with the meta floated at its end (`.bubble` text and `.meta`): the
/// meta sits on the last line when it fits beside it, and below it when not.
/// The bubble's preferred width is the longest line, or the last line plus
/// the meta, as CSS works out a shrink-to-fit width around a float.
class _TextFlow extends SingleChildRenderObjectWidget {
  const _TextFlow({
    required this.span,
    required this.style,
    required Widget meta,
    this.onLink,
  }) : super(child: meta);

  final InlineSpan span;
  final TextStyle style;

  /// A link in the text was tapped; null leaves every tap to the bubble.
  final ValueChanged<String>? onLink;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTextFlow(
    span,
    style,
    MediaQuery.textScalerOf(context),
    Directionality.of(context),
  )..onLink = onLink;

  @override
  void updateRenderObject(BuildContext context, _RenderTextFlow r) => r
    ..span = span
    ..style = style
    ..scaler = MediaQuery.textScalerOf(context)
    ..onLink = onLink;
}

class _RenderTextFlow extends RenderProxyBox {
  _RenderTextFlow(this._span, this._style, this._scaler, this._dir);

  InlineSpan _span;
  TextStyle _style;
  TextScaler _scaler;
  final TextDirection _dir;
  final _text = TextPainter();
  Offset _metaAt = Offset.zero;

  ValueChanged<String>? onLink;
  TapGestureRecognizer? _tap;
  String? _pressed;

  static final _joiners = RegExp('[​⁠]');

  /// The link under [position], if a link's own letters are there.
  String? _linkAt(Offset position) {
    final text = _text.text;
    if (text == null) return null;
    final lines = _text.computeLineMetrics().length;
    final shift = (_line - _line.roundToDouble()) * math.max(1, lines) / 2;
    final local = position - Offset(0, shift);
    final pos = _text.getPositionForOffset(local);
    final at = pos.affinity == TextAffinity.upstream
        ? pos.offset - 1
        : pos.offset;
    if (at < 0) return null;
    final boxes = _text.getBoxesForSelection(
      TextSelection(baseOffset: at, extentOffset: at + 1),
    );
    if (!boxes.any((b) => b.toRect().inflate(2).contains(local))) return null;
    final span = text.getSpanForPosition(TextPosition(offset: at));
    if (span is! TextSpan) return null;
    final url = span.text?.replaceAll(_joiners, '');
    return url != null && _url.hasMatch(url) ? url : null;
  }

  @override
  bool hitTestSelf(Offset position) =>
      onLink != null && _linkAt(position) != null;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is! PointerDownEvent || onLink == null) return;
    _pressed = _linkAt(entry.localPosition);
    if (_pressed == null) return;
    (_tap ??= TapGestureRecognizer(debugOwner: this)
          ..onTap = () {
            final url = _pressed;
            if (url != null) onLink?.call(url);
          })
        .addPointer(event);
  }

  set span(InlineSpan v) {
    if (v == _span) return;
    _span = v;
    markNeedsLayout();
  }

  set style(TextStyle v) {
    if (v == _style) return;
    _style = v;
    markNeedsLayout();
  }

  set scaler(TextScaler v) {
    if (v == _scaler) return;
    _scaler = v;
    markNeedsLayout();
  }

  double get _line => _scaler.scale(_style.fontSize!) * _style.height!;

  void _lay(double width) {
    _text
      ..text = _breakable(width)
      ..textDirection = _dir
      ..textScaler = _scaler
      ..layout(maxWidth: width);
  }

  static final _url = RegExp(r'^https?://\S+$');

  /// The text as Chrome breaks it: a link is one word (Flutter would break
  /// after its slashes), so it moves to the next line whole; only when it is
  /// wider than a line by itself does `overflow-wrap: anywhere` let it break
  /// between any two characters, from the start of its own line.
  InlineSpan _breakable(double width) {
    final leaves = <(String, TextStyle?)>[];
    void walk(InlineSpan s, TextStyle? inherited) {
      if (s is! TextSpan) return;
      final style = inherited?.merge(s.style) ?? s.style;
      final text = s.text;
      if (text != null && text.isNotEmpty) leaves.add((text, style));
      for (final c in s.children ?? const <InlineSpan>[]) {
        walk(c, style);
      }
    }

    walk(_span, null);
    if (!leaves.any((l) => _url.hasMatch(l.$1))) return _span;
    final probe = TextPainter(textDirection: _dir, textScaler: _scaler);
    for (var i = 0; i < leaves.length; i++) {
      final (text, style) = leaves[i];
      if (!_url.hasMatch(text)) continue;
      probe
        ..text = TextSpan(text: text, style: style)
        ..layout();
      final tooWide = probe.width > width;
      leaves[i] = (text.split('').join(tooWide ? '​' : '⁠'), style);
      if (tooWide && i > 0 && leaves[i - 1].$1.endsWith(' ')) {
        final (before, s) = leaves[i - 1];
        leaves[i - 1] = ('${before.substring(0, before.length - 1)}\n', s);
      }
    }
    probe.dispose();
    return TextSpan(
      children: [for (final (t, s) in leaves) TextSpan(text: t, style: s)],
    );
  }

  /// The meta's margin box: its width + 10 - 2, its height + 6 - 2.
  Size get _float {
    final c = child!;
    final w = c.getMaxIntrinsicWidth(double.infinity);
    final h = c.getMaxIntrinsicHeight(w);
    return Size(w + 8, h + 4);
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    _lay(double.infinity);
    final lines = _text.computeLineMetrics();
    if (lines.isEmpty) return _float.width;
    var widest = 0.0;
    for (final l in lines.take(lines.length - 1)) {
      widest = math.max(widest, l.width);
    }
    return math.max(widest, lines.last.width + _float.width);
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    _lay(0);
    return math.max(_text.width, _float.width);
  }

  @override
  void performLayout() {
    final c = child!..layout(const BoxConstraints(), parentUsesSize: true);
    final width = constraints.maxWidth;
    _lay(width);
    final lines = _text.computeLineMetrics();
    final n = math.max(1, lines.length);
    final textHeight = n * _line;
    final float = Size(c.size.width + 8, c.size.height + 4);
    final last = lines.isEmpty ? 0.0 : lines.last.width;
    final beside = last + float.width <= width + 0.01;
    final floatTop = beside ? (n - 1) * _line : textHeight;
    final height = math.max(textHeight, floatTop + float.height);
    size = constraints.constrain(Size(width, height));
    // 6px down from the float's top plus `top: 4px`; 2px past the right.
    _metaAt = Offset(width + 2 - c.size.width, floatTop + 10);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final lines = _text.computeLineMetrics().length;
    final rounded = _line.roundToDouble();
    final shift = (_line - rounded) * math.max(1, lines) / 2;
    _text.paint(context.canvas, offset + Offset(0, shift));
    context.paintChild(child!, offset + _metaAt);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.translateByDouble(_metaAt.dx, _metaAt.dy, 0, 1);

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..label = _span.toPlainText();
  }

  @override
  void dispose() {
    _tap?.dispose();
    _text.dispose();
    super.dispose();
  }
}

/// [_rich] for a test, which reads the spans a message text becomes.
@visibleForTesting
TextSpan richMessageText(OrbitTokens t, HelixTextContent c, TextStyle base) =>
    _rich(t, c, base);

/// `UI.richText`: links underlined in `--accent-ink` (`--cyan-ink` in yours)
/// and @mentions in `--accent-ink` at weight 600.
TextSpan _rich(OrbitTokens t, HelixTextContent c, TextStyle base) {
  final text = c.text;
  final marks = <(int, int, TextStyle)>[];
  for (final r in c.mentions) {
    marks.add((
      r.start,
      r.start + r.length,
      base.copyWith(
        color: t.accentInk,
        fontWeight: FontWeight.w600,
        fontVariations: const [ui.FontVariation('wght', 600)],
      ),
    ));
  }
  for (final link in RegExp(r'https?://[^\s<]+').allMatches(text)) {
    marks.add((
      link.start,
      link.end,
      base.copyWith(
        color: base.color == t.outInk ? t.cyanInk : t.accentInk,
        decoration: TextDecoration.underline,
        decorationColor: base.color == t.outInk ? t.outLine : t.accentLine,
      ),
    ));
  }
  marks.sort((a, b) => a.$1.compareTo(b.$1));
  final spans = <TextSpan>[];
  var at = 0;
  for (final (s, e, style) in marks) {
    if (s < at) continue;
    if (s > at) spans.addAll(_formatted(text.substring(at, s), base, t));
    spans.add(TextSpan(text: text.substring(s, e), style: style));
    at = e;
  }
  if (at < text.length) spans.addAll(_formatted(text.substring(at), base, t));
  return TextSpan(style: base, children: spans);
}

/// `*bold*`, `_italic_`, `~strike~` and `` `mono` ``, as WhatsApp reads them:
/// the markers sit against the words they wrap (never against a space) and
/// start and end at a word edge, so `snake_case_name`, `2*3*4` and a `* ` bullet
/// stay as typed. The markers are hidden, and the text on the wire stays the
/// plain text the sender typed. Mono is literal; the others nest.
final _format = RegExp(
  r'(?<![A-Za-z0-9])([*_~`])(?=\S)(.+?)(?<=\S)\1(?![A-Za-z0-9])',
);

List<TextSpan> _formatted(
  String text,
  TextStyle base,
  OrbitTokens t, [
  int depth = 0,
]) {
  final out = <TextSpan>[];
  var at = 0;
  for (final m in _format.allMatches(text)) {
    if (m.start > at) out.add(TextSpan(text: text.substring(at, m.start)));
    final mark = m[1]!;
    final inner = m[2]!;
    final style = switch (mark) {
      '*' => base.copyWith(
        fontWeight: FontWeight.w700,
        fontVariations: const [ui.FontVariation('wght', 700)],
      ),
      '_' => base.copyWith(fontStyle: FontStyle.italic),
      '~' => base.copyWith(decoration: TextDecoration.lineThrough),
      _ => t.mono.style(
        size: base.fontSize ?? 15,
        color: base.color,
        height: base.height ?? 1.4,
      ),
    };
    out.add(
      mark == '`' || depth >= 2
          ? TextSpan(text: inner, style: style)
          : TextSpan(
              style: style,
              children: _formatted(inner, style, t, depth + 1),
            ),
    );
    at = m.end;
  }
  if (at < text.length) out.add(TextSpan(text: text.substring(at)));
  return out;
}

/// `.fwd`: "Forwarded" over the content, mono 10.5px tracked 0.06em, upper
/// case, in `--ink-3` (`--out-meta` in yours), a bold arrow 5px before it.
class _Forwarded extends StatelessWidget {
  const _Forwarded({required this.look});

  final _BubbleLook look;

  @override
  Widget build(BuildContext context) {
    final t = look.t;
    final ink = look.out ? t.outMeta : t.ink3;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          OrbitIcon(
            OrbitIcons.arrowBendUpRight,
            weight: OrbitIconWeight.bold,
            size: 10.5,
            color: ink,
          ),
          const SizedBox(width: 5),
          OrbitText(
            'FORWARDED',
            style: t.mono.style(size: 10.5, color: ink, letterSpacingEm: 0.06),
          ),
        ],
      ),
    );
  }
}

/// `.quote`: the message replied to. 6px 8px in, corner 10, `--tint`
/// (`--tint-out` in yours), a 3px edge on the left in the author's colour;
/// the author at weight 640 over two lines of text in `--ink-3`, at
/// `--t-caption`, line height 1.35; 6px under it.
class _Quote extends StatelessWidget {
  const _Quote(this.quote, {required this.look});

  final HelixReplyQuote quote;
  final _BubbleLook look;

  @override
  Widget build(BuildContext context) {
    final t = look.t;
    final (_, ink) = OrbitAvatar.palette(t, quote.authorColorIndex);
    final (icon, label) = orbitPreviewLabel(quote.kind);
    final text = quote.missing
        ? 'Original message not available'
        : (quote.text.isEmpty ? label : quote.text);
    final style = t.font.style(
      size: OrbitType.caption,
      color: t.ink3,
      height: 1.35,
    );
    final taps = _BubbleTaps.of(context);
    final onQuote = taps?.actions.onQuote;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: _tappable(
        onQuote == null || quote.missing ? null : () => onQuote(taps!.id),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: look.out ? t.tintOut : t.tint,
              border: Border(left: BorderSide(color: ink, width: 3)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OrbitText(
                    quote.authorName,
                    style: style.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w600,
                      fontVariations: const [ui.FontVariation('wght', 640)],
                    ),
                  ),
                  OrbitText.rich(
                    TextSpan(
                      children: [
                        if (icon != null && quote.kind != HelixPreviewKind.text)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: OrbitIcon(icon, size: 12, color: t.ink3),
                          ),
                        if (icon != null && quote.kind != HelixPreviewKind.text)
                          const TextSpan(text: ' '),
                        TextSpan(text: text),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: quote.missing
                        ? style.copyWith(fontStyle: FontStyle.italic)
                        : style,
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

/// `.linkcard`: a link's title (weight 620, `--t-small`), description
/// (`--t-caption`, `--ink-3`) and host (mono 10.5px, lower case), 8px 10px
/// in on `--tint` (`--tint-out`), corner 10; 6px under it.
class _LinkCard extends StatelessWidget {
  const _LinkCard(this.link, {required this.look});

  final HelixLinkPreview link;
  final _BubbleLook look;

  @override
  Widget build(BuildContext context) {
    final t = look.t;
    final host = Uri.tryParse(link.url)?.host ?? link.url;
    final onLink = _BubbleTaps.of(context)?.actions.onLink;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: _tappable(
        onLink == null ? null : () => onLink(link.url),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: look.out ? t.tintOut : t.tint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (link.title != null)
                OrbitText(
                  link.title!,
                  style: t.font.style(
                    size: OrbitType.small,
                    weight: 620,
                    color: look.ink,
                  ),
                ),
              if (link.description != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: OrbitText(
                    link.description!,
                    style: t.font.style(size: OrbitType.caption, color: t.ink3),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    OrbitIcon(OrbitIcons.linkSimple, size: 10.5, color: t.ink3),
                    Flexible(
                      child: OrbitText(
                        ' ${host.toLowerCase()}',
                        style: t.mono.style(size: 10.5, color: t.ink3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The prototype's stand-in pictures (`.ph-a` to `.ph-f` in
/// `css/screens.css`), so the preview can draw media without files.
Gradient orbitSwatch(String? swatch) => switch (swatch) {
  'ph-b' => const OrbitCssGradient(
    angle: 160,
    colors: [Color(0xFFF6D365), Color(0xFFFDA085)],
    stops: [0, 1],
  ),
  'ph-c' => const OrbitCssGradient(
    angle: 200,
    colors: [Color(0xFF84FAB0), Color(0xFF8FD3F4)],
    stops: [0, 1],
  ),
  'ph-d' => const OrbitCssGradient(
    angle: 120,
    colors: [Color(0xFFA1C4FD), Color(0xFFC2E9FB)],
    stops: [0, 1],
  ),
  'ph-e' => const OrbitCssGradient(
    angle: 180,
    colors: [Color(0xFF2B3A55), Color(0xFF6B5B95), Color(0xFFF7A072)],
    stops: [0, 0.6, 1],
  ),
  'ph-f' => const OrbitCssGradient(
    angle: 140,
    colors: [Color(0xFF43C6AC), Color(0xFF191654)],
    stops: [0, 1],
  ),
  _ => const OrbitCssGradient(
    angle: 135,
    colors: [Color(0xFF8EC5FC), Color(0xFFE0C3FC)],
    stops: [0, 1],
  ),
};

/// The prototype's dark scrim over media, rgba(9, 12, 21, a).
Color _shade(double a) => Color.fromRGBO(9, 12, 21, a);

/// A media bubble (`.bubble.media`, `.media-grid`): 4px in, the pictures
/// 248px wide in a grid 3px apart (one at its own shape, two and four
/// square, three with the first across both columns at 2:1), corner
/// `--r-md`; a "+N" over the fourth when there are more. With no caption the
/// meta sits over the picture on a dark patch; with one, the caption is
/// under the pictures and the meta floats after it.
class _MediaBody extends StatelessWidget {
  const _MediaBody({
    required this.message,
    required this.look,
    required this.text,
  });

  final HelixMessage message;
  final _BubbleLook look;
  final TextStyle text;

  @override
  Widget build(BuildContext context) {
    final t = look.t;
    final m = message;
    final c = m.content as HelixMediaContent;
    final items = c.items.take(4).toList();
    final n = items.length;
    final taps = _BubbleTaps.of(context);
    final onMedia = taps?.actions.onMedia;
    Widget cell(int i, double aspect) => AspectRatio(
      aspectRatio: aspect,
      child: _tappable(
        onMedia == null ? null : () => onMedia(taps!.id, i),
        _MediaCell(
          item: items[i],
          more: i == 3 && c.items.length > 4 ? c.items.length - 4 : 0,
        ),
      ),
    );
    Widget grid;
    if (n == 1) {
      grid = ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 90),
        child: cell(0, items[0].aspectRatio),
      );
    } else {
      final rows = <Widget>[];
      var i = 0;
      if (n == 3) {
        rows.add(cell(0, 2));
        i = 1;
      }
      while (i < n) {
        rows.add(
          Row(
            children: [
              Expanded(child: cell(i, 1)),
              const SizedBox(width: 3),
              Expanded(
                child: i + 1 < n ? cell(i + 1, 1) : const SizedBox.shrink(),
              ),
            ],
          ),
        );
        i += 2;
      }
      grid = Column(
        children: [
          for (final (j, r) in rows.indexed) ...[
            if (j > 0) const SizedBox(height: 3),
            r,
          ],
        ],
      );
    }
    grid = SizedBox(
      width: 248,
      child: ClipRRect(borderRadius: BorderRadius.circular(t.rMd), child: grid),
    );
    final meta = _Meta(
      message: m,
      color: c.caption.isEmpty ? const Color(0xFFFFFFFF) : look.meta,
      readColor: c.caption.isEmpty ? const Color(0xFFB5CCFF) : t.readTick,
    );
    if (c.caption.isEmpty) {
      return Stack(
        children: [
          grid,
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: _shade(0.55),
                borderRadius: BorderRadius.circular(8),
              ),
              child: meta,
            ),
          ),
        ],
      );
    }
    return SizedBox(
      width: 248,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          grid,
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
            child: OrbitText(c.caption, style: text),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
            child: _FloatLine(meta: meta),
          ),
        ],
      ),
    );
  }
}

/// One picture of a media grid (`.mi`): `--media-ph` (or the stand-in), with
/// what its transfer needs in the middle: a dark download pill with the
/// size, a progress ring with ×, Retry, or a play button; a video's length
/// or "GIF" at the bottom left.
class _MediaCell extends StatelessWidget {
  const _MediaCell({required this.item, this.more = 0});

  final HelixMediaItem item;
  final int more;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    const white = Color(0xFFFFFFFF);
    final mono = t.mono;
    Widget pill(OrbitGlyph icon, String label) => Container(
      height: 38,
      padding: const EdgeInsets.only(left: 10, right: 14),
      decoration: BoxDecoration(
        color: _shade(0.6),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OrbitIcon(icon, weight: OrbitIconWeight.bold, size: 18, color: white),
          const SizedBox(width: 8),
          Text(label, style: mono.style(size: 11.5, color: white)),
        ],
      ),
    );
    final center = switch (item.transfer) {
      HelixTransferState.notDownloaded => pill(
        OrbitIcons.downloadSimple,
        item.sizeLabel ?? '',
      ),
      HelixTransferState.downloading ||
      HelixTransferState.uploading => _Ring(progress: item.progress ?? 0.3),
      HelixTransferState.failed => pill(OrbitIcons.arrowClockwise, 'Retry'),
      HelixTransferState.done =>
        item.isVideo
            ? Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: _shade(0.55),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: OrbitIcon(
                    OrbitIcons.play,
                    weight: OrbitIconWeight.fill,
                    size: 20,
                    color: white,
                  ),
                ),
              )
            : null,
    };
    final dur = item.isVideo && item.durationLabel != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const OrbitIcon(
                OrbitIcons.videoCamera,
                weight: OrbitIconWeight.fill,
                size: 10.5,
                color: white,
              ),
              const SizedBox(width: 4),
              Text(
                item.durationLabel!,
                style: mono.style(size: 10.5, color: white, height: 1.4),
              ),
            ],
          )
        : item.isGif
        ? Text('GIF', style: mono.style(size: 10.5, color: white))
        : null;
    return Semantics(
      image: true,
      label: item.semanticLabel ?? (item.isVideo ? 'Video' : 'Photo'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.mediaPh,
          gradient: item.thumbnail == null ? orbitSwatch(item.swatch) : null,
          image: item.thumbnail == null
              ? null
              : DecorationImage(image: item.thumbnail!, fit: BoxFit.cover),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (center != null) Center(child: center),
            if (dur != null)
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _shade(0.55),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: dur,
                ),
              ),
            if (more > 0)
              ColoredBox(
                color: _shade(0.5),
                child: Center(
                  child: Text(
                    '+$more',
                    style: mono.style(size: 22, weight: 600, color: white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// `.ring`: a transfer's progress, 46px, white swept over translucent
/// white, a dark disc 3px in with a bold × to cancel.
class _Ring extends StatelessWidget {
  const _Ring({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 46,
    child: CustomPaint(
      painter: _RingPainter(progress),
      child: const Center(
        child: OrbitIcon(
          OrbitIcons.x,
          weight: OrbitIconWeight.bold,
          size: 18,
          color: Color(0xFFFFFFFF),
        ),
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.p);

  final double p;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    canvas.drawOval(box, Paint()..color = const Color(0x40FFFFFF));
    canvas.drawArc(
      box,
      -math.pi / 2,
      2 * math.pi * p,
      true,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawOval(box.deflate(3), Paint()..color = _shade(0.72));
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.p != p;
}

/// `.voice`: a voice message or an audio file. At least 236 wide; a 40px
/// play button (`--accent`, `--cyan-ink` in yours), then the file's title,
/// the waveform (36 bars, 2px apart, 28px tall, the played part in the
/// accent) and the length in mono 10.5px, with a dot while a voice message
/// is unplayed; a speed chip while playing or not at 1x.
class _Voice extends StatelessWidget {
  const _Voice({
    required this.message,
    required this.content,
    required this.look,
  });

  final HelixMessage message;
  final HelixAudioContent content;
  final _BubbleLook look;

  @override
  Widget build(BuildContext context) {
    final t = look.t;
    final c = content;
    final out = message.outgoing;
    final voice = c.isVoiceNote;
    final icon = c.playing
        ? (OrbitIcons.pause, OrbitIconWeight.fill)
        : c.transfer == HelixTransferState.notDownloaded
        ? (OrbitIcons.downloadSimple, OrbitIconWeight.bold)
        : (OrbitIcons.play, OrbitIconWeight.fill);
    final chip = voice && (c.playing || c.speed != 1);
    final dot = voice && !out && !c.played;
    final meta = t.mono.style(size: 10.5, color: out ? t.outMeta : t.inMeta);
    final taps = _BubbleTaps.of(context);
    final a = taps?.actions;
    final id = taps?.id ?? message.id;
    final onToggle = a?.onAudioToggle;
    final onSpeed = a?.onAudioSpeed;
    final onSeek = a?.onAudioSeek;
    Widget seekable(Widget child) {
      if (onSeek == null) return child;
      return Builder(
        builder: (context) {
          void at(Offset p) {
            final box = context.findRenderObject();
            if (box is! RenderBox || !box.hasSize || box.size.width <= 0) {
              return;
            }
            onSeek(id, (p.dx / box.size.width).clamp(0.0, 1.0));
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => at(d.localPosition),
            onHorizontalDragUpdate: (d) => at(d.localPosition),
            child: child,
          );
        },
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 236),
      child: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(
          children: [
            Semantics(
              button: true,
              label: c.playing ? 'Pause' : 'Play',
              child: _tappable(
                onToggle == null ? null : () => onToggle(id),
                target: true,
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: out ? t.cyanInk : t.accent,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: OrbitIcon(
                      icon.$1,
                      weight: icon.$2,
                      size: 17,
                      color: t.onAccent,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!voice && c.title != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: OrbitText(
                        c.title!,
                        style: t.font.style(
                          size: 13,
                          weight: 560,
                          color: look.ink,
                        ),
                      ),
                    ),
                  seekable(
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 36 * 2 + 35 * 2,
                        minHeight: 28,
                        maxHeight: 28,
                      ),
                      child: CustomPaint(
                        painter: _WavePainter(
                          samples: c.waveform ?? const <int>[],
                          progress: c.progress,
                          idle: out ? t.waveOutIdle : t.waveIdle,
                          on: out ? t.cyanInk : t.accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      OrbitText(
                        c.positionLabel ?? c.durationLabel,
                        style: meta,
                      ),
                      if (dot)
                        Semantics(
                          label: 'Not played yet',
                          child: Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(left: 4),
                            decoration: BoxDecoration(
                              color: t.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (chip) ...[
              const SizedBox(width: 10),
              Semantics(
                button: onSpeed != null,
                label: 'Playback speed ${_speed(c.speed)}x',
                excludeSemantics: true,
                child: _tappable(
                  onSpeed == null ? null : () => onSpeed(id),
                  target: true,
                  Container(
                    height: 26,
                    constraints: const BoxConstraints(minWidth: 38),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: out ? const Color(0x99FFFFFF) : t.surface,
                      border: Border.all(color: out ? t.outLine : t.line),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_speed(c.speed)}x',
                      style: t.mono.style(
                        size: 11,
                        weight: 600,
                        color: out ? t.outInk : t.ink2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _speed(double s) =>
      s == s.roundToDouble() ? '${s.toInt()}' : '$s';
}

/// `UI.wave`: the bars, each at its sample's height (at least 12%), the
/// played share in the accent.
class _WavePainter extends CustomPainter {
  const _WavePainter({
    required this.samples,
    required this.progress,
    required this.idle,
    required this.on,
  });

  final List<int> samples;
  final double progress;
  final Color idle;
  final Color on;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 36;
    final w = (size.width - (bars - 1) * 2) / bars;
    for (var i = 0; i < bars; i++) {
      final v = samples.isEmpty
          ? 60
          : samples[(i / bars * samples.length).floor()];
      final pct = math.max(12, (v / 255 * 100).round()) / 100;
      final h = size.height * pct;
      final x = i * (w + 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - h) / 2, w, h),
          const Radius.circular(2),
        ),
        Paint()..color = i / bars < progress ? on : idle,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.samples != samples ||
      old.progress != progress ||
      old.idle != idle ||
      old.on != on;
}

/// `.doc`: a file. At least 236 wide, 4px above and 2px below; a 44×52 page
/// (`--surface`, a `--line` edge, corner 9) with the file icon and its type,
/// the name (weight 560, `--t-small`, one line), "4.2 MB · PDF" in mono
/// 10.5px, a progress bar while it moves, and a 36px round action.
class _Document extends StatelessWidget {
  const _Document({required this.content, required this.look});

  final HelixDocumentContent content;
  final _BubbleLook look;

  @override
  Widget build(BuildContext context) {
    final t = look.t;
    final c = content;
    final out = look.out;
    final ink = out ? t.cyanInk : t.accent;
    final taps = _BubbleTaps.of(context);
    final onMedia = taps?.actions.onMedia;
    final act = switch (c.transfer) {
      HelixTransferState.notDownloaded => (
        OrbitIcons.downloadSimple,
        OrbitIconWeight.bold,
      ),
      HelixTransferState.downloading ||
      HelixTransferState.uploading => (OrbitIcons.x, OrbitIconWeight.bold),
      HelixTransferState.failed => (
        OrbitIcons.arrowClockwise,
        OrbitIconWeight.bold,
      ),
      HelixTransferState.done => (OrbitIcons.arrowSquareOut, null),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 236),
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 52,
              decoration: BoxDecoration(
                color: t.surface,
                border: Border.all(color: out ? t.outLine : t.line),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Transform.translate(
                    offset: const Offset(0, -4),
                    child: OrbitIcon(
                      OrbitIcons.fileText,
                      weight: OrbitIconWeight.fill,
                      size: 20,
                      color: ink,
                    ),
                  ),
                  Positioned(
                    bottom: 4,
                    child: Text(
                      c.typeLabel,
                      style: t.mono.style(
                        size: 9,
                        weight: 700,
                        color: ink,
                        letterSpacingEm: 0.06,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OrbitText(
                    c.name,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: t.font.style(
                      size: OrbitType.small,
                      weight: 560,
                      color: look.ink,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: OrbitText(
                      '${c.sizeLabel} · ${c.typeLabel}',
                      style: t.mono.style(size: 10.5, color: look.meta),
                    ),
                  ),
                  if (c.progress != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Container(
                          height: 3,
                          color: t.line,
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: c.progress!.clamp(0, 1),
                            child: Container(color: t.accent),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              button: onMedia != null,
              label: switch (c.transfer) {
                HelixTransferState.notDownloaded => 'Download',
                HelixTransferState.downloading ||
                HelixTransferState.uploading => 'Cancel',
                HelixTransferState.failed => 'Try again',
                HelixTransferState.done => 'Open',
              },
              child: _tappable(
                onMedia == null ? null : () => onMedia(taps!.id, 0),
                target: true,
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: t.surface,
                    border: Border.all(color: t.line),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: OrbitIcon(
                      act.$1,
                      weight: act.$2,
                      size: 17,
                      color: t.ink2,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.loc`: a location. 248 wide; a 120px map (`--map-bg` ruled every 22px
/// in `--map-line`, corner 12) with a filled pin at 34px in `--accent`; the
/// label (weight 600, `--t-small`) and address (`--t-caption`, `--ink-3`)
/// 8px in under it; 4px below.
class _Location extends StatelessWidget {
  const _Location({required this.content, required this.look});

  final HelixLocationContent content;
  final _BubbleLook look;

  @override
  Widget build(BuildContext context) {
    final t = look.t;
    return SizedBox(
      width: 248,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 120,
                child: CustomPaint(
                  painter: _MapPainter(bg: t.mapBg, line: t.mapLine),
                  child: Center(
                    child: OrbitIcon(
                      OrbitIcons.mapPin,
                      weight: OrbitIconWeight.fill,
                      size: 34,
                      color: t.accent,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OrbitText(
                    content.label.isEmpty ? 'Location' : content.label,
                    style: t.font.style(
                      size: OrbitType.small,
                      weight: 600,
                      color: look.ink,
                    ),
                  ),
                  OrbitText(
                    content.address,
                    style: t.font.style(size: OrbitType.caption, color: t.ink3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  const _MapPainter({required this.bg, required this.line});

  final Color bg;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final p = Paint()..color = line;
    for (var y = 0.0; y < size.height; y += 22) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), p);
    }
    for (var x = 0.0; x < size.width; x += 22) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.bg != bg || old.line != line;
}

/// `.contact`: a shared contact. At least 236 wide, 4px above and 8px
/// below; a 40px avatar 10px before the name (weight 600) and the number
/// (mono 11px, `--ink-3`).
class _Contact extends StatelessWidget {
  const _Contact({required this.content, required this.look});

  final HelixContactContent content;
  final _BubbleLook look;

  @override
  Widget build(BuildContext context) {
    final t = look.t;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 236),
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Row(
          children: [
            OrbitAvatar(
              avatar: HelixAvatarModel(
                name: content.name,
                colorIndex: HelixAvatarModel.colorIndexFor(content.name),
              ),
              size: 40,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OrbitText(
                    content.name,
                    style: t.font.style(
                      size: OrbitType.body,
                      weight: 600,
                      color: look.ink,
                    ),
                  ),
                  OrbitText(
                    content.detail,
                    style: t.mono.style(size: 11, color: t.ink3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.viewonce`: a photo or video that can be opened once. A 34px circle with
/// a dashed 2px `--accent` edge and "1"; "Photo" or "Video" at weight 560
/// over its state in mono 11px: Tap to view, Sent, or Opened (in `--ink-3`
/// and `--ink-4` once opened).
class _ViewOnce extends StatelessWidget {
  const _ViewOnce({
    required this.content,
    required this.outgoing,
    required this.look,
  });

  final HelixViewOnceContent content;
  final bool outgoing;
  final _BubbleLook look;

  @override
  Widget build(BuildContext context) {
    final t = look.t;
    final opened = content.opened;
    final ring = opened ? t.ink4 : t.accent;
    final status = opened
        ? 'Opened'
        : outgoing
        ? 'Sent'
        : 'Tap to view';
    final taps = _BubbleTaps.of(context);
    final onViewOnce = taps?.actions.onViewOnce;
    return _tappable(
      onViewOnce == null ? null : () => onViewOnce(taps!.id),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 34,
              child: CustomPaint(
                painter: _DashedCircle(ring),
                child: Center(
                  child: Text(
                    '1',
                    style: t.mono.style(size: 15, weight: 700, color: ring),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                OrbitText(
                  content.isVideo ? 'Video' : 'Photo',
                  style: t.font.style(
                    size: OrbitType.body,
                    weight: opened ? 450 : 560,
                    color: opened ? t.ink3 : look.ink,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (opened) ...[
                      OrbitIcon(OrbitIcons.check, size: 11, color: t.ink3),
                      const SizedBox(width: 3),
                    ],
                    OrbitText(
                      status,
                      style: t.mono.style(size: 11, weight: 450, color: t.ink3),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedCircle extends CustomPainter {
  const _DashedCircle(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final r = size.width / 2 - 1;
    final c = size.center(Offset.zero);
    final around = 2 * math.pi * r;
    final n = (around / 12).round();
    final step = 2 * math.pi / n;
    for (var i = 0; i < n; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2 + i * step,
        step / 2,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => old.color != color;
}

/// A placeholder's icon and words (`UI.placeholder`).
(OrbitGlyph, String) _placeholderWords(
  HelixPlaceholderKind kind,
  bool outgoing,
) => switch (kind) {
  HelixPlaceholderKind.deleted => (
    OrbitIcons.prohibit,
    outgoing ? 'You deleted this message' : 'This message was deleted',
  ),
  HelixPlaceholderKind.undecryptable => (
    OrbitIcons.lockSimple,
    "Couldn't decrypt this message",
  ),
  HelixPlaceholderKind.unsupported => (
    OrbitIcons.arrowCircleUp,
    'This message needs a newer version of Orbit',
  ),
  HelixPlaceholderKind.expired => (
    OrbitIcons.timer,
    'This message has disappeared',
  ),
};

/// `.bubble.placeholder`: a deleted, undecryptable, unsupported or
/// disappeared message. No fill, a dashed `--control-line` edge
/// (`--out-line` in yours, `--warning-line` when it could not be
/// decrypted), italic in `--ink-3`; a 16px icon 6px before the text, the
/// meta pushed to the end of whichever line it lands on.
class _PlaceholderBody extends StatelessWidget {
  const _PlaceholderBody({
    required this.message,
    required this.look,
    required this.text,
  });

  final HelixMessage message;
  final _BubbleLook look;
  final TextStyle text;

  @override
  Widget build(BuildContext context) {
    final t = look.t;
    final m = message;
    final c = m.content as HelixPlaceholderContent;
    final (icon, label) = _placeholderWords(c.kind, m.outgoing);
    final warn = c.kind == HelixPlaceholderKind.undecryptable;
    final ink = warn
        ? t.warning
        : m.outgoing
        ? t.outMeta
        : t.ink3;
    final style = text.copyWith(color: ink, fontStyle: FontStyle.italic);
    return _PlaceholderFlow(
      icon: OrbitIcon(icon, size: 16, color: ink),
      text: TextSpan(text: label, style: style),
      style: style,
      meta: _Meta(
        message: m,
        color: look.meta,
        readColor: t.readTick,
        withEdited: false,
      ),
    );
  }
}

/// `display: flex; flex-wrap: wrap; gap: 6px; align-items: center` (the gap
/// between lines too) over the
/// icon, the text and the meta (`margin: 6px -2px -2px auto; top: 4px`).
class _PlaceholderFlow extends MultiChildRenderObjectWidget {
  _PlaceholderFlow({
    required Widget icon,
    required this.text,
    required this.style,
    required Widget meta,
  }) : super(children: [icon, meta]);

  final InlineSpan text;
  final TextStyle style;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPlaceholderFlow(
        text,
        style,
        MediaQuery.textScalerOf(context),
        Directionality.of(context),
      );

  @override
  void updateRenderObject(BuildContext context, _RenderPlaceholderFlow r) => r
    ..text = text
    ..style = style;
}

class _FlowData extends ContainerBoxParentData<RenderBox> {}

class _RenderPlaceholderFlow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FlowData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FlowData> {
  _RenderPlaceholderFlow(this._span, this._style, this._scaler, this._dir);

  InlineSpan _span;
  TextStyle _style;
  final TextScaler _scaler;
  final TextDirection _dir;
  final _painter = TextPainter();
  Offset _textAt = Offset.zero;

  set text(InlineSpan v) {
    if (v == _span) return;
    _span = v;
    markNeedsLayout();
  }

  set style(TextStyle v) {
    if (v == _style) return;
    _style = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FlowData) child.parentData = _FlowData();
  }

  RenderBox get _icon => firstChild!;
  RenderBox get _meta => lastChild!;
  double get _line => _scaler.scale(_style.fontSize!) * _style.height!;

  double _textWidth(double max) {
    _painter
      ..text = _span
      ..textDirection = _dir
      ..textScaler = _scaler
      ..layout(maxWidth: max);
    return _painter.width;
  }

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _icon.getMaxIntrinsicWidth(height) +
      6 +
      _textWidth(double.infinity) +
      6 +
      _meta.getMaxIntrinsicWidth(height) -
      2;

  @override
  double computeMinIntrinsicWidth(double height) =>
      math.max(_textWidth(0), _meta.getMaxIntrinsicWidth(height));

  @override
  void performLayout() {
    final w = constraints.maxWidth;
    _icon.layout(const BoxConstraints(), parentUsesSize: true);
    _meta.layout(const BoxConstraints(), parentUsesSize: true);
    final iconW = _icon.size.width;
    final metaW = _meta.size.width - 2; // the -2px right margin
    final metaH = _meta.size.height + 4;
    final full = _textWidth(double.infinity);

    // Flex lines: [icon, text, meta] while they fit.
    final lines = <List<String>>[[]];
    var used = 0.0;
    void put(String item, double width) {
      final gap = lines.last.isEmpty ? 0 : 6;
      if (lines.last.isNotEmpty && used + gap + width > w + 0.01) {
        lines.add([]);
        used = 0;
      }
      used += (lines.last.isEmpty ? 0 : 6) + width;
      lines.last.add(item);
    }

    put('icon', iconW);
    put('text', math.min(full, w));
    put('meta', metaW);

    // The text wraps to the width it is given on its line.
    var y = 0.0;
    final iconData = _icon.parentData! as _FlowData;
    final metaData = _meta.parentData! as _FlowData;
    for (final line in lines) {
      var x = 0.0;
      final textOnLine = line.contains('text');
      final room = textOnLine ? w - (line.contains('icon') ? iconW + 6 : 0) : w;
      final textW = textOnLine ? _textWidth(room) : 0.0;
      final textLines = textOnLine
          ? math.max(1, _painter.computeLineMetrics().length)
          : 0;
      final textH = textLines * _line;
      final h = [
        if (line.contains('icon')) _icon.size.height,
        if (textOnLine) textH,
        if (line.contains('meta')) metaH,
      ].fold<double>(0, math.max);
      for (final item in line) {
        switch (item) {
          case 'icon':
            iconData.offset = Offset(x, y + (h - _icon.size.height) / 2);
            x += iconW + 6;
          case 'text':
            _textAt = Offset(x, y + (h - textH) / 2);
            x += textW + 6;
          case 'meta':
            // Pushed to the end (`margin-left: auto`), 2px past it.
            metaData.offset = Offset(
              w + 2 - _meta.size.width,
              y + (h - metaH) / 2 + 6 + 4,
            );
        }
      }
      // `gap: 6px` is also the space between wrapped lines.
      y += h + 6;
    }
    y -= 6;
    // Lay the text out again at its own line's width for painting.
    final textLine = lines.firstWhere((l) => l.contains('text'));
    _textWidth(w - (textLine.contains('icon') ? iconW + 6 : 0));
    final widest = constraints.hasBoundedWidth ? w : used;
    size = constraints.constrain(Size(widest, y));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final lines = math.max(1, _painter.computeLineMetrics().length);
    final shift = (_line - _line.roundToDouble()) * lines / 2;
    _painter.paint(context.canvas, offset + _textAt + Offset(0, shift));
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      false;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..label = _span.toPlainText();
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }
}

/// `.reacts`: the reactions under a bubble, overlapping it by 5px, 8px in,
/// 4px apart. Each is a 26px pill (`--surface`, a `--line` edge,
/// `--shadow-card`) with the emoji at 13px and a count in mono 10.5px when
/// more than one; yours is `--accent-soft` with an `--accent-line` edge.
class _Reactions extends StatelessWidget {
  const _Reactions(this.reactions);

  final List<HelixReaction> reactions;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final taps = _BubbleTaps.of(context);
    final onReactions = taps?.actions.onReactions;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final r in reactions)
            Semantics(
              button: true,
              label: r.mine
                  ? '${r.emoji} ${r.count}, tap to remove your reaction'
                  : '${r.emoji} ${r.count}',
              excludeSemantics: true,
              child: _tappable(
                onReactions == null ? null : () => onReactions(taps!.id),
                target: true,
                _Pop(
                  child: Container(
                    height: 26,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: r.mine ? t.accentSoft : t.surface,
                      border: Border.all(color: r.mine ? t.accentLine : t.line),
                      borderRadius: BorderRadius.circular(99),
                      boxShadow: t.shadowCard,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(r.emoji, style: t.font.style(size: 13)),
                        if (r.count > 1) ...[
                          const SizedBox(width: 4),
                          Text(
                            '${r.count}',
                            style: t.mono.style(
                              size: 10.5,
                              weight: 600,
                              color: r.mine ? t.accentInk : t.ink3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A reaction popping in: it grows from 60% with a little overshoot when it
/// first appears, unless the system asks to reduce motion.
class _Pop extends StatelessWidget {
  const _Pop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    if (!OrbitMotion.allowed(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: t.motion.page,
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: child,
    );
  }
}

/// `.failed-line`: under a message that was not sent, or that an action on
/// it did not reach the others. A filled warning, the [label] at
/// `--t-caption` in `--danger`, and Retry in mono 11px at weight 700,
/// tracked, upper case.
class _FailedLine extends StatelessWidget {
  const _FailedLine({
    this.label = 'Not sent',
    this.semanticsLabel = 'Retry sending',
    this.onRetry,
  });

  final String label;

  /// What the Retry button is called to a screen reader (the message's
  /// failure and an action's failure do different things).
  final String semanticsLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OrbitIcon(
            OrbitIcons.warningCircle,
            weight: OrbitIconWeight.fill,
            size: 12,
            color: t.danger,
          ),
          const SizedBox(width: 6),
          OrbitText(
            label,
            style: t.font.style(size: OrbitType.caption, color: t.danger),
          ),
          const SizedBox(width: 6),
          Semantics(
            button: true,
            label: semanticsLabel,
            child: OrbitTapArea(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRetry,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    'RETRY',
                    style: t.mono.style(
                      size: 11,
                      weight: 700,
                      color: t.danger,
                      letterSpacingEm: 0.06,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.typing-bubble`: three 6px dots in `--ink-4` in an incoming bubble,
/// 13px 14px in, each rising 4px in turn every 1.2s; still under reduce
/// motion.
class OrbitTypingBubble extends StatefulWidget {
  const OrbitTypingBubble({super.key});

  @override
  State<OrbitTypingBubble> createState() => _OrbitTypingBubbleState();
}

class _OrbitTypingBubbleState extends State<OrbitTypingBubble>
    with SingleTickerProviderStateMixin {
  late final _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run = OrbitMotion.allowed(context);
    if (run && !_beat.isAnimating) _beat.repeat();
    if (!run && _beat.isAnimating) _beat.reset();
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final radius = _corners(t, false, HelixRunPosition.single);
    final look = _BubbleLook(t, false);
    final (widths, stripe) = look.stripe;
    return Semantics(
      label: 'Typing',
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: CustomPaint(
            painter: _BubbleFrame(
              radius: radius,
              fill: look.fill,
              edge: look.edge,
              widths: widths,
              stripe: stripe,
              shadows: look.glow ?? const [],
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 64),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13) + widths,
                child: AnimatedBuilder(
                  animation: _beat,
                  builder: (context, _) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        _dot(t, i),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// `@keyframes typing`: at rest at 50%, up 4px at full strength 30% of
  /// the way through, each dot 0.15s after the one before.
  Widget _dot(OrbitTokens t, int i) {
    var lift = 0.0;
    var alpha = 1.0;
    if (_beat.isAnimating) {
      final p = ((_beat.value - i * 0.125) % 1 + 1) % 1;
      final k = p < 0.3
          ? Curves.ease.transform(p / 0.3)
          : p < 0.6
          ? 1 - Curves.ease.transform((p - 0.3) / 0.3)
          : 0.0;
      lift = -4 * k;
      alpha = 0.5 + 0.5 * k;
    }
    return Transform.translate(
      offset: Offset(0, lift),
      child: Opacity(
        opacity: alpha,
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: t.ink4, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
