import 'dart:isolate';
import 'dart:typed_data';

import 'package:helix_remote/core/platform/blurhash.dart';
import 'package:helix_remote/core/platform/pixel_decoder.dart';
import 'package:image/image.dart' as img;

/// A thumbnail ready to send, and the BlurHash drawn before it arrives.
final class EncodedThumbnail {
  const EncodedThumbnail({required this.jpeg, required this.blurhash});

  final Uint8List jpeg;
  final String blurhash;
}

/// Compresses decoded pixels into the small JPEG a chat sends as a preview and
/// computes the BlurHash. CPU work, so the real one runs off the UI isolate.
abstract interface class ThumbnailEncoder {
  /// A JPEG of [pixels] and the BlurHash of a 32-pixel copy of them.
  Future<EncodedThumbnail> thumbnail(DecodedPixels pixels);

  /// Only the BlurHash of [pixels] (a video frame already is a JPEG).
  Future<String> blurhash(DecodedPixels pixels);
}

/// [ThumbnailEncoder] in a background isolate.
final class IsolateThumbnailEncoder implements ThumbnailEncoder {
  const IsolateThumbnailEncoder({this.quality = 72});

  final int quality;

  @override
  Future<EncodedThumbnail> thumbnail(DecodedPixels pixels) {
    final quality = this.quality;
    return Isolate.run(() => ThumbnailMath.thumbnail(pixels, quality: quality));
  }

  @override
  Future<String> blurhash(DecodedPixels pixels) =>
      Isolate.run(() => ThumbnailMath.blurhash(pixels));
}

/// The same work on the calling isolate, for tests and tiny inputs.
final class InlineThumbnailEncoder implements ThumbnailEncoder {
  const InlineThumbnailEncoder({this.quality = 72});

  final int quality;

  @override
  Future<EncodedThumbnail> thumbnail(DecodedPixels pixels) async =>
      ThumbnailMath.thumbnail(pixels, quality: quality);

  @override
  Future<String> blurhash(DecodedPixels pixels) async =>
      ThumbnailMath.blurhash(pixels);
}

/// The pure functions behind both encoders (top-level work an isolate can
/// run: it captures only plain data).
abstract final class ThumbnailMath {
  /// How many pixels the long side of the BlurHash input has.
  static const blurSide = 32;

  static EncodedThumbnail thumbnail(DecodedPixels pixels, {int quality = 72}) {
    final rgb = flattenOnWhite(pixels);
    final image = img.Image.fromBytes(
      width: rgb.width,
      height: rgb.height,
      bytes: rgb.rgba.buffer,
      bytesOffset: rgb.rgba.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    final jpeg = Uint8List.fromList(img.encodeJpg(image, quality: quality));
    return EncodedThumbnail(jpeg: jpeg, blurhash: _hashOf(rgb));
  }

  static String blurhash(DecodedPixels pixels) =>
      _hashOf(flattenOnWhite(pixels));

  static String _hashOf(DecodedPixels rgb) {
    final small = shrink(rgb, blurSide);
    final landscape = small.width >= small.height;
    return Blurhash.encode(
      small.rgba,
      width: small.width,
      height: small.height,
      xComponents: landscape ? 4 : 3,
      yComponents: landscape ? 3 : 4,
    );
  }

  /// A full JPEG of [pixels] (a photo re-encoded because its own format could
  /// not be cleaned in place), over white where transparent.
  static Uint8List jpeg(DecodedPixels pixels, {int quality = 90}) {
    final rgb = flattenOnWhite(pixels);
    final image = img.Image.fromBytes(
      width: rgb.width,
      height: rgb.height,
      bytes: rgb.rgba.buffer,
      bytesOffset: rgb.rgba.offsetInBytes,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return Uint8List.fromList(img.encodeJpg(image, quality: quality));
  }

  /// Premultiplied pixels laid over white, so a transparent PNG does not turn
  /// black in a JPEG. A copy: the input is not changed.
  static DecodedPixels flattenOnWhite(DecodedPixels pixels) {
    final src = pixels.rgba;
    final out = Uint8List(pixels.width * pixels.height * 4);
    for (var i = 0; i + 3 < out.length; i += 4) {
      final inverse = 255 - src[i + 3];
      out[i] = (src[i] + inverse).clamp(0, 255);
      out[i + 1] = (src[i + 1] + inverse).clamp(0, 255);
      out[i + 2] = (src[i + 2] + inverse).clamp(0, 255);
      out[i + 3] = 255;
    }
    return DecodedPixels(rgba: out, width: pixels.width, height: pixels.height);
  }

  /// [pixels] reduced by averaging blocks so the long side is at most [side].
  static DecodedPixels shrink(DecodedPixels pixels, int side) {
    final long = pixels.width > pixels.height ? pixels.width : pixels.height;
    if (long <= side) return pixels;
    final w = (pixels.width * side / long).round().clamp(1, side);
    final h = (pixels.height * side / long).round().clamp(1, side);
    final out = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      final y0 = y * pixels.height ~/ h;
      final y1 = ((y + 1) * pixels.height ~/ h).clamp(y0 + 1, pixels.height);
      for (var x = 0; x < w; x++) {
        final x0 = x * pixels.width ~/ w;
        final x1 = ((x + 1) * pixels.width ~/ w).clamp(x0 + 1, pixels.width);
        var r = 0, g = 0, b = 0, a = 0;
        for (var yy = y0; yy < y1; yy++) {
          for (var xx = x0; xx < x1; xx++) {
            final i = (yy * pixels.width + xx) * 4;
            r += pixels.rgba[i];
            g += pixels.rgba[i + 1];
            b += pixels.rgba[i + 2];
            a += pixels.rgba[i + 3];
          }
        }
        final n = (y1 - y0) * (x1 - x0);
        final o = (y * w + x) * 4;
        out[o] = r ~/ n;
        out[o + 1] = g ~/ n;
        out[o + 2] = b ~/ n;
        out[o + 3] = a ~/ n;
      }
    }
    return DecodedPixels(rgba: out, width: w, height: h);
  }
}
