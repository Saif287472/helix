import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/avatar.dart';
import 'package:orbit_ui/src/components/icon_button.dart';
import 'package:orbit_ui/src/components/page_parts.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/theme/motion.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';
import 'package:orbit_ui/src/window/window_scaffold.dart';

/// The height of a chat-list row (`--row-h`).
const double orbitRowHeight = 72;

/// What a preview kind shows when its text is empty, and its icon
/// (`previewLabels` in `js/ui.js`).
(OrbitGlyph?, String) orbitPreviewLabel(HelixPreviewKind kind) =>
    switch (kind) {
      HelixPreviewKind.text => (null, ''),
      HelixPreviewKind.image => (OrbitIcons.image, 'Photo'),
      HelixPreviewKind.video => (OrbitIcons.videoCamera, 'Video'),
      HelixPreviewKind.gif => (OrbitIcons.gif, 'GIF'),
      HelixPreviewKind.voiceNote => (OrbitIcons.microphone, 'Voice message'),
      HelixPreviewKind.document => (OrbitIcons.fileText, 'Document'),
      HelixPreviewKind.sticker => (OrbitIcons.sticker, 'Sticker'),
      HelixPreviewKind.location => (OrbitIcons.mapPin, 'Location'),
      HelixPreviewKind.contact => (OrbitIcons.userCircle, 'Contact'),
      HelixPreviewKind.poll => (OrbitIcons.chartBarHorizontal, 'Poll'),
      HelixPreviewKind.call => (OrbitIcons.phone, 'Call'),
      HelixPreviewKind.deleted => (
        OrbitIcons.prohibit,
        'This message was deleted',
      ),
      HelixPreviewKind.undecryptable => (
        OrbitIcons.lockSimple,
        'Couldn\'t decrypt this message',
      ),
      HelixPreviewKind.unsupported => (
        OrbitIcons.arrowCircleUp,
        'Needs a newer version of Orbit',
      ),
    };

/// `UI.tick(status)` (`js/ui.js`): the delivery tick, 16px, regular weight
/// in the text's colour; read is bold in `--read`, failed a filled warning in
/// `--danger`. Each carries its name for screen readers.
class OrbitTick extends StatelessWidget {
  const OrbitTick(this.status, {super.key, this.color, this.size = 16});

  final HelixDeliveryStatus status;

  /// The colour of pending, sent and delivered (the line's own).
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final (glyph, weight, ink, label) = switch (status) {
      HelixDeliveryStatus.pending => (
        OrbitIcons.clock,
        OrbitIconWeight.regular,
        color,
        'Sending',
      ),
      HelixDeliveryStatus.sent => (
        OrbitIcons.check,
        OrbitIconWeight.regular,
        color,
        'Sent',
      ),
      HelixDeliveryStatus.delivered => (
        OrbitIcons.checks,
        OrbitIconWeight.regular,
        color,
        'Delivered',
      ),
      HelixDeliveryStatus.read => (
        OrbitIcons.checks,
        OrbitIconWeight.bold,
        t.readTick,
        'Read',
      ),
      HelixDeliveryStatus.failed => (
        OrbitIcons.warningCircle,
        OrbitIconWeight.fill,
        t.danger,
        'Not sent',
      ),
    };
    return Semantics(
      label: label,
      child: OrbitIcon(glyph, weight: weight, size: size, color: ink),
    );
  }
}

/// `.badge` (`css/components.css`): a 22px count, at least 22 wide, 7px in,
/// corner 8, `--accent` with mono 11.5px at weight 600 (99+ past 99); muted
/// chats get `--line` and `--ink-2`. [mention] is the `@` badge, in
/// `--accent-soft` and `--accent-ink`, in the body face at weight 700.
class OrbitBadge extends StatelessWidget {
  const OrbitBadge({
    super.key,
    this.count = 0,
    this.muted = false,
    this.mention = false,
  });

  final int count;
  final bool muted;
  final bool mention;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final (bg, ink) = mention
        ? (t.accentSoft, t.accentInk)
        : muted
        ? (t.line, t.ink2)
        : (t.accent, t.onAccent);
    final text = mention
        ? '@'
        : count > 99
        ? '99+'
        : '$count';
    final style = mention
        ? t.font.style(size: 11.5, weight: 700, color: ink)
        : t.mono.style(size: 11.5, weight: 600, color: ink);
    return Semantics(
      label: mention ? 'You were mentioned' : '$text unread',
      excludeSemantics: true,
      child: Container(
        height: 22,
        constraints: const BoxConstraints(minWidth: 22),
        padding: EdgeInsets.symmetric(horizontal: mention ? 0 : 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: style),
      ),
    );
  }
}

