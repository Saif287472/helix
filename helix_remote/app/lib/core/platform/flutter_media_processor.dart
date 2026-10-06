import 'dart:io';
import 'dart:typed_data';

import 'package:helix_remote/core/platform/mp4_metadata.dart';
import 'package:helix_remote/core/platform/pixel_decoder.dart';
import 'package:helix_remote/core/platform/thumbnail_encoder.dart';
import 'package:helix_remote/core/platform/video_frames.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show BasicMediaProcessor, MediaProcessor, ProcessedMedia;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show MediaItemKind;

/// The engine's [MediaProcessor] for the app: what a chat shows before a photo
/// or video has arrived (a size, a BlurHash, a small JPEG, a length) worked out
/// on the phone with Flutter's codecs and the platform's frame extractor.
///
/// The engine hands it the path of its own copy of the file. This class only
/// reads it: stripping metadata happens *before* the engine copies a file (see
/// `MediaSanitizer`), because the engine records the copy's size first.
///
/// It never throws. A file it cannot read comes back as what little is known
/// (or [ProcessedMedia.none]) and is sent without previews, which is what the
/// engine's contract asks.
final class FlutterMediaProcessor implements MediaProcessor {
  FlutterMediaProcessor({
    PixelDecoder decoder = const UiPixelDecoder(),
    VideoFrameSource frames = const NativeVideoFrameSource(),
    ThumbnailEncoder encoder = const IsolateThumbnailEncoder(),
    this.thumbnailSide = 320,
  }) : _decoder = decoder,
       _frames = frames,
       _encoder = encoder;

  final PixelDecoder _decoder;
  final VideoFrameSource _frames;
  final ThumbnailEncoder _encoder;

  /// The long side of the thumbnail, in pixels. Its JPEG is a few kilobytes,
  /// far under the engine's limit for a thumbnail.
  final int thumbnailSide;

  /// Pictures larger than this are not decoded for a thumbnail (a decode of
  /// an image this big would cost more memory than the preview is worth).
  static const maxDecodeBytes = 96 * 1024 * 1024;

  @override
  Future<ProcessedMedia> process({
    required String path,
    required MediaItemKind kind,
    required String mime,
  }) async {
    try {
      return switch (kind) {
        MediaItemKind.image || MediaItemKind.gif => await _image(path),
        MediaItemKind.video => await _video(path),
        _ => ProcessedMedia.none,
      };
    } on Object {
      return ProcessedMedia.none;
    }
  }

  Future<ProcessedMedia> _image(String path) async {
    final file = File(path);
    final length = await file.length();
    final bytes = Uint8List.fromList(await file.readAsBytes());
    final header = BasicMediaProcessor.imageSize(
      Uint8List.sublistView(
        bytes,
        0,
        bytes.length < 262144 ? bytes.length : 262144,
      ),
    );
    if (length > maxDecodeBytes) {
      return _dimensions(header);
    }
    final pixels = await _decoder.decode(bytes, maxSide: thumbnailSide);
    if (pixels == null) return _dimensions(header);
    final EncodedThumbnail encoded;
    try {
      encoded = await _encoder.thumbnail(pixels);
    } on Object {
      return _dimensions(header);
    }
    final (width, height) = _shown(header, pixels);
    return ProcessedMedia(
      width: width,
      height: height,
      thumbnail: encoded.jpeg,
      blurhash: encoded.blurhash,
    );
  }

  Future<ProcessedMedia> _video(String path) async {
    final scan = await Mp4Metadata.scan(File(path));
    final info = scan?.info;
    final at = (info?.durationMs ?? 0) > 2000
        ? const Duration(seconds: 1)
        : null;
    final jpeg = await _frames.frame(path, maxSide: thumbnailSide, at: at);
    String? blurhash;
    (int, int)? frameSize;
    if (jpeg != null) {
      frameSize = BasicMediaProcessor.imageSize(jpeg);
      final pixels = await _decoder.decode(
        jpeg,
        maxSide: ThumbnailMath.blurSide,
      );
      if (pixels != null) {
        try {
          blurhash = await _encoder.blurhash(pixels);
        } on Object {
          blurhash = null;
        }
      }
    }
    final width = info?.width ?? frameSize?.$1;
    final height = info?.height ?? frameSize?.$2;
    return ProcessedMedia(
      width: width,
      height: height,
      durationMs: info?.durationMs,
      thumbnail: jpeg,
      blurhash: blurhash,
    );
  }

  ProcessedMedia _dimensions((int, int)? size) => size == null
      ? ProcessedMedia.none
      : ProcessedMedia(width: size.$1, height: size.$2);

  /// The size to report: the file's real size when its header says, with the
  /// *shape* (portrait or landscape) taken from the decoded thumbnail, since
  /// that is what the platform draws after it has applied the photo's
  /// orientation. Without a header, the thumbnail's own size.
  (int, int) _shown((int, int)? header, DecodedPixels thumb) {
    if (header == null) return (thumb.width, thumb.height);
    final long = header.$1 > header.$2 ? header.$1 : header.$2;
    final thumbLong = thumb.width > thumb.height ? thumb.width : thumb.height;
    final scale = long / thumbLong;
    return ((thumb.width * scale).round(), (thumb.height * scale).round());
  }
}
