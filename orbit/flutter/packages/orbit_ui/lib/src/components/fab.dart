import 'package:flutter/material.dart';

import 'package:orbit_ui/src/icons/orbit_glyph.dart';
import 'package:orbit_ui/src/theme/motion.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// `.fab` (`css/components.css`): the filled round action, 56px, accent, a
/// 24px icon in `--on-accent`, `--accent-ink` under the pointer, the theme's
/// `--glow` as its shadow (`css/pages.css` overrides the base shadow with it).
///
/// [gone] is `.gone`: it shrinks away and stops taking taps.
class OrbitFab extends StatelessWidget {
  const OrbitFab({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconWeight,
    this.gone = false,
    this.size = 56,
  });

  final OrbitGlyph icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final OrbitIconWeight? iconWeight;
  final bool gone;

  /// 56, or 62 in the dock.
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final fab = Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: t.glow),
          child: Material(
            color: t.accent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: gone ? null : onPressed,
              splashFactory: NoSplash.splashFactory,
              hoverColor: t.accentInk,
              highlightColor: Colors.transparent,
              child: Center(
                child: OrbitIcon(
                  icon,
                  weight: iconWeight,
                  size: 24,
                  color: t.onAccent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final motion = OrbitMotion.allowed(context)
        ? t.motion.short
        : Duration.zero;
    return IgnorePointer(
      ignoring: gone,
      child: AnimatedScale(
        scale: gone ? 0 : 1,
        duration: motion,
        curve: t.motion.curve,
        child: AnimatedOpacity(
          opacity: gone ? 0 : 1,
          duration: motion,
          curve: t.motion.curve,
          child: fab,
        ),
      ),
    );
  }
}
