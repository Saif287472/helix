import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/button.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/theme/effect_shapes.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// `.eyebrow` (`css/components.css`): mono at `--t-meta`, tracked 0.08em,
/// upper case, in `--ink-3`, or the colour the theme's `eyebrowColour` gives
/// (Arcade). [color] overrides both, as `.dz-title` does with `!important`.
class OrbitEyebrow extends StatelessWidget {
  const OrbitEyebrow(this.text, {super.key, this.color, this.ornament});

  final String text;
  final Color? color;

  /// The `ornament` target this eyebrow stands for (`group` for a section
  /// title), whose glyphs the theme puts around it.
  final String? ornament;

  static Color colourOf(OrbitTokens t) {
    final e = orbitEffectOn(t, 'eyebrowColour', '.eyebrow');
    final token = e?.param<String>('token');
    return token == null ? t.ink3 : t.value<Color>(token);
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final style = t.mono.style(
      size: OrbitType.meta,
      color: color ?? colourOf(t),
      letterSpacingEm: 0.08,
    );
    final marks = ornament == null
        ? (before: const <OrbitEffect>[], after: const <OrbitEffect>[])
        : orbitOrnaments(t, ornament!);
    // An ornament is `::before`/`::after` content, so it is upper-cased too.
    TextSpan mark(OrbitEffect e) {
      final span = orbitOrnamentSpan(t, e, style);
      return TextSpan(text: span.text!.toUpperCase(), style: span.style);
    }

    return OrbitText.rich(
      style: style,
      TextSpan(
        children: [
          ...marks.before.map(mark),
          TextSpan(text: text.toUpperCase()),
          ...marks.after.map(mark),
        ],
      ),
    );
  }
}

/// `.sec-foot` (`css/pages.css`): the note under a section, `--t-caption` in
/// `--ink-3` at line height 1.5, 8px below and 22px in.
class OrbitSectionFoot extends StatelessWidget {
  const OrbitSectionFoot(this.text, {super.key, this.top = 8});

  final String text;

  /// The top margin, which a few pages change inline.
  final double top;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        OrbitSpace.gutter + 6,
        top,
        OrbitSpace.gutter + 6,
        0,
      ),
      child: OrbitText(
        text,
        style: t.font.style(
          size: OrbitType.caption,
          color: t.ink3,
          height: 1.5,
        ),
      ),
    );
  }
}

enum OrbitNoticeKind { info, success, warning, error }

/// The tone colours of a notice or banner: its fill, edge and icon.
(Color, Color, Color) _tone(OrbitTokens t, OrbitNoticeKind kind) =>
    switch (kind) {
      OrbitNoticeKind.info => (t.accentSoft, t.accentLine, t.accent),
      OrbitNoticeKind.success => (t.successSoft, t.successLine, t.success),
      OrbitNoticeKind.warning => (t.warningSoft, t.warningLine, t.warning),
      OrbitNoticeKind.error => (t.dangerSoft, t.dangerLine, t.danger),
    };

/// A button inside a notice or banner: what [OrbitInlineNotice.action] and
/// [OrbitBanner.actions] take.
class OrbitNoticeAction {
  const OrbitNoticeAction(this.label, this.onPressed);

  final String label;
  final VoidCallback? onPressed;
}

/// `Kit.notice(kind, text, action)` (`.inotice` in `css/pages.css`): a
/// tinted box 12px below what is above it, inset by the gutter, 12px 14px
/// in, corner `--r-md`, a 1px edge; a filled 20px icon 12px before the text
/// at `--t-small`, line height 1.45. Its [action] is a 36px button 8px under
/// the text: `.danger` for an error, `.secondary` otherwise.
class OrbitInlineNotice extends StatelessWidget {
  const OrbitInlineNotice({
    super.key,
    required this.kind,
    required this.text,
    this.action,
  });

