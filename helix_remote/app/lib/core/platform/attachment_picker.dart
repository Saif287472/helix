import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

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
  });

  final String path;
  final String name;
  final String mime;
  final int size;
  final PickedKind kind;
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

  /// Takes a photo with the camera.
  Future<PickedFile?> takePhoto();
}

/// The real picker, over `file_picker`. There is no camera plugin in this
/// build (`takePhoto` returns null and [cameraAvailable] is false): taking a
/// photo needs one, and adding it is a dependency decision recorded in the
/// phase report.
final class DeviceAttachmentPicker implements AttachmentPicker {
  const DeviceAttachmentPicker();

  @override
  bool get cameraAvailable => false;

  @override
  Future<List<PickedFile>> pickGallery() => _pick(FileType.media);

  @override
  Future<List<PickedFile>> pickDocuments() => _pick(FileType.any);

  @override
  Future<List<PickedFile>> pickAudio() => _pick(FileType.audio);

  @override
  Future<PickedFile?> takePhoto() async => null;

  Future<List<PickedFile>> _pick(FileType type) async {
    try {
      final files = await FilePicker.pickFiles(type: type);
      final out = <PickedFile>[];
      for (final file in files) {
        final path = file.path;
        if (path == null) continue;
        final size = await File(path).length();
        out.add(describePickedFile(path: path, name: file.name, size: size));
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
