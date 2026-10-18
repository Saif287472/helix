import 'dart:io';
import 'dart:typed_data';

import 'package:orbit_ui/src/compare/orbit_png.dart';

/// Thrown when a comparison cannot happen.
///
/// Every one of these is a hard stop, never a warning and never a score:
/// a missing file, an unreadable PNG, two images of different sizes. The
/// reason this tool exists is that "looks roughly right" passed once because
/// nobody could see the difference; a comparison that silently did not happen
/// is the same failure with extra steps.
final class OrbitCompareException implements Exception {
  OrbitCompareException(this.message);

  final String message;

  @override
  String toString() => 'OrbitCompareException: $message';
}

/// What one comparison found.
///
/// The score is exactly one number, and it is the plain percentage of pixels
/// that are not byte-identical between the two images:
///
/// ```text
/// score = differingPixels / (width * height) * 100
/// ```
///
/// There is no tolerance, no anti-aliasing allowance and no "close enough"
/// band: a pixel counts if a single one of its four channel bytes differs. Any
/// of those would hide a difference, and a tool whose job is to show differences
/// must not have a dial that hides them.
///
/// **A non-zero score is normal and expected.** Chrome and Flutter shape the
/// same glyph with different rasterisers, hint one pixel apart, and round colour
/// blurs differently, so a screen that is correct to the eye still scores in
/// the low tens of a percent. The score is a triage number that flags a screen
/// for a person's eye, not a pass mark. The compare page sorts worst first for
/// exactly that reason, and "a screen is done" is decided by eye on the compare
/// page plus the widget tests, never by a threshold in here.
final class OrbitImageDiff {
  OrbitImageDiff({
    required this.width,
    required this.height,
    required this.differingPixels,
    required this.differingChannels,
    required this.maxChannelDelta,
    required this.totalChannelDelta,
  });

  final int width;
  final int height;

  /// Pixels where at least one of R, G, B or A differs.
  final int differingPixels;

  /// Individual channel bytes that differ, out of `width * height * 4`. Only
  /// reported, never scored: it says how *loudly* two images differ, which is
  /// a different question from how many pixels moved.
  final int differingChannels;

  /// The largest single-channel difference anywhere, 0-255.
  final int maxChannelDelta;

  /// The sum of every channel difference, for a mean. Reported, not scored.
  final int totalChannelDelta;

  int get totalPixels => width * height;

  /// The plain percentage of differing pixels, 0 to 100.
  double get score => differingPixels * 100.0 / totalPixels;

  /// The mean channel difference over every channel, 0 to 255.
  double get meanChannelDelta => totalChannelDelta / (totalPixels * 4.0);

  /// The score rounded the way it is written to JSON, so two runs of the same
  /// comparison produce the same bytes in `results.json`.
  double get roundedScore => (score * 1000000).roundToDouble() / 1000000;

  @override
  String toString() =>
      'OrbitImageDiff($width x $height, $differingPixels/$totalPixels pixels '
      'differ, ${roundedScore.toStringAsFixed(4)}%)';
}

/// Compares two images of the same size.
///
/// Throws [OrbitCompareException] naming **both** sizes when they differ. It
/// never resizes, never crops, never pads and never compares a region: if the
/// two sides are not the same shape, the port drew the wrong window and a
/// resized comparison would report it as "looks nearly right".
///
/// [left] and [right] are the prototype and the Flutter render, in that order,
/// so [diffPixels] is "what is different in Flutter relative to the
/// prototype".
OrbitImageDiff compareOrbitImages(
  OrbitImage left,
  OrbitImage right, {
  String leftName = 'left',
  String rightName = 'right',
}) {
  if (left.width != right.width || left.height != right.height) {
    throw OrbitCompareException(
      '$leftName is ${left.width}x${left.height} and $rightName is '
      '${right.width}x${right.height}; a comparison needs the same size on '
      'both sides. The compare tool does not resize, so re-shoot both sides at '
      'the same device.',
    );
  }
  var differingPixels = 0;
  var differingChannels = 0;
  var maxDelta = 0;
  var totalDelta = 0;
  final n = left.pixels.length;
  for (var i = 0; i < n; i++) {
    final a = left.pixels[i];
    final b = right.pixels[i];
    if (a == b) continue;
    final delta = a > b ? a - b : b - a;
    differingChannels++;
    totalDelta += delta;
    if (delta > maxDelta) maxDelta = delta;
  }
  for (var i = 0; i < n; i += 4) {
    if (left.pixels[i] != right.pixels[i] ||
        left.pixels[i + 1] != right.pixels[i + 1] ||
        left.pixels[i + 2] != right.pixels[i + 2] ||
        left.pixels[i + 3] != right.pixels[i + 3]) {
      differingPixels++;
    }
  }
  return OrbitImageDiff(
    width: left.width,
    height: left.height,
    differingPixels: differingPixels,
    differingChannels: differingChannels,
    maxChannelDelta: maxDelta,
    totalChannelDelta: totalDelta,
  );
}

/// Reads two PNG files and compares them.
///
/// The file names are only used in the error messages, so a failure says which
/// of the two files is missing or the wrong size rather than which index.
OrbitImageDiff compareOrbitPngFiles(
  String leftPath,
  String rightPath, {
  String leftName = 'prototype',
  String rightName = 'flutter',
}) => compareOrbitImages(
  readOrbitPngFile(leftPath, name: leftName),
  readOrbitPngFile(rightPath, name: rightName),
  leftName: '$leftName ($leftPath)',
  rightName: '$rightName ($rightPath)',
);

/// Reads a PNG from disk, or throws [OrbitCompareException].
///
/// A missing file is an error here, not an empty result: an empty result would
/// score as a 100% difference and put the screen at the top of the worst-first
/// list for the wrong reason, or - worse - be skipped silently.
OrbitImage readOrbitPngFile(String path, {String name = 'image'}) {
  final file = File(path);
  if (!file.existsSync()) {
    throw OrbitCompareException(
      '$name: no file at $path. The compare tool will not invent one; shoot '
      'the missing side first.',
    );
  }
  final Uint8List bytes;
  try {
    bytes = file.readAsBytesSync();
  } on Object catch (e) {
    throw OrbitCompareException('$name: cannot read $path ($e)');
  }
  try {
    return decodeOrbitPng(bytes, name: '$name ($path)');
  } on OrbitPngException catch (e) {
    throw OrbitCompareException(
      '$name at $path is not a readable PNG: ${e.message}',
    );
  }
}
