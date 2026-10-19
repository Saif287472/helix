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

/// A colour as the theme table writes an effect's: a literal hex with an
/// optional alpha, or the name of a token.
Color orbitEffectColour(OrbitTokens t, Object? spec) {
  if (spec is Map) {
    if (spec['kind'] == 'token' && spec['name'] is String) {
      return t.value<Color>(spec['name']! as String);
    }
    final hex = spec['colour'];
    if (hex is String) {
      final rgb = int.parse(hex.replaceFirst('#', ''), radix: 16);
      final alpha = spec['alpha'];
      return Color.fromARGB(
        alpha is num ? (alpha * 255).round() : 255,
        (rgb >> 16) & 0xff,
        (rgb >> 8) & 0xff,
        rgb & 0xff,
      );
    }
  }
  throw FormatException('not an effect colour', '$spec');
}

/// The `ornament` effects a theme puts on [target] (`day`, `group`,
/// `wordmark`): glyphs before and after the text.
({List<OrbitEffect> before, List<OrbitEffect> after}) orbitOrnaments(
  OrbitTokens t,
  String target,
) {
  final before = <OrbitEffect>[];
  final after = <OrbitEffect>[];
  for (final e in t.meta.effects) {
    if (e.kind != 'ornament' || e.param<String>('target') != target) continue;
    (e.param<String>('pseudo') == 'after' ? after : before).add(e);
  }
  return (before: before, after: after);
}

/// An ornament as a span in [base]'s style, in its own colour and size
/// (`0.62em`) when it gives them.
TextSpan orbitOrnamentSpan(OrbitTokens t, OrbitEffect e, TextStyle base) {
  final size = e.param<String>('size');
  final em = size != null && size.endsWith('em')
      ? double.parse(size.substring(0, size.length - 2))
      : 1.0;
  final colour = e.params['colour'];
  return TextSpan(
    text: e.param<String>('glyph') ?? '',
    style: base.copyWith(
      fontSize: (base.fontSize ?? OrbitTextDefaults.size) * em,
      color: colour == null ? null : orbitEffectColour(t, colour),
    ),
  );
}

/// The size a span falls back to when its style names none.
abstract final class OrbitTextDefaults {
  static const double size = 15;
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

/// Shadows drawn the way CSS draws a `box-shadow`: only outside the box, so
/// a see-through fill (the call tray's glass) never shows its own shadow
/// through it. Put it behind the box with `CustomPaint(painter: ...)`.
class OrbitOuterShadow extends CustomPainter {
  const OrbitOuterShadow({required this.radius, required this.shadows});

  final BorderRadius radius;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final box = radius.toRRect(Offset.zero & size);
    canvas
      ..save()
      ..clipPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect((Offset.zero & size).inflate(128)),
          Path()..addRRect(box),
        ),
      );
    for (final s in shadows) {
      canvas.drawRRect(
        box.shift(s.offset).inflate(s.spreadRadius),
        s.toPaint(),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(OrbitOuterShadow old) =>
      old.radius != radius || old.shadows != shadows;
}
