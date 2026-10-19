import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/avatar.dart';
import 'package:orbit_ui/src/components/page_parts.dart';
import 'package:orbit_ui/src/components/toggles.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/theme/effect_shapes.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// `.card` (`css/components.css`): inset by the gutter, `--surface` with a
/// 1px `--line` edge, corner `--r-lg`, `--shadow-card`, its rows clipped to
/// it. Rows after the first get a 1px `--line-2` rule along their top, from
/// [dividerIndent] (64, past the row icon; 14 in a card with no icons).
///
/// - [dangerZone]: `.card.danger-zone`, `--danger-line` edge on
///   `--danger-zone-bg`, rules in `--danger-zone-line`.
/// - [padding]: a card that holds fields (`.form-card`: 14px 14px 2px) or
///   other content instead of rows.
/// - Papyrus's `cardRing` replaces the shadow with a 3px `--surface` and a
///   1px `--line` rule just inside the edge.
class OrbitCard extends StatelessWidget {
  const OrbitCard({
    super.key,
    required this.children,
    this.dangerZone = false,
    this.dividerIndent = 64,
    this.padding = EdgeInsets.zero,
    this.margin = const EdgeInsets.symmetric(horizontal: OrbitSpace.gutter),
    this.dividers = true,
  });

  final List<Widget> children;
  final bool dangerZone;
  final double dividerIndent;
  final EdgeInsets padding;
  final EdgeInsets margin;

  /// Rows get rules between them; other content does not.
  final bool dividers;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final ring = orbitEffectOn(t, 'cardRing', '.card');
    final radius = t.rLg;
    final rule = dangerZone ? t.dangerZoneLine : t.line2;
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: ring == null ? t.shadowCard : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: CustomPaint(
            painter: _CardFace(
              fill: dangerZone ? t.dangerZoneBg : t.surface,
              edge: dangerZone ? t.dangerLine : t.line,
              radius: radius,
              ring: ring == null ? null : _rings(t, ring),
            ),
            child: Padding(
              padding: padding + const EdgeInsets.all(1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, c) in children.indexed)
                    if (i == 0 || !dividers)
                      c
                    else
                      Stack(
                        children: [
                          c,
                          Positioned(
                            top: 0,
                            left: dividerIndent,
                            right: 0,
                            height: 1,
                            child: ColoredBox(color: rule),
                          ),
                        ],
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The `cardRing` rules, outermost last: (colour, width) as inset shadows.
  static List<(Color, double)> _rings(OrbitTokens t, OrbitEffect e) => [
    for (final r in e.param<List<Object?>>('rings') ?? const [])
      if (r is Map && r['token'] is String && r['width'] is num)
        (
          t.value<Color>(r['token']! as String),
          (r['width']! as num).toDouble(),
        ),
  ];
}

class _CardFace extends CustomPainter {
  const _CardFace({
    required this.fill,
    required this.edge,
    required this.radius,
    this.ring,
  });

  final Color fill;
  final Color edge;
  final double radius;
  final List<(Color, double)>? ring;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final inner = outer.deflate(1);
    canvas.drawRRect(outer, Paint()..color = edge);
    canvas.drawRRect(inner, Paint()..color = fill);
    // Inset shadows, painted bottom first: CSS lists the top one first.
    for (final (colour, width) in (ring ?? const []).reversed) {
      canvas.drawDRRect(inner, inner.deflate(width), Paint()..color = colour);
    }
  }

  @override
  bool shouldRepaint(_CardFace old) =>
      old.fill != fill || old.edge != edge || old.radius != radius;
}

/// What sits at the end of an [OrbitListRow].
enum OrbitRowEnd { none, chevron, toggle }

/// `UI.row` (`.row` in `css/components.css`): at least 60px, 10px 14px in,
/// 14px between parts.
///
/// - The icon tile is 36px, corner 11, a 19px icon in the palette colour
///   [iconColor] (`--av-N-bg`/`--av-N-ink`), or `--field`/`--ink-2`.
/// - The title is `--t-body` at weight 520; the [sub] under it at
///   `--t-caption` in `--ink-3`, 2px down, line height 1.35 (`--t-meta` mono
///   when [subMono]).
/// - The end: a [value] at `--t-small` in `--ink-3`, then an 18px chevron in
///   `--ink-4`, or a switch, 6px apart.
/// - [danger]: the title and icon in `--danger` on `--danger-soft`.
/// - [accent]: the title in `--accent-ink`.
/// - A switch row toggles from anywhere on it.
class OrbitListRow extends StatelessWidget {
  const OrbitListRow({
    super.key,
    required this.title,
    this.icon,
    this.iconColor,
    this.iconWeight,
    this.sub = '',
    this.subMono = false,
    this.value = '',
    this.end = OrbitRowEnd.none,
    this.on = false,
    this.danger = false,
    this.accent = false,
    this.trailing,
    this.onTap,
    this.onChanged,
    this.leading,
    this.subLeading,
    this.titleWidget,
  });

  final String title;
  final OrbitGlyph? icon;
  final int? iconColor;
  final OrbitIconWeight? iconWeight;
  final String sub;
  final bool subMono;
  final String value;
  final OrbitRowEnd end;

