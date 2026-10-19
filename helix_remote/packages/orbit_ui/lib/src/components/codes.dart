import 'package:flutter/material.dart';

import 'package:orbit_ui/src/components/page_parts.dart';
import 'package:orbit_ui/src/models/view_models.dart';
import 'package:orbit_ui/src/theme/motion.dart';
import 'package:orbit_ui/src/theme/orbit_metrics.dart';
import 'package:orbit_ui/src/theme/orbit_text.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

enum OrbitCodeSize {
  /// `.codebox`: mono 22px at weight 600, tracked 0.12em, broken anywhere.
  regular,

  /// `.codebox.huge`: 34px, tracked 0.3em, centred (a check number).
  huge,

  /// `.codebox.secret`: 17px, tracked 0.06em, line height 1.6, broken only
  /// between dash-separated groups, the lines balanced.
  secret,
}

/// `Kit.code(label, value, opts)` (`.codebox` in `css/pages.css`): an
/// eyebrow label over a large monospaced code, and an optional note at
/// `--t-caption` in `--ink-3`, 6px apart, 14px 16px in, on `--surface` with
/// a `--line` edge, corner `--r-md`. 12px under what is above it and inset by
/// the gutter, unless [margin] says otherwise (`.secret-card .codebox`).
class OrbitCodeBox extends StatelessWidget {
  const OrbitCodeBox({
    super.key,
    required this.label,
    required this.code,
    this.note = '',
    this.size = OrbitCodeSize.regular,
    this.margin = const EdgeInsets.fromLTRB(
      OrbitSpace.gutter,
      12,
      OrbitSpace.gutter,
      0,
    ),
  });

  final String label;
  final String code;
  final String note;
  final OrbitCodeSize size;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final style = switch (size) {
      OrbitCodeSize.regular => t.mono.style(
        size: 22,
        weight: 600,
        color: t.ink,
        letterSpacingEm: 0.12,
      ),
      OrbitCodeSize.huge => t.mono.style(
        size: 34,
        weight: 600,
        color: t.ink,
        letterSpacingEm: 0.3,
      ),
      OrbitCodeSize.secret => t.mono.style(
        size: 17,
        weight: 600,
        color: t.ink,
        letterSpacingEm: 0.06,
        height: 1.6,
      ),
    };
    final Widget shown = switch (size) {
      OrbitCodeSize.regular => OrbitText(_anywhere(code), style: style),
      OrbitCodeSize.huge => OrbitText(
        code,
        style: style,
        textAlign: TextAlign.center,
      ),
      OrbitCodeSize.secret => _BalancedGroups(code: code, style: style),
    };
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.line),
        borderRadius: BorderRadius.circular(t.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OrbitEyebrow(label),
          const SizedBox(height: 6),
          shown,
          if (note.isNotEmpty) ...[
            const SizedBox(height: 6),
            OrbitText(
              note,
              style: t.font.style(
                size: OrbitType.caption,
                color: t.ink3,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// `word-break: break-all`: a line may break between any two characters.
  static String _anywhere(String s) => s.characters.join('​');
}

/// `.cb-grp` groups with `text-wrap: balance`: the code breaks only after a
/// dash, into as few lines as fit, as evenly long as they can be.
class _BalancedGroups extends StatelessWidget {
  const _BalancedGroups({required this.code, required this.style});

  final String code;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final parts = code.split('-');
    final groups = [
      for (final (i, p) in parts.indexed) i < parts.length - 1 ? '$p-' : p,
    ];
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        double width(String s) {
          final tp = TextPainter(
            text: TextSpan(text: s, style: style),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
          )..layout();
          final w = tp.width;
          tp.dispose();
          return w;
        }

        final widths = groups.map(width).toList();
        List<String> lines(double max) {
          final out = <String>[];
          var line = '';
          var used = 0.0;
          for (final (i, g) in groups.indexed) {
            if (line.isNotEmpty && used + widths[i] > max) {
              out.add(line);
              line = '';
              used = 0;
            }
            line += g;
            used += widths[i];
          }
          return out..add(line);
        }

        final fit = lines(box.maxWidth);
        // The narrowest width that still needs no more lines.
        var lo = 0.0;
        var hi = box.maxWidth;
        for (var i = 0; i < 24; i++) {
          final mid = (lo + hi) / 2;
          if (lines(mid).length <= fit.length) {
            hi = mid;
          } else {
            lo = mid;
          }
        }
        return OrbitText(lines(hi).join('\n'), style: style);
      },
    );
  }
}

