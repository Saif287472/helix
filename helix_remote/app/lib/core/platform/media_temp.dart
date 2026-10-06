import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where media the app makes for a moment lives (a camera capture, a voice
/// recording in progress, a copy with its metadata removed) and the one place
/// that deletes it again.
///
/// Everything here is a plain file under the platform's cache directory, in a
/// folder the app owns. A file is deleted as soon as the engine has copied it
/// (or the person backed out), and anything a crash left behind is swept the
/// first time the folder is used in a later run, so a private photo or a voice
/// note never sits in the cache for long.
///
/// An interface-free class on purpose: the root is injectable, which is all a
/// test needs.
final class MediaTemp {
  MediaTemp({Future<Directory> Function()? root, Random? random})
    : _root = root ?? _cacheRoot,
      _random = random ?? Random.secure();

  final Future<Directory> Function() _root;
  final Random _random;

  /// A folder is swept (files older than this go) the first time it is used
  /// in a process.
  static const staleAfter = Duration(hours: 6);

  /// The folders this class owns, under the cache root.
  static const captures = 'helix_capture';
  static const voice = 'helix_voice';
  static const clean = 'helix_clean';

  /// Where `file_picker` copies a picked file on Android, which the app may
  /// delete after sending: the original is untouched in the gallery.
  static const pickerCache = 'file_picker';

  static const _owned = {captures, voice, clean, pickerCache};

  final Set<String> _swept = {};

  static Future<Directory> _cacheRoot() => getTemporaryDirectory();

  /// The folder [name] (one of the constants above), created and swept.
  Future<Directory> folder(String name) async {
    assert(_owned.contains(name), 'unknown temp folder $name');
    final dir = Directory(p.join((await _root()).path, name));
    await dir.create(recursive: true);
    if (_swept.add(name)) await _sweep(dir);
    return dir;
  }

  /// A new path in [folderName] that nothing uses yet. Names are random.
  Future<String> newPath(String folderName, {String extension = ''}) async {
    final dir = await folder(folderName);
    final bytes = List<int>.generate(12, (_) => _random.nextInt(256));
    final name = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final dot = extension.isEmpty
        ? ''
        : extension.startsWith('.')
        ? extension
        : '.$extension';
    return p.join(dir.path, '$name$dot');
  }

  /// Whether [path] is a file this class (or `file_picker`'s cache) made, and
  /// so one the app may delete. A file the person picked from their own
  /// storage is never one.
  Future<bool> owns(String path) async {
    final root = p.normalize(p.absolute((await _root()).path));
    final target = p.normalize(p.absolute(path));
    for (final name in _owned) {
      if (p.isWithin(p.join(root, name), target)) return true;
    }
    return false;
  }

  /// Deletes [path] when [owns] it. Best effort, and never throws: a file
  /// already gone is not a failure of the send, and one still held open (the
  /// preview that shows it has not let go yet; Windows will not delete an open
  /// file) is tried again a moment later, then left for the next sweep.
  Future<void> delete(String path) async {
    try {
      if (!await owns(path)) return;
    } on Object {
      return;
    }
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
        return;
      } on Object {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  Future<void> deleteAll(Iterable<String> paths) async {
    for (final path in paths.toSet()) {
      await delete(path);
    }
  }

  Future<void> _sweep(Directory dir) async {
    try {
      final cutoff = DateTime.now().subtract(staleAfter);
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          try {
            await entity.delete();
          } on Object {
            // In use or already gone.
          }
        }
      }
    } on Object {
      // A sweep is housekeeping; never let it stop a send.
    }
  }
}