  /// The switch's state, for [OrbitRowEnd.toggle].
  final bool on;
  final bool danger;
  final bool accent;

  /// Anything else at the end (`end: html`), after [value].
  final Widget? trailing;
  final VoidCallback? onTap;

  /// A switch row's change.
  final ValueChanged<bool>? onChanged;

  /// In place of the icon tile: a picture (`avatar(…, 40)`) or a thumbnail.
  final Widget? leading;

  /// Before the sub line, on its baseline (the ticks in Message info).
  final Widget? subLeading;

  /// In place of the title text (a link set in mono).
  final Widget? titleWidget;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final ic = icon;
    final lead = leading;
    final subLead = subLeading;
    final (tileBg, tileInk) = danger
        ? (t.dangerSoft, t.danger)
        : iconColor == null
        ? (t.field, t.ink2)
        : OrbitAvatar.palette(t, iconColor!);
    final titleInk = danger
        ? t.danger
        : accent
        ? t.accentInk
        : t.ink;
    final change = onChanged;
    final tap = end == OrbitRowEnd.toggle && change != null
        ? () => change(!on)
        : onTap;
    final ends = <Widget>[
      if (value.isNotEmpty)
        OrbitText(
          value,
          style: t.font.style(size: OrbitType.small, color: t.ink3),
        ),
      ?trailing,
      if (end == OrbitRowEnd.chevron)
        OrbitIcon(OrbitIcons.caretRight, size: 18, color: t.ink4),
      if (end == OrbitRowEnd.toggle) OrbitSwitch(on: on),
    ];
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            if (lead != null) ...[
              lead,
              const SizedBox(width: 14),
            ] else if (ic != null) ...[
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tileBg,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: OrbitIcon(
                  ic,
                  weight: iconWeight,
                  size: 19,
                  color: tileInk,
                ),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleWidget ??
                      OrbitText(
                        title,
                        style: t.font.style(
                          size: OrbitType.body,
                          weight: 520,
                          color: titleInk,
                        ),
                      ),
                  if (sub.isNotEmpty && subLead != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          subLead,
                          const SizedBox(width: 4),
                          Expanded(
                            child: OrbitText(
                              sub,
                              style: t.font.style(
                                size: OrbitType.caption,
                                color: t.ink3,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (sub.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: OrbitText(
                        sub,
                        style: subMono
                            ? t.mono.style(
                                size: OrbitType.meta,
                                color: t.ink3,
                                height: 1.35,
                                letterSpacingEm: 0.02,
                              )
                            : t.font.style(
                                size: OrbitType.caption,
                                color: t.ink3,
                                height: 1.35,
                              ),
                      ),
                    ),
                ],
              ),
            ),
            if (ends.isNotEmpty) ...[
              const SizedBox(width: 14),
              for (final (i, e) in ends.indexed) ...[
                if (i > 0) const SizedBox(width: 6),
                e,
              ],
            ],
          ],
        ),
      ),
    );
    return Semantics(
      button: tap != null && end != OrbitRowEnd.toggle,
      toggled: end == OrbitRowEnd.toggle ? on : null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: tap,
          splashFactory: NoSplash.splashFactory,
          hoverColor: t.hover,
          highlightColor: Colors.transparent,
          child: row,
        ),
      ),
    );
  }
}

/// `.group-title.eyebrow` (`css/components.css`): a section's title, 22px
/// above, 8px below and 20px in, with the theme's `group` ornaments.
/// [danger] is `.dz-title`, in `--danger`.
class OrbitGroupTitle extends StatelessWidget {
  const OrbitGroupTitle(this.text, {super.key, this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OrbitSpace.gutter + 4,
        22,
        OrbitSpace.gutter + 4,
        8,
      ),
      child: OrbitEyebrow(
        text,
        ornament: 'group',
        color: danger ? t.danger : null,
      ),
    );
  }
}

/// `Kit.section(title, rows, footer)` (`js/kit.js`): a [OrbitGroupTitle], or
/// 14px of space when there is no title; the rows in an [OrbitCard]; then
/// the [footer] as an [OrbitSectionFoot].
class OrbitSection extends StatelessWidget {
  const OrbitSection({
    super.key,
    this.title = '',
    required this.rows,
    this.footer = '',
  });

  final String title;
  final List<Widget> rows;
  final String footer;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (title.isEmpty) const SizedBox(height: 14) else OrbitGroupTitle(title),
      OrbitCard(children: rows),
      if (footer.isNotEmpty) OrbitSectionFoot(footer),
    ],
  );
}

/// `Kit.danger(rows, footer)` (`js/kit.js`): "Danger zone" in `--danger`
/// over a danger-zone card, then the [footer].
class OrbitDangerZone extends StatelessWidget {
  const OrbitDangerZone({super.key, required this.rows, this.footer = ''});

  final List<Widget> rows;
  final String footer;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const OrbitGroupTitle('Danger zone', danger: true),
      OrbitCard(dangerZone: true, children: rows),
      if (footer.isNotEmpty) OrbitSectionFoot(footer),
    ],
  );
}
