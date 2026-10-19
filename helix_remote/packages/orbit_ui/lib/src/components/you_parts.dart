import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/theme/effect_shapes.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// The tone of a hero card's icon.
enum OrbitHeroTone { brand, ok, warn, danger }

/// One pill under a hero card's title (`.hc-pill`).
class OrbitHeroPill {
  const OrbitHeroPill({required this.text, this.icon, this.tone});

  final String text;
  final OrbitGlyph? icon;

  /// `ok`, `warn` or `accent`; null is the plain `--field` pill.
  final OrbitPillTone? tone;
}

enum OrbitPillTone { ok, warn, accent }

/// `Kit.hero` (`.hero-card` in `css/pages.css`): the summary card at the top
/// of a You-style page. 6px under what is above it, inset by the gutter, 16px
/// in, corner 24, `--surface` with a `--line` edge and a soft shadow (or
/// Papyrus's `cardRing`).
///
/// - [art] replaces the 48px icon tile (a status ring, an avatar); the tile
///   is the brand gradient, or the soft colour of its [tone].
/// - The title is in the display face at 18px, line height 1.25; the [sub]
///   in mono 11.5px in `--ink-3`, 3px under it.
/// - [slot] goes under the top row; [pills] 14px under that.
class OrbitHeroCard extends StatelessWidget {
  const OrbitHeroCard({
    super.key,
    required this.title,
    this.sub = '',
    this.icon,
    this.art,
    this.tone = OrbitHeroTone.brand,
    this.pills = const [],
    this.slot,
    this.margin = const EdgeInsets.fromLTRB(
      OrbitSpace.gutter,
      6,
      OrbitSpace.gutter,
      0,
    ),
  });

  final String title;
  final String sub;
  final OrbitGlyph? icon;
  final Widget? art;
  final OrbitHeroTone tone;
  final List<OrbitHeroPill> pills;
  final Widget? slot;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final ring = orbitEffectOn(t, 'cardRing', '.hero-card');
    final lead = art ?? _tile(t);
    final s = slot;
    return Padding(
      padding: margin,
      child: CustomPaint(
        painter: ring == null ? null : _InsetRings(t, ring, 24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ring == null ? t.surface : null,
            border: Border.all(
              color: tone == OrbitHeroTone.danger ? t.dangerLine : t.line,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: ring == null
                ? [
                    BoxShadow(
                      // The prototype's own rgba(19, 23, 34, 0.35).
                      color: const Color(0x59131722),
                      offset: const Offset(0, 16),
                      blurRadius: orbitCssBlur(34),
                      spreadRadius: -26,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  lead,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OrbitText(
                          orbitTransform(title, t.displayTransform),
                          style: t.display(size: 18, height: 1.25),
                        ),
                        if (sub.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: OrbitText(
                              sub,
                              style: t.mono.style(size: 11.5, color: t.ink3),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              ?s,
              if (pills.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: OrbitPills(pills: pills),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(OrbitTokens t) {
    final glyph = icon ?? OrbitIcons.info;
    if (tone == OrbitHeroTone.brand) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: t.brandGradient,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: const Color(0xBF1D63D8),
              offset: const Offset(0, 10),
              blurRadius: orbitCssBlur(22),
              spreadRadius: -10,
            ),
          ],
        ),
        child: Center(
          child: OrbitIcon(
            glyph,
            weight: OrbitIconWeight.fill,
            size: 24,
            color: t.onBrand,
          ),
        ),
      );
    }
    final (bg, ink, line) = switch (tone) {
      OrbitHeroTone.ok => (t.successSoft, t.success, t.successLine),
      OrbitHeroTone.warn => (t.warningSoft, t.warning, t.warningLine),
      _ => (t.dangerSoft, t.danger, t.dangerLine),
    };
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: line, width: 1.5),
      ),
      child: Center(
        child: OrbitIcon(
          glyph,
          weight: OrbitIconWeight.fill,
          size: 24,
          color: ink,
        ),
      ),
    );
  }
}

/// Papyrus's `cardRing` on a hero card: `--surface` with inset rules.
class _InsetRings extends CustomPainter {
  _InsetRings(this.t, this.effect, this.radius);

