import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// CSS `linear-gradient(<angle>deg, ...)`: the gradient line runs through the
/// box's centre at [angle] (0 is up, 90 is right), and is just long enough
/// that the corners on either side get the first and last colours.
///
/// Flutter's [LinearGradient] places its ends by alignment, so the same angle
/// lands differently on a wide box and a tall one; this works the ends out
/// from the box it paints, as CSS does.
class OrbitCssGradient extends LinearGradient {
  const OrbitCssGradient({
    required this.angle,
    required super.colors,
    super.stops,
  });

  /// Degrees, as CSS writes them.
  final double angle;

  @override
  ui.Shader createShader(Rect rect, {TextDirection? textDirection}) {
    final a = angle * math.pi / 180;
    final dx = math.sin(a);
    final dy = -math.cos(a);
    final half = ((rect.width * dx).abs() + (rect.height * dy).abs()) / 2;
    final from = rect.center - Offset(dx, dy) * half;
    final to = rect.center + Offset(dx, dy) * half;
    return ui.Gradient.linear(from, to, colors, stops);
  }

  @override
  bool operator ==(Object other) =>
      other is OrbitCssGradient && other.angle == angle && super == other;

  @override
  int get hashCode => Object.hash(angle, super.hashCode);
}
