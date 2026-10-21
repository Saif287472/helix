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
  /// The id of the first account on a device. Its files keep the names a
  /// one-account install always had, directly in the app folder; every other
  /// account has its own folder, `accounts/<id>/`.
  static const firstAccount = 'primary';

  static final _accountId = RegExp(r'^[a-z0-9]{1,32}$');

  /// Where [account]'s database, attachments and picture live.
  static Future<Directory> accountDirectory(String account) async {
    if (!_accountId.hasMatch(account)) {
      throw ArgumentError.value(account, 'account', 'not an account id');
    }
    final base = await _base();
    if (account == firstAccount) return base;
    return Directory(p.join(base.path, 'accounts', account))
      ..createSync(recursive: true);
  }

  /// The folders of accounts other than the first, by id, whether or not the
  /// device still lists them (a sign-in that never finished leaves one).
  static Future<List<String>> accountFolders() async {
    final dir = Directory(p.join((await _base()).path, 'accounts'));
    if (!await dir.exists()) return const [];
    return [
      for (final entity in dir.listSync())
        if (entity is Directory) p.basename(entity.path),
    ].where(_accountId.hasMatch).toList();
  }

  /// Deletes the folder of an account other than the first, with whatever
  /// is left in it.
  static Future<void> deleteAccountFolder(String account) async {
    if (account == firstAccount) return;
    final dir = await accountDirectory(account);
    try {
      await dir.delete(recursive: true);
    } on Object {
      // Tried again at the next start.
    }
  }

  /// `<account folder>/helix_remote.db`; for the first account that is
  /// `<app data>/helix_remote/helix_remote.db` (see `_base`).
  static Future<File> databaseFile(String account) async {
    final dir = await accountDirectory(account);
    return File(p.join(dir.path, 'helix_remote.db'));
  }

  /// Where [account]'s attachment downloads are written before they are
  /// shown.
  static Future<Directory> attachmentCache(String account) async {
    final dir = await accountDirectory(account);
    return Directory(p.join(dir.path, 'attachments'))
      ..createSync(recursive: true);
  }

  /// The profile picture chosen on this phone for [account] (PNG). Not
  /// synced: the engine does not publish avatars yet, so it is only ever shown
  /// on this device.
  static Future<File> profileAvatarFile(String account) async {
    final dir = await accountDirectory(account);
    return File(p.join(dir.path, 'profile_avatar.png'));
  }

  /// Settings that belong to this device, not the account (the theme). Kept
  /// when the account is signed out, and only ever plain choices.
  static Future<File> deviceSettingsFile() async {
    final dir = await _base();
    return File(p.join(dir.path, 'device_settings.json'));
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

  /// Deletes what a signed-out account must not leave: the avatar picture (a
  /// plaintext PNG) and every downloaded attachment. With [includeDatabase],
  /// the database file and its journal files go too (the destructive reset),
  /// and so does the account's own folder once it is empty.
  ///
  /// Works from the paths alone, so it still finishes when the engine, the
  /// database or the keystore cannot be opened. Each file is tried on its own:
  /// one that cannot be deleted does not stop the rest.
  static Future<void> wipeLocalFiles(
    String account, {
    bool includeDatabase = false,
  }) async {
    final Directory dir;
    try {
      dir = await accountDirectory(account);
    } on Object {
      // No app folder can be found (no platform plugin), so none was written.
      return;
    }
    final targets = <FileSystemEntity>[
      File(p.join(dir.path, 'profile_avatar.png')),
      Directory(p.join(dir.path, 'attachments')),
      if (includeDatabase)
        for (final suffix in const ['', '-wal', '-shm', '-journal'])
          File(p.join(dir.path, 'helix_remote.db$suffix')),
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
    if (includeDatabase && account != firstAccount) {
      try {
        await dir.delete();
      } on Object {
        // Not empty (a file above was stuck): left for the next clean-up.
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

  /// The keystore entry for [account]'s key. The first account keeps the
  /// name a one-account install always used.
  static String _entry(String account) => account == AppPaths.firstAccount
      ? 'helix_remote_db_key'
      : 'helix_remote_db_key.$account';

  final FlutterSecureStorage _storage;

  /// [account]'s key for [file], generating and storing one the first time.
  ///
  /// When [file] already exists but the keystore has no key, the database was
  /// written by an install whose keystore is gone (a restore onto new
  /// hardware). That is not recoverable, so it throws [KeyUnavailable] rather
  /// than generating a second key that cannot open anything.
  Future<DatabaseKey> keyFor(String account, File file) async {
    final stored = await _read(account);
    if (stored != null) return stored;
    if (await file.exists()) throw const KeyUnavailable();
    final key = DatabaseKey.generate();
    await _write(account, key);
    return key;
  }

  /// Whether [account] has a key stored, without reading its bytes.
  Future<bool> hasKey(String account) async => (await _read(account)) != null;

  /// Forgets [account]'s key. Only ever called after its database has been
  /// deleted.
  Future<void> forget(String account) => _storage.delete(key: _entry(account));

  Future<DatabaseKey?> _read(String account) async {
    final encoded = await _storage.read(key: _entry(account));
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final bytes = base64Decode(encoded);
      return DatabaseKey(bytes);
    } on Object {
      // A key that is not 32 bytes was never written by this code.
      return null;
    }
  }

  Future<void> _write(String account, DatabaseKey key) =>
      _storage.write(key: _entry(account), value: base64Encode(key.bytes));
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
