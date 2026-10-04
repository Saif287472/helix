import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote_api/v2.dart' show HelixApi;
import 'package:helix_remote_crypto/v2.dart'
    show AttachmentCrypto, CryptoRandom, SecureCryptoRandom;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show CreateUploadRequest, JsonReader, MediaKind, MediaPointer;

/// The group's picture, end to end encrypted.
///
/// A group picture is a small image encrypted with a fresh key and stored as a
/// `persistent` media object; the group's encrypted state carries only the
/// pointer (id, key, digest). The server sees a random id and ciphertext, so
/// the picture is as private as the group's name.
abstract interface class GroupPictureStore {
  /// Encrypts and uploads [bytes] (an image), and returns its pointer JSON for
  /// the group state.
  Future<Map<String, Object?>> upload(Uint8List bytes);

  /// Downloads and decrypts the picture [pointer] names, or null when it
  /// cannot be fetched or does not check out (a missing object, a digest that
  /// does not match). Never throws.
  Future<Uint8List?> fetch(Map<String, Object?> pointer);
}

/// The largest picture, after the app has scaled it down.
const kMaxGroupPictureBytes = 1024 * 1024;

/// [GroupPictureStore] over the media API and the attachment crypto.
final class ApiGroupPictureStore implements GroupPictureStore {
  ApiGroupPictureStore(this._api, {CryptoRandom? random})
    : _random = random ?? SecureCryptoRandom();

  final HelixApi _api;
  final CryptoRandom _random;
  final Map<String, Uint8List> _cache = {};

  @override
  Future<Map<String, Object?>> upload(Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > kMaxGroupPictureBytes) {
      throw ArgumentError.value(bytes.length, 'bytes', 'picture size');
    }
    final key = AttachmentCrypto.newKey(_random);
    final sealed = await AttachmentCrypto.encryptBytes(
      bytes,
      key,
      random: _random,
    );
    final target = await _api.media.createUpload(
      CreateUploadRequest(
        size: sealed.ciphertext.length,
        kind: MediaKind.persistent,
      ),
    );
    await _api.media.upload(target, sealed.ciphertext);
    final pointer = MediaPointer(
      id: target.mediaId,
      key: key,
      digest: sealed.digest,
      size: bytes.length,
      mime: 'image/png',
    );
    _cache[pointer.id] = bytes;
    return pointer.toJson();
  }

  @override
  Future<Uint8List?> fetch(Map<String, Object?> pointer) async {
    try {
      final parsed = MediaPointer.fromJson(JsonReader(pointer));
      final cached = _cache[parsed.id];
      if (cached != null) return cached;
      if (parsed.size <= 0 || parsed.size > kMaxGroupPictureBytes) return null;
      final download = await _api.media.download(parsed.id);
      // Whatever the server sends is bounded by what the pointer says.
      if (download.bytes.length >
          AttachmentCrypto.ciphertextLength(
            parsed.size,
            chunkSize: AttachmentCrypto.maxChunkSize,
          )) {
        return null;
      }
      final bytes = await AttachmentCrypto.decryptBytes(
        download.bytes,
        parsed.key,
        digest: parsed.digest,
      );
      if (bytes.length != parsed.size) return null;
      return _cache[parsed.id] = bytes;
    } on Object {
      return null;
    }
  }
}

/// The picture store of the live runtime.
final groupPictureStoreProvider = FutureProvider<GroupPictureStore>((
  ref,
) async {
  final runtime = await ref.watch(runtimeProvider.future);
  return ApiGroupPictureStore(runtime.api);
});

/// A group picture's bytes for [pointerJson] (the pointer, JSON-encoded so it
/// can key a provider), or null when there is none or it cannot be fetched.
final groupPictureProvider = FutureProvider.family<Uint8List?, String>((
  ref,
  pointerJson,
) async {
  final store = await ref.watch(groupPictureStoreProvider.future);
  try {
    final decoded = jsonDecode(pointerJson);
    if (decoded is! Map) return null;
    return await store.fetch(decoded.cast<String, Object?>());
  } on FormatException {
    return null;
  }
});

/// Lets the person choose a picture and makes it small enough to upload.
abstract interface class GroupPicturePicker {
  /// The chosen image scaled down (PNG), or null when nothing was chosen or
  /// the file is not an image this device can read.
  Future<Uint8List?> pick();
}

/// Picks from the phone's files and scales to at most [maxSide] pixels.
final class FileGroupPicturePicker implements GroupPicturePicker {
  const FileGroupPicturePicker({this.maxSide = 512});

  final int maxSide;

  @override
  Future<Uint8List?> pick() async {
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return null;
      final original = await file.readAsBytes();
      return await scaleImage(original, maxSide: maxSide);
    } on Object {
      return null;
    }
  }
}

/// Decodes [bytes], scales the longer side down to [maxSide] and re-encodes
/// as PNG, or null when it is not an image or still too large.
Future<Uint8List?> scaleImage(Uint8List bytes, {int maxSide = 512}) async {
  ui.Codec? codec;
  try {
    codec = await ui.instantiateImageCodec(bytes, targetWidth: maxSide);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (data == null) return null;
    final out = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    return out.length > kMaxGroupPictureBytes ? null : out;
  } on Object {
    return null;
  } finally {
    codec?.dispose();
  }
}

final groupPicturePickerProvider = Provider<GroupPicturePicker>(
  (ref) => const FileGroupPicturePicker(),
);
