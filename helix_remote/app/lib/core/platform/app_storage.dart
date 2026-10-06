import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where the app keeps its files and its small non-secret settings.
///
/// The database key is **not** here: it lives in the platform keystore, in
/// [SecureKeyStore].
abstract final class AppPaths {
  /// `<app data>/helix_remote/helix_remote.db` (see `_base`).
  static Future<File> databaseFile() async {
    final dir = await _base();
    return File(p.join(dir.path, 'helix_remote.db'));
  }

  /// Where attachment downloads are written before they are shown. The engine
  /// stores `transfer: remote` rows in C3b; C4's transfer queue fills this.
  static Future<Directory> attachmentCache() async {
    final dir = await _base();
    return Directory(p.join(dir.path, 'attachments'))
      ..createSync(recursive: true);
  }

  /// The profile picture chosen on this phone (PNG). Not synced: the engine
  /// does not publish avatars yet, so it is only ever shown on this device.
  static Future<File> profileAvatarFile() async {
    final dir = await _base();
    return File(p.join(dir.path, 'profile_avatar.png'));
  }

  /// Everything the app keeps on disk, for the storage page.
  static Future<Directory> appDirectory() => _base();

  /// Windows only: the machine-local, non-roaming per-user folder
  /// (`%LOCALAPPDATA%/<company>/<product>`). Overridden in tests.
  @visibleForTesting
  static Future<Directory> Function() localDataDirectory =
      getApplicationCacheDirectory;

  /// Android's app-private files directory. Overridden in tests.
  @visibleForTesting
  static Future<Directory> Function() privateDataDirectory =
      getApplicationDocumentsDirectory;

  /// Whether this is Windows; a test sets it to exercise both paths.
  @visibleForTesting
  static bool Function() isWindows = () => Platform.isWindows;

  /// Where the app's folder lives.
  ///
  /// **Not** `Documents` on Windows: that folder is the person's own, and
  /// OneDrive's "known folder backup" syncs it, which would carry the encrypted
  /// database, its attachments and the avatar to a cloud they never chose. The
  /// per-user local application-data folder is machine-local and is not
  /// roamed (the "application support" folder is, in a domain), so it is used
  /// instead. On Android `getApplicationDocumentsDirectory` is the app's
  /// private directory and stays.
  static Future<Directory> _base() async {
    final parent = isWindows()
        ? await localDataDirectory()
        : await privateDataDirectory();
    return Directory(p.join(parent.path, 'helix_remote'))
      ..createSync(recursive: true);
  }

  /// Deletes what a signed-out device must not keep: the avatar picture (a
  /// plaintext PNG) and every downloaded attachment. With [includeDatabase],
  /// the database file and its journal files go too (the destructive reset).
  ///
  /// Works from the paths alone, so it still finishes when the engine, the
  /// database or the keystore cannot be opened. Each file is tried on its own:
  /// one that cannot be deleted does not stop the rest.
  static Future<void> wipeLocalFiles({bool includeDatabase = false}) async {
    final Directory base;
    try {
      base = await _base();
    } on Object {
      // No app folder can be found (no platform plugin), so none was written.
      return;
    }
    final targets = <FileSystemEntity>[
      File(p.join(base.path, 'profile_avatar.png')),
      Directory(p.join(base.path, 'attachments')),
      if (includeDatabase)
        for (final suffix in const ['', '-wal', '-shm', '-journal'])
          File(p.join(base.path, 'helix_remote.db$suffix')),
    ];
    for (final entity in targets) {
      try {
        if (entity is Directory) {
          if (await entity.exists()) await entity.delete(recursive: true);
        } else if (await entity.exists()) {
          await entity.delete();
        }
      } on Object {
        // Nothing sensible to do about one stuck file; the others still go.
      }
    }
  }
}

/// The 32-byte SQLCipher key for the local database, in the platform keystore.
///
/// The key is generated once, on this device, and never leaves it. A device
/// that loses it cannot read its database: the app reports that and asks the
/// user to reset (see `EngineStatus` / `core/engine`), rather than opening a
/// new empty database over the old one.
final class SecureKeyStore {
  SecureKeyStore({FlutterSecureStorage? storage})
    : _storage =
          storage ?? const FlutterSecureStorage(aOptions: AndroidOptions());

  static const _accountName = 'helix_remote_db_key';

  final FlutterSecureStorage _storage;

  /// The key for [file], generating and storing one the first time.
  ///
  /// When [file] already exists but the keystore has no key, the database was
  /// written by an install whose keystore is gone (a restore onto new
  /// hardware). That is not recoverable, so it throws [KeyUnavailable] rather
  /// than generating a second key that cannot open anything.
  Future<DatabaseKey> keyFor(File file) async {
    final stored = await _read();
    if (stored != null) return stored;
    if (await file.exists()) throw const KeyUnavailable();
    final key = DatabaseKey.generate();
    await _write(key);
    return key;
  }

  /// Whether a key is already stored, without reading its bytes.
  Future<bool> hasKey() async => (await _read()) != null;

  /// Forgets the key. Only ever called after the database has been deleted.
  Future<void> forget() => _storage.delete(key: _accountName);

  Future<DatabaseKey?> _read() async {
    final encoded = await _storage.read(key: _accountName);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final bytes = base64Decode(encoded);
      return DatabaseKey(bytes);
    } on Object {
      // A key that is not 32 bytes was never written by this code.
      return null;
    }
  }

  Future<void> _write(DatabaseKey key) =>
      _storage.write(key: _accountName, value: base64Encode(key.bytes));
}

/// The database exists but its key is not in the keystore.
///
/// The engine cannot open it and must not open a new one over it. The app
/// shows a destructive reset, exactly as v1 did.
final class KeyUnavailable implements Exception {
  const KeyUnavailable();

  @override
  String toString() => 'the local database key is not available';
}

/// The server this device is signed in to, remembered between launches.
///
/// An empty value means "no server chosen yet", which is the state right
/// after a wipe or a first install: sign-in opens on Helix Global.
final class ServerUrlStore {
  ServerUrlStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _accountName = 'helix_remote_server_url';

  final FlutterSecureStorage _storage;

  Future<String?> load() async {
    final value = await _storage.read(key: _accountName);
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> save(String url) =>
      _storage.write(key: _accountName, value: url);

  Future<void> clear() => _storage.delete(key: _accountName);
}
