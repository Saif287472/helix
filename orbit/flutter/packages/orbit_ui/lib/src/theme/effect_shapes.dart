import 'package:flutter/widgets.dart';

import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// Whether the theme switches [kind] on for [target], one of the prototype's
/// CSS selectors the effect lists (`.btn.primary`, `.xfab`, `.card`, ...).
///
/// The selectors stay as the theme table writes them, because a theme pack
/// carries the same data; each component asks for the selector it stands for.
OrbitEffect? orbitEffectOn(OrbitTokens t, String kind, String target) {
  final effect = t.meta.effect(kind);
  if (effect == null) return null;
  final targets = effect.param<List<Object?>>('targets');
  if (targets != null && !targets.contains(target)) return null;
  return effect;
}

/// `cornerClip` (Arcade): `clip-path: polygon(n 0, 100% 0, 100% calc(100% -
/// n), calc(100% - n) 100%, 0 100%, 0 n)`, the top-left and bottom-right
/// corners cut off at 45 degrees. A clip also removes the shadow outside it,
/// which is why the effect says `box-shadow: none`.
class OrbitNotchClipper extends CustomClipper<Path> {
  const OrbitNotchClipper(this.notch);

  final double notch;

  @override
  Path getClip(Size size) => Path()
    ..moveTo(notch, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height - notch)
    ..lineTo(size.width - notch, size.height)
    ..lineTo(0, size.height)
    ..lineTo(0, notch)
    ..close();

  @override
  bool shouldReclip(OrbitNotchClipper oldClipper) => oldClipper.notch != notch;
}
