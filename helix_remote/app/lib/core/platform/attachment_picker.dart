import 'dart:io';

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
        final path = file.path;
        if (path == null) continue;
        final size = await File(path).length();
        out.add(
          describePickedFile(
            path: path,
            name: file.name,
            size: size,
            temporary: await _temp.owns(path),
          ),
        );
      }
      return out;
    } on Object {
      // A refused permission or a platform without a picker is "nothing
      // picked", which the screen already handles.
      return const [];
    }
  }
}

/// A [PickedFile] for [path], its kind and mime type guessed from the name.
PickedFile describePickedFile({
  required String path,
  String? name,
  required int size,
  bool temporary = false,
}) {
  final fileName = name ?? p.basename(path);
  final mime = mimeForFileName(fileName);
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
