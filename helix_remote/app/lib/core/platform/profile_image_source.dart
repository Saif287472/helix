import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
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
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? source;
    ui.Image? cropped;
    try {
      // Decoded no larger than twice the result on the short side: a
      // 12-megapixel photo is never held at full size, which on a small phone
      // is what threw (AUD-14c-2).
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final shortSide = descriptor.width < descriptor.height
          ? descriptor.width
          : descriptor.height;
      final scale = shortSide <= size * 2 ? 1.0 : (size * 2) / shortSide;
      codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * scale).round().clamp(1, 1 << 14),
        targetHeight: (descriptor.height * scale).round().clamp(1, 1 << 14),
      );
      final frame = await codec.getNextFrame();
      final image = source = frame.image;
      final side = image.width < image.height ? image.width : image.height;
      final left = (image.width - side) / 2;
      final top = (image.height - side) / 2;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(left, top, side.toDouble(), side.toDouble()),
        ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final result = cropped = await recorder.endRecording().toImage(
        size,
        size,
      );
      final data = await result.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw const ProfileImageException();
      return data.buffer.asUint8List();
    } on ProfileImageException {
      rethrow;
    } on Object {
      throw const ProfileImageException();
    } finally {
      // Every native object goes, whether the crop worked or not.
      cropped?.dispose();
      source?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
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

/// [account]'s picture file (see [AppPaths.profileAvatarFile]).
final class FileProfileAvatarStore implements ProfileAvatarStore {
  const FileProfileAvatarStore(this.account);

  final String account;

  @override
  Future<Uint8List?> load() async {
    try {
      final file = await AppPaths.profileAvatarFile(account);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(Uint8List png) async {
    final file = await AppPaths.profileAvatarFile(account);
    await file.writeAsBytes(png, flush: true);
  }

  @override
  Future<void> clear() async {
    final file = await AppPaths.profileAvatarFile(account);
    if (await file.exists()) await file.delete();
  }
}

/// The picture store of the account on screen; a switch rebuilds it.
final profileAvatarStoreProvider = Provider<ProfileAvatarStore>(
  (ref) => FileProfileAvatarStore(
    ref.watch(activeAccountProvider)?.id ?? AppPaths.firstAccount,
  ),
);

/// The picture on this device, or null. Changing it rebuilds everything that
/// shows it (the Settings header, the profile page).
final profileAvatarProvider =
    AsyncNotifierProvider<ProfileAvatarNotifier, Uint8List?>(
      ProfileAvatarNotifier.new,
    );

final class ProfileAvatarNotifier extends AsyncNotifier<Uint8List?> {
  @override
  Future<Uint8List?> build() => ref.watch(profileAvatarStoreProvider).load();

  Future<void> set(Uint8List png) async {
    await ref.read(profileAvatarStoreProvider).save(png);
    state = AsyncData(png);
  }

  Future<void> remove() async {
    await ref.read(profileAvatarStoreProvider).clear();
    state = const AsyncData(null);
  }
}
