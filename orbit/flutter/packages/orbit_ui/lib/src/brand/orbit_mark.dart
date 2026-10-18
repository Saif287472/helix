import 'package:flutter/widgets.dart';

/// The Orbit logo: `prototype/assets/orbit-mark.svg`, drawn as paths.
///
/// Drawn rather than loaded so `orbit_ui` needs no SVG package: Part B moves it
/// into `helix_remote/packages` unchanged, and the app has none. The numbers
/// are the SVG's own, on its 64-unit grid, scaled to the widget's size.
///
/// The logo is the brand, not a theme colour, so its three gradient colours
/// are the file's and every theme shows the same mark.
class OrbitMark extends StatelessWidget {
  const OrbitMark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Orbit',
    image: true,
    child: CustomPaint(size: Size.square(size), painter: const _MarkPainter()),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  static const _teal = Color(0xFF0EA5B7);
  static const _blue = Color(0xFF2563EB);
  static const _violet = Color(0xFF7C3AED);
  static const _white = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 64;
    canvas.scale(s);
    const box = Rect.fromLTWH(0, 0, 64, 64);

    // <rect rx="18" fill="url(#og)">, the gradient corner to corner.
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(18)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_teal, _blue, _violet],
          stops: [0, 0.5, 1],
        ).createShader(box),
    );

    Paint stroke(double opacity) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..color = _white.withValues(alpha: opacity);
    // "A21 8.5 -28 0 1": an ellipse arc tilted -28 degrees, the short way
    // round, clockwise (SVG's sweep flag 1). arcToPoint takes degrees too.
    Path arc(Offset from, Offset to) => Path()
      ..moveTo(from.dx, from.dy)
      ..arcToPoint(
        to,
        radius: const Radius.elliptical(21, 8.5),
        rotation: -28,
        clockwise: true,
      );
    const left = Offset(12.6, 39.6);
    const right = Offset(51.4, 24.4);

    // The back half of the orbit, the planet, then the front half over it.
    canvas.drawPath(arc(left, right), stroke(0.55));
    canvas.drawCircle(const Offset(32, 32), 10, Paint()..color = _white);
    canvas.drawPath(arc(right, left), stroke(1));
    canvas.drawCircle(const Offset(49.6, 20.6), 3.4, Paint()..color = _white);
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => false;
}