/// `.list-label` (`css/components.css`): a list section's eyebrow, 16px
/// above and 6px below, inset by the gutter, with an optional [count].
class OrbitListLabel extends StatelessWidget {
  const OrbitListLabel(this.text, {super.key, this.count});

  final String text;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final n = count;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OrbitSpace.gutter,
        16,
        OrbitSpace.gutter,
        6,
      ),
      child: Row(
        children: [
          OrbitEyebrow(text),
          if (n != null) ...[
            const SizedBox(width: 6),
            // A number people read: `--ink-3`, never the decorative --ink-4.
            OrbitEyebrow('$n', color: t.ink3),
          ],
        ],
      ),
    );
  }
}

/// The parts every list row shares (`.chat-row`): 72px, inset by the
/// gutter, a 52px avatar 14px before the text; a name line (`--t-headline`
/// at weight 600) over a preview line (`--t-small` in `--ink-3`), 3px apart.
/// `--hover` under the pointer, `--pressed` while pressed, `--accent-soft`
/// when [selected].
class _RowFrame extends StatelessWidget {
  const _RowFrame({
    required this.avatar,
    required this.top,
    required this.bottom,
    this.trailing,
    this.selected = false,
    this.background,
    this.onTap,
    this.onLongPress,
    this.label,
    this.current = false,
  });

  final Widget avatar;
  final Widget top;
  final Widget bottom;
  final Widget? trailing;
  final bool selected;
  final Color? background;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? label;

  /// Open on the right of a wide window (`.chat-row.current`):
  /// `--accent-soft` with a 3px `--accent` bar on the left.
  final bool current;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final end = trailing;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected || current
            ? t.accentSoft
            : background ?? Colors.transparent,
        shape: current
            ? Border(left: BorderSide(color: t.accent, width: 3))
            : null,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          splashFactory: NoSplash.splashFactory,
          hoverColor: t.hover,
          highlightColor: t.pressed,
          child: SizedBox(
            height: orbitRowHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: OrbitSpace.gutter,
              ),
              child: Row(
                children: [
                  avatar,
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [top, const SizedBox(height: 3), bottom],
                    ),
                  ),
                  if (end != null) ...[const SizedBox(width: 14), end],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The name of a row: `--t-headline` at weight 600, tracked -0.01em, cut
/// with an ellipsis, with a filled seal in `--accent` after it when
/// [verified].
class _RowName extends StatelessWidget {
  const _RowName(this.name, {this.verified = false, this.color});

  final String name;
  final bool verified;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Row(
      children: [
        Flexible(
          child: OrbitText(
            name,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: t.font.style(
              size: OrbitType.headline,
              weight: 600,
              color: color ?? t.ink,
              letterSpacingEm: -0.01,
            ),
          ),
        ),
        if (verified) ...[
          const SizedBox(width: 5),
          Semantics(
            label: 'Safety number verified',
            child: OrbitIcon(
              OrbitIcons.sealCheck,
              weight: OrbitIconWeight.fill,
              size: 15,
              color: t.accent,
            ),
          ),
        ],
      ],
    );
  }
}

/// `UI.chatRow(item, opts)` (`js/ui.js`; `.chat-row` in
/// `css/components.css`): one row of the chat list.
///
/// - The time is mono `--t-meta` in `--ink-3`; with unread messages (and not
///   muted) it is `--accent-ink` at weight 600, and the preview `--ink-2`.
/// - The preview: an italic typing label in `--accent-ink`; or "Draft:" in
///   `--danger`; or the tick and the sender ("You:", "Ammu:" in `--ink-2`),
///   then the kind's icon and the text or the kind's label (italic for a
///   deleted, undecryptable or unsupported message).
/// - The flags at the end, 6px apart in `--ink-4`: muted, pinned, archived
///   (when [showArchived]), then the `@` and count badges.
/// - [selected] shows the avatar ticked on `--accent-soft`.
class OrbitChatListTile extends StatelessWidget {
  const OrbitChatListTile({
    super.key,
    required this.item,
    this.selected = false,
    this.showArchived = false,
    this.background,
    this.onTap,
    this.onLongPress,
  });

  final HelixChatListItem item;
  final bool selected;
  final bool showArchived;

