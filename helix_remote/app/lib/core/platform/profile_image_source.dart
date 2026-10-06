import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/platform/app_storage.dart';

/// Where a profile picture comes from.
///
/// The screens never see a file picker, a codec or a path: they ask this for
/// a finished square picture and get PNG bytes (or null when the person
/// backed out). Cropping to the centre square and shrinking happen here, off
/// the screen's code, so a 12-megapixel photo never reaches a widget.
abstract interface class ProfileImageSource {
  /// Whether this platform can pick a picture at all.
  bool get canPick;

  /// Lets the person choose a picture and returns it cropped to a [size] x
  /// [size] square, as PNG. Null when cancelled. Throws
  /// [ProfileImageException] when the file cannot be read as a picture.
  Future<Uint8List?> pickSquare({int size = 256});
}

final class ProfileImageException implements Exception {
  const ProfileImageException();

  @override
  String toString() => 'ProfileImageException';
}

final class DeviceProfileImageSource implements ProfileImageSource {
  const DeviceProfileImageSource();

  @override
  bool get canPick => true;

  @override
  Future<Uint8List?> pickSquare({int size = 256}) async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return null;
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on Object {
      throw const ProfileImageException();
    }
    return cropToSquare(bytes, size: size);
  }

  /// Decodes [bytes], takes the centre square and scales it to [size].
  static Future<Uint8List> cropToSquare(
    Uint8List bytes, {
    int size = 256,
  }) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final source = frame.image;
      final side = source.width < source.height ? source.width : source.height;
      final left = (source.width - side) / 2;
      final top = (source.height - side) / 2;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        source,
        ui.Rect.fromLTWH(left, top, side.toDouble(), side.toDouble()),
        ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final cropped = await recorder.endRecording().toImage(size, size);
      final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
      source.dispose();
      cropped.dispose();
      codec.dispose();
      if (data == null) throw const ProfileImageException();
      return data.buffer.asUint8List();
    } on ProfileImageException {
      rethrow;
    } on Object {
      throw const ProfileImageException();
    }
  }
}

final profileImageSourceProvider = Provider<ProfileImageSource>(
  (ref) => const DeviceProfileImageSource(),
);

/// Keeps the chosen picture on this device.
abstract interface class ProfileAvatarStore {
  Future<Uint8List?> load();

  Future<void> save(Uint8List png);

  Future<void> clear();
}

final class FileProfileAvatarStore implements ProfileAvatarStore {
  const FileProfileAvatarStore();

  @override
  Future<Uint8List?> load() async {
    try {
      final file = await AppPaths.profileAvatarFile();
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(Uint8List png) async {
    final file = await AppPaths.profileAvatarFile();
    await file.writeAsBytes(png, flush: true);
  }

  @override
  Future<void> clear() async {
    final file = await AppPaths.profileAvatarFile();
    if (await file.exists()) await file.delete();
  }
}

final profileAvatarStoreProvider = Provider<ProfileAvatarStore>(
  (ref) => const FileProfileAvatarStore(),
);

/// The picture on this device, or null. Changing it rebuilds everything that
/// shows it (the Settings header, the profile page).
final profileAvatarProvider =
    AsyncNotifierProvider<ProfileAvatarNotifier, Uint8List?>(
      ProfileAvatarNotifier.new,
    );

final class ProfileAvatarNotifier extends AsyncNotifier<Uint8List?> {
  @override
  Future<Uint8List?> build() => ref.read(profileAvatarStoreProvider).load();

  Future<void> set(Uint8List png) async {
    await ref.read(profileAvatarStoreProvider).save(png);
    state = AsyncData(png);
  }

  Future<void> remove() async {
    await ref.read(profileAvatarStoreProvider).clear();
    state = const AsyncData(null);
  }
}
