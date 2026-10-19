import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/components/page_bits.dart';
import 'package:orbit_ui/src/components/spinner.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/theme/motion.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// The shape of the rows an [OrbitSkeleton] stands in for.
enum OrbitSkeletonKind {
  /// A chat row: a 52px avatar, two lines and a time.
  chat,

  /// A person: a 44px avatar and two lines, the second short.
  person,

  /// A settings row: a 36px icon tile and one line, 56px tall.
  row,

  /// Two tiles side by side, 104px tall.
  tile,
}

/// `Kit.skeleton(n, kind, label)` (`.skel` in `css/pages.css`): placeholder
/// rows the shape of the real ones, `--field` with corner 8, announced as
/// [label]. A highlight in `--hover` sweeps across every 1.4s unless the
/// system asks to reduce motion.
class OrbitSkeleton extends StatefulWidget {
  const OrbitSkeleton({
    super.key,
    this.count = 6,
    this.kind = OrbitSkeletonKind.chat,
    this.label = 'Loading',
  });

  final int count;
  final OrbitSkeletonKind kind;
  final String label;

  @override
  State<OrbitSkeleton> createState() => _OrbitSkeletonState();
}

class _OrbitSkeletonState extends State<OrbitSkeleton>
    with SingleTickerProviderStateMixin {
  late final _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run = OrbitMotion.allowed(context);
    if (run && !_sweep.isAnimating) _sweep.repeat();
    if (!run && _sweep.isAnimating) _sweep.reset();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    Widget bone(double w, double h, {double radius = 8}) =>
        _Bone(width: w, height: h, radius: radius, sweep: _sweep);
    Widget lines(List<(double, double)> parts) => Expanded(
      child: LayoutBuilder(
        builder: (context, box) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, (w, h)) in parts.indexed) ...[
              if (i > 0) const SizedBox(height: 8),
              bone(box.maxWidth * w, h),
            ],
          ],
        ),
      ),
    );
    Widget row() => switch (widget.kind) {
      // The time sits 18px from the top of the 72px row (`align-self:
      // flex-start`), not centred like the rest.
      OrbitSkeletonKind.chat => SizedBox(
        height: 72,
        child: Row(
          children: [
            bone(52, 52, radius: 52 * t.avatarR / 100),
            const SizedBox(width: 14),
            lines([(0.52, 13), (0.78, 11)]),
            const SizedBox(width: 14),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 18),
                child: bone(34, 10),
              ),
            ),
          ],
        ),
      ),
      OrbitSkeletonKind.person => Row(
        children: [
          bone(44, 44, radius: 44 * t.avatarR / 100),
          const SizedBox(width: 14),
          lines([(0.52, 13), (0.36, 11)]),
        ],
      ),
      OrbitSkeletonKind.row => Row(
        children: [
          bone(36, 36, radius: 11),
          const SizedBox(width: 14),
          lines([(0.52, 13)]),
        ],
      ),
      OrbitSkeletonKind.tile => Row(
        children: [
          Expanded(child: bone(double.infinity, 104, radius: t.rLg)),
          const SizedBox(width: 10),
          Expanded(child: bone(double.infinity, 104, radius: t.rLg)),
        ],
      ),
    };
    final minHeight = switch (widget.kind) {
      OrbitSkeletonKind.row => 56.0,
      OrbitSkeletonKind.tile => 0.0,
      _ => 72.0,
    };
    final vertical = widget.kind == OrbitSkeletonKind.tile ? 6.0 : 0.0;
    return Semantics(
      label: widget.label,
      liveRegion: true,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < widget.count; i++)
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: minHeight),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: OrbitSpace.gutter,
                      vertical: vertical,
                    ),
                    child: Center(child: row()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One `.sk` shape, with the `::after` sweep.
class _Bone extends StatelessWidget {
  const _Bone({
    required this.width,
    required this.height,
    required this.radius,
    required this.sweep,
  });

  final double width;
  final double height;
  final double radius;
  final AnimationController sweep;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: ColoredBox(
          color: t.field,
          child: AnimatedBuilder(
            animation: sweep,
            builder: (context, _) {
              if (!sweep.isAnimating) return const SizedBox.expand();
              final p = t.motion.curve.transform(sweep.value);
              return FractionalTranslation(
                translation: Offset(-1 + 2 * p, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        t.hover.withValues(alpha: 0),
                        t.hover,
                        t.hover.withValues(alpha: 0),
                      ],
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// `Kit.loading(label)` (`.page-loading` in `css/pages.css`): a page that
/// is opening. A 26px spinner in `--accent` over [label] at `--t-small` in
/// `--ink-3`, 10px apart and centred, 48px 24px in.
class OrbitPageLoading extends StatelessWidget {
  const OrbitPageLoading({super.key, this.label = 'Loading…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OrbitSpinner(size: 26, color: t.accent),
              const SizedBox(height: 10),
              OrbitText(
                label,
                textAlign: TextAlign.center,
                style: t.font.style(size: OrbitType.small, color: t.ink3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `Kit.loadFailed(title, opts)` (`.load-failed` in `css/pages.css`): a page
/// or list that could not load, centred, 40px 28px in: a 56px `--field` tile
/// (corner 18) with a cloud, the title at `--t-body` weight 600, the [sub]
/// at `--t-small` in `--ink-3` at most 280 wide, then Try again, a 40px
/// secondary button 16px down. [compact] lays it in a row for inside a card
/// or list: a 40px tile, the text, and a 36px button, 14px in.
class OrbitLoadFailed extends StatelessWidget {
  const OrbitLoadFailed({
    super.key,
    this.title = 'This could not be loaded.',
    this.sub = 'Check your connection and try again.',
    this.onRetry,
    this.retry = true,
    this.compact = false,
  });

  final String title;
  final String sub;
  final VoidCallback? onRetry;
  final bool retry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final tile = compact ? 40.0 : 56.0;
    final icon = Container(
      width: tile,
      height: tile,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.field,
        borderRadius: BorderRadius.circular(compact ? 12 : 18),
      ),
      child: OrbitIcon(
        OrbitIcons.cloudSlash,
        size: compact ? 20 : 26,
        color: t.ink3,
      ),
    );
    final align = compact ? TextAlign.left : TextAlign.center;
    final text = Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        OrbitText(
          title,
          textAlign: align,
          style: t.font.style(size: OrbitType.body, weight: 600, color: t.ink),
        ),
        if (sub.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: OrbitText(
                sub,
                textAlign: align,
                style: t.font.style(
                  size: OrbitType.small,
                  color: t.ink3,
                  height: 1.5,
                ),
              ),
            ),
          ),
      ],
    );
    final button = retry
        ? OrbitButton(
            label: 'Try again',
            kind: OrbitButtonKind.secondary,
            icon: OrbitIcons.arrowsClockwise,
            onPressed: onRetry,
            height: compact ? 36 : 40,
            padding: compact ? 12 : 20,
            fontSize: compact ? 13 : OrbitType.small,
          )
        : null;
    return Semantics(
      liveRegion: true,
      child: compact
          ? Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Expanded(child: text),
                  if (button != null) ...[const SizedBox(width: 12), button],
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
              child: Column(
                children: [
                  icon,
                  const SizedBox(height: 10),
                  text,
                  if (button != null) ...[const SizedBox(height: 16), button],
                ],
              ),
            ),
    );
  }
}

/// What an [OrbitPermissionCard] asks for.
enum OrbitPermission { camera, microphone, contacts, notifications }

/// `Kit.permission(kind, opts)` (`.perm-card` in `css/pages.css`): asking
/// for a system permission. 12px under what is above it and inset by the
/// gutter, 14px in, `--surface` with a `--line` edge, corner `--r-lg`; a
/// 44px `--accent-soft` tile (corner 14) with the filled icon at 22px in
/// `--accent`, 14px before the title (weight 600), the [text] at `--t-small`
/// in `--ink-3`, and a 38px button 10px under it: Allow (primary), or after a
/// refusal ([denied]) Open settings (secondary).
class OrbitPermissionCard extends StatelessWidget {
  const OrbitPermissionCard({
    super.key,
    required this.kind,
    this.denied = false,
    this.text = '',
    this.onPressed,
    this.dark = false,
  });

  final OrbitPermission kind;
  final bool denied;

  /// `.perm-card.dark`: on a night page (the scanner), a faint white card
  /// in `--night-text`.
  final bool dark;
  final String text;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final (icon, name) = switch (kind) {
      OrbitPermission.camera => (OrbitIcons.camera, 'camera'),
      OrbitPermission.microphone => (OrbitIcons.microphone, 'microphone'),
      OrbitPermission.contacts => (OrbitIcons.addressBook, 'contacts'),
      OrbitPermission.notifications => (
        OrbitIcons.bellRinging,
        'notifications',
      ),
    };
    final title = denied ? 'Orbit can’t use your $name' : 'Allow your $name';
    return Container(
      margin: const EdgeInsets.fromLTRB(
        OrbitSpace.gutter,
        12,
        OrbitSpace.gutter,
        0,
      ),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? const Color(0x0FFFFFFF) : t.surface,
        border: Border.all(color: dark ? const Color(0x24FFFFFF) : t.line),
        borderRadius: BorderRadius.circular(t.rLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.accentSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: OrbitIcon(
              icon,
              weight: OrbitIconWeight.fill,
              size: 22,
              color: t.accent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OrbitText(
                  title,
                  style: t.font.style(
                    size: OrbitType.body,
                    weight: 600,
                    color: dark ? OrbitNight.text : t.ink,
                  ),
                ),
                if (text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: OrbitText(
                      text,
                      style: t.font.style(
                        size: OrbitType.small,
                        color: dark
                            ? OrbitNight.text.withValues(alpha: 0.75)
                            : t.ink3,
                        height: 1.5,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                OrbitButton(
                  label: denied ? 'Open settings' : 'Allow',
                  kind: denied
                      ? OrbitButtonKind.secondary
                      : OrbitButtonKind.primary,
                  onPressed: onPressed,
                  height: 38,
                  padding: 14,
                  fontSize: 13,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `Kit.fieldLock(text)` (`.fld-lock` in `css/pages.css`): under a field,
/// locked for a while after too many tries. A filled hourglass at 15px and
/// the text at `--t-caption` in `--warning`, line height 1.45, pulled 8px up
/// into the field's own space, 12px over what follows.
class OrbitFieldLock extends StatelessWidget {
  const OrbitFieldLock(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Semantics(
      liveRegion: true,
      child: Transform.translate(
        offset: const Offset(0, -8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 12 - 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: OrbitIcon(
                  OrbitIcons.hourglassMedium,
                  weight: OrbitIconWeight.fill,
                  size: 15,
                  color: t.warning,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OrbitText(
                  text,
                  style: t.font.style(
                    size: OrbitType.caption,
                    color: t.warning,
                    height: 1.45,
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
