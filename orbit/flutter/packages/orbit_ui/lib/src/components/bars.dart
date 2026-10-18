import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/avatar.dart';
import 'package:orbit_ui/src/components/fab.dart';
import 'package:orbit_ui/src/components/icon_button.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/icons/orbit_icons.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/theme/effect_shapes.dart';
import 'package:orbit_ui/src/theme/motion.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// What leads an [OrbitAppBar].
enum OrbitAppBarLead {
  /// An 8px space (`back: false`).
  none,

  /// ← Back.
  back,

  /// × Close.
  close,
}

/// `UI.appbar` (`.appbar` in `css/components.css`): at least 60px, 4px 6px
/// in, its parts 2px apart, on `--surface` with a 1px `--line-2` rule under
/// it. The title is in the display face at `--t-title`, 6px in, cut with an
/// ellipsis.
///
/// - [flat]: `.flat`, no fill and no rule (the You-style pages).
/// - [selection]: `.selection`, `--inverse` with its icons and title in
///   `--on-inverse`, the title at 17px.
/// - [background] and [rule]: the inline styles some pages set (a search bar
///   is `--bg` with no rule).
class OrbitAppBar extends StatelessWidget {
  const OrbitAppBar({
    super.key,
    this.title = '',
    this.titleWidget,
    this.lead = OrbitAppBarLead.back,
    this.leadTooltip,
    this.onLead,
    this.actions = const [],
    this.flat = false,
    this.selection = false,
    this.background,
    this.rule = true,
  });

  final String title;

  /// Replaces the title (a search field).
  final Widget? titleWidget;
  final OrbitAppBarLead lead;

  /// The lead button's tooltip when it is not "Back" or "Close" ("Close
  /// search", "Cancel selection").
  final String? leadTooltip;
  final VoidCallback? onLead;
  final List<Widget> actions;
  final bool flat;
  final bool selection;
  final Color? background;
  final bool rule;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final fill =
        background ??
        (selection
            ? t.inverse
            : flat
            ? Colors.transparent
            : t.surface);
    final ruleColour = !rule || flat
        ? Colors.transparent
        : selection
        ? t.inverse
        : t.line2;
    final ink = selection ? t.onInverse : null;
    final leadButton = switch (lead) {
      OrbitAppBarLead.none => const SizedBox(width: 8),
      OrbitAppBarLead.back => OrbitIconButton(
        icon: OrbitIcons.arrowLeft,
        tooltip: leadTooltip ?? 'Back',
        onPressed: onLead,
        color: ink,
      ),
      OrbitAppBarLead.close => OrbitIconButton(
        icon: OrbitIcons.x,
        tooltip: leadTooltip ?? 'Close',
        onPressed: onLead,
        color: ink,
      ),
    };
    final heading = titleWidget;
    final children = <Widget>[
      leadButton,
      Expanded(
        child:
            heading ??
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Semantics(
                header: true,
                child: Text(
                  orbitTransform(title, t.displayTransform),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.display(
                    size: selection ? 17 : OrbitType.title,
                    color: selection ? t.onInverse : t.ink,
                  ),
                ),
              ),
            ),
      ),
      ...actions,
    ];
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: fill,
        border: Border(bottom: BorderSide(color: ruleColour)),
      ),
      child: IconTheme.merge(
        data: IconThemeData(color: ink),
        child: Row(
          children: [
            for (final (i, c) in children.indexed) ...[
              if (i > 0) const SizedBox(width: 2),
              c,
            ],
          ],
        ),
      ),
    );
  }
}