  /// The row's own fill (`--bg` inside a swipe wrapper).
  final Color? background;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final unread = item.unreadCount > 0;
    final loud = unread && !item.muted;
    final time = OrbitText(
      item.timeLabel,
      style: t.mono.style(
        size: OrbitType.meta,
        weight: loud ? 600 : 400,
        color: loud ? t.accentInk : t.ink3,
        letterSpacingEm: 0,
      ),
    );
    final flags = <Widget>[
      if (item.muted) OrbitIcon(OrbitIcons.bellSlash, size: 16, color: t.ink4),
      if (item.pinned)
        OrbitIcon(
          OrbitIcons.pushPin,
          weight: OrbitIconWeight.fill,
          size: 16,
          color: t.ink4,
        ),
      if (showArchived && item.archived)
        OrbitIcon(OrbitIcons.archive, size: 16, color: t.ink4),
      if (item.hasMention && unread)
        OrbitBadge(mention: true, muted: item.muted),
      if (unread) OrbitBadge(count: item.unreadCount, muted: item.muted),
    ];
    return _RowFrame(
      label: item.title,
      selected: selected,
      current: OrbitCurrentScope.of(context) == item.id,
      background: background,
      onTap: onTap,
      onLongPress: onLongPress,
      avatar: OrbitAvatar(avatar: item.avatar, size: 52, check: selected),
      top: Row(
        children: [
          Expanded(child: _RowName(item.title, verified: item.verified)),
          const SizedBox(width: 8),
          time,
        ],
      ),
      bottom: Row(
        children: [
          Expanded(child: _preview(t, loud)),
          if (flags.isNotEmpty) ...[
            const SizedBox(width: 8),
            for (final (i, f) in flags.indexed) ...[
              if (i > 0) const SizedBox(width: 6),
              f,
            ],
          ],
        ],
      ),
    );
  }

  Widget _preview(OrbitTokens t, bool loud) {
    final base = t.font.style(
      size: OrbitType.small,
      color: loud ? t.ink2 : t.ink3,
    );
    final typing = item.typingLabel;
    if (typing != null) {
      return OrbitText(
        typing,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        // Italic (`css/screens.css`); `--accent-ink`, except that an unread
        // row's `--ink-2` comes later in the prototype's CSS and wins.
        style: base.copyWith(
          color: loud ? t.ink2 : t.accentInk,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w500,
          fontVariations: const [FontVariation('wght', 500)],
        ),
      );
    }
    final p = item.preview;
    if (p == null) return const SizedBox.shrink();
    final (icon, label) = orbitPreviewLabel(p.kind);
    final italic =
        p.kind == HelixPreviewKind.deleted ||
        p.kind == HelixPreviewKind.undecryptable ||
        p.kind == HelixPreviewKind.unsupported;
    final parts = <Widget>[];
    TextStyle weight(TextStyle s, int w) => s.copyWith(
      fontWeight: FontWeight.values[(w ~/ 100) - 1],
      fontVariations: [FontVariation('wght', w.toDouble())],
    );
    if (p.isDraft) {
      parts.add(
        OrbitText('Draft:', style: weight(base.copyWith(color: t.danger), 560)),
      );
    } else {
      final status = p.status;
      if (status != null) parts.add(OrbitTick(status, color: base.color));
      final who = p.senderPrefix;
      if (who != null) {
        parts.add(
          OrbitText('$who:', style: weight(base.copyWith(color: t.ink2), 500)),
        );
      }
    }
    if (icon != null) {
      parts.add(OrbitIcon(icon, size: 15, color: base.color));
    }
    return Row(
      children: [
        for (final w in parts) ...[w, const SizedBox(width: 4)],
        Flexible(
          child: OrbitText(
            p.text.isEmpty ? label : p.text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: italic ? base.copyWith(fontStyle: FontStyle.italic) : base,
          ),
        ),
      ],
    );
  }
}

/// `UI.callRow(item)` (`js/ui.js`): one row of the call log. The name in
/// `--danger` for a missed or failed call, "(3)" after it for folded calls;
/// under it the direction (bold arrows: incoming and outgoing in
/// `--success`, missed in `--danger`, declined in `--ink-4`; failed a filled
/// warning in `--danger`), a video camera for video calls, and the time in
/// mono 12px; at the end, an accent button that calls back the same way.
class OrbitCallLogTile extends StatelessWidget {
  const OrbitCallLogTile({
    super.key,
    required this.item,
    this.background,
    this.onTap,
    this.onLongPress,
    this.onCallBack,
  });

