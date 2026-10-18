import 'package:flutter/material.dart';

import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

enum OrbitIconButtonTone { normal, accent, danger }

/// `.ibtn` (`css/components.css`; `UI.ibtn` in `js/ui.js`): a round 48px
/// target with a 22px icon (20px when [small]) in `--ink-2`, `--accent` or
/// `--danger`, `--pressed` under the pointer and `--line` while pressed.
///
/// [tooltip] is required: it is the prototype's `title` and `aria-label`.
class OrbitIconButton extends StatelessWidget {
  const OrbitIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.tone = OrbitIconButtonTone.normal,
    this.small = false,
    this.weight,
    this.color,
  });

  final OrbitGlyph icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final OrbitIconButtonTone tone;
  final bool small;

  /// The icon's weight when the call site names one; otherwise the theme's.
  final OrbitIconWeight? weight;

  /// Overrides the tone's colour (an app bar in selection mode).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final ink =
        color ??
        switch (tone) {
          OrbitIconButtonTone.normal => t.ink2,
          OrbitIconButtonTone.accent => t.accent,
          OrbitIconButtonTone.danger => t.danger,
        };
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: tooltip,
        child: SizedBox.square(
          dimension: OrbitSpace.target,
          child: Material(
            type: MaterialType.transparency,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(t.rPill),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              splashFactory: NoSplash.splashFactory,
              hoverColor: t.pressed,
              highlightColor: t.line,
              focusColor: t.pressed,
              child: Center(
                child: OrbitIcon(
                  icon,
                  weight: weight,
                  size: small ? 20 : 22,
                  color: ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