  final OrbitTokens t;
  final OrbitEffect effect;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final inner = outer.deflate(1);
    canvas.drawRRect(inner, Paint()..color = t.surface);
    final rings = <(Color, double)>[
      for (final r in effect.param<List<Object?>>('rings') ?? const [])
        if (r is Map && r['token'] is String && r['width'] is num)
          (
            t.value<Color>(r['token']! as String),
            (r['width']! as num).toDouble(),
          ),
    ];
    for (final (c, w) in rings.reversed) {
      canvas.drawDRRect(inner, inner.deflate(w), Paint()..color = c);
    }
  }

  @override
  bool shouldRepaint(_InsetRings old) => true;
}

/// `.hc-pills`: 28px pills, 6px apart, wrapping. Each is 10px in, corner 9,
/// `--field` at 12px weight 560 in `--ink-2`, a 14px icon 5px before the
/// text; `ok`, `warn` and `accent` tint it.
class OrbitPills extends StatelessWidget {
  const OrbitPills({super.key, required this.pills, this.stepPills = false});

  final List<OrbitHeroPill> pills;

  /// `.step-pills`: the current step's pill is at weight 600.
  final bool stepPills;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final p in pills)
          () {
            final (bg, ink) = switch (p.tone) {
              OrbitPillTone.ok => (t.successSoft, t.success),
              OrbitPillTone.warn => (t.warningSoft, t.warning),
              OrbitPillTone.accent => (t.accentSoft, t.accentInk),
              null => (t.field, t.ink2),
            };
            final weight = stepPills && p.tone == OrbitPillTone.accent
                ? 600
                : 560;
            return Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (p.icon != null) ...[
                    OrbitIcon(
                      p.icon!,
                      weight: p.tone == null ? null : OrbitIconWeight.fill,
                      size: 14,
                      color: ink,
                    ),
                    const SizedBox(width: 5),
                  ],
                  // Shrinks to an ellipsis rather than overflowing a pill
                  // wider than the row (large text).
                  Flexible(
                    child: Text(
                      p.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.font.style(
                        size: OrbitType.caption,
                        weight: weight,
                        color: ink,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }(),
      ],
    );
  }
}

/// `Kit.steps(labels, current)`: where a flow is. Earlier steps are ticked
/// `ok` pills, the current one an `accent` pill, later ones plain, each
/// numbered in mono 11px.
class OrbitStepPills extends StatelessWidget {
  const OrbitStepPills({
    super.key,
    required this.labels,
    required this.current,
  });

  final List<String> labels;
  final int current;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Semantics(
      label: 'Step ${current + 1} of ${labels.length}',
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (i, l) in labels.indexed)
            () {
              final done = i < current;
              final now = i == current;
              final (bg, ink) = done
                  ? (t.successSoft, t.success)
                  : now
                  ? (t.accentSoft, t.accentInk)
                  : (t.field, t.ink2);
              return Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (done)
                      OrbitIcon(
                        OrbitIcons.checkCircle,
                        weight: OrbitIconWeight.fill,
                        size: 14,
                        color: ink,
                      )
                    else
                      Text(
                        '${i + 1}',
                        style: t.mono.style(size: 11, weight: 600, color: ink),
                      ),
                    const SizedBox(width: 5),
                    Text(
                      l,
                      style: t.font.style(
                        size: OrbitType.caption,
                        weight: now ? 600 : 560,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              );
            }(),
        ],
      ),
    );
  }
}

/// The state of an [OrbitStatusRing].
enum OrbitRingState { ok, bad, run, idle }

/// `Kit.ring` (`.b-ring`): a 64px status ring (56 in a hero card's top row).
/// `ok` is a tick on `--success-soft` inside a 3px `--success` ring; `bad` a
/// warning in the warning colours; `idle` an icon in the accent; `run` the
/// accent swept round a `--line` track, 5px thick, with the percentage (or a
/// [label] like "2/4") in mono 13px.
class OrbitStatusRing extends StatelessWidget {
  const OrbitStatusRing({
    super.key,
    required this.state,
    this.progress = 0,
    this.icon,
    this.label,
    this.size = 56,
  });