/// The search field in a search bar (`.search` in `css/components.css`, as
/// Home writes it inside an [OrbitAppBar]): 46px, corner `--r-md`,
/// `--field` with a clear 1px edge, 14px in on the left and 6px on the right,
/// a 19px search icon in `--ink-3` 10px before the text at `--t-body`, and
/// a small × button once there is text. Focused, it is `--surface` with an
/// `--accent-line` edge. 8px of space after it.
class OrbitSearchField extends StatefulWidget {
  const OrbitSearchField({
    super.key,
    required this.hint,
    this.controller,
    this.initialValue = '',
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  final String hint;
  final TextEditingController? controller;
  final String initialValue;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  State<OrbitSearchField> createState() => _OrbitSearchFieldState();
}

class _OrbitSearchFieldState extends State<OrbitSearchField> {
  late final TextEditingController _own = TextEditingController(
    text: widget.initialValue,
  );
  final _focus = FocusNode();

  TextEditingController get _controller => widget.controller ?? _own;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
    _controller.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _own.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final focused = _focus.hasFocus;
    final text = t.font.style(size: OrbitType.body, color: t.ink);
    return Container(
      height: 46,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        color: focused ? t.surface : t.field,
        border: Border.all(color: focused ? t.accentLine : Colors.transparent),
        borderRadius: BorderRadius.circular(t.rMd),
      ),
      child: Row(
        children: [
          OrbitIcon(OrbitIcons.magnifyingGlass, size: 19, color: t.ink3),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              autofocus: widget.autofocus,
              textInputAction: TextInputAction.search,
              onChanged: widget.onChanged,
              onSubmitted: widget.onSubmitted,
              style: text,
              cursorColor: t.accent,
              cursorHeight: OrbitType.body * 1.2,
              decoration: const InputDecoration.collapsed(hintText: null)
                  .copyWith(
                    isDense: true,
                    hint: Text(
                      widget.hint,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: text.copyWith(color: t.ink4),
                    ),
                  ),
            ),
          ),
          if (_controller.text.isNotEmpty) ...[
            const SizedBox(width: 10),
            // A 48px button in a 44px row: it hangs over the edge, as the
            // prototype's does.
            SizedBox(
              width: OrbitSpace.target,
              height: 44,
              child: OverflowBox(
                maxHeight: OrbitSpace.target,
                child: OrbitIconButton(
                  icon: OrbitIcons.x,
                  tooltip: 'Clear search',
                  small: true,
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged?.call('');
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `.wordmark` (`css/components.css`, `css/pages.css`): "Orbit" at 32px in
/// the display face, line height 1.1, 2px 2px 4px 0 in, filled with
/// `--wordmark-gradient`, tracked by `--wordmark-tracking`.
///
/// The theme's effects: `wordmarkItalic` (Bloom), `wordmarkGlow` (a drop
/// shadow: Arcade, Terminal), `cursor` (a blinking `_` after it: Terminal)
/// and a `wordmark` ornament (Mochi's heart). The cursor holds still under
/// reduce motion.
class OrbitWordmark extends StatefulWidget {
  const OrbitWordmark({super.key, this.size = 32});

  final double size;

  @override
  State<OrbitWordmark> createState() => _OrbitWordmarkState();
}

class _OrbitWordmarkState extends State<OrbitWordmark>
    with SingleTickerProviderStateMixin {
  late final _blink = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final t = OrbitTokens.of(context);
    final run = t.meta.has('cursor') && OrbitMotion.allowed(context);
    if (run && !_blink.isAnimating) _blink.repeat();
    if (!run && _blink.isAnimating) _blink.reset();
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final base = t.fontDisplay
        .style(
          size: widget.size,
          weight: t.displayWeight,
          letterSpacingEm: t.wordmarkTracking,
          height: 1.1,
        )
        .copyWith(
          fontStyle: t.meta.has('wordmarkItalic') ? FontStyle.italic : null,
        );
    final word = orbitTransform('Orbit', t.displayTransform);
    final marks = orbitOrnaments(t, 'wordmark');
    final cursor = t.meta.effect('cursor');
    const clear = Color(0x00000000);

    // The word and its after-content. A part with its own fill
    // (`-webkit-text-fill-color`) is drawn by the [own] layer; the rest by
    // the gradient layer. [glow] draws everything in one colour.
    List<InlineSpan> spans({
      required bool gradient,
      Color? glow,
      double cursorOpacity = 1,
    }) {
      Color pick(Color? fill) =>
          glow ?? (gradient ? (fill == null ? t.ink : clear) : fill ?? clear);
      final out = <InlineSpan>[
        TextSpan(
          text: word,
          style: base.copyWith(color: pick(null)),
        ),
      ];
      for (final e in marks.after) {
        final s = orbitOrnamentSpan(t, e, base);
        final fill = e.params['colour'] == null ? null : s.style!.color;
        out.add(
          TextSpan(
            text: s.text,
            style: s.style!.copyWith(color: pick(fill)),
          ),
        );
      }
      if (cursor != null) {
        final c = pick(orbitEffectColour(t, cursor.params['colour']));
        out.add(
          TextSpan(
            text: cursor.param<String>('glyph') ?? '_',
            style: base.copyWith(
              color: c.withValues(alpha: c.a * cursorOpacity),
            ),
          ),
        );
      }
      return out;
    }

    final glow = t.meta.effect('wordmarkGlow');
    return AnimatedBuilder(
      animation: _blink,
      builder: (context, _) {
        // `@keyframes blink { 50% { opacity: 0.25 } }`, each half eased.
        final v = _blink.isAnimating ? _blink.value : 0.0;
        final cursorOpacity = v < 0.5
            ? 1 - 0.75 * Curves.ease.transform(v * 2)
            : 0.25 + 0.75 * Curves.ease.transform((v - 0.5) * 2);
        Widget layer(List<InlineSpan> s) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 2, 2, 4),
          child: Text.rich(TextSpan(children: s), maxLines: 1, softWrap: false),
        );
        final gradient = ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (rect) => t.wordmarkGradient.createShader(rect),
          child: layer(spans(gradient: true)),
        );
        final own = layer(spans(gradient: false, cursorOpacity: cursorOpacity));
        final children = <Widget>[];
        if (glow != null) {
          final colour = orbitEffectColour(t, glow.params['colour']);
          final blur = (glow.param<num>('blur') ?? 0).toDouble();
          children.add(
            Transform.translate(
              offset: Offset(
                (glow.param<num>('dx') ?? 0).toDouble(),
                (glow.param<num>('dy') ?? 0).toDouble(),
              ),
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: blur / 2,
                  sigmaY: blur / 2,
                  tileMode: TileMode.decal,
                ),
                child: layer(
                  spans(
                    gradient: false,
                    glow: colour,
                    cursorOpacity: cursorOpacity,
                  ),
                ),
              ),
            ),
          );
        }
        children
          ..add(gradient)
          ..add(own);
        return Semantics(
          header: true,
          label: 'Orbit',
          child: ExcludeSemantics(child: Stack(children: children)),
        );
      },
    );
  }
}

/// `.me-pic` (`css/components.css`): your picture at the top right of a
/// tab, 48px with a 44px ring in `--wordmark-gradient` around a round 36px
/// avatar with a 2px `--bg` gap; [attention] adds a 12px `--warning` dot at
/// the top right. Opens Settings.
class OrbitMePicture extends StatelessWidget {
  const OrbitMePicture({
    super.key,
    required this.avatar,
    required this.onPressed,
    this.attention = false,
  });

