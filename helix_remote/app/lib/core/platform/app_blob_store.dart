import 'dart:io';
import 'dart:math';

import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:path/path.dart' as p;

/// The engine's file store over the app's private directory.
///
/// Two folders, `media` (what the screens open: decrypted attachments and
/// thumbnails) and `staging` (encrypted bytes in transit). File names are
/// random, so nothing about a file's name says who sent it or what it is, and
/// the engine, not this class, decides what lives and what is swept.
///
/// `modifiedAt` of a [BlobInfo] is the write time, and [copy] writes a new file
/// (it never carries the source's time over), which is what the engine's
/// janitor relies on when it decides a file is old enough to sweep.
final class AppBlobStore implements BlobStore {
  AppBlobStore(this.root, {Random? random})
    : _random = random ?? Random.secure();

  /// The directory holding the two areas.
  final Directory root;
  final Random _random;

  Directory _area(BlobArea area) =>
      Directory(p.join(root.path, area.name))..createSync(recursive: true);

  static final _safeName = RegExp(r'^[A-Za-z0-9._-]{1,128}$');

  @override
  Future<String> newPath(BlobArea area, {String? extension}) async {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final name = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final ext =
        extension == null || !RegExp(r'^[A-Za-z0-9]{1,8}$').hasMatch(extension)
        ? ''
        : '.$extension';
    return p.join(_area(area).path, '$name$ext');
  }

  @override
  Future<String> namedPath(BlobArea area, String name) async {
    if (!_safeName.hasMatch(name) || name.contains('..')) {
      throw ArgumentError.value(name, 'name', 'is not a safe file name');
    }
    return p.join(_area(area).path, name);
  }

  @override
  Future<int?> length(String path) async {
    final file = File(path);
    return await file.exists() ? await file.length() : null;
  }

  @override
  Stream<List<int>> read(String path, {int start = 0, int? end}) =>
      File(path).openRead(start, end);

  @override
  Future<BlobSink> openWrite(String path, {int keep = 0}) async {
    final file = File(path);
    final existing = await file.exists();
    if (!existing) {
      if (keep != 0) throw StateError('nothing to keep');
      await file.parent.create(recursive: true);
      await file.create();
    } else if (keep > await file.length()) {
      throw StateError('keep is past the end of the file');
    }
    // Cut the file to [keep] bytes, then append.
    final handle = await file.open(mode: FileMode.append);
    await handle.truncate(keep);
    await handle.setPosition(keep);
    return _FileSink(handle, file);
  }

  @override
  Future<void> move(String from, String to) async {
    final target = File(to);
    if (await target.exists()) await target.delete();
    try {
      await File(from).rename(to);
    } on FileSystemException {
      // A different volume: copy and remove.
      await copy(from, to);
      await File(from).delete();
    }
  }

  @override
  Future<void> copy(String from, String to) async {
    final target = File(to);
    await target.parent.create(recursive: true);
    final sink = target.openWrite();
    try {
      await sink.addStream(File(from).openRead());
    } finally {
      await sink.close();
    }
  }

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<List<BlobInfo>> list(BlobArea area) async {
    final dir = _area(area);
    final out = <BlobInfo>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      out.add(
        BlobInfo(
          path: entity.path,
          area: area,
          size: stat.size,
          modifiedAt: stat.modified,
        ),
      );
    }
    return out;
  }

  @override
  Future<void> clear() async {
    for (final area in BlobArea.values) {
      final dir = Directory(p.join(root.path, area.name));
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }
}

final class _FileSink implements BlobSink {
  _FileSink(this._handle, this._file);

  final RandomAccessFile _handle;
  final File _file;
  bool _closed = false;

  @override
  Future<void> add(List<int> bytes) async {
    await _handle.writeFrom(bytes);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _handle.flush();
    await _handle.close();
  }

  @override
  Future<void> abort() async {
    if (!_closed) {
      _closed = true;
      await _handle.close();
    }
    if (await _file.exists()) await _file.delete();
  }
}