  final OrbitRingState state;
  final double progress;
  final OrbitGlyph? icon;
  final String? label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final iconSize = size == 64 ? 28.0 : 24.0;
    if (state == OrbitRingState.run) {
      return SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _Sweep(progress, t.accent, t.line, t.surface),
          child: Center(
            child: Text(
              label ?? '${(progress * 100).round()}%',
              style: t.mono.style(size: 13, weight: 600, color: t.accentInk),
            ),
          ),
        ),
      );
    }
    final (bg, ink, ring, glyph, weight) = switch (state) {
      OrbitRingState.ok => (
        t.successSoft,
        t.success,
        t.success,
        OrbitIcons.check,
        OrbitIconWeight.bold,
      ),
      OrbitRingState.bad => (
        t.warningSoft,
        t.warning,
        t.warning,
        OrbitIcons.warning,
        OrbitIconWeight.fill,
      ),
      _ => (
        t.accentSoft,
        t.accent,
        t.accentLine,
        icon ?? OrbitIcons.cloudArrowDown,
        null,
      ),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 3),
      ),
      child: Center(
        child: OrbitIcon(glyph, weight: weight, size: iconSize, color: ink),
      ),
    );
  }
}

class _Sweep extends CustomPainter {
  _Sweep(this.p, this.on, this.track, this.hole);

  final double p;
  final Color on;
  final Color track;
  final Color hole;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    canvas
      ..drawOval(box, Paint()..color = track)
      ..drawArc(
        box,
        -math.pi / 2,
        2 * math.pi * p.clamp(0, 1),
        true,
        Paint()..color = on,
      )
      ..drawOval(box.deflate(5), Paint()..color = hole);
  }

  @override
  bool shouldRepaint(_Sweep old) =>
      old.p != p || old.on != on || old.track != track || old.hole != hole;
}

/// One line of [OrbitRules].
class OrbitRule {
  const OrbitRule(this.text, {this.ok = false});

  final String text;
  final bool ok;
}

/// `Kit.rules`: rules that tick as the person types. 6px apart, pulled 4px
/// up into the field above, 2px in, 10px over what follows; each a 16px
/// circle (a filled tick once met, in `--success`) 8px before its text at
/// `--t-caption` in `--ink-3`.
class OrbitRules extends StatelessWidget {
  const OrbitRules({super.key, required this.rules});

  final List<OrbitRule> rules;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Semantics(
      liveRegion: true,
      child: Transform.translate(
        offset: const Offset(0, -4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 10 - 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (i, r) in rules.indexed) ...[
                if (i > 0) const SizedBox(height: 6),
                Row(
                  children: [
                    OrbitIcon(
                      r.ok ? OrbitIcons.checkCircle : OrbitIcons.circle,
                      weight: r.ok ? OrbitIconWeight.fill : null,
                      size: 16,
                      color: r.ok ? t.success : t.ink3,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OrbitText(
                        r.text,
                        style: t.font.style(
                          size: OrbitType.caption,
                          color: r.ok ? t.success : t.ink3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// `.center-page` (`css/pages.css`): one message in the middle of the
/// screen. 24px 32px in, 10px apart; an 84px icon tile (corner 28) 8px more
/// above the title (21px, weight 650, tracked -0.02em)
/// and the text at `--t-small` in `--ink-3`, line height 1.55, at most 300
/// wide; then whatever [children] follow.
class OrbitCenterPage extends StatelessWidget {
  const OrbitCenterPage({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    this.text = '',
    this.children = const [],
    this.top = false,
    this.iconRing = false,
  });

  final OrbitGlyph icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String text;
  final List<Widget> children;

  /// Starts 40px from the top instead of in the middle.
  final bool top;

  /// The app lock's tile: a `--line` edge and a `--line-2` ring outside it.
  final bool iconRing;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(32, top ? 40 : 24, 32, 24),
      child: Column(
        mainAxisAlignment: top
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: iconBackground,
              borderRadius: BorderRadius.circular(28),
              border: iconRing ? Border.all(color: t.line) : null,
              boxShadow: iconRing
                  ? [
                      BoxShadow(color: t.line2, spreadRadius: 11),
                      BoxShadow(color: t.bg, spreadRadius: 10),
                    ]
                  : null,
            ),
            child: Center(
              child: OrbitIcon(
                icon,
                weight: OrbitIconWeight.fill,
                size: 38,
                color: iconColor,
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Not in the prototype's display-face list: the body face.
          OrbitText(
            title,
            textAlign: TextAlign.center,
            style: t.font.style(
              size: 21,
              weight: 650,
              color: t.ink,
              letterSpacingEm: -0.02,
            ),
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: OrbitText(
                text,
                textAlign: TextAlign.center,
                style: t.font.style(
                  size: OrbitType.small,
                  color: t.ink3,
                  height: 1.55,
                ),
              ),
            ),
          ],
          for (final c in children) ...[const SizedBox(height: 10), c],
        ],
      ),
    );
  }
}
