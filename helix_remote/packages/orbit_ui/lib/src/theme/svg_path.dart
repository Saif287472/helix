import 'dart:ui';

/// Path data (`<path d="...">`) as a Flutter [Path], for the few shapes the
/// theme patterns draw: move, line, cubic and smooth cubic, absolute and
/// relative, and close. Numbers may run together as SVG allows (`7-2`,
/// `1.6-3.4`).
Path orbitSvgPath(String d) {
  final tokens = RegExp(
    r'[MmLlCcSsZz]|-?(?:\d+\.?\d*|\.\d+)',
  ).allMatches(d).map((m) => m[0]!).toList();
  final path = Path();
  var i = 0;
  var cmd = '';
  var x = 0.0, y = 0.0, startX = 0.0, startY = 0.0;
  // The last cubic's second control point, for `s`.
  double? cx2, cy2;
  double next() => double.parse(tokens[i++]);
  bool atNumber() =>
      i < tokens.length && !RegExp(r'[A-Za-z]').hasMatch(tokens[i]);

  while (i < tokens.length) {
    if (!atNumber()) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase();
    final dx = rel ? x : 0.0, dy = rel ? y : 0.0;
    switch (cmd.toLowerCase()) {
      case 'm':
        x = dx + next();
        y = dy + next();
        path.moveTo(x, y);
        startX = x;
        startY = y;
        // Further pairs after a move are lines.
        cmd = rel ? 'l' : 'L';
        cx2 = null;
      case 'l':
        x = dx + next();
        y = dy + next();
        path.lineTo(x, y);
        cx2 = null;
      case 'c':
        final x1 = dx + next(), y1 = dy + next();
        final x2 = dx + next(), y2 = dy + next();
        x = dx + next();
        y = dy + next();
        path.cubicTo(x1, y1, x2, y2, x, y);
        cx2 = x2;
        cy2 = y2;
      case 's':
        // The first control point mirrors the previous cubic's second.
        final x1 = cx2 == null ? x : 2 * x - cx2;
        final y1 = cy2 == null ? y : 2 * y - cy2;
        final x2 = dx + next(), y2 = dy + next();
        x = dx + next();
        y = dy + next();
        path.cubicTo(x1, y1, x2, y2, x, y);
        cx2 = x2;
        cy2 = y2;
      case 'z':
        path.close();
        x = startX;
        y = startY;
        cx2 = null;
      default:
        throw FormatException('unsupported path command "$cmd"', d);
    }
  }
  return path;
}
