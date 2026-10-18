/// The three pictures a comparison leaves behind.
///
/// The point of the compare page is that a person puts the prototype and the
/// Flutter render next to each other and looks. These are the pictures it
/// needs: the prototype on its own (the HTML half's file), the Flutter render
/// on its own (the render's file), and the two derived views here.
///
/// Every function is a pure function of its inputs. Same images in, same bytes
/// out - no clock, no random, no machine name.
library;

import 'dart:typed_data';

import 'package:orbit_ui/src/compare/orbit_png.dart';

/// The backdrop a comparison composites against before it writes anything.
///
/// Screenshots of a screen are opaque, so this only ever matters for an image
/// that carries real alpha. White is the choice because it is what a browser
/// shows for an unpainted area and because a colour that is not the backdrop
/// cannot be confused with it.
const int orbitBackdrop = 0xFFFFFFFF;

/// Draws the difference heat map: a pale ghost of the prototype with every
/// differing pixel marked in a yellow-to-red ramp.
///
/// The ghost matters as much as the marks. A heat map on its own says
/// *where*, but not *against what*; a pale version of the prototype underneath
/// says where and lets the eye line the marks up with the layout. Equal pixels
/// are the prototype's own luminance mixed half way to white, so a saturated
/// mark cannot be mistaken for a saturated area of the design.
///
/// [deltaOf] gives the largest channel difference at a pixel, 0 to 255, and is
/// the same number [OrbitImageDiff.maxChannelDelta] is built from. A pixel it
/// returns 0 for is drawn as background.
///
/// The ramp is [0xFFFF00] at a delta of 1 through [0xFF0000] at 255: yellow
/// means "this pixel moved a little", red means "this pixel is wrong".
OrbitImage orbitDiffHeatMap(
  OrbitImage prototype,
  OrbitImage flutter, {
  required int Function(int pixelIndex) deltaOf,
}) {
  final out = Uint8List(prototype.pixels.length);
  for (var p = 0; p < prototype.pixelCount; p++) {
    final o = p * 4;
    final delta = deltaOf(p);
    if (delta <= 0) {
      final luma =
          (77 * prototype.pixels[o] +
              150 * prototype.pixels[o + 1] +
              29 * prototype.pixels[o + 2]) >>
          8;
      // Half way to white, which leaves the layout readable and every mark
      // unmistakable.
      final grey = (luma + 255) >> 1;
      out[o] = grey;
      out[o + 1] = grey;
      out[o + 2] = grey;
      out[o + 3] = 255;
    } else {
      out[o] = 255;
      out[o + 1] = 255 - delta;
      out[o + 2] = 0;
      out[o + 3] = 255;
    }
  }
  return OrbitImage(
    width: prototype.width,
    height: prototype.height,
    pixels: out,
  );
}

/// Blends the two sides into one image, for the overlay slider.
///
/// [mix] is how much of the **Flutter** render shows: 0 is the prototype
/// alone, 1 is Flutter alone, and the default 0.5 is the picture worth
/// looking at first. The formula is the plain weighted mean of the two
/// flattened images, `round((1 - mix) * prototype + mix * flutter)`, per
/// channel, with the result fully opaque.
///
/// The compare page does not have to use this: stacking the two source PNGs on
/// top of each other and clipping the top one at the slider position is the
/// usual way to build a reveal slider and it is lossless. This is here for the
/// cases where a single blended file is wanted - a thumbnail, a viewer's
/// fallback, or a page that wants one file per step of the slider - and for
/// the reference implementation of what "mix" means. Any [mix] outside 0 to 1
/// is an error rather than a clamp, because a clamped mix would produce a
/// picture that is not what the caller asked for.
OrbitImage orbitOverlay(
  OrbitImage prototype,
  OrbitImage flutter, {
  double mix = 0.5,
}) {
  if (mix < 0.0 || mix > 1.0) {
    throw ArgumentError.value(mix, 'mix', 'between 0 and 1');
  }
  if (prototype.width != flutter.width || prototype.height != flutter.height) {
    throw ArgumentError(
      'the two sides are ${prototype.width}x${prototype.height} and '
      '${flutter.width}x${flutter.height}; there is nothing to blend',
    );
  }
  final out = Uint8List(prototype.pixels.length);
  final t = (mix * 1024).round();
  for (var i = 0; i < out.length; i += 4) {
    for (var c = 0; c < 3; c++) {
      final a = prototype.pixels[i + c];
      final b = flutter.pixels[i + c];
      out[i + c] = (((1024 - t) * a + t * b) / 1024).round().clamp(0, 255);
    }
    out[i + 3] = 255;
  }
  return OrbitImage(
    width: prototype.width,
    height: prototype.height,
    pixels: out,
  );
}

/// Flattens [image] onto [backdrop], so anything this tool writes is opaque.
///
/// A `RepaintBoundary` over a Scaffold is opaque already; this only does
/// anything for a screen with a deliberately transparent background, and it
/// makes that explicit rather than leaving an alpha channel that would compare
/// differently against a browser screenshot for no visible reason.
OrbitImage flattenOrbitImage(OrbitImage image, {int backdrop = orbitBackdrop}) {
  final r = (backdrop >> 16) & 0xFF;
  final g = (backdrop >> 8) & 0xFF;
  final b = backdrop & 0xFF;
  final out = Uint8List(image.pixels.length);
  for (var i = 0; i < out.length; i += 4) {
    final a = image.pixels[i + 3];
    if (a == 255) {
      out[i] = image.pixels[i];
      out[i + 1] = image.pixels[i + 1];
      out[i + 2] = image.pixels[i + 2];
    } else {
      // Straight alpha over an opaque backdrop.
      final inv = 255 - a;
      out[i] = (image.pixels[i] * a + r * inv) ~/ 255;
      out[i + 1] = (image.pixels[i + 1] * a + g * inv) ~/ 255;
      out[i + 2] = (image.pixels[i + 2] * a + b * inv) ~/ 255;
    }
    out[i + 3] = 255;
  }
  return OrbitImage(width: image.width, height: image.height, pixels: out);
}
