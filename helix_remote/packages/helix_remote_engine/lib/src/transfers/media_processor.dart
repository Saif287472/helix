import 'dart:typed_data';

import 'package:helix_remote_engine/src/transfers/blob_store.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show MediaItemKind;
import 'package:meta/meta.dart';

/// What a [MediaProcessor] learned about a file.
@immutable
final class ProcessedMedia {
  const ProcessedMedia({
    this.width,
    this.height,
    this.durationMs,
    this.blurhash,
    this.thumbnail,
    this.waveform,
  });

  /// Nothing known: the item is sent as a plain file.
  static const none = ProcessedMedia();

  final int? width;
  final int? height;
  final int? durationMs;

  /// A compact placeholder shown before the image has loaded.
  final String? blurhash;

  /// A small preview (JPEG, PNG or WebP bytes), sent as its own encrypted
  /// object so the receiver can show it before (or without) the full file.
  final Uint8List? thumbnail;

  /// Voice notes: one byte (0-255) per sample.
  final Uint8List? waveform;
}

/// Looks inside a media file: dimensions, duration, a thumbnail, a blurhash.
///
/// The engine has no image or video code (it is pure Dart); the app supplies
/// one over Flutter's codecs and the platform's media APIs. [path] is a path
/// in the engine's [BlobStore]; for a file-backed store it names a real file.
/// A processor that cannot read a file returns [ProcessedMedia.none] rather
/// than failing: the file is then sent without previews.
abstract interface class MediaProcessor {
  Future<ProcessedMedia> process({
    required String path,
    required MediaItemKind kind,
    required String mime,
  });
}

/// A pure-Dart default: image dimensions from the PNG, GIF, JPEG and WebP
/// headers; no thumbnails, blurhash or durations. Good enough for the CLI
/// and tests, and a safe fallback when the app supplies no processor.
final class BasicMediaProcessor implements MediaProcessor {
  const BasicMediaProcessor(this._blobs);

  final BlobStore _blobs;

  /// Enough for any header, and for the EXIF block in front of a JPEG's
  /// frame header.
  static const _peek = 256 * 1024;

  @override
  Future<ProcessedMedia> process({
    required String path,
    required MediaItemKind kind,
    required String mime,
  }) async {
    if (kind != MediaItemKind.image &&
        kind != MediaItemKind.gif &&
        kind != MediaItemKind.video) {
      return ProcessedMedia.none;
    }
    final size = await _blobs.length(path);
    if (size == null || size < 12) return ProcessedMedia.none;
    final head = await _blobs.readBytes(path, end: size < _peek ? size : _peek);
    final dims = imageSize(head);
    return dims == null
        ? ProcessedMedia.none
        : ProcessedMedia(width: dims.$1, height: dims.$2);
  }

  /// `(width, height)` of a PNG, GIF, JPEG or WebP, or null.
  static (int, int)? imageSize(Uint8List b) {
    if (b.length >= 24 && _is(b, 0, const [0x89, 0x50, 0x4E, 0x47])) {
      final d = ByteData.sublistView(b);
      return (d.getUint32(16), d.getUint32(20));
    }
    if (b.length >= 10 && _is(b, 0, const [0x47, 0x49, 0x46, 0x38])) {
      final d = ByteData.sublistView(b);
      return (d.getUint16(6, Endian.little), d.getUint16(8, Endian.little));
    }
    if (b.length >= 4 && b[0] == 0xFF && b[1] == 0xD8) return _jpeg(b);
    if (b.length >= 30 &&
        _is(b, 0, const [0x52, 0x49, 0x46, 0x46]) &&
        _is(b, 8, const [0x57, 0x45, 0x42, 0x50])) {
      return _webp(b);
    }
    return null;
  }

  static (int, int)? _jpeg(Uint8List b) {
    final d = ByteData.sublistView(b);
    var at = 2;
    while (at + 9 < b.length) {
      if (b[at] != 0xFF) return null;
      final marker = b[at + 1];
      if (marker == 0xFF) {
        at++;
        continue;
      }
      // Frame headers: SOF0-3, 5-7, 9-11, 13-15.
      final isFrame =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isFrame) return (d.getUint16(at + 7), d.getUint16(at + 5));
      if (marker == 0xD9 || marker == 0xDA) return null;
      at += 2 + d.getUint16(at + 2);
    }
    return null;
  }

  static (int, int)? _webp(Uint8List b) {
    final d = ByteData.sublistView(b);
    final kind = String.fromCharCodes(b.sublist(12, 16));
    switch (kind) {
      case 'VP8X':
        final w = 1 + (b[24] | b[25] << 8 | b[26] << 16);
        final h = 1 + (b[27] | b[28] << 8 | b[29] << 16);
        return (w, h);
      case 'VP8L':
        final bits = d.getUint32(21, Endian.little);
        return (1 + (bits & 0x3FFF), 1 + ((bits >> 14) & 0x3FFF));
      case 'VP8 ':
        return (
          d.getUint16(26, Endian.little) & 0x3FFF,
          d.getUint16(28, Endian.little) & 0x3FFF,
        );
    }
    return null;
  }

  static bool _is(Uint8List b, int at, List<int> magic) {
    for (var i = 0; i < magic.length; i++) {
      if (b[at + i] != magic[i]) return false;
    }
    return true;
  }
}