/// `.qr-card` around a QR code (`css/pages.css`): 14px of white, corner 24,
/// a `--line` edge and `--shadow-card`, with two 22px `--accent` corner marks
/// 6px outside it, top left and bottom right.
class OrbitQrCard extends StatelessWidget {
  const OrbitQrCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    return CustomPaint(
      foregroundPainter: _QrCorners(t.accent),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          // A QR code is dark on white in every theme, so scanners read it.
          color: const Color(0xFFFFFFFF),
          border: Border.all(color: t.line),
          borderRadius: BorderRadius.circular(24),
          boxShadow: t.shadowCard,
        ),
        child: child,
      ),
    );
  }
}

class _QrCorners extends CustomPainter {
  const _QrCorners(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    // `top: -6px; left: -6px` from inside the 1px edge: 5px outside the box.
    const s = 22.0, w = 3.0, r = 10.0;
    // Each mark is a 22px box with a 3px border on two sides and a 10px
    // outer corner (7px inside), which is the box minus its inner rectangle.
    Path mark(Rect box, {required bool topLeft}) {
      final outer = topLeft
          ? RRect.fromRectAndCorners(box, topLeft: const Radius.circular(r))
          : RRect.fromRectAndCorners(
              box,
              bottomRight: const Radius.circular(r),
            );
      final inner = topLeft
          ? RRect.fromRectAndCorners(
              Rect.fromLTRB(box.left + w, box.top + w, box.right, box.bottom),
              topLeft: const Radius.circular(r - w),
            )
          : RRect.fromRectAndCorners(
              Rect.fromLTRB(box.left, box.top, box.right - w, box.bottom - w),
              bottomRight: const Radius.circular(r - w),
            );
      return Path.combine(
        PathOperation.difference,
        Path()..addRRect(outer),
        Path()..addRRect(inner),
      );
    }

    canvas
      ..drawPath(
        mark(const Offset(-5, -5) & const Size(s, s), topLeft: true),
        paint,
      )
      ..drawPath(
        mark(
          Offset(size.width + 5 - s, size.height + 5 - s) & const Size(s, s),
          topLeft: false,
        ),
        paint,
      );
  }

  @override
  bool shouldRepaint(_QrCorners old) => old.color != color;
}

/// `Kit.qr(seed, size)` (`js/kit.js`): the prototype's stand-in QR, a 29×29
/// matrix with three finder squares and the rest from a seeded generator,
/// on white with 2 cells of margin, dark cells `#0E1220`.
///
/// It draws the same cells as the prototype for the same [seed]. The app
/// passes a real code as [matrix] (an encoder's modules), drawn the same
/// way.
class OrbitQr extends StatelessWidget {
  const OrbitQr({super.key, this.seed = '', this.matrix, this.size = 200});

  final String seed;
  final HelixQrMatrix? matrix;
  final double size;

  @override
  Widget build(BuildContext context) {
    final q = matrix;
    return Semantics(
      image: true,
      label: 'QR code',
      child: CustomPaint(
        size: Size.square(size),
        painter: _QrPainter(
          q == null
              ? orbitQrCells(seed)
              : [
                  for (var y = 0; y < q.size; y++)
                    [for (var x = 0; x < q.size; x++) q.at(x, y)],
                ],
        ),
      ),
    );
  }
}

