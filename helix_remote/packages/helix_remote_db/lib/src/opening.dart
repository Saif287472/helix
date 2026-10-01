import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:sqlite3/sqlite3.dart';

/// The 32-byte SQLCipher key for one local database.
///
/// It is applied as a raw key (`PRAGMA key = "x'…'"`), so SQLCipher skips its
/// passphrase KDF: the key is already random, and opening stays fast in the
/// FCM background isolate. The app keeps it in the platform keystore; it
/// never leaves the device. [toString] never shows it.
@immutable
final class DatabaseKey {
  DatabaseKey(List<int> bytes) : _bytes = Uint8List.fromList(bytes) {
    if (_bytes.length != length) {
      throw ArgumentError.value(
        '<${_bytes.length} bytes>',
        'bytes',
        'a database key is exactly $length bytes',
      );
    }
  }

  /// A fresh key from the OS CSPRNG.
  factory DatabaseKey.generate() {
    final random = Random.secure();
    return DatabaseKey(List<int>.generate(length, (_) => random.nextInt(256)));
  }

  static const length = 32;

  final Uint8List _bytes;

  /// A copy of the key, for the caller to store in the keystore.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  String get _hex =>
      _bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  @override
  bool operator ==(Object other) {
    if (other is! DatabaseKey) return false;
    var diff = 0;
    for (var i = 0; i < length; i++) {
      diff |= _bytes[i] ^ other._bytes[i];
    }
    return diff == 0;
  }

  @override
  int get hashCode => Object.hashAll(_bytes);

  @override
  String toString() => 'DatabaseKey(<redacted>)';
}

/// The database could not be opened as an encrypted database: SQLCipher is
/// missing or inactive, the key is wrong, or the file is plaintext. Opening
/// fails closed; there is no unencrypted fallback. The message never contains
/// key material.
final class DbEncryptionException implements Exception {
  const DbEncryptionException(this.message);

  final String message;

  @override
  String toString() => 'DbEncryptionException: $message';
}

const _plaintextHeader = 'SQLite format 3\u0000';

/// True if [file] starts with the plaintext SQLite header. An encrypted
/// SQLCipher file starts with its random salt instead.
bool hasPlaintextSqliteHeader(File file) {
  if (!file.existsSync() || file.lengthSync() < 16) return false;
  final handle = file.openSync();
  try {
    return ascii.decode(handle.readSync(16), allowInvalid: true) ==
        _plaintextHeader;
  } finally {
    handle.closeSync();
  }
}

/// Refuses to open a plaintext database file. v2 starts from an empty
/// encrypted database (plan D2), so a plaintext file is never migrated.
void refusePlaintextFile(File file) {
  if (hasPlaintextSqliteHeader(file)) {
    throw const DbEncryptionException(
      'refusing to open a plaintext database file',
    );
  }
}

/// Connection setup for an encrypted database. Runs on the database isolate
/// before drift issues its first statement.
///
/// Fails closed: SQLCipher must be the loaded library, the key must take
/// effect (`cipher_status`), and the file must decrypt with it.
void setUpEncryptedConnection(Database db, String keyHex, {required bool wal}) {
  final version = db.select('PRAGMA cipher_version;');
  if (version.isEmpty || '${version.first.values.first ?? ''}'.isEmpty) {
    throw const DbEncryptionException(
      'SQLCipher is not loaded; refusing to open the database',
    );
  }
  db.execute('PRAGMA key = "x\'$keyHex\'";');
  final status = db.select('PRAGMA cipher_status;');
  if (status.isEmpty || '${status.first.values.first}' != '1') {
    throw const DbEncryptionException('the SQLCipher key did not take effect');
  }
  try {
    db.select('SELECT count(*) FROM sqlite_master;');
  } on SqliteException {
    throw const DbEncryptionException(
      'the database does not decrypt with this key',
    );
  }
  _setUpConnection(db, wal: wal);
}

/// Connection setup for an unencrypted in-memory database (tests only).
void setUpPlainMemoryConnection(Database db) =>
    _setUpConnection(db, wal: false);

void _setUpConnection(Database db, {required bool wal}) {
  if (wal) {
    final mode = db.select('PRAGMA journal_mode = WAL;');
    if ('${mode.first.values.first}'.toLowerCase() != 'wal') {
      throw StateError('could not enable write-ahead logging');
    }
    db.execute('PRAGMA synchronous = NORMAL;');
  }
  db.execute('PRAGMA foreign_keys = ON;');
}

/// The hex form of [key] for [setUpEncryptedConnection]. Internal: it exists
/// so the setup closure sent to the database isolate captures only a string.
String keyHexOf(DatabaseKey key) => key._hex;
