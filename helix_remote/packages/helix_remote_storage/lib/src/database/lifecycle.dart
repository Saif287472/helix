part of '../database.dart';

mixin RemoteDatabaseLifecycle on HelixRemoteDatabaseBase {
  Database _openDatabase() {
    final key = password;
    if (key == null) {
      return sqlite3.open(file.path);
    }

    if (file.path == ':memory:') {
      final db = sqlite3.openInMemory();
      _assertSqlCipherAvailable(db);
      _applySqlCipherKey(db, key);
      _assertDatabaseReadable(db);
      return db;
    }

    if (!file.existsSync() || file.lengthSync() == 0) {
      final db = sqlite3.open(file.path);
      _assertSqlCipherAvailable(db);
      _applySqlCipherKey(db, key);
      _assertDatabaseReadable(db);
      return db;
    }

    final db = sqlite3.open(file.path);
    var sqlCipherAvailable = false;
    try {
      _assertSqlCipherAvailable(db);
      sqlCipherAvailable = true;
      _applySqlCipherKey(db, key);
      _assertDatabaseReadable(db);
      return db;
    } catch (error) {
      db.close();
      if (!sqlCipherAvailable) {
        rethrow;
      }
      if (!_hasPlaintextSqliteHeader(file)) {
        throw RemoteDatabaseEncryptionException(
          'Unable to open encrypted Remote database with the supplied key.',
          error,
        );
      }
      _migratePlaintextDatabase(key);
      final migrated = sqlite3.open(file.path);
      _assertSqlCipherAvailable(migrated);
      _applySqlCipherKey(migrated, key);
      _assertDatabaseReadable(migrated);
      return migrated;
    }
  }

  void _configureDatabase(Database db) {
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA foreign_keys = ON;');
  }

  void _assertSqlCipherAvailable(Database db) {
    final rows = db.select('PRAGMA cipher_version;');
    if (rows.isEmpty || '${rows.first.values.first}'.isEmpty) {
      throw RemoteDatabaseEncryptionException(
        'SQLCipher is not loaded; refusing to open Remote database with a key.',
      );
    }
  }

  void _applySqlCipherKey(Database db, String key) {
    db.execute("PRAGMA key = '${_escapeSingleQuotes(key)}';");
  }

  void _assertDatabaseReadable(Database db) {
    db.select('SELECT count(*) FROM sqlite_master;');
  }

  void _assertIntegrityOk(Database db) {
    final rows = db.select('PRAGMA integrity_check;');
    if (rows.length != 1 || rows.first.values.first != 'ok') {
      throw RemoteDatabaseEncryptionException(
        'Remote database integrity check failed.',
      );
    }
  }

  void _assertAttachedIntegrityOk(Database db, String schemaName) {
    final rows = db.select('PRAGMA $schemaName.integrity_check;');
    if (rows.length != 1 || rows.first.values.first != 'ok') {
      throw RemoteDatabaseMigrationException(
        'Encrypted Remote database migration integrity check failed.',
      );
    }
  }

  bool _hasPlaintextSqliteHeader(File file) {
    if (!file.existsSync() || file.lengthSync() < 16) {
      return false;
    }
    final header = file.openSync()..setPositionSync(0);
    try {
      final bytes = header.readSync(16);
      return ascii.decode(bytes, allowInvalid: true) == 'SQLite format 3\u0000';
    } finally {
      header.closeSync();
    }
  }

  void _migratePlaintextDatabase(String key) {
    final encryptedTemp = File('${file.path}.p2-encrypted-temp');
    final plaintextBackup = File('${file.path}.p2-plaintext-backup');
    _deleteDatabaseFiles(encryptedTemp);
    _deleteDatabaseFiles(plaintextBackup);

    final source = sqlite3.open(file.path);
    try {
      _assertIntegrityOk(source);
      try {
        source.execute('PRAGMA wal_checkpoint(TRUNCATE);');
      } catch (_) {}
      source.execute('PRAGMA journal_mode = DELETE;');
      final attach = source.prepare('ATTACH DATABASE ? AS encrypted KEY ?;');
      try {
        attach.execute([encryptedTemp.path, key]);
      } finally {
        attach.close();
      }
      source.execute("SELECT sqlcipher_export('encrypted');");
      _assertAttachedIntegrityOk(source, 'encrypted');
      source.execute('DETACH DATABASE encrypted;');
    } catch (error) {
      throw RemoteDatabaseMigrationException(
        'Failed to copy plaintext Remote database into encrypted SQLCipher database.',
        error,
      );
    } finally {
      source.close();
    }

    _validateEncryptedFile(encryptedTemp, key);
    _swapEncryptedDatabaseWithRollback(
      encryptedTemp: encryptedTemp,
      plaintextBackup: plaintextBackup,
      key: key,
    );
  }

  void _validateEncryptedFile(File encryptedFile, String key) {
    final encrypted = sqlite3.open(encryptedFile.path);
    try {
      _assertSqlCipherAvailable(encrypted);
      _applySqlCipherKey(encrypted, key);
      _assertDatabaseReadable(encrypted);
      _assertIntegrityOk(encrypted);
    } finally {
      encrypted.close();
    }
  }

  void _swapEncryptedDatabaseWithRollback({
    required File encryptedTemp,
    required File plaintextBackup,
    required String key,
  }) {
    try {
      file.renameSync(plaintextBackup.path);
      if (migrationFault ==
          RemoteDatabaseMigrationFault.afterPlaintextBackupRename) {
        throw StateError('Injected migration fault after plaintext backup.');
      }

      encryptedTemp.renameSync(file.path);
      if (migrationFault ==
          RemoteDatabaseMigrationFault.afterEncryptedSwapRename) {
        throw StateError('Injected migration fault after encrypted swap.');
      }

      _validateEncryptedFile(file, key);
      _deleteDatabaseFiles(plaintextBackup);
    } catch (error) {
      if (plaintextBackup.existsSync()) {
        if (file.existsSync()) {
          _deleteDatabaseFiles(file);
        }
        plaintextBackup.renameSync(file.path);
      }
      _deleteDatabaseFiles(encryptedTemp);
      throw RemoteDatabaseMigrationException(
        'Plaintext-to-encrypted Remote database migration rolled back.',
        error,
      );
    }
  }

  void _deleteDatabaseFiles(File databaseFile) {
    for (final suffix in const ['', '-wal', '-shm']) {
      final candidate = File('${databaseFile.path}$suffix');
      if (candidate.existsSync()) {
        try {
          candidate.deleteSync();
        } catch (_) {}
      }
    }
  }

  // SQLCipher PRAGMA key does not accept sqlite3 bound parameters.
  String _escapeSingleQuotes(String s) => s.replaceAll("'", "''");

  void close() => _db.close();

  /// Execute a raw SQL statement (e.g. BEGIN / COMMIT / ROLLBACK).
  void rawExecute(String sql) => _db.execute(sql);

  void deleteFiles() {
    _db.close();
    _deleteDatabaseFiles(file);
  }
}
