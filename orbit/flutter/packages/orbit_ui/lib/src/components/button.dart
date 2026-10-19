import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/spinner.dart';
import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/theme/effect_shapes.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

enum OrbitButtonKind { primary, ink, secondary, ghost, danger }

/// `.btn` (`css/components.css`): a 48px pill, 20px each side, a 1px edge,
/// the label at `--t-small` and weight 560 in the body face, an 18px icon 8px
/// before it.
///
/// - [kind]: `.primary` (accent, with the theme's `--glow`), `.ink`,
///   `.secondary` (surface with a `--line` edge), `.ghost`, `.danger`.
/// - [block]: `.block`, the full width.
/// - [busy]: the prototype's busy button keeps its label and shows the
///   spinner in the icon's place (`devices_backup.js`, `groups.js`); taps are
///   ignored while it is busy.
/// - No [onPressed] is `:disabled`: 45% opacity and no glow.
class OrbitButton extends StatelessWidget {
  const OrbitButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = OrbitButtonKind.primary,
    this.icon,
    this.iconWeight,
    this.busy = false,
    this.block = false,
    this.height = OrbitSpace.target,
    this.padding = 20,
    this.fontSize = OrbitType.small,
    this.tint,
  });

  final String label;
  final VoidCallback? onPressed;
  final OrbitButtonKind kind;
  final OrbitGlyph? icon;
  final OrbitIconWeight? iconWeight;
  final bool busy;
  final bool block;

  /// The smaller buttons in notices and banners (`height: 36px; padding: 0
  /// 14px; font-size: 13px`) set these; they still take taps across 48px.
  final double height;
  final double padding;
  final double fontSize;

  /// The label's colour in place of the kind's (Revoke's `--danger` ghost).
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final disabled = onPressed == null;
    final (bg, kindFg, edge) = switch (kind) {
      OrbitButtonKind.primary => (t.accent, t.onAccent, Colors.transparent),
      OrbitButtonKind.ink => (t.inverse, t.onInverse, Colors.transparent),
      OrbitButtonKind.secondary => (t.surface, t.ink, t.line),
      OrbitButtonKind.ghost => (
        Colors.transparent,
        t.accentInk,
        Colors.transparent,
      ),
      OrbitButtonKind.danger => (t.dangerSoft, t.danger, Colors.transparent),
    };
    final fg = tint ?? kindFg;
    final hover = switch (kind) {
      OrbitButtonKind.primary => t.accentInk,
      OrbitButtonKind.ghost => t.accentSoft,
      _ => null,
    };
    // Arcade's cornerClip: square corners, a 10px notch, and no glow.
    final notch = kind == OrbitButtonKind.primary
        ? orbitEffectOn(t, 'cornerClip', '.btn.primary')
        : null;
    final radius = BorderRadius.circular(notch == null ? t.rPill : 0);
    final lead = busy
        ? OrbitSpinner(size: 18, color: fg)
        : icon == null
        ? null
        : OrbitIcon(icon!, weight: iconWeight, size: 18, color: fg);

    // CSS's border-box: the 1px edge is inside the 48px, and the fill runs
    // under it; the label starts 21px in (the edge, then 20px).
    Widget button = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: kind == OrbitButtonKind.primary && !disabled && notch == null
            ? t.glow
            : null,
      ),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: edge),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onPressed,
          splashFactory: NoSplash.splashFactory,
          // The highlight paints under the label, so an opaque colour reads as
          // the prototype's background change on hover.
          hoverColor: hover ?? Colors.transparent,
          highlightColor: Colors.transparent,
          child: SizedBox(
            height: height,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: padding + 1),
              child: Row(
                mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (lead != null) ...[lead, const SizedBox(width: 8)],
                  // A label too wide for its button wraps and stays centred,
                  // as the prototype's does (Terminal's "Error toast").
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: t.font.style(
                        size: fontSize,
                        weight: 560,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (notch != null) {
      button = ClipPath(
        clipper: OrbitNotchClipper(
          (notch.param<num>('notch') ?? 10).toDouble(),
        ),
        child: button,
      );
    }
    if (disabled) button = Opacity(opacity: 0.45, child: button);
    final semantic = Semantics(
      button: true,
      enabled: !disabled,
      label: busy ? '$label, busy' : null,
      child: button,
    );
    return height < OrbitSpace.target
        ? OrbitTapArea(child: semantic)
        : semantic;
  }
}
