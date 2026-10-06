import 'dart:typed_data';

import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail_platform_interface.dart'
    show FcVideoThumbnailTime, FcVideoThumbnailTimeUnit;

/// One still picture out of a video file.
///
/// An interface so [FlutterMediaProcessor] is tested with a list of bytes, and
/// so a platform without the native extractor (or a video it cannot read)
/// simply has no thumbnail: the video is then sent with only its size and
/// length.
abstract interface class VideoFrameSource {
  /// A JPEG of the frame at [at] (the first frame when null) of the video at
  /// [path], scaled to fit [maxSide] pixels on the long side. Null when it
  /// cannot be read; never throws.
  Future<Uint8List?> frame(String path, {required int maxSide, Duration? at});
}

/// The native frame extractor (`MediaMetadataRetriever` on Android, Media
/// Foundation on Windows), through `fc_native_video_thumbnail`.
final class NativeVideoFrameSource implements VideoFrameSource {
  const NativeVideoFrameSource();

  @override
  Future<Uint8List?> frame(
    String path, {
    required int maxSide,
    Duration? at,
  }) async {
    try {
      final bytes = await FcNativeVideoThumbnail().saveThumbnailToBytes(
        srcFile: path,
        width: maxSide,
        height: maxSide,
        format: 'jpeg',
        quality: 70,
        at: at == null
            ? null
            : FcVideoThumbnailTime(
                at.inMilliseconds,
                FcVideoThumbnailTimeUnit.milliseconds,
              ),
      );
      return bytes == null || bytes.isEmpty ? null : bytes;
    } on Object {
      // No extractor on this platform, or a file it cannot read.
      return null;
    }
  }
}