  final HelixAvatarModel avatar;
  final VoidCallback? onPressed;
  final bool attention;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final label = attention
        ? 'Your profile and settings, privacy checkup needs attention'
        : 'Your profile and settings';
    return Tooltip(
      message: 'Your profile and settings',
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox.square(
            dimension: OrbitSpace.target,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: t.wordmarkGradient,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: t.bg, spreadRadius: 2)],
                    ),
                    child: OrbitAvatar(avatar: avatar, size: 36, round: true),
                  ),
                ),
                if (attention)
                  Positioned(
                    top: 3,
                    right: 3,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: t.warning,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: t.bg, spreadRadius: 2)],
                      ),
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

/// `.tab-head` (`css/components.css`): the top of a Home tab, 10px 16px 6px
/// in: the [OrbitWordmark] on the left and the [actions] on the right, in a
/// row at least 48px tall.
class OrbitTabHeader extends StatelessWidget {
  const OrbitTabHeader({super.key, required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      OrbitSpace.gutter,
      10,
      OrbitSpace.gutter,
      6,
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: OrbitSpace.target),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const OrbitWordmark(),
          Row(mainAxisSize: MainAxisSize.min, children: actions),
        ],
      ),
    ),
  );
}

/// One tab of an [OrbitDock].
class OrbitDockItem {
  const OrbitDockItem({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final OrbitGlyph icon;
  final String label;
  final bool on;
  final VoidCallback? onTap;
}

/// `.dock` and `.dock-item` (`css/components.css`): a 62px pill 6px in, on
/// `--dock-bg` with a 1px `--line` edge (the theme's `dockBorder`: Mochi's
/// 2px pink) and `--shadow-float`, its tabs 4px apart. A tab is 50px tall,
/// at least 56 wide, 16px in, its 23px icon in `--ink-3`; the open tab is
/// `--inverse` with `--glow`, its icon filled and its label shown at
/// `--t-small` weight 600, 8px after the icon, 18px in on the right.
class OrbitDock extends StatelessWidget {
  const OrbitDock({super.key, required this.items});

  final List<OrbitDockItem> items;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final border = t.meta.effect('dockBorder');
    final edgeWidth = (border?.param<num>('width') ?? 1).toDouble();
    final edge = border == null
        ? t.line
        : orbitEffectColour(t, border.params['colour']);
    return Semantics(
      container: true,
      label: 'Main',
      // The pill is drawn behind the tabs rather than around them: its
      // content box is shorter than a 50px tab, which the prototype lets
      // overflow evenly above and below.
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.dockBg,
                border: Border.all(color: edge, width: edgeWidth),
                borderRadius: BorderRadius.circular(t.rPill),
                boxShadow: t.shadowFloat,
              ),
            ),
          ),
          SizedBox(
            height: 62,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 6 + edgeWidth),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (i, item) in items.indexed) ...[
                    if (i > 0) const SizedBox(width: 4),
                    _tab(t, item),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tab(OrbitTokens t, OrbitDockItem item) {
    final ink = item.on ? t.onInverse : t.ink3;
    return Tooltip(
      message: item.label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        selected: item.on,
        label: item.label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: item.onTap,
          child: Container(
            height: 50,
            constraints: const BoxConstraints(minWidth: 56),
            padding: EdgeInsets.only(left: 16, right: item.on ? 18 : 16),
            decoration: BoxDecoration(
              color: item.on ? t.inverse : null,
              borderRadius: BorderRadius.circular(t.rPill),
              boxShadow: item.on ? t.glow : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OrbitIcon(
                  item.icon,
                  weight: item.on ? OrbitIconWeight.fill : null,
                  size: 23,
                  color: ink,
                ),
                if (item.on) ...[
                  const SizedBox(width: 8),
                  Text(
                    item.label,
                    style: t.font.style(
                      size: OrbitType.small,
                      weight: 600,
                      color: ink,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.dock-area` (`css/components.css`): the 120px band at the bottom of Home,
/// fading from `--bg` (solid for its lowest 30%) to clear, with the [dock]
/// and the 62px round [fab] 12px apart, centred, 22px up from the bottom.
class OrbitDockArea extends StatelessWidget {
  const OrbitDockArea({super.key, required this.dock, required this.fab});

  final OrbitDock dock;
  final OrbitFab fab;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return Container(
      height: 120,
      padding: const EdgeInsets.fromLTRB(
        OrbitSpace.gutter,
        0,
        OrbitSpace.gutter,
        22,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          // CSS fades through clear in premultiplied colour: the page colour
          // at zero alpha, not black.
          colors: [t.bg, t.bg, t.bg.withValues(alpha: 0)],
          stops: const [0, 0.3, 1],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [dock, const SizedBox(width: 12), fab],
      ),
    );
  }
}