  final OrbitNoticeKind kind;
  final String text;
  final OrbitNoticeAction? action;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final (fill, edge, ink) = _tone(t, kind);
    final icon = switch (kind) {
      OrbitNoticeKind.info => OrbitIcons.info,
      OrbitNoticeKind.success => OrbitIcons.checkCircle,
      OrbitNoticeKind.error => OrbitIcons.warningCircle,
      OrbitNoticeKind.warning => OrbitIcons.warning,
    };
    final a = action;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        OrbitSpace.gutter,
        12,
        OrbitSpace.gutter,
        0,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: edge),
        borderRadius: BorderRadius.circular(t.rMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: OrbitIcon(
              icon,
              weight: OrbitIconWeight.fill,
              size: 20,
              color: ink,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OrbitText(
                  text,
                  style: t.font.style(
                    size: OrbitType.small,
                    color: t.ink,
                    height: 1.45,
                  ),
                ),
                if (a != null) ...[
                  const SizedBox(height: 8),
                  OrbitButton(
                    label: a.label,
                    onPressed: a.onPressed,
                    kind: kind == OrbitNoticeKind.error
                        ? OrbitButtonKind.danger
                        : OrbitButtonKind.secondary,
                    height: 36,
                    padding: 14,
                    fontSize: 13,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `.banner` (`css/components.css`): like a notice, but 8px above and below,
/// with a bold title line and ghost actions 36px tall, 6px apart, pulled 10px
/// left so their labels line up with the text. [kind] is `.accent`
/// ([OrbitNoticeKind.info]), `.warning` or `.danger` ([OrbitNoticeKind.error]).
class OrbitBanner extends StatelessWidget {
  const OrbitBanner({
    super.key,
    required this.kind,
    required this.icon,
    required this.title,
    required this.text,
    this.actions = const [],
    this.margin = const EdgeInsets.symmetric(
      horizontal: OrbitSpace.gutter,
      vertical: 8,
    ),
  });

  final OrbitNoticeKind kind;
  final OrbitGlyph icon;

  /// 8px above and below; a banner right under another has no top margin,
  /// because CSS collapses the two 8px margins into one.
  final EdgeInsets margin;
  final String title;
  final String text;
  final List<OrbitNoticeAction> actions;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final (fill, edge, ink) = _tone(t, kind);
    final body = t.font.style(
      size: OrbitType.small,
      color: t.ink,
      height: 1.45,
    );
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: edge),
        borderRadius: BorderRadius.circular(t.rMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: OrbitIcon(
              icon,
              weight: OrbitIconWeight.fill,
              size: 20,
              color: ink,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OrbitText(
                  title,
                  style: t.font.style(
                    size: OrbitType.small,
                    weight: 600,
                    color: t.ink,
                    height: 1.45,
                  ),
                ),
                OrbitText(text, style: body),
                if (actions.isNotEmpty)
                  Transform.translate(
                    offset: const Offset(-10, 0),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 6,
                        children: [
                          for (final a in actions)
                            OrbitButton(
                              label: a.label,
                              onPressed: a.onPressed,
                              kind: OrbitButtonKind.ghost,
                              height: 36,
                              padding: 12,
                              fontSize: 13,
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `Kit.intro(title, text)` (`.pintro` in `css/pages.css`): 16px 20px 4px
/// in; the title in the display face at 18px, 6px above the text at
/// `--t-small` in `--ink-3`, line height 1.55. Either may be empty.
class OrbitPageIntro extends StatelessWidget {
  const OrbitPageIntro({super.key, this.title = '', this.text = ''});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        OrbitSpace.gutter + 4,
        16,
        OrbitSpace.gutter + 4,
        4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: OrbitText(
                orbitTransform(title, t.displayTransform),
                style: t.display(size: 18),
              ),
            ),
          if (text.isNotEmpty)
            OrbitText(
              text,
              style: t.font.style(
                size: OrbitType.small,
                color: t.ink3,
                height: 1.55,
              ),
            ),
        ],
      ),
    );
  }
}

/// `UI.empty` (`.empty` in `css/components.css`): centred, 48px 32px in,
/// 10px between parts; an 84px tile (corner 28, `--surface`, a `--line`
/// edge, the icon at 36px in `--accent`) inside an 8px `--bg` ring and a 1px
/// `--line-2` ring, 6px more space under it; the title in the display face
/// at `--t-headline`; the text at `--t-small` in `--ink-3`, line height 1.5,
/// at most 280px wide; then the [action], which brings its own 8px.
class OrbitEmptyState extends StatelessWidget {
  const OrbitEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.text = '',
    this.action,
  });

  final OrbitGlyph icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final a = action;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.surface,
              border: Border.all(color: t.line),
              borderRadius: BorderRadius.circular(28),
              // CSS lists the top shadow first; Flutter paints in order.
              boxShadow: [
                BoxShadow(color: t.line2, spreadRadius: 9),
                BoxShadow(color: t.bg, spreadRadius: 8),
              ],
            ),
            child: OrbitIcon(icon, size: 36, color: t.accent),
          ),
          const SizedBox(height: 16),
          OrbitText(
            orbitTransform(title, t.displayTransform),
            textAlign: TextAlign.center,
            style: t.display(size: OrbitType.headline),
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: OrbitText(
                text,
                textAlign: TextAlign.center,
                style: t.font.style(
                  size: OrbitType.small,
                  color: t.ink3,
                  height: 1.5,
                ),
              ),
            ),
          ],
          if (a != null) ...[const SizedBox(height: 10 + 8), a],
        ],
      ),
    );
  }
}
