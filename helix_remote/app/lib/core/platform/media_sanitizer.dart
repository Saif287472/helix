import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:helix_remote/core/platform/attachment_picker.dart';
import 'package:helix_remote/core/platform/image_metadata.dart';
import 'package:helix_remote/core/platform/media_temp.dart';
import 'package:helix_remote/core/platform/mp4_metadata.dart';
import 'package:helix_remote/core/platform/pixel_decoder.dart';
import 'package:helix_remote/core/platform/thumbnail_encoder.dart';
import 'package:path/path.dart' as p;

/// What [MediaSanitizer.sanitize] did to a file.
enum SanitizeOutcome {
  /// Nothing to remove (or a kind of file that carries none): the original is
  /// sent as it is.
  clean,

  /// Metadata was found and removed; the result is a new file.
  stripped,

  /// A video in a container the cleaner does not read (WebM, MKV). It is sent
  /// as it is; phones record MP4, MOV and 3GP.
  unsupported,

  /// A photo whose metadata could not be removed and that could not be
  /// re-encoded either. It must not be sent.
  failed,
}

/// The result: the file to send, and what happened to get it.
final class SanitizedFile {
  const SanitizedFile(this.file, this.outcome);

  final PickedFile file;
  final SanitizeOutcome outcome;
}

/// Removes where, when and with what a photo or video was taken before the
/// engine copies it (plan: nothing identifying leaves the phone inside a
/// file). The person's original is never changed.
///
/// An interface so the composer's send is tested with a fake, and so the heavy
/// part (reading and rewriting megabytes) is one implementation's business.
abstract interface class MediaSanitizer {
  Future<SanitizedFile> sanitize(PickedFile file);
}

/// The real sanitizer: byte-level cleaning of JPEG, PNG and WebP (lossless,
/// in a background isolate), box-level cleaning of MP4, MOV and 3GP, and, for
/// a photo format it cannot clean in place (HEIC and the like), a decode and
/// JPEG re-encode, which carries no metadata.
final class FileMediaSanitizer implements MediaSanitizer {
  FileMediaSanitizer({
    MediaTemp? temp,
    PixelDecoder decoder = const UiPixelDecoder(),
    this.fallbackSide = 4096,
  }) : _temp = temp ?? MediaTemp(),
       _decoder = decoder;

  final MediaTemp _temp;
  final PixelDecoder _decoder;

  /// A re-encoded photo is no larger than this on the long side.
  final int fallbackSide;

  @override
  Future<SanitizedFile> sanitize(PickedFile file) async {
    try {
      switch (file.kind) {
        case PickedKind.image:
          return await _image(file);
        case PickedKind.video:
          return await _video(file);
        case PickedKind.audio:
        case PickedKind.document:
          return SanitizedFile(file, SanitizeOutcome.clean);
      }
    } on Object {
      return SanitizedFile(file, SanitizeOutcome.failed);
    }
  }

  Future<SanitizedFile> _image(PickedFile file) async {
    final target = await _temp.newPath(
      MediaTemp.clean,
      extension: p.extension(file.name).replaceFirst('.', ''),
    );
    final source = file.path;
    final code = await Isolate.run(() => _stripImageFile(source, target));
    switch (code) {
      case _clean:
        return SanitizedFile(file, SanitizeOutcome.clean);
      case _stripped:
        return SanitizedFile(
          file.copyWith(
            path: target,
            size: await File(target).length(),
            temporary: true,
          ),
          SanitizeOutcome.stripped,
        );
      case _unsupported:
        return _reencode(file);
      default:
        return SanitizedFile(file, SanitizeOutcome.failed);
    }
  }

  Future<SanitizedFile> _reencode(PickedFile file) async {
    final bytes = await File(file.path).readAsBytes();
    final pixels = await _decoder.decode(
      Uint8List.fromList(bytes),
      maxSide: fallbackSide,
    );
    if (pixels == null) return SanitizedFile(file, SanitizeOutcome.failed);
    final jpeg = await Isolate.run(() => ThumbnailMath.jpeg(pixels));
    final target = await _temp.newPath(MediaTemp.clean, extension: 'jpg');
    await File(target).writeAsBytes(jpeg, flush: true);
    return SanitizedFile(
      file.copyWith(
        path: target,
        name: p.setExtension(file.name, '.jpg'),
        mime: 'image/jpeg',
        size: jpeg.length,
        temporary: true,
      ),
      SanitizeOutcome.stripped,
    );
  }

  Future<SanitizedFile> _video(PickedFile file) async {
    final scan = await Mp4Metadata.scan(File(file.path));
    if (scan == null) return SanitizedFile(file, SanitizeOutcome.unsupported);
    if (scan.isClean) return SanitizedFile(file, SanitizeOutcome.clean);
    final target = await _temp.newPath(
      MediaTemp.clean,
      extension: p.extension(file.name).replaceFirst('.', ''),
    );
    try {
      await Mp4Metadata.writeCleaned(
        File(file.path),
        File(target),
        scan.patches,
      );
    } on Object {
      await _temp.delete(target);
      return SanitizedFile(file, SanitizeOutcome.failed);
    }
    return SanitizedFile(
      file.copyWith(
        path: target,
        size: await File(target).length(),
        temporary: true,
      ),
      SanitizeOutcome.stripped,
    );
  }
}

const _clean = 0;
const _stripped = 1;
const _unsupported = 2;
const _failed = 3;

/// Runs in a background isolate: reads [source], writes the cleaned bytes to
/// [target] when anything was removed, and answers with one of the codes
/// above.
int _stripImageFile(String source, String target) {
  try {
    final bytes = File(source).readAsBytesSync();
    if (ImageMetadata.isGif(bytes)) return _clean;
    final stripped = ImageMetadata.strip(bytes);
    if (stripped == null) return _unsupported;
    if (_same(bytes, stripped)) return _clean;
    File(target).writeAsBytesSync(stripped, flush: true);
    return _stripped;
  } on Object {
    return _failed;
  }
}

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
