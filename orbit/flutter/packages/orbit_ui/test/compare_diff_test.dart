import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/src/compare/orbit_diff.dart';
import 'package:orbit_ui/src/compare/orbit_png.dart';

/// The comparison and the score.
///
/// The score is the plain percentage of pixels that are not byte-identical.
/// Four things have to be true of it, and each of them is a test here:
/// identical images score exactly zero, one changed pixel scores exactly that
/// one pixel's share, a size mismatch is an error rather than a resize, and a
/// missing file is an error rather than an empty image.
void main() {
  /// A test image: opaque, and deterministic.
  OrbitImage image(int width, int height, {int seed = 0}) {
    final pixels = Uint8List(width * height * 4);
    for (var i = 0; i < width * height; i++) {
      pixels[i * 4] = (i * 5 + seed) % 256;
      pixels[i * 4 + 1] = (i * 3 + seed) % 256;
      pixels[i * 4 + 2] = (i * 11 + seed) % 256;
      pixels[i * 4 + 3] = 255;
    }
    return OrbitImage(width: width, height: height, pixels: pixels);
  }

  /// The same image with one pixel's red channel moved by [delta].
  OrbitImage withOnePixelChanged(
    OrbitImage from, {
    required int pixel,
    int delta = 1,
  }) {
    final pixels = Uint8List.fromList(from.pixels);
    pixels[pixel * 4] = (pixels[pixel * 4] + delta) % 256;
    return OrbitImage(
      width: from.width,
      height: from.height,
      pixels: pixels,
    );
  }

  group('the score', () {
    test('identical images score exactly zero', () {
      final a = image(412, 866);
      final b = OrbitImage(
        width: a.width,
        height: a.height,
        pixels: Uint8List.fromList(a.pixels),
      );
      final diff = compareOrbitImages(a, b);
      expect(diff.differingPixels, 0);
      expect(diff.differingChannels, 0);
      expect(diff.maxChannelDelta, 0);
      expect(diff.score, 0.0, reason: 'the score of two copies of the same '
          'file is zero, not nearly zero');
      expect(diff.roundedScore, 0.0);
    });

    test('one changed pixel in 100 scores exactly one percent', () {
      final a = image(10, 10);
      final b = withOnePixelChanged(a, pixel: 42);
      final diff = compareOrbitImages(a, b);
      expect(diff.differingPixels, 1);
      expect(diff.totalPixels, 100);
      expect(diff.differingChannels, 1,
          reason: 'one channel moved, so one channel differs');
      expect(diff.maxChannelDelta, 1);
      expect(diff.score, closeTo(1.0, 1e-12));
      expect(diff.roundedScore, 1.0);
    });

    test('one changed pixel in a phone screen scores the tiny value it is', () {
      // 412 x 866 is the phone device. One pixel out of 356,792 is 0.00028%.
      final a = image(412, 866);
      final b = withOnePixelChanged(a, pixel: 200000);
      final diff = compareOrbitImages(a, b);
      expect(diff.totalPixels, 356792);
      expect(diff.differingPixels, 1);
      expect(diff.score, closeTo(100 / 356792, 1e-12));
      expect(diff.roundedScore, 0.00028);
    });

    test('a one-bit change counts, because there is no tolerance', () {
      // Anti-aliasing arguments are how a "close enough" band gets invented,
      // and a band is how a real difference stops being visible. One unit is
      // one unit.
      final a = image(10, 10);
      final b = withOnePixelChanged(a, pixel: 7, delta: 1);
      expect(compareOrbitImages(a, b).score, 1.0,
          reason: 'one unit out of one hundred pixels is one percent, not a '
              'fraction of a percent');
    });

    test('a moved pixel counts once however many channels moved', () {
      final a = image(10, 10);
      final pixels = Uint8List.fromList(a.pixels);
      // Wrap-free on purpose, so the expected mean is exact.
      for (var c = 0; c < 4; c++) {
        pixels[3 * 4 + c] = (pixels[3 * 4 + c] + 200) & 0xFF;
      }
      final b = OrbitImage(width: 10, height: 10, pixels: pixels);
      final diff = compareOrbitImages(a, b);
      expect(diff.differingPixels, 1);
      expect(diff.differingChannels, 4);
      expect(diff.score, 1.0, reason: 'four channels in one pixel is still '
          'one pixel, so the score is one percent and not four');
      expect(diff.meanChannelDelta, greaterThan(0));
      expect(diff.meanChannelDelta, lessThanOrEqualTo(255));
    });

    test('every pixel different scores one hundred', () {
      final a = OrbitImage(
        width: 8,
        height: 8,
        pixels: Uint8List.fromList(
          List<int>.filled(8 * 8 * 4, 0xFF),
        ),
      );
      final b = OrbitImage(
        width: 8,
        height: 8,
        pixels: Uint8List.fromList(
          List<int>.filled(8 * 8 * 4, 0x00),
        ),
      );
      expect(compareOrbitImages(a, b).score, 100.0);
    });

    test('the score is in percent, not a fraction', () {
      final diff = compareOrbitImages(image(4, 5), image(4, 5, seed: 9));
      expect(diff.score, greaterThan(0));
      expect(diff.score, lessThanOrEqualTo(100));
      expect(diff.roundedScore, lessThanOrEqualTo(100));
    });
  });

  group('a comparison that cannot happen is an error', () {
    test('two different sizes, naming both', () {
      final a = image(412, 866);
      final b = image(412, 865);
      expect(
        () => compareOrbitImages(a, b,
            leftName: 'the prototype', rightName: 'the Flutter render'),
        throwsA(
          isA<OrbitCompareException>()
              .having((e) => e.message, 'message', contains('412x866'))
              .having((e) => e.message, 'message', contains('412x865'))
              .having((e) => e.message, 'message', contains('the prototype'))
              .having(
                  (e) => e.message, 'message', contains('the Flutter render')),
        ),
      );
    });

    test('the width alone is enough to stop it', () {
      expect(
        () => compareOrbitImages(image(412, 866), image(411, 866)),
        throwsA(isA<OrbitCompareException>().having(
          (e) => e.message,
          'message',
          allOf(contains('411x866'), contains('412x866')),
        )),
      );
    });

    test('a missing file on the left', () {
      expect(
        () => readOrbitPngFile(
          'no\\such\\file.png',
          name: 'the prototype',
        ),
        throwsA(
          isA<OrbitCompareException>()
              .having((e) => e.message, 'message', contains('no file at'))
              .having((e) => e.message, 'message', contains('the prototype')),
        ),
      );
    });

    test('a missing file on the right', () {
      final dir = Directory.systemTemp.createTempSync('orbit_compare_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final left = File('${dir.path}/there.png')
        ..writeAsBytesSync(encodeOrbitPng(image(8, 8)));
      expect(
        () => compareOrbitPngFiles(left.path, '${dir.path}/not-there.png'),
        throwsA(
          isA<OrbitCompareException>()
              .having((e) => e.message, 'message', contains('flutter')),
        ),
      );
    });

    test('a file that is not a PNG', () {
      final dir = Directory.systemTemp.createTempSync('orbit_compare_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bad = File('${dir.path}/bad.png')
        ..writeAsStringSync('this is not a PNG, it is a sentence');
      expect(
        () => readOrbitPngFile(bad.path),
        throwsA(
          isA<OrbitCompareException>()
              .having((e) => e.message, 'message', contains('not a readable PNG'))
              .having((e) => e.message, 'message', contains('bad.png')),
        ),
      );
    });

    test('an empty file', () {
      final dir = Directory.systemTemp.createTempSync('orbit_compare_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final empty = File('${dir.path}/empty.png')..writeAsBytesSync(<int>[]);
      expect(
        () => readOrbitPngFile(empty.path),
        throwsA(isA<OrbitCompareException>().having(
          (e) => e.message,
          'message',
          contains('too short'),
        )),
      );
    });
  });

  group('the same comparison through files', () {
    test('two identical files score zero, two that differ do not', () {
      final dir = Directory.systemTemp.createTempSync('orbit_compare_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final original = image(60, 40);
      final changed = withOnePixelChanged(original, pixel: 100);
      final a = File('${dir.path}/a.png')
        ..writeAsBytesSync(encodeOrbitPng(original));
      final b = File('${dir.path}/b.png')
        ..writeAsBytesSync(encodeOrbitPng(original));
      final c = File('${dir.path}/c.png')
        ..writeAsBytesSync(encodeOrbitPng(changed));

      expect(compareOrbitPngFiles(a.path, b.path).score, 0.0);
      expect(compareOrbitPngFiles(a.path, c.path).differingPixels, 1);
    });
  });
}