import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/compare.dart';

/// The shot writer, without rendering a screen.
///
/// Screens are photographed by the preview app's shoot mode
/// (`apps/orbit_preview/lib/shoot.dart`), in the real engine with real fonts.
/// A widget test could not do it: `toImage` and font loading wait on the real
/// event loop, and under `testWidgets`' fake clock they never finished (the
/// hang that had this file's predecessor switched off). So these are plain
/// `test`s on the parts that do not need a screen: the fonts, the pixel-ratio
/// rule, and what `writeOrbitShot` makes of an image.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// A [width]x[height] image from raw RGBA bytes, via the engine.
  Future<ui.Image> image(int width, int height, Uint8List rgba) {
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return done.future;
  }

  Uint8List gradient(int width, int height) {
    final px = Uint8List(width * height * 4);
    for (var i = 0; i < width * height; i++) {
      px[i * 4] = i % 256;
      px[i * 4 + 1] = (i ~/ width) % 256;
      px[i * 4 + 2] = 128;
      px[i * 4 + 3] = 255;
    }
    return px;
  }

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('orbit_shot_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the bundled fonts load, and they are the real ones', () async {
    await loadOrbitBundledFonts();
    for (final family in orbitBundledFonts.keys) {
      expect(orbitFamilyIsReallyLoaded(family), isTrue, reason: family);
    }
    expect(
      orbitBundledFonts.keys,
      containsAll(<String>['Geist', 'Geist Mono']),
    );
  });

  test('a family that was never loaded does not claim to be loaded', () {
    // Otherwise the check above could not fail, and would prove nothing.
    expect(orbitFamilyIsReallyLoaded('__orbit_nope__'), isFalse);
  });

  test('a pixel ratio other than 1 is refused', () {
    expect(
      () => captureOrbitShot(
        GlobalKey(),
        device: OrbitDevice.phone,
        pixelRatio: 2,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a capture with nothing mounted is an error, not an empty file', () {
    expect(
      () => captureOrbitShot(GlobalKey(), device: OrbitDevice.phone),
      throwsA(isA<OrbitShotException>()),
    );
  });

  test('a one-colour shot is refused: nothing was drawn', () async {
    final flat = Uint8List(40 * 30 * 4)..fillRange(0, 40 * 30 * 4, 200);
    await expectLater(
      writeOrbitShot(
        await image(40, 30, flat),
        outDir: dir.path,
        fileName: 'flat.png',
      ),
      throwsA(isA<OrbitShotException>()),
    );
    expect(File('${dir.path}/flat.png').existsSync(), isFalse);
  });

  test(
    'a shot is written at its size, opaque, and the same bytes twice',
    () async {
      final px = gradient(40, 30);
      final a = await writeOrbitShot(
        await image(40, 30, px),
        outDir: dir.path,
        fileName: 'a.png',
      );
      final b = await writeOrbitShot(
        await image(40, 30, px),
        outDir: dir.path,
        fileName: 'b.png',
      );

      final back = decodeOrbitPng(File(a.path).readAsBytesSync());
      expect((back.width, back.height), (40, 30));
      for (var i = 3; i < back.pixels.length; i += 4) {
        expect(back.pixels[i], 255, reason: 'pixel ${i ~/ 4} is not opaque');
      }
      expect(back.pixels, orderedEquals(px));
      // A tool whose own output changes between runs makes every difference
      // look new.
      expect(
        File(a.path).readAsBytesSync(),
        orderedEquals(File(b.path).readAsBytesSync()),
      );
    },
  );
}
