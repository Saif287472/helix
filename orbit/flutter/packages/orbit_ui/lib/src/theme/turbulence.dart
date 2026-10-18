import 'dart:math' as math;
import 'dart:typed_data';

/// SVG's `feTurbulence`, ported from the reference code in the SVG 1.1
/// specification (section 15.22), so the grain pattern is the prototype's own
/// noise rather than a look-alike.
///
/// The prototype's grain is `<feTurbulence type="fractalNoise"
/// baseFrequency=".85" numOctaves="3" stitchTiles="stitch"/>` with the default
/// seed of 0, on a 160×160 tile.
///
/// Checked against Chrome on 2026-10-18 (Papyrus's grain tile read back from a
/// canvas): with the filter region as the stitch tile (192×192 at -16, -16)
/// and each pixel sampled at (x + 1, y + 1), the alpha matched to within
/// rounding (mean error 0.07 of 255).
final class OrbitTurbulence {
  OrbitTurbulence({int seed = 0}) {
    _init(seed);
  }

  static const _bSize = 0x100;
  static const _bm = 0xff;
  static const _perlinN = 0x1000;
  static const _randM = 2147483647;
  static const _randA = 16807;
  static const _randQ = 127773;
  static const _randR = 2836;

  final _lattice = Int32List(_bSize + _bSize + 2);
  final _gradient = List.generate(
    4,
    (_) => List.generate(_bSize + _bSize + 2, (_) => Float64List(2)),
  );

  static int _setupSeed(int seed) {
    var s = seed;
    if (s <= 0) s = -(s % (_randM - 1)) + 1;
    if (s > _randM - 1) s = _randM - 1;
    return s;
  }

  static int _random(int seed) {
    var r = _randA * (seed % _randQ) - _randR * (seed ~/ _randQ);
    if (r <= 0) r += _randM;
    return r;
  }

  void _init(int seed) {
    var s = _setupSeed(seed);
    int i;
    for (var k = 0; k < 4; k++) {
      for (i = 0; i < _bSize; i++) {
        _lattice[i] = i;
        for (var j = 0; j < 2; j++) {
          s = _random(s);
          _gradient[k][i][j] = ((s % (_bSize + _bSize)) - _bSize) / _bSize;
        }
        final g = _gradient[k][i];
        final len = math.sqrt(g[0] * g[0] + g[1] * g[1]);
        g[0] /= len;
        g[1] /= len;
      }
    }
    i = _bSize;
    while (--i > 0) {
      final k = _lattice[i];
      s = _random(s);
      final j = s % _bSize;
      _lattice[i] = _lattice[j];
      _lattice[j] = k;
    }
    for (i = 0; i < _bSize + 2; i++) {
      _lattice[_bSize + i] = _lattice[i];
      for (var k = 0; k < 4; k++) {
        for (var j = 0; j < 2; j++) {
          _gradient[k][_bSize + i][j] = _gradient[k][i][j];
        }
      }
    }
  }

  static double _sCurve(double t) => t * t * (3 - 2 * t);
  static double _lerp(double t, double a, double b) => a + t * (b - a);

  double _noise2(int channel, double x, double y, _Stitch? stitch) {
    var t = x + _perlinN;
    var bx0 = t.toInt() & _bm;
    var bx1 = (bx0 + 1) & _bm;
    final rx0 = t - t.toInt();
    final rx1 = rx0 - 1;
    t = y + _perlinN;
    var by0 = t.toInt() & _bm;
    var by1 = (by0 + 1) & _bm;
    final ry0 = t - t.toInt();
    final ry1 = ry0 - 1;
    if (stitch != null) {
      if (bx0 >= stitch.wrapX) bx0 -= stitch.width;
      if (bx1 >= stitch.wrapX) bx1 -= stitch.width;
      if (by0 >= stitch.wrapY) by0 -= stitch.height;
      if (by1 >= stitch.wrapY) by1 -= stitch.height;
    }
    bx0 &= _bm;
    bx1 &= _bm;
    by0 &= _bm;
    by1 &= _bm;
    final i = _lattice[bx0];
    final j = _lattice[bx1];
    final b00 = _lattice[i + by0];
    final b10 = _lattice[j + by0];
    final b01 = _lattice[i + by1];
    final b11 = _lattice[j + by1];
    final sx = _sCurve(rx0);
    final sy = _sCurve(ry0);
    final g = _gradient[channel];
    var q = g[b00];
    var u = rx0 * q[0] + ry0 * q[1];
    q = g[b10];
    var v = rx1 * q[0] + ry0 * q[1];
    final a = _lerp(sx, u, v);
    q = g[b01];
    u = rx0 * q[0] + ry1 * q[1];
    q = g[b11];
    v = rx1 * q[0] + ry1 * q[1];
    final b = _lerp(sx, u, v);
    return _lerp(sy, a, b);
  }

  /// The turbulence function for one colour [channel] (0 red ... 3 alpha) at
  /// [x], [y], stitched to the [tileWidth]×[tileHeight] tile at [tileX],
  /// [tileY]: the filter region, which by default reaches 10% past the shape
  /// on every side.
  double turbulence(
    int channel,
    double x,
    double y, {
    required double baseFrequency,
    required int octaves,
    required bool fractalSum,
    required double tileWidth,
    required double tileHeight,
    double tileX = 0,
    double tileY = 0,
  }) {
    var fx = baseFrequency;
    var fy = baseFrequency;
    // Stitching: adjust the frequencies so the tile repeats seamlessly.
    if (fx != 0) {
      final lo = (tileWidth * fx).floorToDouble() / tileWidth;
      final hi = (tileWidth * fx).ceilToDouble() / tileWidth;
      fx = (fx / lo < hi / fx) ? lo : hi;
    }
    if (fy != 0) {
      final lo = (tileHeight * fy).floorToDouble() / tileHeight;
      final hi = (tileHeight * fy).ceilToDouble() / tileHeight;
      fy = (fy / lo < hi / fy) ? lo : hi;
    }
    final w = (tileWidth * fx + 0.5).toInt();
    final h = (tileHeight * fy + 0.5).toInt();
    final stitch = _Stitch(
      w,
      h,
      (tileX * fx + _perlinN + w).toInt(),
      (tileY * fy + _perlinN + h).toInt(),
    );
    var sum = 0.0;
    var vx = x * fx;
    var vy = y * fy;
    var ratio = 1.0;
    for (var octave = 0; octave < octaves; octave++) {
      final n = _noise2(channel, vx, vy, stitch);
      sum += fractalSum ? n / ratio : n.abs() / ratio;
      vx *= 2;
      vy *= 2;
      ratio *= 2;
      stitch
        ..width += stitch.width
        ..wrapX = 2 * stitch.wrapX - _perlinN
        ..height += stitch.height
        ..wrapY = 2 * stitch.wrapY - _perlinN;
    }
    return sum;
  }
}

class _Stitch {
  _Stitch(this.width, this.height, this.wrapX, this.wrapY);
  int width;
  int height;
  int wrapX;
  int wrapY;
}