  final HelixCallLogItem item;
  final Color? background;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onCallBack;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final (glyph, ink, label, weight) = switch (item.direction) {
      HelixCallDirection.incoming => (
        OrbitIcons.arrowDownLeft,
        t.success,
        'Incoming',
        OrbitIconWeight.bold,
      ),
      HelixCallDirection.outgoing => (
        OrbitIcons.arrowUpRight,
        t.success,
        'Outgoing',
        OrbitIconWeight.bold,
      ),
      HelixCallDirection.missed => (
        OrbitIcons.arrowDownLeft,
        t.danger,
        'Missed',
        OrbitIconWeight.bold,
      ),
      HelixCallDirection.declined => (
        OrbitIcons.arrowDownLeft,
        t.ink4,
        'Declined',
        OrbitIconWeight.bold,
      ),
      HelixCallDirection.failed => (
        OrbitIcons.warningCircle,
        t.danger,
        'Failed',
        OrbitIconWeight.fill,
      ),
    };
    final red =
        item.direction == HelixCallDirection.missed ||
        item.direction == HelixCallDirection.failed;
    final base = t.font.style(size: OrbitType.small, color: t.ink3);
    return _RowFrame(
      label: item.title,
      background: background,
      onTap: onTap,
      onLongPress: onLongPress,
      avatar: OrbitAvatar(avatar: item.avatar, size: 52),
      top: _RowName(
        item.count > 1 ? '${item.title} (${item.count})' : item.title,
        color: red ? t.danger : null,
      ),
      bottom: Row(
        children: [
          Semantics(
            label: label,
            child: OrbitIcon(glyph, weight: weight, size: 15, color: ink),
          ),
          const SizedBox(width: 4),
          if (item.video) ...[
            OrbitIcon(OrbitIcons.videoCamera, size: 15, color: base.color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: OrbitText(
              item.timeLabel,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: t.mono.style(
                size: 12,
                color: t.ink3,
                letterSpacingEm: 0.02,
              ),
            ),
          ),
        ],
      ),
      trailing: OrbitIconButton(
        icon: item.video ? OrbitIcons.videoCamera : OrbitIcons.phone,
        tooltip: item.video ? 'Video call' : 'Voice call',
        tone: OrbitIconButtonTone.accent,
        onPressed: onCallBack,
      ),
    );
  }
}

/// What a swipe does: its label and icon behind the row, and what runs
/// past 30% of the row's width.
class OrbitSwipeAction {
  const OrbitSwipeAction({
    required this.icon,
    required this.label,
    required this.onSwiped,
  });

  final OrbitGlyph icon;
  final String label;
  final VoidCallback onSwiped;
}

/// `.swipe-wrap` (`css/components.css`; the drag in `js/screens/home.js`):
/// a row that follows a sideways drag over a colour showing what letting go
/// will do; past 30% of the width it does it, and the row springs back over
/// 200ms either way. [start] is a drag to the right (pin), [end] to the left
/// (archive, delete). The labels are mono `--t-meta` upper case in
/// `--on-accent`, 24px in, under a 20px filled icon.
class OrbitSwipeRow extends StatefulWidget {
  const OrbitSwipeRow({
    super.key,
    required this.child,
    this.start,
    this.end,
    this.color,
  });

  final Widget child;
  final OrbitSwipeAction? start;
  final OrbitSwipeAction? end;

  /// The colour behind the row: `--accent`, or `--danger` for a delete.
  final Color? color;

  @override
  State<OrbitSwipeRow> createState() => _OrbitSwipeRowState();
}

class _OrbitSwipeRowState extends State<OrbitSwipeRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _back;
  double _dx = 0;
  double _from = 0;
  double Function(double) _ease = (v) => v;

  @override
  void initState() {
    super.initState();
    _back = AnimationController(vsync: this)
      ..addListener(
        () => setState(() => _dx = _from * (1 - _ease(_back.value))),
      );
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _drag(DragUpdateDetails d) {
    _back.stop();
    setState(() {
      _dx += d.delta.dx;
      if (widget.start == null && _dx > 0) _dx = 0;
      if (widget.end == null && _dx < 0) _dx = 0;
    });
  }

  void _release(double width) {
    final t = OrbitTokens.of(context);
    if (_dx > width * 0.3) widget.start?.onSwiped();
    if (_dx < -width * 0.3) widget.end?.onSwiped();
    _from = _dx;
    _ease = t.motion.curve.transform;
    _back.duration = OrbitMotion.allowed(context)
        ? const Duration(milliseconds: 200)
        : Duration.zero;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    Widget side(OrbitSwipeAction a, bool visible) => Opacity(
      opacity: visible ? 1 : 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OrbitIcon(
            a.icon,
            weight: OrbitIconWeight.fill,
            size: 20,
            color: t.onAccent,
          ),
          const SizedBox(height: 4),
          OrbitText(
            a.label.toUpperCase(),
            style: t.mono.style(
              size: OrbitType.meta,
              color: t.onAccent,
              letterSpacingEm: 0.06,
            ),
          ),
        ],
      ),
    );
    final start = widget.start;
    final end = widget.end;
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        onHorizontalDragUpdate: _drag,
        onHorizontalDragEnd: (_) => _release(box.maxWidth),
        onHorizontalDragCancel: () => _release(box.maxWidth),
        child: ClipRect(
          child: Stack(
            children: [
              if (_dx != 0)
                Positioned.fill(
                  child: ColoredBox(
                    color: widget.color ?? t.accent,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: [
                          if (start != null) side(start, _dx > 0),
                          const Spacer(),
                          if (end != null) side(end, _dx < 0),
                        ],
                      ),
                    ),
                  ),
                ),
              Transform.translate(offset: Offset(_dx, 0), child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}
