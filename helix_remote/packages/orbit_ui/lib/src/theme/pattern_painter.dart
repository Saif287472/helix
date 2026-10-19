import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'package:orbit_ui/src/theme/svg_path.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';
import 'package:orbit_ui/src/theme/turbulence.dart';

/// A chat pattern (`--chat-pattern` in `css/themes.css`) drawn behind
/// [child] on [color], from the top-left corner of the box as CSS's
/// `background-position: 0 0` does.
///
/// The pattern types ship in the app; a theme picks one by name and gives its
/// settings (`tools/themes.py`):
/// - `grain` (Bloom, Papyrus): SVG fractal noise, a 160px tile;
/// - `hearts` (Mochi): a heart, a sparkle and a dot on a 64px tile;
/// - `neonGrid` (Arcade): 1px lines along the top and left of each tile;
/// - `scanlines` (Terminal): a 1px line every 3px, counted from the bottom;
/// - `contours` (Field): five contour lines on a 220px tile.
class OrbitPatternBackground extends StatelessWidget {
  const OrbitPatternBackground({
    super.key,
    required this.pattern,
    required this.color,
    this.child,
  });

  final OrbitPattern pattern;
  final Color color;
  final Widget? child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _PatternPainter(pattern, color),
    child: child ?? const SizedBox.expand(),
  );
}

/// The page background: `--bg`, with the chat pattern behind every page in a
/// theme that switches on `pagePattern` (Papyrus).
class OrbitPageBackground extends StatelessWidget {
  const OrbitPageBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    if (t.meta.effect('pagePattern') == null) {
      return ColoredBox(color: t.bg, child: child);
    }
    return OrbitPatternBackground(
      pattern: t.chatPattern,
      color: t.bg,
      child: child,
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter(this.pattern, this.color);

  final OrbitPattern pattern;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    canvas.drawRect(box, Paint()..color = color);
    switch (pattern.kind) {
      case 'none':
        return;
      case 'scanlines':
        _scanlines(canvas, size);
      default:
        final tile = _Tiles.of(pattern);
        if (tile == null) return;
        canvas.drawRect(
          box,
          Paint()
            ..shader = ui.ImageShader(
              tile,
              TileMode.repeated,
              TileMode.repeated,
              Matrix4.identity().storage,
              filterQuality: FilterQuality.none,
            ),
        );
    }
  }

  /// `repeating-linear-gradient(0deg, c 0 1px, transparent 1px 3px)`: the
  /// gradient runs from the bottom edge up, so the lines are counted from it.
  void _scanlines(Canvas canvas, Size size) {
    final period = (pattern.param<num>('period') ?? 3).toDouble();
    final thick = (pattern.param<num>('thickness') ?? 1).toDouble();
    final paint = Paint()
      ..color = _hex(
        pattern.param<String>('colour')!,
        pattern.param<num>('a')!.toDouble(),
      );
    for (var y = size.height - thick; y > -thick; y -= period) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, thick), paint);
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) =>
      old.pattern != pattern || old.color != color;
}

Color _hex(String hex, double alpha) {
  final v = int.parse(hex.replaceFirst('#', ''), radix: 16);
  return Color.fromARGB(
    (alpha * 255).round(),
    (v >> 16) & 0xff,
    (v >> 8) & 0xff,
    v & 0xff,
  );
}

/// One drawn tile per pattern setting, made once.
abstract final class _Tiles {
  static final _cache = <String, ui.Image>{};

  static ui.Image? of(OrbitPattern p) {
    final key = '${p.kind}${p.params}';
    final hit = _cache[key];
    if (hit != null) return hit;
    final made = switch (p.kind) {
      'grain' => _grain(p),
      'hearts' => _picture(64, 64, _hearts),
      'neonGrid' => _neonGrid(p),
      'contours' => _contours(p),
      _ => null,
    };
    if (made != null) _cache[key] = made;
    return made;
  }