/// The prototype's matrix for [seed]: FNV-1a over the seed, then xorshift32,
/// with JavaScript's 32-bit integer rules.
List<List<bool>> orbitQrCells(String seed) {
  const n = 29;
  var h = 2166136261;
  for (final c in seed.codeUnits) {
    h = ((h ^ c) * 16777619) & 0xffffffff;
  }
  int int32(int u) => (u & 0xffffffff) >= 0x80000000
      ? (u & 0xffffffff) - 0x100000000
      : u & 0xffffffff;
  double rnd() {
    h = (h ^ (h << 13)) & 0xffffffff;
    h = (h ^ (int32(h) >> 17)) & 0xffffffff;
    h = (h ^ (h << 5)) & 0xffffffff;
    return h / 4294967296;
  }

  const finders = [(0, 0), (n - 7, 0), (0, n - 7)];
  bool? finder(int x, int y) {
    for (final (fx, fy) in finders) {
      final dx = x - fx, dy = y - fy;
      if (dx >= 0 && dx < 7 && dy >= 0 && dy < 7) {
        return dx == 0 ||
            dx == 6 ||
            dy == 0 ||
            dy == 6 ||
            (dx >= 2 && dx <= 4 && dy >= 2 && dy <= 4);
      }
    }
    return null;
  }

  return [
    for (var y = 0; y < n; y++)
      [for (var x = 0; x < n; x++) finder(x, y) ?? rnd() > 0.52],
  ];
}

class _QrPainter extends CustomPainter {
  const _QrPainter(this.cells);

  final List<List<bool>> cells;

  @override
  void paint(Canvas canvas, Size size) {
    final n = cells.length;
    // `viewBox="-2 -2 n+4 n+4"`: two cells of white around the matrix.
    final unit = size.width / (n + 4);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final dark = Paint()..color = const Color(0xFF0E1220);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (!cells[y][x]) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            (x + 2) * unit,
            (y + 2) * unit,
            1.02 * unit,
            1.02 * unit,
          ),
          dark,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.cells != cells;
}

/// `Kit.progress(p)` (`.prog` in `css/pages.css`): a 4px `--line` track,
/// corner 4, 12px under what is above it and inset by the gutter, filled to
/// [value] in `--accent`. With no value a 36% bar slides across every 1.2s
/// on the theme's curve;
/// under reduce motion it stays at the start.
class OrbitProgress extends StatefulWidget {
  const OrbitProgress({
    super.key,
    this.value,
    this.margin = const EdgeInsets.fromLTRB(
      OrbitSpace.gutter,
      12,
      OrbitSpace.gutter,
      0,
    ),
  });

  final double? value;
  final EdgeInsets margin;

  @override
  State<OrbitProgress> createState() => _OrbitProgressState();
}

class _OrbitProgressState extends State<OrbitProgress>
    with SingleTickerProviderStateMixin {
  late final _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(OrbitProgress old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.value == null && OrbitMotion.allowed(context);
    if (run && !_slide.isAnimating) _slide.repeat();
    if (!run && _slide.isAnimating) _slide.reset();
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = OrbitTokens.of(context);
    final value = widget.value;
    final radius = BorderRadius.circular(4);
    final bar = DecoratedBox(
      decoration: BoxDecoration(color: t.accent, borderRadius: radius),
    );
    return Padding(
      padding: widget.margin,
      child: ClipRRect(
        borderRadius: radius,
        child: Container(
          height: 4,
          color: t.line,
          child: LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              if (value != null) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: w * value.clamp(0, 1),
                    height: 4,
                    child: bar,
                  ),
                );
              }
              return AnimatedBuilder(
                animation: _slide,
                builder: (context, _) {
                  final p = _slide.isAnimating
                      ? t.motion.curve.transform(_slide.value)
                      : null;
                  final left = p == null ? 0.0 : -0.36 * w + p * 1.36 * w;
                  return Stack(
                    children: [
                      Positioned(
                        left: left,
                        top: 0,
                        bottom: 0,
                        width: w * 0.36,
                        child: bar,
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
