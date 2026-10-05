import 'dart:typed_data';
import 'dart:ui' as ui;

/// A picture decoded to pixels: four bytes per pixel, red first, with
/// premultiplied alpha (what Flutter's `rawRgba` is).
final class DecodedPixels {
  const DecodedPixels({
    required this.rgba,
    required this.width,
    required this.height,
  });

  final Uint8List rgba;
  final int width;
  final int height;
}

/// Turns encoded picture bytes into pixels no larger than a given size.
///
/// An interface so thumbnail logic runs in a test on generated pixels. The
/// real one decodes on the engine's own thread and scales *while* decoding, so
/// a 12-megapixel photo never exists in memory at full size.
abstract interface class PixelDecoder {
  /// Pixels of [encoded] scaled so the long side is at most [maxSide], or
  /// null when the bytes are not a picture the platform can decode.
  Future<DecodedPixels?> decode(Uint8List encoded, {required int maxSide});
}

/// The platform's codecs, through `dart:ui`.
final class UiPixelDecoder implements PixelDecoder {
  const UiPixelDecoder();

  @override
  Future<DecodedPixels?> decode(
    Uint8List encoded, {
    required int maxSide,
  }) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width;
      final h = descriptor.height;
      if (w <= 0 || h <= 0) return null;
      final landscape = w >= h;
      final long = landscape ? w : h;
      codec = await descriptor.instantiateCodec(
        targetWidth: long > maxSide && landscape ? maxSide : null,
        targetHeight: long > maxSide && !landscape ? maxSide : null,
      );
      image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return null;
      return DecodedPixels(
        rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        width: image.width,
        height: image.height,
      );
    } on Object {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}