  static ui.Image _picture(int w, int h, void Function(Canvas) draw) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    );
    draw(canvas);
    return recorder.endRecording().toImageSync(w, h);
  }

  /// `linear-gradient(h 1px, transparent 1px), linear-gradient(90deg, v 1px,
  /// transparent 1px)` on a tile: the first layer is on top.
  static ui.Image _neonGrid(OrbitPattern p) {
    final size = p.size;
    final w = size.width!.round(), h = size.height!.round();
    return _picture(w, h, (c) {
      c.drawRect(
        Rect.fromLTWH(0, 0, 1, h.toDouble()),
        Paint()
          ..color = _hex(p.param<String>('v')!, p.param<num>('va')!.toDouble()),
      );
      c.drawRect(
        Rect.fromLTWH(0, 0, w.toDouble(), 1),
        Paint()
          ..color = _hex(p.param<String>('h')!, p.param<num>('ha')!.toDouble()),
      );
    });
  }

  /// Mochi's tile, the prototype's SVG shapes and colours.
  static void _hearts(Canvas c) {
    c.drawPath(
      orbitSvgPath('M16 20c-2-3-7-2-7 2 0 3 4 5 7 8 3-3 7-5 7-8 0-4-5-5-7-2z'),
      Paint()..color = _hex('#FFB3D1', 0.4),
    );
    c.drawPath(
      orbitSvgPath(
        'M46 40l1.6 3.4 3.4 1.6-3.4 1.6L46 50l-1.6-3.4L41 45l3.4-1.6z',
      ),
      Paint()..color = _hex('#B9A2FF', 0.45),
    );
    c.drawCircle(
      const Offset(50, 14),
      1.6,
      Paint()..color = _hex('#7FD0F5', 0.5),
    );
  }

  /// Field's tile: five strokes, from the prototype's SVG.
  static ui.Image _contours(OrbitPattern p) {
    final size = p.size;
    final w = size.width!.round(), h = size.height!.round();
    const lines = [
      'M-10 110c25-45 65-55 100-32s70 12 80-22 40-30 60-10',
      'M-10 150c35-32 78-38 112-16s62 6 88-26 30-22 40-14',
      'M-10 70c28-28 60-33 88-12s56 2 78-32 40-20 70-8',
      'M-10 195c38-22 82-28 115-6s66 10 104-16',
      'M-10 30c30-20 66-24 96-4s60 0 80-26',
    ];
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = p.param<num>('width')!.toDouble()
      ..color = _hex(p.param<String>('stroke')!, 1);
    return _picture(w, h, (c) {
      for (final d in lines) {
        c.drawPath(orbitSvgPath(d), paint);
      }
    });
  }

  /// The SVG `feTurbulence` grain: fractal noise's alpha channel scaled by
  /// `a`, in the colour (`r`, `g`, `b`) the colour matrix gives. SVG filters
  /// work in linear light, so that colour is converted to sRGB.
  static ui.Image _grain(OrbitPattern p) {
    final size = p.size;
    final w = size.width!.round(), h = size.height!.round();
    final noise = OrbitTurbulence();
    double srgb(double c) =>
        c <= 0.0031308 ? 12.92 * c : 1.055 * math.pow(c, 1 / 2.4) - 0.055;
    final r = (srgb(p.param<num>('r')!.toDouble()) * 255).round();
    final g = (srgb(p.param<num>('g')!.toDouble()) * 255).round();
    final b = (srgb(p.param<num>('b')!.toDouble()) * 255).round();
    final a = p.param<num>('a')!.toDouble();
    // Points grouped by alpha, drawn as single pixels.
    final byAlpha = <int, List<double>>{};
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final t = noise.turbulence(
          3,
          x + 1.0,
          y + 1.0,
          baseFrequency: 0.85,
          octaves: 3,
          fractalSum: true,
          tileWidth: w * 1.2,
          tileHeight: h * 1.2,
          tileX: -w * 0.1,
          tileY: -h * 0.1,
        );
        final level = (a * ((t + 1) / 2).clamp(0.0, 1.0) * 255).round();
        if (level == 0) continue;
        (byAlpha[level] ??= []).addAll([x + 0.5, y + 0.5]);
      }
    }
    return _picture(w, h, (c) {
      byAlpha.forEach((level, points) {
        c.drawRawPoints(
          ui.PointMode.points,
          Float32List.fromList(points),
          Paint()
            ..isAntiAlias = false
            ..strokeWidth = 1
            ..strokeCap = StrokeCap.square
            ..color = Color.fromARGB(level, r, g, b),
        );
      });
    });
  }
}
