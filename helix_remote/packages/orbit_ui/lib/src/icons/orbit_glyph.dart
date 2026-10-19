import 'package:flutter/material.dart';

import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// A Phosphor weight. The prototype writes it as `ph`, `ph-light`, `ph-bold`,
/// `ph-fill` or `ph-duotone`.
enum OrbitIconWeight { regular, light, bold, fill, duotone }

/// One icon at every weight, so the theme can choose at draw time.
///
/// All five are constants, so release builds still tree-shake the icon fonts.
final class OrbitGlyph {
  const OrbitGlyph(
    this.name, {
    required this.regular,
    required this.light,
    required this.bold,
    required this.fill,
    required this.duotone,
    required this.duotoneBack,
  });

  /// The prototype's name, `ph-<name>`.
  final String name;
  final IconData regular;
  final IconData light;
  final IconData bold;
  final IconData fill;

  /// Duotone's front layer; [duotoneBack] is drawn under it at 20%.
  final IconData duotone;
  final IconData duotoneBack;

  IconData at(OrbitIconWeight weight) => switch (weight) {
    OrbitIconWeight.regular => regular,
    OrbitIconWeight.light => light,
    OrbitIconWeight.bold => bold,
    OrbitIconWeight.fill => fill,
    OrbitIconWeight.duotone => duotone,
  };
}

/// An icon, drawn the way the prototype's `UI.icon(name, weight)` does: at
/// [weight] when the call site names one, otherwise at the theme's weight
/// (regular for Orbit and Night, light for Bloom, Papyrus and Terminal, bold
/// for Arcade and Field, duotone for Mochi).
///
/// Size and colour come from the surrounding [IconTheme] unless given, as the
/// prototype's `<i>` takes its parent's `font-size` and `color`.
class OrbitIcon extends StatelessWidget {
  const OrbitIcon(this.glyph, {super.key, this.weight, this.size, this.color});

  final OrbitGlyph glyph;
  final OrbitIconWeight? weight;
  final double? size;
  final Color? color;

  /// The theme's default weight.
  static OrbitIconWeight themeWeight(BuildContext context) {
    final w = Theme.of(context).extension<OrbitTokens>()?.meta.icon ?? '';
    return OrbitIconWeight.values.firstWhere(
      (v) => v.name == w,
      orElse: () => OrbitIconWeight.regular,
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = weight ?? themeWeight(context);
    final icon = Icon(glyph.at(w), size: size, color: color);
    if (w != OrbitIconWeight.duotone) return icon;
    // Phosphor's duotone: the back layer at 20% under the outline.
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: 0.2,
          child: Icon(glyph.duotoneBack, size: size, color: color),
        ),
        icon,
      ],
    );
  }
}
