/// Turning a pumped widget into a PNG on disk.
///
/// The Flutter half of the compare tool. It photographs a widget the caller
/// has already built, at exactly the size the HTML half used, and writes a file
/// the compare page can load. The widget comes from the caller on purpose:
/// Phase 4 adds one compare test per screen key, and every one of them is the
/// same call around a different `Screen`.
///
/// **This half is deterministic in a way the HTML half cannot be, and that
/// matters.** A test pumps a fixed number of frames and captures the result;
/// there is no "wait until it looks settled" heuristic and no animation caught
/// at an arbitrary point in a loop. Anything that animates has to be given a
/// fixed end state by the screen under test, which is a rule the port should
/// want anyway.
///
/// `dart:ui` and `widgets` are the only Flutter dependencies, so none of this
/// needs `flutter_test`. The test binding sets the surface size; everything
/// after that is the same code the app runs.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:orbit_ui/src/compare/orbit_artefacts.dart';
import 'package:orbit_ui/src/compare/orbit_devices.dart';
import 'package:orbit_ui/src/compare/orbit_png.dart';

/// Thrown when a render cannot produce a screenshot.
///
/// The size check is the one that matters most. `RepaintBoundary.toImage`
/// happily returns whatever the widget's box turned out to be - a screen that
/// laid out at 412x700, or one with no constraints at all - and a screenshot at
/// the wrong size would then be compared against the prototype's and score as
/// if the whole screen were wrong. Better to stop.
final class OrbitShotException implements Exception {
  OrbitShotException(this.message);

  final String message;

  @override
  String toString() => 'OrbitShotException: $message';
}

/// What [writeOrbitShot] produced.
final class OrbitShotFile {
  OrbitShotFile({required this.path, required this.bytes, required this.image});

  /// Where the PNG was written.
  final String path;

  /// Its size on disk.
  final int bytes;

  /// The flattened image it was written from.
  final OrbitImage image;

  /// How many distinct colours the shot has. One means nothing was drawn.
  int get distinctColours => image.distinctColours();
}

/// The key the caller puts on the `RepaintBoundary` it wants photographed.
///
/// There is no way to photograph "whatever is on screen" from here, so the
/// boundary is named: [orbitShotBoundary] gives the widget one name and
/// [captureOrbitShot] finds it again through the same key.
class OrbitShotBoundary extends StatelessWidget {
  const OrbitShotBoundary({
    super.key,
    required this.shotKey,
    required this.child,
  });

  /// The key this boundary is found by. Pass the same one to
  /// [captureOrbitShot].
  final GlobalKey shotKey;

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(key: shotKey, child: child);
}

