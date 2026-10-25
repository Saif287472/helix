import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:helix_remote/core/platform/device_camera.dart';
import 'package:helix_remote/core/platform/media_temp.dart';
import 'package:path/path.dart' as p;

export 'package:helix_remote/core/platform/device_camera.dart'
    show AttachmentPermissionDenied;

/// What a picked file is, for how a chat sends it.
enum PickedKind { image, video, audio, document }

/// A file the person chose to send. The engine copies it into its own store
/// and never touches the original.
final class PickedFile {
  const PickedFile({
    required this.path,
    required this.name,
    required this.mime,
    required this.size,
    required this.kind,
    this.temporary = false,
  });

  final String path;
  final String name;
  final String mime;
  final int size;
  final PickedKind kind;

  /// A copy the app made (a camera capture, a cached copy of a gallery pick)
  /// rather than the person's own file: deleted once it has been sent.
  final bool temporary;

  PickedFile copyWith({
    String? path,
    String? name,
    String? mime,
    int? size,
    PickedKind? kind,
    bool? temporary,
  }) => PickedFile(
    path: path ?? this.path,
    name: name ?? this.name,
    mime: mime ?? this.mime,
    size: size ?? this.size,
    kind: kind ?? this.kind,
    temporary: temporary ?? this.temporary,
  );
}

/// Where attachments come from: the phone's gallery, its files, its camera.
///
/// An interface so the conversation never imports a plugin, and so a test
/// hands it a list instead of opening a system dialog. Every method answers
/// "nothing" (an empty list, or null) when the person cancels or the platform
/// has no such source; none throws for that.
abstract interface class AttachmentPicker {
  /// Whether this build can take a photo at all. When false the attach sheet
  /// does not offer Camera.
  bool get cameraAvailable;

  /// Photos and videos from the gallery, several at once.
  Future<List<PickedFile>> pickGallery();

  /// Any files.
  Future<List<PickedFile>> pickDocuments();

  /// Audio files.
  Future<List<PickedFile>> pickAudio();

  /// Takes a photo with the camera. Null when the person backs out. Throws
  /// [AttachmentPermissionDenied] when the camera permission is refused.
  Future<PickedFile?> takePhoto();

  /// Records a video with the camera (at most [maxVideo] long). The same
  /// contract as [takePhoto].
  Future<PickedFile?> recordVideo();

  /// The longest video the camera is asked to record.
  static const maxVideo = Duration(minutes: 5);
}

/// The real picker: the gallery and files through `file_picker`, the camera
/// through a [CameraCapture].
final class DeviceAttachmentPicker implements AttachmentPicker {
  DeviceAttachmentPicker({
    CameraCapture camera = const NoCamera(),
    MediaTemp? temp,
  }) : _camera = camera,
       _temp = temp ?? MediaTemp();

  final CameraCapture _camera;
  final MediaTemp _temp;

  @override
  bool get cameraAvailable => _camera.isAvailable;

  @override
  Future<List<PickedFile>> pickGallery() => _pick(FileType.media);

  @override
  Future<List<PickedFile>> pickDocuments() => _pick(FileType.any);

  @override
  Future<List<PickedFile>> pickAudio() => _pick(FileType.audio);

  @override
  Future<PickedFile?> takePhoto() async =>
      _captured(await _camera.photo(), fallback: 'photo.jpg');

  @override
  Future<PickedFile?> recordVideo() async => _captured(
    await _camera.video(maxDuration: AttachmentPicker.maxVideo),
    fallback: 'video.mp4',
  );

  Future<PickedFile?> _captured(
    String? path, {
    required String fallback,
  }) async {
    if (path == null) return null;
    try {
      final size = await File(path).length();
      if (size == 0) {
        await _temp.delete(path);
        return null;
      }
      // A neutral name: the camera's own file name carries the time.
      final ext = p.extension(path);
      final name = ext.isEmpty
          ? fallback
          : '${p.basenameWithoutExtension(fallback)}$ext';
      return describePickedFile(
        path: path,
        name: name,
        size: size,
        temporary: true,
        head: await readHead(path),
      );
    } on Object {
      return null;
    }
  }

  Future<List<PickedFile>> _pick(FileType type) async {
    try {
      final files = await FilePicker.pickFiles(type: type);
      final out = <PickedFile>[];
      for (final file in files) {
        // One file that cannot be read (a cloud placeholder, a revoked
        // provider) is left out; the others still attach (AUD-14c-3).
        try {
          final path = file.path;
          if (path == null) continue;
          final size = await File(path).length();
          out.add(
            describePickedFile(
              path: path,
              name: file.name,
              size: size,
              temporary: await _temp.owns(path),
              head: await readHead(path),
            ),
          );
        } on Object {
          continue;
        }
      }
      return out;
    } on Object {
      // A refused permission or a platform without a picker is "nothing
      // picked", which the screen already handles.
      return const [];
    }
  }
}

