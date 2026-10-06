part of '../helix_remote_ui.dart';

/// The safety number of a chat: groups of digits in a grid, so two people can
/// read them out and compare. [groups] is the number already split (the
/// crypto layer decides how; the usual form is twelve groups of five digits).
class HelixSafetyNumberView extends StatelessWidget {
  const HelixSafetyNumberView({
    super.key,
    required this.groups,
    this.columns = 4,
    this.verified = false,
  });

  final List<String> groups;
  final int columns;

  /// Verified numbers show a green shield and the word "Verified".
  final bool verified;

  /// Spoken form: digits separated so a screen reader does not read
  /// "twelve thousand three hundred".
  static String spoken(List<String> groups) =>
      groups.map((g) => g.split('').join(' ')).join(', ');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < groups.length; i += columns) {
      final slice = groups.sublist(i, math.min(i + columns, groups.length));
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final g in slice)
                Expanded(
                  child: Text(
                    g,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: scheme.onSurface,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Semantics(
      container: true,
      label: 'Safety number${verified ? ', verified' : ''}',
      value: spoken(groups),
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: HelixRadius.card,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(HelixSpace.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...rows,
                if (verified)
                  Padding(
                    padding: const EdgeInsets.only(top: HelixSpace.xs),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.verified_user,
                          size: 18,
                          color: HelixStatusColors.positive,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Verified',
                          style: TextStyle(color: scheme.onSurface),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws a QR code from a ready-made module matrix: black modules on white
/// with the four-module quiet zone. The UI package never encodes a payload;
/// the app does, and passes the matrix.
class HelixQrDisplay extends StatelessWidget {
  const HelixQrDisplay({
    super.key,
    required this.matrix,
    this.size = 240,
    this.semanticLabel = 'QR code',
  });

  final HelixQrMatrix matrix;
  final double size;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: semanticLabel,
    child: ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: RepaintBoundary(child: CustomPaint(painter: _QrPainter(matrix))),
      ),
    ),
  );
}

class _QrPainter extends CustomPainter {
  const _QrPainter(this.matrix);
  final HelixQrMatrix matrix;

  static const _quiet = 4;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = HelixScrimColors.onBackdrop,
    );
    final n = matrix.size;
    final cell = size.shortestSide / (n + _quiet * 2);
    final path = Path();
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (matrix.at(x, y)) {
          path.addRect(
            Rect.fromLTWH((x + _quiet) * cell, (y + _quiet) * cell, cell, cell),
          );
        }
      }
    }
    canvas.drawPath(path, Paint()..color = HelixScrimColors.backdrop);
  }

  @override
  bool shouldRepaint(_QrPainter old) => !identical(old.matrix, matrix);
}

/// The framing overlay for a QR scanner: [child] (the camera preview, owned
/// by the app) with corner brackets and a hint. No camera code lives here.
class HelixQrScanFrame extends StatelessWidget {
  const HelixQrScanFrame({
    super.key,
    required this.child,
    this.hint = 'Point the camera at the QR code',
    this.frameSize = 240,
  });

  final Widget child;
  final String hint;
  final double frameSize;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      Center(
        child: ExcludeSemantics(
          child: CustomPaint(
            size: Size.square(frameSize),
            painter: const _ScanFramePainter(),
          ),
        ),
      ),
      PositionedDirectional(
        start: HelixSpace.md,
        end: HelixSpace.md,
        bottom: HelixSpace.xl,
        child: Semantics(
          liveRegion: true,
          child: Text(
            hint,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: HelixScrimColors.onBackdrop,
              fontSize: 16,
              shadows: [Shadow(blurRadius: 4, color: HelixScrimColors.barrier)],
            ),
          ),
        ),
      ),
    ],
  );
}

class _ScanFramePainter extends CustomPainter {
  const _ScanFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = HelixScrimColors.onBackdrop
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final arm = size.shortestSide * .18;
    final w = size.width;
    final h = size.height;
    void corner(Offset a, Offset b, Offset c) => canvas.drawPath(
      Path()
        ..moveTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..lineTo(c.dx, c.dy),
      paint,
    );
    corner(Offset(0, arm), Offset.zero, Offset(arm, 0));
    corner(Offset(w - arm, 0), Offset(w, 0), Offset(w, arm));
    corner(Offset(0, h - arm), Offset(0, h), Offset(arm, h));
    corner(Offset(w - arm, h), Offset(w, h), Offset(w, h - arm));
  }

  @override
  bool shouldRepaint(_ScanFramePainter old) => false;
}
