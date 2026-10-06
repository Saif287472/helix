import 'dart:math' as math;
import 'dart:typed_data';

/// The BlurHash encoder (https://blurha.sh): a 20-30 character string that
/// describes a blurred version of a picture, which a receiver paints while the
/// real thumbnail is still on its way.
///
/// Pure Dart, no plugin. Encode a *small* picture (the caller scales to about
/// 32 pixels on the long side): the work is `width x height x components`.
abstract final class Blurhash {
  static const _alphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#\$%*+,-.:;=?@[]^_{|}~';

  /// The hash of [rgba] (four bytes per pixel, straight alpha ignored) with
  /// [xComponents] x [yComponents] (each 1-9) frequency components.
  static String encode(
    Uint8List rgba, {
    required int width,
    required int height,
    int xComponents = 4,
    int yComponents = 3,
  }) {
    assert(xComponents >= 1 && xComponents <= 9);
    assert(yComponents >= 1 && yComponents <= 9);
    assert(rgba.length >= width * height * 4);

    final factors = <List<double>>[];
    for (var y = 0; y < yComponents; y++) {
      for (var x = 0; x < xComponents; x++) {
        factors.add(_factor(rgba, width, height, x, y));
      }
    }
    final dc = factors.first;
    final ac = factors.sublist(1);

    final out = StringBuffer();
    out.write(_base83(xComponents - 1 + (yComponents - 1) * 9, 1));

    double maximum;
    if (ac.isNotEmpty) {
      var actual = 0.0;
      for (final f in ac) {
        for (final v in f) {
          actual = math.max(actual, v.abs());
        }
      }
      final quantised = (actual * 166 - 0.5).floor().clamp(0, 82);
      maximum = (quantised + 1) / 166;
      out.write(_base83(quantised, 1));
    } else {
      maximum = 1;
      out.write(_base83(0, 1));
    }

    out.write(
      _base83(
        (_toSrgb(dc[0]) << 16) + (_toSrgb(dc[1]) << 8) + _toSrgb(dc[2]),
        4,
      ),
    );
    for (final f in ac) {
      out.write(
        _base83(
          _quant(f[0] / maximum) * 19 * 19 +
              _quant(f[1] / maximum) * 19 +
              _quant(f[2] / maximum),
          2,
        ),
      );
    }
    return out.toString();
  }

  static List<double> _factor(
    Uint8List rgba,
    int width,
    int height,
    int xc,
    int yc,
  ) {
    var r = 0.0;
    var g = 0.0;
    var b = 0.0;
    final normalisation = xc == 0 && yc == 0 ? 1.0 : 2.0;
    for (var y = 0; y < height; y++) {
      final cy = math.cos(math.pi * yc * y / height);
      for (var x = 0; x < width; x++) {
        final basis = math.cos(math.pi * xc * x / width) * cy;
        final i = (y * width + x) * 4;
        r += basis * _toLinear(rgba[i]);
        g += basis * _toLinear(rgba[i + 1]);
        b += basis * _toLinear(rgba[i + 2]);
      }
    }
    final scale = normalisation / (width * height);
    return [r * scale, g * scale, b * scale];
  }

  static double _toLinear(int value) {
    final v = value / 255;
    return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) * 1.0;
  }

  static int _toSrgb(double value) {
    final v = value.clamp(0.0, 1.0);
    return v <= 0.0031308
        ? (v * 12.92 * 255 + 0.5).toInt()
        : ((1.055 * math.pow(v, 1 / 2.4) - 0.055) * 255 + 0.5).toInt();
  }

  static int _quant(double value) {
    final signed = value.isNegative ? -math.sqrt(-value) : math.sqrt(value);
    return (signed * 9 + 9.5).floor().clamp(0, 18);
  }

  static String _base83(int value, int length) {
    final out = List<String>.filled(length, '');
    var v = value;
    for (var i = length - 1; i >= 0; i--) {
      out[i] = _alphabet[v % 83];
      v ~/= 83;
    }
    return out.join();
  }
}
