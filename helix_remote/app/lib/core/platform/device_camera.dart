import 'dart:io';

import 'package:flutter/services.dart';
import 'package:helix_remote/core/platform/media_temp.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

/// Thrown when the person has refused the permission a source needs. The
/// screen turns it into one sentence pointing at the phone's settings.
final class AttachmentPermissionDenied implements Exception {
  const AttachmentPermissionDenied(this.permission);

  /// `camera`.
  final String permission;

  @override
  String toString() => 'permission denied: $permission';
}

/// Taking a picture or a video with the phone's camera.
///
/// An interface so the attach flow is tested with files a fake hands over, and
/// so only one file in the app (this one) knows the camera plugin.
abstract interface class CameraCapture {
  /// Whether this device can capture at all (a phone can; a Windows desktop is
  /// offered the gallery only).
  bool get isAvailable;

  /// Opens the camera for one photo. The path of a file the app owns (it is
  /// deleted after the send), or null when the person backed out or the
  /// camera could not be opened. Throws [AttachmentPermissionDenied].
  Future<String?> photo();

  /// The same for one video, at most [maxDuration] long.
  Future<String?> video({required Duration maxDuration});
}

/// No camera: every capture is "nothing".
final class NoCamera implements CameraCapture {
  const NoCamera();

  @override
  bool get isAvailable => false;

  @override
  Future<String?> photo() async => null;

  @override
  Future<String?> video({required Duration maxDuration}) async => null;
}

/// The system camera app, through `image_picker`.
///
/// The system camera is used on purpose: it needs no in-app camera screen to
/// get wrong, offers the phone's own controls, and the permission prompt
/// appears only when the person taps Camera. The plugin asks for the camera
/// permission itself (the manifest declares it) and reports a refusal as a
/// `camera_access_denied` error.
final class ImagePickerCamera implements CameraCapture {
  ImagePickerCamera({ImagePicker? picker, MediaTemp? temp})
    : _picker = picker ?? ImagePicker(),
      _temp = temp ?? MediaTemp();

  final ImagePicker _picker;
  final MediaTemp _temp;

  @override
  bool get isAvailable => Platform.isAndroid || Platform.isIOS;

  @override
  Future<String?> photo() => _capture(
    // The full original, not a re-scaled copy: nothing is resized or
    // re-encoded here, and the metadata is stripped before sending.
    () => _picker.pickImage(source: ImageSource.camera),
    fallbackExtension: 'jpg',
  );

  @override
  Future<String?> video({required Duration maxDuration}) => _capture(
    () =>
        _picker.pickVideo(source: ImageSource.camera, maxDuration: maxDuration),
    fallbackExtension: 'mp4',
  );

  Future<String?> _capture(
    Future<XFile?> Function() open, {
    required String fallbackExtension,
  }) async {
    final XFile? shot;
    try {
      shot = await open();
    } on PlatformException catch (e) {
      if (e.code == 'camera_access_denied') {
        throw const AttachmentPermissionDenied('camera');
      }
      return null;
    } on Object {
      return null;
    }
    if (shot == null) return null;
    // Move the capture into a folder the app sweeps, so it is deleted as soon
    // as it has been sent (or the person changes their mind).
    try {
      final ext = p.extension(shot.path).replaceFirst('.', '');
      final target = await _temp.newPath(
        MediaTemp.captures,
        extension: ext.isEmpty ? fallbackExtension : ext,
      );
      await File(shot.path).copy(target);
      try {
        await File(shot.path).delete();
      } on Object {
        // The plugin's own cache; the system clears it.
      }
      return target;
    } on Object {
      return null;
    }
  }
}
