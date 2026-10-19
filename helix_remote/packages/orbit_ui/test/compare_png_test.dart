import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/src/compare/orbit_png.dart';

/// The PNG codec the compare tool reads the browser's screenshots with.
///
/// A compare tool that cannot decode what `shoot_html.py` wrote is not a
/// compare tool, so the first test here decodes a real Chrome screenshot that
/// ships with the tests (`test/fixtures/chrome-startup.phone.orbit.png`)
/// rather than only images this codec produced itself.
void main() {
  /// Builds a test image: opaque, deterministic, and not one flat colour.
  OrbitImage gradient(int width, int height) {
    final pixels = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final o = (y * width + x) * 4;
        pixels[o] = (x * 7 + y * 3) % 256;
        pixels[o + 1] = (x * 3 + y * 11) % 256;
        pixels[o + 2] = (x * 13) % 256;
        pixels[o + 3] = 255;
      }
    }
    return OrbitImage(width: width, height: height, pixels: pixels);
  }

  group('a round trip loses nothing', () {
    test('an image survives being written and read back', () {
      final image = gradient(64, 48);
      final decoded = decodeOrbitPng(encodeOrbitPng(image));
      expect(decoded.width, 64);
      expect(decoded.height, 48);
      expect(decoded.pixels, orderedEquals(image.pixels));
    });

    test('the smallest legal image works', () {
      final image = OrbitImage(
        width: 1,
        height: 1,
        pixels: Uint8List.fromList(<int>[12, 34, 56, 255]),
      );
      final decoded = decodeOrbitPng(encodeOrbitPng(image));
      expect(decoded.pixels, orderedEquals(<int>[12, 34, 56, 255]));
    });

    test('the encoder is deterministic: same image, same bytes', () {
      final image = gradient(200, 140);
      final first = encodeOrbitPng(image);
      final second = encodeOrbitPng(
        OrbitImage(
          width: 200,
          height: 140,
          pixels: Uint8List.fromList(image.pixels),
        ),
      );
      expect(
        first,
        orderedEquals(second),
        reason:
            'two runs over the same image must produce the same file, or '
            'git shows a change every time the compare tool runs',
      );
    });

    test('the output is a real PNG', () {
      final bytes = encodeOrbitPng(gradient(8, 8));
      expect(
        bytes.sublist(0, 8),
        orderedEquals(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
      );
      expect(
        String.fromCharCodes(bytes.sublist(12, 16)),
        'IHDR',
        reason: 'the first chunk after the signature is always IHDR',
      );
    });
  });

  group('a real browser screenshot', () {
    // The startup screen, written by shoot_html.py with --reduce-motion and
    // kept as a test input. It is 8-bit truecolour, non-interlaced, and the
    // exact size the Flutter side has to render at.
    final sample = File('test/fixtures/chrome-startup.phone.orbit.png');

    test('decodes at 412x866', () {
      expect(
        sample.existsSync(),
        isTrue,
        reason:
            'the fixture is missing; shoot startup again with '
            'shoot_html.py --reduce-motion and copy it in',
      );
      final image = decodeOrbitPng(
        sample.readAsBytesSync(),
        name: 'chrome-startup.phone.orbit.png',
      );
      expect(image.width, 412);
      expect(image.height, 866);
      expect(image.pixels.length, 412 * 866 * 4);
      expect(
        image.distinctColours(),
        greaterThan(1),
        reason: 'a screenshot of a screen is not one flat colour',
      );
      for (var i = 3; i < image.pixels.length; i += 4) {
        expect(image.pixels[i], 255, reason: 'a Chrome screenshot is opaque');
        if (image.pixels[i] != 255) break;
      }
    });
  });

  group('bad input is an error, never a picture', () {
    test('something that is not a PNG', () {
      expect(
        () => decodeOrbitPng(Uint8List.fromList(<int>[1, 2, 3, 4])),
        throwsA(isA<OrbitPngException>()),
      );
    });

    test('a wrong signature', () {
      final bytes = encodeOrbitPng(gradient(4, 4));
      final broken = Uint8List.fromList(bytes)..[1] = 0x00;
      expect(
        () => decodeOrbitPng(broken),
        throwsA(
          isA<OrbitPngException>().having(
            (e) => e.message,
            'message',
            contains('signature'),
          ),
        ),
      );
    });

    test('a truncated file', () {
      final bytes = encodeOrbitPng(gradient(16, 16));
      final broken = bytes.sublist(0, bytes.length ~/ 2);
      expect(() => decodeOrbitPng(broken), throwsA(isA<OrbitPngException>()));
    });

    test('an edited file, caught by the CRC', () {
      // Corrupting the compressed data without fixing the CRC is exactly what
      // a half-written download or a bad disk looks like.
      final bytes = encodeOrbitPng(gradient(16, 16));
      final broken = Uint8List.fromList(bytes);
      // The IDAT payload sits after IHDR (25 bytes) + IDAT header (8).
      broken[30] = broken[30] ^ 0xFF;
      expect(
        () => decodeOrbitPng(broken),
        throwsA(
          isA<OrbitPngException>().having(
            (e) => e.message,
            'message',
            contains('CRC'),
          ),
        ),
      );
    });

    test('image data that is not deflate', () {
      // Replace the IDAT payload with rubbish and fix the CRCs, so the failure
      // has to come from the inflate rather than from the checksum catching it
      // first.
      final bytes = encodeOrbitPng(gradient(8, 8));
      final idatAt = _findChunk(bytes, 'IDAT');
      expect(idatAt, greaterThan(0));
      final payloadEnd = bytes.length - 12; // IEND: length, type, crc
      final broken = Uint8List.fromList(<int>[
        ...bytes.sublist(0, idatAt),
        ...List<int>.filled(payloadEnd - idatAt, 0x5A),
        ...bytes.sublist(payloadEnd),
      ]);
      expect(
        () => decodeOrbitPng(_fixCrcs(broken)),
        throwsA(
          isA<OrbitPngException>().having(
            (e) => e.message,
            'message',
            contains('does not inflate'),
          ),
        ),
      );
    });

    test('an image of no size', () {
      expect(
        () => OrbitImage(width: 0, height: 10, pixels: Uint8List(0)),
        throwsA(isA<OrbitPngException>()),
      );
    });
  });
}

