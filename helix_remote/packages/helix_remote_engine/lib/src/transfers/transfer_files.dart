import 'dart:typed_data';

import 'package:helix_remote_engine/src/transfers/blob_store.dart';

/// Names of the files a transfer job may own in [BlobArea.staging]. The same
/// job id always gives the same path, so work in progress is found again
/// after a restart, and the file sweep knows which to keep.
abstract final class TransferFiles {
  /// The encrypted file of an upload (what is sent, resumable at any byte).
  static Future<String> encrypted(BlobStore blobs, int jobId) =>
      blobs.namedPath(BlobArea.staging, 'up-$jobId');

  /// The encrypted bytes of a download so far.
  static Future<String> downloading(BlobStore blobs, int jobId) =>
      blobs.namedPath(BlobArea.staging, 'dl-$jobId');

  /// The plaintext of a download being assembled, before it moves into place.
  static Future<String> assembling(BlobStore blobs, int jobId) =>
      blobs.namedPath(BlobArea.staging, 'dl-$jobId.plain');

  /// Every staging path a job may own.
  static Future<List<String>> allFor(BlobStore blobs, int jobId) async => [
    await encrypted(blobs, jobId),
    await downloading(blobs, jobId),
    await assembling(blobs, jobId),
  ];

  /// A file extension (without the dot) for [name] or, failing that, [mime];
  /// null when neither says. Lower case letters and digits only, so a hostile
  /// name cannot smuggle a path.
  static String? extension({String? name, required String mime}) {
    if (name != null) {
      final dot = name.lastIndexOf('.');
      if (dot > 0 && dot < name.length - 1) {
        final ext = name.substring(dot + 1).toLowerCase();
        if (ext.length <= 8 && RegExp(r'^[a-z0-9]+$').hasMatch(ext)) {
          return ext;
        }
      }
    }
    return _byMime[mime.toLowerCase().split(';').first.trim()];
  }

  static const _byMime = {
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/gif': 'gif',
    'image/webp': 'webp',
    'image/heic': 'heic',
    'video/mp4': 'mp4',
    'video/quicktime': 'mov',
    'video/webm': 'webm',
    'audio/ogg': 'ogg',
    'audio/opus': 'opus',
    'audio/mpeg': 'mp3',
    'audio/mp4': 'm4a',
    'audio/aac': 'aac',
    'audio/wav': 'wav',
    'application/pdf': 'pdf',
    'text/plain': 'txt',
  };

  /// The MIME type of a thumbnail from its first bytes (the processor does
  /// not say), `image/jpeg` when unsure.
  static String sniffImageMime(Uint8List bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }
}