/// The first bytes of [path], enough to tell what the file is; null when it
/// cannot be read.
Future<Uint8List?> readHead(String path, {int length = 32}) async {
  try {
    final file = await File(path).open();
    try {
      return await file.read(length);
    } finally {
      await file.close();
    }
  } on Object {
    return null;
  }
}

/// A [PickedFile] for [path]: its kind and mime type from what the file *is*
/// when [head] (its first bytes) says so, and from its name otherwise.
///
/// The sanitizer cleans a file because of its kind, so the kind cannot depend
/// on a name: a photo saved as `.heif`, `.avif` or with no extension used to
/// be a "document" and went out with its position and camera (AUD-14c-1).
PickedFile describePickedFile({
  required String path,
  String? name,
  required int size,
  bool temporary = false,
  Uint8List? head,
}) {
  final fileName = name ?? p.basename(path);
  final mime =
      (head == null ? null : sniffMime(head)) ?? mimeForFileName(fileName);
  final kind = switch (mime.split('/').first) {
    'image' => PickedKind.image,
    'video' => PickedKind.video,
    'audio' => PickedKind.audio,
    _ => PickedKind.document,
  };
  return PickedFile(
    path: path,
    name: fileName,
    mime: mime,
    size: size,
    kind: kind,
    temporary: temporary,
  );
}

/// The media type of a file from its first bytes, for the formats whose
/// identity matters to what is done with them (photos, video, audio); null
/// when [head] says nothing certain.
String? sniffMime(Uint8List head) {
  bool at(int offset, List<int> bytes) {
    if (head.length < offset + bytes.length) return false;
    for (var i = 0; i < bytes.length; i++) {
      if (head[offset + i] != bytes[i]) return false;
    }
    return true;
  }

  if (at(0, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (at(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (at(0, const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (at(0, const [0x52, 0x49, 0x46, 0x46]) &&
      at(8, const [0x57, 0x45, 0x42, 0x50])) {
    return 'image/webp';
  }
  if (at(0, const [0x52, 0x49, 0x46, 0x46]) &&
      at(8, const [0x57, 0x41, 0x56, 0x45])) {
    return 'audio/wav';
  }
  if (at(0, const [0x49, 0x49, 0x2A, 0x00]) ||
      at(0, const [0x4D, 0x4D, 0x00, 0x2A])) {
    return 'image/tiff';
  }
  if (at(0, const [0x42, 0x4D]) && head.length >= 14) return 'image/bmp';
  if (at(4, const [0x66, 0x74, 0x79, 0x70]) && head.length >= 12) {
    // ISO base media: the major brand says photo or video.
    final brand = String.fromCharCodes(head.sublist(8, 12));
    return switch (brand) {
      'heic' || 'heix' || 'hevc' || 'hevx' => 'image/heic',
      'mif1' || 'msf1' || 'heim' || 'heis' => 'image/heif',
      'avif' || 'avis' => 'image/avif',
      'qt  ' => 'video/quicktime',
      '3gp4' || '3gp5' || '3gp6' || '3ge6' || '3gg6' => 'video/3gpp',
      'M4A ' || 'M4B ' => 'audio/aac',
      _ => 'video/mp4',
    };
  }
  if (at(0, const [0x1A, 0x45, 0xDF, 0xA3])) return 'video/webm';
  if (at(0, const [0x4F, 0x67, 0x67, 0x53])) return 'audio/ogg';
  if (at(0, const [0x66, 0x4C, 0x61, 0x43])) return 'audio/flac';
  if (at(0, const [0x49, 0x44, 0x33])) return 'audio/mpeg';
  return null;
}

/// The media type for a file name, by its extension. The few that matter to a
/// chat; everything else is `application/octet-stream`.
String mimeForFileName(String fileName) {
  final extension = p.extension(fileName).toLowerCase().replaceFirst('.', '');
  return switch (extension) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'heif' => 'image/heif',
    'avif' => 'image/avif',
    'tif' || 'tiff' => 'image/tiff',
    'bmp' => 'image/bmp',
    'mp4' || 'm4v' => 'video/mp4',
    'mov' => 'video/quicktime',
    'webm' => 'video/webm',
    'mkv' => 'video/x-matroska',
    '3gp' => 'video/3gpp',
    'mp3' => 'audio/mpeg',
    'm4a' || 'aac' => 'audio/aac',
    'ogg' || 'oga' || 'opus' => 'audio/ogg',
    'wav' => 'audio/wav',
    'flac' => 'audio/flac',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'zip' => 'application/zip',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt' => 'application/vnd.ms-powerpoint',
    'pptx' =>
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    _ => 'application/octet-stream',
  };
}
