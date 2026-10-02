import 'dart:typed_data';

import 'package:helix_remote_engine/src/transfers/blob_store.dart';
import 'package:helix_remote_engine/src/util/ids.dart';

/// A [BlobStore] in memory: tests, and hosts that have no disk. Paths look
/// like `mem://media/f3`; the engine never parses them.
///
/// [seed] puts a file where [BlobStore.copy] can read it, standing in for a
/// file the user picked.
final class MemoryBlobStore implements BlobStore {
  MemoryBlobStore({Clock? clock, this.readChunk = 16 * 1024})
    : _clock = clock ?? (() => DateTime.utc(2026));

  final Clock _clock;

  /// Reads come in pieces this large, so streaming code is exercised.
  final int readChunk;

  final Map<String, _Entry> _files = {};
  int _counter = 0;

  /// Paths of every file (any area).
  Iterable<String> get paths => _files.keys;

  bool exists(String path) => _files.containsKey(path);

  /// The file's bytes (a copy), or null.
  Uint8List? bytesOf(String path) {
    final entry = _files[path];
    return entry == null ? null : Uint8List.fromList(entry.bytes);
  }

  /// Puts [bytes] at [path] (area unspecified: a source file). Returns the
  /// path.
  String seed(String path, List<int> bytes) {
    _files[path] = _Entry(null, Uint8List.fromList(bytes), _clock());
    return path;
  }

  Iterable<String> pathsIn(BlobArea area) => [
    for (final entry in _files.entries)
      if (entry.value.area == area) entry.key,
  ];

  /// Makes every file look [age] older (to test the sweep's grace period).
  void age(Duration age) {
    for (final entry in _files.values) {
      entry.modifiedAt = entry.modifiedAt.subtract(age);
    }
  }

  static const _scheme = 'mem://';

  @override
  Future<String> newPath(BlobArea area, {String? extension}) async =>
      '$_scheme${area.name}/f${_counter++}'
      '${extension == null ? '' : '.$extension'}';

  @override
  Future<String> namedPath(BlobArea area, String name) async =>
      '$_scheme${area.name}/n-$name';

  @override
  Future<int?> length(String path) async => _files[path]?.length;

  @override
  Stream<List<int>> read(String path, {int start = 0, int? end}) async* {
    final entry = _files[path];
    if (entry == null) throw StateError('no such file');
    final data = entry.bytes;
    final stop = end == null || end > data.length ? data.length : end;
    for (var at = start; at < stop; at += readChunk) {
      final upTo = at + readChunk < stop ? at + readChunk : stop;
      yield Uint8List.sublistView(data, at, upTo);
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<BlobSink> openWrite(String path, {int keep = 0}) async {
    final existing = _files[path];
    if (existing == null && keep != 0) {
      throw StateError('cannot keep bytes of a missing file');
    }
    if (existing != null && keep > existing.length) {
      throw StateError('keep is past the end of the file');
    }
    final area = _areaOf(path);
    final entry = _Entry(
      area,
      existing == null
          ? Uint8List(0)
          : Uint8List.sublistView(existing.bytes, 0, keep),
      _clock(),
    );
    _files[path] = entry;
    return _Sink(this, path, entry);
  }

  @override
  Future<void> move(String from, String to) async {
    final entry = _files.remove(from);
    if (entry == null) throw StateError('no such file');
    _files[to] = _Entry(_areaOf(to), entry.bytes, _clock());
  }

  @override
  Future<void> copy(String from, String to) async {
    final entry = _files[from];
    if (entry == null) throw StateError('no such file');
    _files[to] = _Entry(_areaOf(to), Uint8List.fromList(entry.bytes), _clock());
  }

  @override
  Future<void> delete(String path) async {
    _files.remove(path);
  }

  @override
  Future<List<BlobInfo>> list(BlobArea area) async => [
    for (final entry in _files.entries)
      if (_areaOf(entry.key) == area)
        BlobInfo(
          path: entry.key,
          area: area,
          size: entry.value.length,
          modifiedAt: entry.value.modifiedAt,
        ),
  ];

  @override
  Future<void> clear() async {
    _files.removeWhere((path, _) => _areaOf(path) != null);
  }

  BlobArea? _areaOf(String path) {
    if (!path.startsWith(_scheme)) return null;
    final first = path.substring(_scheme.length).split('/').first;
    for (final area in BlobArea.values) {
      if (area.name == first) return area;
    }
    return null;
  }
}

final class _Entry {
  _Entry(this.area, Uint8List data, this.modifiedAt) : _data = data;

  final BlobArea? area;
  DateTime modifiedAt;
  Uint8List _data;
  BytesBuilder? _builder;

  int get length => _builder?.length ?? _data.length;

  Uint8List get bytes {
    final builder = _builder;
    if (builder != null) {
      _data = builder.takeBytes();
      _builder = null;
    }
    return _data;
  }

  void append(List<int> more) {
    _builder ??= BytesBuilder(copy: false)..add(_data);
    _builder!.add(Uint8List.fromList(more));
  }
}

final class _Sink implements BlobSink {
  _Sink(this._store, this._path, this._entry);

  final MemoryBlobStore _store;
  final String _path;
  final _Entry _entry;
  bool _closed = false;

  @override
  Future<void> add(List<int> bytes) async {
    if (_closed) throw StateError('closed');
    _entry.append(bytes);
  }

  @override
  Future<void> close() async {
    _closed = true;
  }

  @override
  Future<void> abort() async {
    _closed = true;
    if (_store._files[_path] == _entry) _store._files.remove(_path);
  }
}