/// The app shell a compare render needs.
///
/// The only reason this exists is `debugShowCheckedModeBanner`, which Flutter
/// 3.44 has no global for: `MaterialApp` draws a red "DEBUG" ribbon across the
/// top right of a debug build unless it is told not to, and in a screenshot
/// that ribbon is a difference nobody designed. A screen under comparison is
/// wrapped in this rather than in a bare `MaterialApp`, so the ribbon cannot be
/// forgotten.
///
/// [screen] is the screen itself, not a route: a compare render photographs one
/// screen, and a router would put a transition or a back arrow in the shot that
/// the prototype never had.
Widget orbitShotApp({
  required Widget screen,
  required ThemeData theme,
  Locale? locale,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: theme,
  locale: locale,
  home: screen,
);

/// Photographs whatever [shotKey] wraps, at exactly [device].
///
/// The pixel ratio is fixed at 1.0 and is not a parameter: one Flutter logical
/// pixel must be one image pixel must be one CSS pixel, which is the only way a
/// screenshot of the Flutter side can mean anything next to a screenshot of the
/// prototype. A shot at a ratio of 2 or 3 would be a different image, not a
/// sharper one.
///
/// Throws [OrbitShotException] when the boundary is not laid out or painted, or
/// when the captured image is not exactly [device].
Future<ui.Image> captureOrbitShot(
  GlobalKey shotKey, {
  required OrbitDevice device,
  double pixelRatio = 1.0,
}) async {
  if (pixelRatio != 1.0) {
    throw ArgumentError.value(
      pixelRatio,
      'pixelRatio',
      'the compare tool only renders at 1.0; anything else changes what a '
          'pixel is',
    );
  }
  final context = shotKey.currentContext;
  if (context == null) {
    throw OrbitShotException(
      'nothing is mounted at this key. Pump the widget before capturing it.',
    );
  }
  final object = context.findRenderObject();
  if (object is! RenderRepaintBoundary) {
    throw OrbitShotException(
      'the key is on a ${object.runtimeType}, not a RepaintBoundary. Wrap the '
      'screen in OrbitShotBoundary.',
    );
  }
  // `debugNeedsPaint` exists only in debug builds; a profile build skips the
  // check rather than throwing.
  if (kDebugMode && object.debugNeedsPaint) {
    // Capturing mid-frame photographs whatever was on the canvas before the
    // last layout, which is how a shot ends up half a screen tall.
    throw OrbitShotException(
      'the widget has not been painted yet. Pump it, then pump once more so '
      'the frame is on the canvas.',
    );
  }
  if (!object.hasSize) {
    throw OrbitShotException(
      'the widget has no size, so there is nothing to photograph.',
    );
  }

  final ui.Image image;
  try {
    image = await object.toImage(pixelRatio: 1.0);
  } on Object catch (e) {
    throw OrbitShotException('the surface could not be photographed ($e)');
  }

  if (image.width != device.width || image.height != device.height) {
    final width = image.width;
    final height = image.height;
    image.dispose();
    throw OrbitShotException(
      'the shot is ${width}x$height but $device is ${device.width}x'
      '${device.height}. Set the surface to exactly ${device.width}x'
      '${device.height} at a pixel ratio of 1.0 before pumping; a widget that '
      'cannot fill that space is a bug in the screen.',
    );
  }
  return image;
}

/// Photographs [shotKey] and writes the PNG to `<outDir>/<fileName>`.
///
/// The image is flattened onto an opaque backdrop first, so the file is 8-bit
/// RGBA with no transparency and cannot compare differently against a browser
/// screenshot for a reason nobody can see.
///
/// [allowUniform] exists for one reason: a capture that came out as a single
/// flat colour almost certainly means nothing was drawn - the widget threw, the
/// tree was empty, or a theme loaded with every token missing. Left at the
/// default that is an error, because a blank screenshot would still produce a
/// PNG and would show up on the compare page as a screen that is merely very
/// wrong. No Orbit screen is one flat colour, and if one ever were, the caller
/// can say so.
Future<OrbitShotFile> writeOrbitShot(
  ui.Image image, {
  required String outDir,
  required String fileName,
  int backdrop = orbitBackdrop,
  bool allowUniform = false,
}) async {
  final width = image.width;
  final height = image.height;
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawStraightRgba,
  );
  image.dispose();
  if (data == null) {
    throw OrbitShotException('the captured surface could not be read back');
  }
  final raw = Uint8List.view(
    data.buffer,
    data.offsetInBytes,
    data.lengthInBytes,
  );
  if (raw.length != width * height * 4) {
    throw OrbitShotException(
      'the engine returned ${raw.length} bytes for a ${width}x$height image',
    );
  }

  final flattened = flattenOrbitImage(
    OrbitImage(width: width, height: height, pixels: Uint8List.fromList(raw)),
    backdrop: backdrop,
  );
  final colours = flattened.distinctColours();
  if (colours <= 1 && !allowUniform) {
    throw OrbitShotException(
      'the shot is one flat colour, so nothing was drawn. A widget that threw '
      'during build, an empty tree and a theme with no tokens all look like '
      'this. Pass allowUniform: true only if a screen really is one colour.',
    );
  }

  final file = File(
    outDir.endsWith('/') ? '$outDir/$fileName' : '$outDir/$fileName',
  );
  file.parent.createSync(recursive: true);
  final bytes = encodeOrbitPng(flattened);
  file.writeAsBytesSync(bytes);
  return OrbitShotFile(path: file.path, bytes: bytes.length, image: flattened);
}
