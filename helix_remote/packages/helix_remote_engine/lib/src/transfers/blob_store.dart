import 'dart:typed_data';

import 'package:helix_remote_crypto/v2.dart' show Sha256Accumulator;

/// Where the engine keeps files.
enum BlobArea {
  /// Decrypted attachments and thumbnails of messages, for the UI to open.
  /// Kept until their message goes.
  media,

  /// Work in progress: encrypted bytes on their way up or down, and
  /// plaintext being assembled. Kept only while the transfer may resume.
  staging,
}

/// A file the store holds.
final class BlobInfo {
  const BlobInfo({
    required this.path,
    required this.area,
    required this.size,
    required this.modifiedAt,
  });

  final String path;
  final BlobArea area;
  final int size;
  final DateTime modifiedAt;
}

/// An open file being written, appending.
abstract interface class BlobSink {
  Future<void> add(List<int> bytes);

  /// Flushes and closes. The bytes are durable after this.
  Future<void> close();

  /// Closes and removes what was written by this sink's own call
  /// (best effort; the caller deletes the path anyway).
  Future<void> abort();
}

/// The engine's file access (plan §6.3: the engine does no file I/O of its
/// own). The app implements it over its private directories, the CLI over a
/// folder, tests over [MemoryBlobStore].
///
/// Paths are opaque strings: the engine stores them in the database and hands
/// them back, and never builds or parses one. Every path the store hands out
/// must stay valid across restarts.
///
/// The engine owns what is in [BlobArea]s: it deletes files there, and only
/// there (never a file the user picked, which [copy] reads but never
/// touches).
abstract interface class BlobStore {
  /// A new, unused path in [area]. Names must not be guessable (random) and
  /// nothing is created yet. [extension] is a hint without the dot (`jpg`)
  /// so the OS can open the file.
  Future<String> newPath(BlobArea area, {String? extension});

  /// The fixed path for [name] in [area] (letters, digits, `-`, `_`, `.`).
  /// The same name gives the same path, so work in progress can be found
  /// again after a restart.
  Future<String> namedPath(BlobArea area, String name);

  /// The file's size, or null when it does not exist.
  Future<int?> length(String path);

  /// Bytes [start] up to [end] (exclusive; the end of the file when null),
  /// in chunks.
  Stream<List<int>> read(String path, {int start = 0, int? end});

  /// Opens [path] for appending after its first [keep] bytes (the rest is
  /// cut off). Creates it when [keep] is 0 and it does not exist. [keep] must
  /// not exceed the current length.
  Future<BlobSink> openWrite(String path, {int keep = 0});

  /// Renames [from] to [to], replacing [to], atomically where the platform
  /// can.
  Future<void> move(String from, String to);

  /// Copies [from] (any readable file, including one the user picked) to the
  /// engine-owned [to].
  Future<void> copy(String from, String to);

  /// Deletes the file. Nothing happens when it is not there.
  Future<void> delete(String path);

  /// The files in [area].
  Future<List<BlobInfo>> list(BlobArea area);

  /// Deletes every file in every area (sign-out and revocation).
  Future<void> clear();
}

/// Whole-file helpers over [BlobStore].
extension BlobStoreBytes on BlobStore {
  Future<Uint8List> readBytes(String path, {int start = 0, int? end}) async {
    final out = BytesBuilder(copy: false);
    await for (final part in read(path, start: start, end: end)) {
      out.add(part);
    }
    return out.takeBytes();
  }

  Future<void> writeBytes(String path, List<int> bytes) async {
    final sink = await openWrite(path);
    try {
      await sink.add(bytes);
      await sink.close();
    } on Object {
      await sink.abort();
      rethrow;
    }
  }

  /// SHA-256 of the file, streamed.
  Future<Uint8List> sha256Of(String path) async {
    final digest = Sha256Accumulator();
    await for (final part in read(path)) {
      digest.add(part);
    }
    return digest.close();
  }
}

/// The store of an engine built without one: nothing can be sent or kept.
/// Every operation that would touch a file throws a [StateError].
final class NoBlobStore implements BlobStore {
  const NoBlobStore();

  static StateError _none() => StateError('this engine has no BlobStore');

  @override
  Future<String> newPath(BlobArea area, {String? extension}) async =>
      throw _none();

  @override
  Future<String> namedPath(BlobArea area, String name) async => throw _none();

  @override
  Future<int?> length(String path) async => throw _none();

  @override
  Stream<List<int>> read(String path, {int start = 0, int? end}) =>
      Stream.error(_none());

  @override
  Future<BlobSink> openWrite(String path, {int keep = 0}) async =>
      throw _none();

  @override
  Future<void> move(String from, String to) async => throw _none();

  @override
  Future<void> copy(String from, String to) async => throw _none();

  @override
  Future<void> delete(String path) async {}

  @override
  Future<List<BlobInfo>> list(BlobArea area) async => const [];

  @override
  Future<void> clear() async {}
}
