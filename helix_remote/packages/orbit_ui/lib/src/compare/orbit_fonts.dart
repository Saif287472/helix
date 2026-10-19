/// Loading the bundled fonts into a test's font collection, and refusing to
/// carry on if they did not land.
///
/// This is the step that makes the compare tool honest. A `flutter test` does
/// not register the fonts its own `pubspec.yaml` declares: text falls back to
/// the test font, every glyph becomes a filled box, and the resulting
/// screenshot differs from the prototype across every character. That failure
/// is invisible in a diff - it just looks like a port with the wrong typeface -
/// so the loader here **throws** rather than returning and letting the caller
/// shoot a screenshot in the fallback font.
library;

import 'dart:ui' as ui;

import 'package:flutter/services.dart' show FontLoader, rootBundle;

/// The font families `orbit_ui` bundles, and the assets each one is loaded
/// from.
///
/// The families are the two built-in themes' families, declared in
/// `orbit_ui/pubspec.yaml`. The asset keys are exactly what that file declares,
/// which is what `rootBundle` keys a package's own assets by. Both are
/// variable fonts covering wght 100-900; a weight other than the file's default
/// is reached with `fontVariations: [FontVariation('wght', n)]`, exactly as
/// the app does it, so the render and the app draw the same glyphs.
const Map<String, List<String>> orbitBundledFonts = <String, List<String>>{
  'Geist': <String>['fonts/Geist[wght].ttf', 'fonts/Geist-Italic[wght].ttf'],
  'Geist Mono': <String>[
    'fonts/GeistMono[wght].ttf',
    'fonts/GeistMono-Italic[wght].ttf',
  ],
};

/// Thrown when a bundled font cannot be loaded, or loaded and still not the
/// font the text asked for.
///
/// Both are the same failure - a screenshot in the wrong typeface - so they are
/// one exception type, and neither is ever ignored.
final class OrbitFontException implements Exception {
  OrbitFontException(this.message);

  final String message;

  @override
  String toString() => 'OrbitFontException: $message';
}

/// Loads every family in [orbitBundledFonts] into the current font collection.
///
/// Call it inside `tester.runAsync`, because loading reads the asset bundle:
///
/// ```dart
/// await tester.runAsync(loadOrbitBundledFonts);
/// ```
///
/// It throws [OrbitFontException] if an asset is missing or unreadable, and if
/// a family is loaded and still measures exactly like a family that does not
/// exist. The second check is the important one: `FontLoader.load` completes
/// happily even when the bytes were not a font at all, and a silent fallback is
/// the failure mode this whole tool is built to prevent.
Future<void> loadOrbitBundledFonts({
  Map<String, List<String>> families = orbitBundledFonts,
}) async {
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final asset in entry.value) {
      try {
        loader.addFont(rootBundle.load(asset));
      } on Object catch (e) {
        throw OrbitFontException(
          'cannot add $asset to the ${entry.key} family ($e). The asset key '
          'must be the one orbit_ui/pubspec.yaml declares.',
        );
      }
    }
    try {
      await loader.load();
    } on Object catch (e) {
      throw OrbitFontException('the ${entry.key} family did not load ($e)');
    }
    if (!orbitFamilyIsReallyLoaded(entry.key)) {
      throw OrbitFontException(
        'the ${entry.key} family loaded but text still measures exactly like '
        'the fallback, so the render would be a screenshot in the wrong '
        'typeface. Check the asset keys in orbitBundledFonts against '
        'orbit_ui/pubspec.yaml.',
      );
    }
  }
}

/// Whether [family] is really in the font collection, or only in the pubspec.
///
/// The test is a measurement, not a flag lookup: a string is laid out in
/// [family] and in a family name nothing can possibly have, and if the two
/// come out the same width then the first one is falling back. The fallback
/// font in a widget test draws every glyph as a filled box, so any real
/// typeface has a different advance width from it.
///
/// This costs two paragraph layouts. It is the only check in the render step
/// that can tell "the fonts loaded" from "the fonts claimed to load".
bool orbitFamilyIsReallyLoaded(
  String family, {
  String sample = 'Handgloves 0123 Mm',
  double fontSize = 40,
}) {
  double widthOf(String name) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontFamily: name, fontSize: fontSize),
    )..addText(sample);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 4000));
    final width = paragraph.maxIntrinsicWidth;
    paragraph.dispose();
    return width;
  }

  final real = widthOf(family);
  final missing = widthOf('__orbit_no_such_family__');
  return real != missing;
}