/// The offset of the first byte of chunk [type]'s data, or -1.
int _findChunk(Uint8List png, String type) {
  var pos = 8;
  while (pos + 8 <= png.length) {
    final length =
        (png[pos] << 24) |
        (png[pos + 1] << 16) |
        (png[pos + 2] << 8) |
        png[pos + 3];
    final here = String.fromCharCodes(png.sublist(pos + 4, pos + 8));
    if (here == type) return pos + 8;
    pos += 12 + length;
  }
  return -1;
}

/// Recomputes every chunk CRC in a PNG, so a test can corrupt the data and
/// check the failure comes from the data rather than from the checksum.
Uint8List _fixCrcs(Uint8List png) {
  final out = Uint8List.fromList(png);
  var pos = 8;
  while (pos + 8 <= out.length) {
    final length =
        (out[pos] << 24) |
        (out[pos + 1] << 16) |
        (out[pos + 2] << 8) |
        out[pos + 3];
    final end = pos + 8 + length;
    if (end + 4 > out.length) break;
    var c = 0xFFFFFFFF;
    for (var i = pos + 4; i < end; i++) {
      c ^= out[i];
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
    }
    c = (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
    out[end] = (c >> 24) & 0xFF;
    out[end + 1] = (c >> 16) & 0xFF;
    out[end + 2] = (c >> 8) & 0xFF;
    out[end + 3] = c & 0xFF;
    pos = end + 4;
  }
  return out;
}
