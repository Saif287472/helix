import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:sqlite3/sqlite3.dart';
import 'package:helix_remote_domain/models.dart';

enum RemoteDatabaseMigrationFault {
  afterPlaintextBackupRename,
  afterEncryptedSwapRename,
}

class RemoteDatabaseEncryptionException implements Exception {
  RemoteDatabaseEncryptionException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() {
    final suffix = cause == null ? '' : ' Cause: $cause';
    return 'RemoteDatabaseEncryptionException: $message$suffix';
  }
}

class RemoteDatabaseMigrationException implements Exception {
  RemoteDatabaseMigrationException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() {
    final suffix = cause == null ? '' : ' Cause: $cause';
    return 'RemoteDatabaseMigrationException: $message$suffix';
  }
}

class HelixRemoteDatabase {
  final File file;
  final String? password;
  final RemoteDatabaseMigrationFault? migrationFault;
  late final Database _db;

  HelixRemoteDatabase(this.file, {this.password, this.migrationFault});

  void initialize() {
    Database? opened;
    try {
      opened = _openDatabase();
      _db = opened;
      _configureDatabase(_db);
      _onCreate();
      _applyMigrations();
      _assertIntegrityOk(_db);
    } catch (_) {
      opened?.close();
      rethrow;
    }
  }

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

  static void _assertSqlCipherAvailable(Database db) {
    final rows = db.select('PRAGMA cipher_version;');
    if (rows.isEmpty || '${rows.first.values.first}'.isEmpty) {
      throw RemoteDatabaseEncryptionException(
        'SQLCipher is not loaded; refusing to open Remote database with a key.',
      );
    }
  }

  static void _applySqlCipherKey(Database db, String key) {
    db.execute("PRAGMA key = '${_escapeSingleQuotes(key)}';");
  }

  static void _assertDatabaseReadable(Database db) {
    db.select('SELECT count(*) FROM sqlite_master;');
  }

  static void _assertIntegrityOk(Database db) {
    final rows = db.select('PRAGMA integrity_check;');
    if (rows.length != 1 || rows.first.values.first != 'ok') {
      throw RemoteDatabaseEncryptionException(
        'Remote database integrity check failed.',
      );
    }
  }

  static void _assertAttachedIntegrityOk(Database db, String schemaName) {
    final rows = db.select('PRAGMA $schemaName.integrity_check;');
    if (rows.length != 1 || rows.first.values.first != 'ok') {
      throw RemoteDatabaseMigrationException(
        'Encrypted Remote database migration integrity check failed.',
      );
    }
  }

  static bool _hasPlaintextSqliteHeader(File file) {
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

  static void _deleteDatabaseFiles(File databaseFile) {
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
  static String _escapeSingleQuotes(String s) => s.replaceAll("'", "''");

  int get schemaVersion =>
      _db.select('PRAGMA user_version').first['user_version'] as int;

  void _onCreate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        account_id TEXT PRIMARY KEY,
        username TEXT NOT NULL,
        identity_public_key TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        status TEXT NOT NULL
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS devices (
        device_id TEXT NOT NULL,
        account_id TEXT NOT NULL,
        device_name TEXT NOT NULL,
        device_signing_public_key TEXT NOT NULL,
        device_agreement_public_key TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (account_id, device_id),
        FOREIGN KEY (account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS contacts (
        peer_account_id TEXT PRIMARY KEY,
        nickname TEXT NOT NULL,
        status TEXT NOT NULL
      );
    ''');
    _createContactRequestsTable();

    _db.execute('''
      CREATE TABLE IF NOT EXISTS conversations (
        conversation_id TEXT PRIMARY KEY,
        title TEXT,
        type TEXT NOT NULL,
        last_sequence INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS members (
        conversation_id TEXT NOT NULL,
        account_id TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'MEMBER',
        PRIMARY KEY (conversation_id, account_id),
        FOREIGN KEY (conversation_id) REFERENCES conversations(conversation_id) ON DELETE CASCADE
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        message_id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        sender_account_id TEXT NOT NULL,
        sender_device_id TEXT NOT NULL,
        ciphertext_blob TEXT NOT NULL,
        server_sequence INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        status TEXT NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES conversations(conversation_id) ON DELETE CASCADE
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS message_receipts (
        receipt_id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        account_id TEXT NOT NULL,
        device_id TEXT,
        receipt_type TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      );
    ''');

    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_conv_seq
      ON messages(conversation_id, server_sequence ASC);
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_timestamp
      ON messages(timestamp DESC);
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS revisions (
        revision_id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        type TEXT NOT NULL,
        author_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        FOREIGN KEY (message_id) REFERENCES messages(message_id) ON DELETE CASCADE
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS attachments (
        attachment_id TEXT PRIMARY KEY,
        filename TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        encrypted_key TEXT NOT NULL,
        local_path TEXT,
        imported_source_path TEXT,
        encrypted_cache_path TEXT,
        downloaded_ciphertext_path TEXT,
        exported_plaintext_path TEXT,
        status TEXT NOT NULL
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS groups (
        group_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        owner_id TEXT NOT NULL,
        status TEXT NOT NULL
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS group_epoch_keys (
        group_id TEXT NOT NULL,
        epoch INTEGER NOT NULL,
        key_id TEXT NOT NULL,
        key_material TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (group_id, epoch)
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS call_history (
        call_id TEXT PRIMARY KEY,
        peer_id TEXT NOT NULL,
        is_video INTEGER NOT NULL,
        direction TEXT NOT NULL,
        duration INTEGER NOT NULL,
        timestamp INTEGER NOT NULL
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS sync_cursors (
        conversation_id TEXT PRIMARY KEY,
        last_sequence INTEGER NOT NULL
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS processed_event_ids (
        event_id TEXT PRIMARY KEY,
        server_sequence INTEGER NOT NULL UNIQUE,
        event_type TEXT NOT NULL,
        content_fingerprint TEXT NOT NULL,
        processed_at INTEGER NOT NULL
      );
    ''');

    // Schema v2 layout for pending_operations:
    // - idempotency_key: server-visible stable ID to prevent duplicate delivery
    // - next_attempt_at: persisted backoff deadline (milliseconds since epoch)
    _db.execute('''
      CREATE TABLE IF NOT EXISTS pending_operations (
        op_id TEXT PRIMARY KEY,
        idempotency_key TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL,
        payload TEXT NOT NULL,
        status TEXT NOT NULL,
        retries INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        next_attempt_at INTEGER NOT NULL DEFAULT 0
      );
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pending_operations_due
      ON pending_operations(status, next_attempt_at, created_at);
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS tombstones (
        item_id TEXT NOT NULL,
        type TEXT NOT NULL,
        deleted_at INTEGER NOT NULL,
        PRIMARY KEY (item_id, type)
      );
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_tombstones_type_deleted
      ON tombstones(type, deleted_at);
    ''');

    // P4-04: Inbound events that fail parsing or application are quarantined
    // here so they never block subsequent valid events or advance the cursor.
    _db.execute('''
      CREATE TABLE IF NOT EXISTS quarantine_events (
        event_id TEXT PRIMARY KEY,
        server_sequence INTEGER NOT NULL,
        event_type TEXT NOT NULL,
        raw_payload TEXT NOT NULL,
        failure_reason TEXT NOT NULL,
        quarantined_at INTEGER NOT NULL
      );
    ''');

    _createRemoteCryptoTables();
  }

  void _applyMigrations() {
    final version = schemaVersion;
    if (version < 1) {
      // Rename messages.text to ciphertext_blob for schema clarity.
      // On fresh databases the new column name is created by _onCreate above;
      // this branch only runs on pre-existing v0 DBs that have 'text'.
      try {
        _db.execute(
          'ALTER TABLE messages RENAME COLUMN text TO ciphertext_blob;',
        );
      } catch (_) {
        // Column may already be renamed or may not exist yet; safe to ignore.
      }
      _db.execute('PRAGMA user_version = 1;');
    }
    if (version < 2) {
      // Add columns introduced in schema v2 to pre-existing databases.
      try {
        _db.execute(
          "ALTER TABLE pending_operations ADD COLUMN idempotency_key TEXT NOT NULL DEFAULT '';",
        );
      } catch (_) {}
      try {
        _db.execute(
          'ALTER TABLE pending_operations ADD COLUMN next_attempt_at INTEGER NOT NULL DEFAULT 0;',
        );
      } catch (_) {}
      _db.execute('PRAGMA user_version = 2;');
    }
    if (version < 3) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS processed_event_ids (
          event_id TEXT PRIMARY KEY,
          server_sequence INTEGER NOT NULL UNIQUE,
          event_type TEXT NOT NULL,
          content_fingerprint TEXT NOT NULL,
          processed_at INTEGER NOT NULL
        );
      ''');
      _db.execute('PRAGMA user_version = 3;');
    }
    if (version < 4) {
      // Single-row table tracking the in-progress call so crash recovery
      // can detect stale calls and mark them as missed on next launch.
      _db.execute('''
        CREATE TABLE IF NOT EXISTS active_call (
          call_id TEXT NOT NULL,
          peer_id TEXT NOT NULL,
          is_video INTEGER NOT NULL,
          started_at INTEGER NOT NULL
        );
      ''');
      _db.execute('PRAGMA user_version = 4;');
    }
    if (version < 5) {
      // P16-001: Group metadata columns on existing groups table.
      try {
        _db.execute('ALTER TABLE groups ADD COLUMN avatar_uri TEXT;');
      } catch (_) {}
      try {
        _db.execute(
          "ALTER TABLE groups ADD COLUMN creator_id TEXT NOT NULL DEFAULT '';",
        );
      } catch (_) {}
      try {
        _db.execute(
          'ALTER TABLE groups ADD COLUMN epoch INTEGER NOT NULL DEFAULT 0;',
        );
      } catch (_) {}
      // P16-003: Pending and responded invite records for the current device.
      _db.execute('''
        CREATE TABLE IF NOT EXISTS group_invites (
          invite_id TEXT PRIMARY KEY,
          group_id TEXT NOT NULL,
          inviter_id TEXT NOT NULL,
          status TEXT NOT NULL,
          created_at INTEGER NOT NULL
        );
      ''');
      _db.execute('PRAGMA user_version = 5;');
    }
    if (version < 6) {
      _migrateDeviceIdentifiersToText();
      _db.execute('PRAGMA user_version = 6;');
    }
    if (version < 7) {
      _createRemoteCryptoTables();
      _db.execute('PRAGMA user_version = 7;');
    }
    if (version < 8) {
      // P4-04: Quarantine table for inbound events that fail application.
      _db.execute('''
        CREATE TABLE IF NOT EXISTS quarantine_events (
          event_id TEXT PRIMARY KEY,
          server_sequence INTEGER NOT NULL,
          event_type TEXT NOT NULL,
          raw_payload TEXT NOT NULL,
          failure_reason TEXT NOT NULL,
          quarantined_at INTEGER NOT NULL
        );
      ''');
      // P4-05: Add server_sequence to revisions for deterministic conflict
      // resolution — server sequence wins over wall-clock ordering.
      try {
        _db.execute(
          'ALTER TABLE revisions ADD COLUMN server_sequence INTEGER NOT NULL DEFAULT 0;',
        );
      } catch (_) {}
      _db.execute('PRAGMA user_version = 8;');
    }
    if (version < 9) {
      for (final column in const {
        'imported_source_path': 'TEXT',
        'encrypted_cache_path': 'TEXT',
        'downloaded_ciphertext_path': 'TEXT',
        'exported_plaintext_path': 'TEXT',
      }.entries) {
        try {
          _db.execute(
            'ALTER TABLE attachments ADD COLUMN ${column.key} ${column.value};',
          );
        } catch (_) {}
      }
      _db.execute('PRAGMA user_version = 9;');
    }
    if (version < 10) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS group_epoch_keys (
          group_id TEXT NOT NULL,
          epoch INTEGER NOT NULL,
          key_id TEXT NOT NULL,
          key_material TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          PRIMARY KEY (group_id, epoch)
        );
      ''');
      _db.execute('PRAGMA user_version = 10;');
    }
    if (version < 11) {
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_messages_timestamp
        ON messages(timestamp DESC);
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_pending_operations_due
        ON pending_operations(status, next_attempt_at, created_at);
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_tombstones_type_deleted
        ON tombstones(type, deleted_at);
      ''');
      _db.execute('PRAGMA user_version = 11;');
    }
    if (version < 12) {
      _createContactRequestsTable();
      _db.execute('PRAGMA user_version = 12;');
    }
  }

  void _createContactRequestsTable() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS contact_requests (
        request_id TEXT PRIMARY KEY,
        peer_account_id TEXT NOT NULL,
        direction TEXT NOT NULL,
        status TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        nickname TEXT NOT NULL DEFAULT ''
      );
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_contact_requests_peer_status
      ON contact_requests(peer_account_id, status);
    ''');
  }

  void _createRemoteCryptoTables() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS crypto_sessions (
        session_id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        peer_account_id TEXT,
        peer_device_id TEXT,
        role TEXT NOT NULL,
        protocol_version INTEGER NOT NULL,
        root_key TEXT NOT NULL,
        sending_chain_key TEXT NOT NULL,
        receiving_chain_key TEXT NOT NULL,
        send_count INTEGER NOT NULL DEFAULT 0,
        receive_count INTEGER NOT NULL DEFAULT 0,
        previous_chain_length INTEGER NOT NULL DEFAULT 0,
        skipped_keys_json TEXT NOT NULL DEFAULT '[]',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_crypto_sessions_conversation
      ON crypto_sessions(conversation_id);
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS local_prekeys (
        key_id INTEGER NOT NULL,
        role TEXT NOT NULL,
        device_id TEXT NOT NULL,
        public_key TEXT NOT NULL,
        private_key_ref TEXT NOT NULL,
        signature TEXT,
        created_at INTEGER NOT NULL,
        expires_at INTEGER,
        rotation_state TEXT NOT NULL,
        PRIMARY KEY (key_id, role, device_id)
      );
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_local_prekeys_state
      ON local_prekeys(device_id, role, rotation_state, expires_at);
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS trusted_devices (
        account_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        identity_fingerprint TEXT NOT NULL,
        safety_number TEXT NOT NULL,
        status TEXT NOT NULL,
        first_seen_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (account_id, device_id)
      );
    ''');
  }

  void _migrateDeviceIdentifiersToText() {
    final deviceColumns = _tableColumns('devices');
    final hasLegacyDevicePublicKey = deviceColumns.contains(
      'device_public_key',
    );
    _db.execute('PRAGMA foreign_keys = OFF;');
    _db.execute('BEGIN;');
    try {
      if (hasLegacyDevicePublicKey) {
        _db.execute('''
          CREATE TABLE IF NOT EXISTS devices_v6 (
            device_id TEXT NOT NULL,
            account_id TEXT NOT NULL,
            device_name TEXT NOT NULL,
            device_signing_public_key TEXT NOT NULL,
            device_agreement_public_key TEXT NOT NULL,
            status TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            PRIMARY KEY (account_id, device_id),
            FOREIGN KEY (account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
          );
        ''');
        _db.execute('''
          INSERT OR REPLACE INTO devices_v6 (
            device_id,
            account_id,
            device_name,
            device_signing_public_key,
            device_agreement_public_key,
            status,
            created_at
          )
          SELECT
            CAST(device_id AS TEXT),
            account_id,
            device_name,
            device_public_key,
            device_public_key,
            status,
            created_at
          FROM devices;
        ''');
        _db.execute('DROP TABLE devices;');
        _db.execute('ALTER TABLE devices_v6 RENAME TO devices;');
      }

      _db.execute('''
        CREATE TABLE IF NOT EXISTS messages_v6 (
          message_id TEXT PRIMARY KEY,
          conversation_id TEXT NOT NULL,
          sender_account_id TEXT NOT NULL,
          sender_device_id TEXT NOT NULL,
          ciphertext_blob TEXT NOT NULL,
          server_sequence INTEGER NOT NULL,
          timestamp INTEGER NOT NULL,
          status TEXT NOT NULL,
          FOREIGN KEY (conversation_id) REFERENCES conversations(conversation_id) ON DELETE CASCADE
        );
      ''');
      _db.execute('''
        INSERT OR REPLACE INTO messages_v6 (
          message_id,
          conversation_id,
          sender_account_id,
          sender_device_id,
          ciphertext_blob,
          server_sequence,
          timestamp,
          status
        )
        SELECT
          message_id,
          conversation_id,
          sender_account_id,
          CAST(sender_device_id AS TEXT),
          ciphertext_blob,
          server_sequence,
          timestamp,
          status
        FROM messages;
      ''');
      _db.execute('DROP TABLE messages;');
      _db.execute('ALTER TABLE messages_v6 RENAME TO messages;');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_messages_conv_seq
        ON messages(conversation_id, server_sequence ASC);
      ''');

      _db.execute('''
        CREATE TABLE IF NOT EXISTS message_receipts_v6 (
          receipt_id TEXT PRIMARY KEY,
          message_id TEXT NOT NULL,
          conversation_id TEXT NOT NULL,
          account_id TEXT NOT NULL,
          device_id TEXT,
          receipt_type TEXT NOT NULL,
          timestamp INTEGER NOT NULL
        );
      ''');
      _db.execute('''
        INSERT OR REPLACE INTO message_receipts_v6 (
          receipt_id,
          message_id,
          conversation_id,
          account_id,
          device_id,
          receipt_type,
          timestamp
        )
        SELECT
          receipt_id,
          message_id,
          conversation_id,
          account_id,
          CAST(device_id AS TEXT),
          receipt_type,
          timestamp
        FROM message_receipts;
      ''');
      _db.execute('DROP TABLE message_receipts;');
      _db.execute(
        'ALTER TABLE message_receipts_v6 RENAME TO message_receipts;',
      );
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    } finally {
      _db.execute('PRAGMA foreign_keys = ON;');
    }
  }

  Set<String> _tableColumns(String table) {
    return _db
        .select("PRAGMA table_info('$table');")
        .map((row) => row['name'] as String)
        .toSet();
  }

  void close() => _db.close();

  /// Execute a raw SQL statement (e.g. BEGIN / COMMIT / ROLLBACK).
  void rawExecute(String sql) => _db.execute(sql);

  void deleteFiles() {
    _db.close();
    _deleteDatabaseFiles(file);
  }

  // ---------------------------------------------------------------------------
  // Account operations
  // ---------------------------------------------------------------------------

  void upsertAccount(RemoteAccount account) {
    final stmt = _db.prepare('''
      INSERT INTO accounts (account_id, username, identity_public_key, created_at, status)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(account_id) DO UPDATE SET
        username = excluded.username,
        identity_public_key = excluded.identity_public_key,
        status = excluded.status;
    ''');
    stmt.execute([
      account.accountId,
      account.username,
      account.identityPublicKey,
      account.createdAt.millisecondsSinceEpoch,
      account.status,
    ]);
    stmt.close();
  }

  RemoteAccount? getAccount(String accountId) {
    final stmt = _db.prepare('SELECT * FROM accounts WHERE account_id = ?;');
    final res = stmt.select([accountId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return RemoteAccount(
      accountId: row['account_id'] as String,
      username: row['username'] as String,
      identityPublicKey: row['identity_public_key'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      status: row['status'] as String,
    );
  }

  // ---------------------------------------------------------------------------
  // Device operations
  // ---------------------------------------------------------------------------

  void upsertDevice(String accountId, RemoteDevice device) {
    final stmt = _db.prepare('''
      INSERT INTO devices (device_id, account_id, device_name, device_signing_public_key, device_agreement_public_key, status, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(account_id, device_id) DO UPDATE SET
        device_name = excluded.device_name,
        device_signing_public_key = excluded.device_signing_public_key,
        device_agreement_public_key = excluded.device_agreement_public_key,
        status = excluded.status;
    ''');
    stmt.execute([
      device.deviceId,
      accountId,
      device.deviceName,
      device.deviceSigningPublicKey,
      device.deviceAgreementPublicKey,
      device.status,
      device.createdAt.millisecondsSinceEpoch,
    ]);
    stmt.close();
  }

  List<RemoteDevice> getDevices(String accountId) {
    final stmt = _db.prepare('SELECT * FROM devices WHERE account_id = ?;');
    final res = stmt.select([accountId]);
    stmt.close();
    return res
        .map(
          (row) => RemoteDevice(
            deviceId: row['device_id'] as String,
            deviceName: row['device_name'] as String,
            deviceSigningPublicKey: row['device_signing_public_key'] as String,
            deviceAgreementPublicKey:
                row['device_agreement_public_key'] as String,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['created_at'] as int,
            ),
            status: row['status'] as String,
          ),
        )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Contact operations
  // ---------------------------------------------------------------------------

  void upsertContact(RemoteContact contact) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO contacts (peer_account_id, nickname, status)
      VALUES (?, ?, ?);
    ''');
    stmt.execute([contact.peerAccountId, contact.nickname, contact.status]);
    stmt.close();
  }

  List<RemoteContact> getContacts() {
    final stmt = _db.prepare('SELECT * FROM contacts;');
    final res = stmt.select();
    stmt.close();
    return res
        .map(
          (row) => RemoteContact(
            peerAccountId: row['peer_account_id'] as String,
            nickname: row['nickname'] as String,
            status: row['status'] as String,
          ),
        )
        .toList();
  }

  RemoteContact? getContact(String peerAccountId) {
    final stmt = _db.prepare(
      'SELECT * FROM contacts WHERE peer_account_id = ?;',
    );
    final res = stmt.select([peerAccountId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return RemoteContact(
      peerAccountId: row['peer_account_id'] as String,
      nickname: row['nickname'] as String,
      status: row['status'] as String,
    );
  }

  void deleteContact(String peerAccountId) {
    final stmt = _db.prepare('DELETE FROM contacts WHERE peer_account_id = ?;');
    stmt.execute([peerAccountId]);
    stmt.close();
  }

  void upsertContactRequest(RemoteContactRequest request) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO contact_requests (
        request_id,
        peer_account_id,
        direction,
        status,
        updated_at,
        nickname
      )
      VALUES (?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      request.requestId,
      request.peerAccountId,
      request.direction,
      request.status,
      request.updatedAt,
      request.nickname,
    ]);
    stmt.close();
  }

  List<RemoteContactRequest> getContactRequests({String? status}) {
    final stmt = status == null
        ? _db.prepare(
            'SELECT * FROM contact_requests ORDER BY updated_at DESC;',
          )
        : _db.prepare(
            'SELECT * FROM contact_requests WHERE status = ? ORDER BY updated_at DESC;',
          );
    final res = status == null ? stmt.select() : stmt.select([status]);
    stmt.close();
    return res.map(_contactRequestFromRow).toList();
  }

  RemoteContactRequest? getContactRequest(String requestId) {
    final stmt = _db.prepare(
      'SELECT * FROM contact_requests WHERE request_id = ?;',
    );
    final res = stmt.select([requestId]);
    stmt.close();
    if (res.isEmpty) return null;
    return _contactRequestFromRow(res.first);
  }

  RemoteContactRequest? getOpenContactRequestForPeer(String peerAccountId) {
    final stmt = _db.prepare('''
      SELECT * FROM contact_requests
      WHERE peer_account_id = ? AND status = 'Pending'
      ORDER BY updated_at DESC
      LIMIT 1;
    ''');
    final res = stmt.select([peerAccountId]);
    stmt.close();
    if (res.isEmpty) return null;
    return _contactRequestFromRow(res.first);
  }

  void updateContactRequestStatus(
    String requestId,
    String status,
    int updatedAt,
  ) {
    final stmt = _db.prepare('''
      UPDATE contact_requests
      SET status = ?, updated_at = ?
      WHERE request_id = ?;
    ''');
    stmt.execute([status, updatedAt, requestId]);
    stmt.close();
  }

  RemoteContactRequest _contactRequestFromRow(Row row) {
    return RemoteContactRequest(
      requestId: row['request_id'] as String,
      peerAccountId: row['peer_account_id'] as String,
      direction: row['direction'] as String,
      status: row['status'] as String,
      updatedAt: row['updated_at'] as int,
      nickname: row['nickname'] as String? ?? '',
    );
  }

  // ---------------------------------------------------------------------------
  // Conversation operations
  // ---------------------------------------------------------------------------

  void upsertConversation(
    RemoteConversation conversation,
    List<String> memberIds,
  ) {
    _db.execute('SAVEPOINT upsert_conversation;');
    try {
      final stmt = _db.prepare('''
        INSERT INTO conversations (conversation_id, title, type, last_sequence, created_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(conversation_id) DO UPDATE SET
          title = excluded.title,
          type = excluded.type,
          last_sequence = excluded.last_sequence;
      ''');
      stmt.execute([
        conversation.conversationId,
        conversation.title,
        conversation.type,
        conversation.lastActivitySequence,
        conversation.createdAt.millisecondsSinceEpoch,
      ]);
      stmt.close();

      final clearStmt = _db.prepare(
        'DELETE FROM members WHERE conversation_id = ?;',
      );
      clearStmt.execute([conversation.conversationId]);
      clearStmt.close();

      final memStmt = _db.prepare('''
        INSERT INTO members (conversation_id, account_id)
        VALUES (?, ?);
      ''');
      for (final memId in memberIds) {
        memStmt.execute([conversation.conversationId, memId]);
      }
      memStmt.close();

      _db.execute('RELEASE SAVEPOINT upsert_conversation;');
    } catch (_) {
      _db.execute('ROLLBACK TO SAVEPOINT upsert_conversation;');
      _db.execute('RELEASE SAVEPOINT upsert_conversation;');
      rethrow;
    }
  }

  List<RemoteConversation> getConversations() {
    final stmt = _db.prepare('SELECT * FROM conversations;');
    final res = stmt.select();
    stmt.close();
    return res
        .map(
          (row) => RemoteConversation(
            conversationId: row['conversation_id'] as String,
            title: row['title'] as String? ?? '',
            type: row['type'] as String,
            lastActivitySequence: row['last_sequence'] as int,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['created_at'] as int,
            ),
          ),
        )
        .toList();
  }

  List<String> getConversationMembers(String conversationId) {
    final stmt = _db.prepare(
      'SELECT account_id FROM members WHERE conversation_id = ?;',
    );
    final res = stmt.select([conversationId]);
    stmt.close();
    return res.map((row) => row['account_id'] as String).toList();
  }

  void upsertConversationMember(
    String conversationId,
    String accountId, {
    String role = 'MEMBER',
  }) {
    final stmt = _db.prepare('''
      INSERT INTO members (conversation_id, account_id, role)
      VALUES (?, ?, ?)
      ON CONFLICT(conversation_id, account_id) DO UPDATE SET
        role = excluded.role;
    ''');
    stmt.execute([conversationId, accountId, role]);
    stmt.close();
  }

  void removeConversationMember(String conversationId, String accountId) {
    final stmt = _db.prepare(
      'DELETE FROM members WHERE conversation_id = ? AND account_id = ?;',
    );
    stmt.execute([conversationId, accountId]);
    stmt.close();
  }

  // ---------------------------------------------------------------------------
  // Message operations
  // ---------------------------------------------------------------------------

  void saveMessage(
    RemoteMessage message,
    int sequence,
    int timestamp,
    String status,
  ) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO messages (message_id, conversation_id, sender_account_id, sender_device_id, ciphertext_blob, server_sequence, timestamp, status)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      message.messageId,
      message.conversationId,
      message.senderAccountId,
      message.senderDeviceId,
      message.ciphertext,
      sequence,
      timestamp,
      status,
    ]);
    stmt.close();
  }

  List<Map<String, dynamic>> getMessages(
    String conversationId, {
    int limit = 50,
    int offset = 0,
  }) {
    final stmt = _db.prepare('''
      SELECT * FROM messages
      WHERE conversation_id = ?
      ORDER BY server_sequence DESC
      LIMIT ? OFFSET ?;
    ''');
    final res = stmt.select([conversationId, limit, offset]);
    stmt.close();
    return res
        .map(
          (row) => {
            'message_id': row['message_id'],
            'conversation_id': row['conversation_id'],
            'sender_account_id': row['sender_account_id'],
            'sender_device_id': row['sender_device_id'],
            'ciphertext_blob': row['ciphertext_blob'],
            'server_sequence': row['server_sequence'],
            'timestamp': row['timestamp'],
            'status': row['status'],
          },
        )
        .toList();
  }

  Map<String, dynamic>? getMessageById(String messageId) {
    final stmt = _db.prepare('SELECT * FROM messages WHERE message_id = ?;');
    final res = stmt.select([messageId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'message_id': row['message_id'],
      'conversation_id': row['conversation_id'],
      'sender_account_id': row['sender_account_id'],
      'sender_device_id': row['sender_device_id'],
      'ciphertext_blob': row['ciphertext_blob'],
      'server_sequence': row['server_sequence'],
      'timestamp': row['timestamp'],
      'status': row['status'],
    };
  }

  void deleteMessage(String messageId) {
    final stmt = _db.prepare('DELETE FROM messages WHERE message_id = ?;');
    stmt.execute([messageId]);
    stmt.close();
  }

  void saveMessageAndOperation({
    required RemoteMessage message,
    required int sequence,
    required int timestamp,
    required String status,
    required String opId,
    required String type,
    required String payload,
    required String idempotencyKey,
  }) {
    _db.execute('SAVEPOINT save_message_and_operation;');
    try {
      saveMessage(message, sequence, timestamp, status);
      enqueueOperation(opId, type, payload, idempotencyKey: idempotencyKey);
      _db.execute('RELEASE SAVEPOINT save_message_and_operation;');
    } catch (_) {
      _db.execute('ROLLBACK TO SAVEPOINT save_message_and_operation;');
      _db.execute('RELEASE SAVEPOINT save_message_and_operation;');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Remote crypto session, prekey, and trust state
  // ---------------------------------------------------------------------------

  String getOrCreateLocalHistorySessionSeed(String conversationId) {
    final existing = getCryptoSession('local_history:$conversationId');
    if (existing != null) {
      return existing['root_key'] as String;
    }
    final random = math.Random.secure();
    final seed = base64Url.encode(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    upsertCryptoSession(
      sessionId: 'local_history:$conversationId',
      conversationId: conversationId,
      role: 'local_history',
      protocolVersion: 1,
      rootKey: seed,
      sendingChainKey: seed,
      receivingChainKey: seed,
      createdAt: now,
      updatedAt: now,
    );
    return seed;
  }

  void upsertCryptoSession({
    required String sessionId,
    required String conversationId,
    required String role,
    required int protocolVersion,
    required String rootKey,
    required String sendingChainKey,
    required String receivingChainKey,
    required int createdAt,
    required int updatedAt,
    String? peerAccountId,
    String? peerDeviceId,
    int sendCount = 0,
    int receiveCount = 0,
    int previousChainLength = 0,
    String skippedKeysJson = '[]',
  }) {
    final stmt = _db.prepare('''
      INSERT INTO crypto_sessions (
        session_id,
        conversation_id,
        peer_account_id,
        peer_device_id,
        role,
        protocol_version,
        root_key,
        sending_chain_key,
        receiving_chain_key,
        send_count,
        receive_count,
        previous_chain_length,
        skipped_keys_json,
        created_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(session_id) DO UPDATE SET
        root_key = excluded.root_key,
        sending_chain_key = excluded.sending_chain_key,
        receiving_chain_key = excluded.receiving_chain_key,
        send_count = excluded.send_count,
        receive_count = excluded.receive_count,
        previous_chain_length = excluded.previous_chain_length,
        skipped_keys_json = excluded.skipped_keys_json,
        updated_at = excluded.updated_at;
    ''');
    stmt.execute([
      sessionId,
      conversationId,
      peerAccountId,
      peerDeviceId,
      role,
      protocolVersion,
      rootKey,
      sendingChainKey,
      receivingChainKey,
      sendCount,
      receiveCount,
      previousChainLength,
      skippedKeysJson,
      createdAt,
      updatedAt,
    ]);
    stmt.close();
  }

  Map<String, dynamic>? getCryptoSession(String sessionId) {
    final stmt = _db.prepare(
      'SELECT * FROM crypto_sessions WHERE session_id = ?;',
    );
    final res = stmt.select([sessionId]);
    stmt.close();
    if (res.isEmpty) return null;
    return Map<String, dynamic>.from(res.first);
  }

  List<Map<String, dynamic>> getCryptoSessionsForConversation(
    String conversationId,
  ) {
    final stmt = _db.prepare(
      'SELECT * FROM crypto_sessions WHERE conversation_id = ? ORDER BY session_id;',
    );
    final res = stmt.select([conversationId]);
    stmt.close();
    return res.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void saveLocalPrekey({
    required int keyId,
    required String role,
    required String deviceId,
    required String publicKey,
    required String privateKeyRef,
    required int createdAt,
    required String rotationState,
    String? signature,
    int? expiresAt,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO local_prekeys (
        key_id,
        role,
        device_id,
        public_key,
        private_key_ref,
        signature,
        created_at,
        expires_at,
        rotation_state
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      keyId,
      role,
      deviceId,
      publicKey,
      privateKeyRef,
      signature,
      createdAt,
      expiresAt,
      rotationState,
    ]);
    stmt.close();
  }

  List<Map<String, dynamic>> getLocalPrekeys({
    required String deviceId,
    String? role,
    String? rotationState,
  }) {
    final where = <String>['device_id = ?'];
    final args = <Object?>[deviceId];
    if (role != null) {
      where.add('role = ?');
      args.add(role);
    }
    if (rotationState != null) {
      where.add('rotation_state = ?');
      args.add(rotationState);
    }
    final stmt = _db.prepare(
      'SELECT * FROM local_prekeys WHERE ${where.join(' AND ')} ORDER BY key_id;',
    );
    final res = stmt.select(args);
    stmt.close();
    return res.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  int countActiveOneTimePrekeys(String deviceId) {
    final stmt = _db.prepare('''
      SELECT count(*) AS c FROM local_prekeys
      WHERE device_id = ? AND role = 'one_time_prekey' AND rotation_state = 'active';
    ''');
    final res = stmt.select([deviceId]);
    stmt.close();
    return res.first['c'] as int;
  }

  void markLocalPrekeyState({
    required int keyId,
    required String role,
    required String deviceId,
    required String rotationState,
  }) {
    final stmt = _db.prepare('''
      UPDATE local_prekeys
      SET rotation_state = ?
      WHERE key_id = ? AND role = ? AND device_id = ?;
    ''');
    stmt.execute([rotationState, keyId, role, deviceId]);
    stmt.close();
  }

  void upsertTrustDecision({
    required String accountId,
    required String deviceId,
    required String identityFingerprint,
    required String safetyNumber,
    required String status,
    required int timestamp,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO trusted_devices (
        account_id,
        device_id,
        identity_fingerprint,
        safety_number,
        status,
        first_seen_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(account_id, device_id) DO UPDATE SET
        identity_fingerprint = excluded.identity_fingerprint,
        safety_number = excluded.safety_number,
        status = excluded.status,
        updated_at = excluded.updated_at;
    ''');
    stmt.execute([
      accountId,
      deviceId,
      identityFingerprint,
      safetyNumber,
      status,
      timestamp,
      timestamp,
    ]);
    stmt.close();
  }

  Map<String, dynamic>? getTrustDecision({
    required String accountId,
    required String deviceId,
  }) {
    final stmt = _db.prepare('''
      SELECT * FROM trusted_devices WHERE account_id = ? AND device_id = ?;
    ''');
    final res = stmt.select([accountId, deviceId]);
    stmt.close();
    if (res.isEmpty) return null;
    return Map<String, dynamic>.from(res.first);
  }

  // ---------------------------------------------------------------------------
  // Attachment operations
  // ---------------------------------------------------------------------------

  void saveAttachment({
    required String attachmentId,
    required String filename,
    required int sizeBytes,
    required String encryptedKey,
    String? localPath,
    String? importedSourcePath,
    String? encryptedCachePath,
    String? downloadedCiphertextPath,
    String? exportedPlaintextPath,
    required String status,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO attachments (
        attachment_id,
        filename,
        size_bytes,
        encrypted_key,
        local_path,
        imported_source_path,
        encrypted_cache_path,
        downloaded_ciphertext_path,
        exported_plaintext_path,
        status
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      attachmentId,
      filename,
      sizeBytes,
      encryptedKey,
      localPath,
      importedSourcePath,
      encryptedCachePath,
      downloadedCiphertextPath,
      exportedPlaintextPath,
      status,
    ]);
    stmt.close();
  }

  Map<String, dynamic>? getAttachment(String attachmentId) {
    final stmt = _db.prepare(
      'SELECT * FROM attachments WHERE attachment_id = ?;',
    );
    final res = stmt.select([attachmentId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'attachment_id': row['attachment_id'],
      'filename': row['filename'],
      'size_bytes': row['size_bytes'],
      'encrypted_key': row['encrypted_key'],
      'local_path': row['local_path'],
      'imported_source_path': row['imported_source_path'],
      'encrypted_cache_path': row['encrypted_cache_path'],
      'downloaded_ciphertext_path': row['downloaded_ciphertext_path'],
      'exported_plaintext_path': row['exported_plaintext_path'],
      'status': row['status'],
    };
  }

  // ---------------------------------------------------------------------------
  // Message revisions
  // ---------------------------------------------------------------------------

  void saveMessageRevision({
    required String revisionId,
    required String messageId,
    required String type,
    required String authorId,
    required String payload,
    required int timestamp,
    int serverSequence = 0,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO revisions (
        revision_id,
        message_id,
        type,
        author_id,
        payload,
        timestamp,
        server_sequence
      )
      VALUES (?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      revisionId,
      messageId,
      type,
      authorId,
      payload,
      timestamp,
      serverSequence,
    ]);
    stmt.close();
  }

  // P4-05: Order by server_sequence first (server wins over wall-clock),
  // then timestamp as tie-breaker for locally-generated revisions.
  List<Map<String, dynamic>> getMessageRevisions(String messageId) {
    final stmt = _db.prepare(
      'SELECT * FROM revisions WHERE message_id = ? ORDER BY server_sequence ASC, timestamp ASC;',
    );
    final res = stmt.select([messageId]);
    stmt.close();
    return res
        .map(
          (row) => {
            'revision_id': row['revision_id'],
            'message_id': row['message_id'],
            'type': row['type'],
            'author_id': row['author_id'],
            'payload': row['payload'],
            'timestamp': row['timestamp'],
            'server_sequence': row['server_sequence'] ?? 0,
          },
        )
        .toList();
  }

  void saveMessageReceipt({
    required String receiptId,
    required String messageId,
    required String conversationId,
    required String accountId,
    required String receiptType,
    required int timestamp,
    String? deviceId,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO message_receipts (
        receipt_id,
        message_id,
        conversation_id,
        account_id,
        device_id,
        receipt_type,
        timestamp
      )
      VALUES (?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      receiptId,
      messageId,
      conversationId,
      accountId,
      deviceId,
      receiptType,
      timestamp,
    ]);
    stmt.close();
  }

  List<Map<String, dynamic>> getMessageReceipts(String messageId) {
    final stmt = _db.prepare(
      'SELECT * FROM message_receipts WHERE message_id = ? ORDER BY timestamp ASC;',
    );
    final res = stmt.select([messageId]);
    stmt.close();
    return res
        .map(
          (row) => {
            'receipt_id': row['receipt_id'],
            'message_id': row['message_id'],
            'conversation_id': row['conversation_id'],
            'account_id': row['account_id'],
            'device_id': row['device_id'],
            'receipt_type': row['receipt_type'],
            'timestamp': row['timestamp'],
          },
        )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Cursors
  // ---------------------------------------------------------------------------

  void updateSyncCursor(String conversationId, int lastSequence) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO sync_cursors (conversation_id, last_sequence)
      VALUES (?, ?);
    ''');
    stmt.execute([conversationId, lastSequence]);
    stmt.close();
  }

  int getSyncCursor(String conversationId) {
    final stmt = _db.prepare(
      'SELECT last_sequence FROM sync_cursors WHERE conversation_id = ?;',
    );
    final res = stmt.select([conversationId]);
    stmt.close();
    if (res.isEmpty) return 0;
    return res.first['last_sequence'] as int;
  }

  bool hasProcessedEventId(String eventId) {
    final stmt = _db.prepare(
      'SELECT 1 FROM processed_event_ids WHERE event_id = ?;',
    );
    final res = stmt.select([eventId]);
    stmt.close();
    return res.isNotEmpty;
  }

  void saveProcessedEvent({
    required String eventId,
    required int serverSequence,
    required String eventType,
    required String contentFingerprint,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO processed_event_ids (
        event_id,
        server_sequence,
        event_type,
        content_fingerprint,
        processed_at
      )
      VALUES (?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      eventId,
      serverSequence,
      eventType,
      contentFingerprint,
      DateTime.now().millisecondsSinceEpoch,
    ]);
    stmt.close();
  }

  // P4-04: Quarantine an inbound event that failed parsing or application.
  // The event is recorded so operators can inspect it; it does NOT advance
  // the sync cursor.
  void saveQuarantinedEvent({
    required String eventId,
    required int serverSequence,
    required String eventType,
    required String rawPayload,
    required String failureReason,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO quarantine_events (
        event_id,
        server_sequence,
        event_type,
        raw_payload,
        failure_reason,
        quarantined_at
      )
      VALUES (?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      eventId,
      serverSequence,
      eventType,
      rawPayload,
      failureReason,
      DateTime.now().millisecondsSinceEpoch,
    ]);
    stmt.close();
  }

  List<Map<String, dynamic>> getQuarantinedEvents() {
    final stmt = _db.prepare(
      'SELECT * FROM quarantine_events ORDER BY server_sequence ASC;',
    );
    final res = stmt.select();
    stmt.close();
    return res
        .map(
          (row) => {
            'event_id': row['event_id'],
            'server_sequence': row['server_sequence'],
            'event_type': row['event_type'],
            'raw_payload': row['raw_payload'],
            'failure_reason': row['failure_reason'],
            'quarantined_at': row['quarantined_at'],
          },
        )
        .toList();
  }

  bool isQuarantinedEventId(String eventId) {
    final stmt = _db.prepare(
      'SELECT 1 FROM quarantine_events WHERE event_id = ?;',
    );
    final res = stmt.select([eventId]);
    stmt.close();
    return res.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // Pending operation queue
  // ---------------------------------------------------------------------------

  /// Enqueue an outbound operation. [idempotencyKey] is a stable server-visible
  /// ID that prevents duplicate delivery if the same operation is retried.
  void enqueueOperation(
    String opId,
    String type,
    String payload, {
    String idempotencyKey = '',
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO pending_operations (op_id, idempotency_key, type, payload, status, retries, created_at, next_attempt_at)
      VALUES (?, ?, ?, ?, 'PENDING', 0, ?, ?);
    ''');
    stmt.execute([opId, idempotencyKey, type, payload, now, now]);
    stmt.close();
  }

  /// Returns operations that are due for execution now.
  List<Map<String, dynamic>> getPendingOperations() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      SELECT * FROM pending_operations
      WHERE (status = 'PENDING' OR status = 'FAILED')
        AND retries < 5
        AND next_attempt_at <= ?
      ORDER BY created_at ASC;
    ''');
    final res = stmt.select([now]);
    stmt.close();
    return res
        .map(
          (row) => {
            'op_id': row['op_id'],
            'idempotency_key': row['idempotency_key'],
            'type': row['type'],
            'payload': row['payload'],
            'status': row['status'],
            'retries': row['retries'],
            'created_at': row['created_at'],
            'next_attempt_at': row['next_attempt_at'],
          },
        )
        .toList();
  }

  /// Returns the raw state of a single pending operation, or null if not found.
  /// Useful for diagnostics and tests. Does NOT filter by [next_attempt_at].
  Map<String, dynamic>? getOperationById(String opId) {
    final stmt = _db.prepare(
      'SELECT * FROM pending_operations WHERE op_id = ?;',
    );
    final res = stmt.select([opId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'op_id': row['op_id'],
      'idempotency_key': row['idempotency_key'],
      'type': row['type'],
      'payload': row['payload'],
      'status': row['status'],
      'retries': row['retries'],
      'created_at': row['created_at'],
      'next_attempt_at': row['next_attempt_at'],
    };
  }

  List<Map<String, dynamic>> getOutboxOperations() {
    final stmt = _db.prepare('''
      SELECT * FROM pending_operations
      WHERE status != 'COMPLETED'
      ORDER BY created_at ASC;
    ''');
    final res = stmt.select();
    stmt.close();
    return res
        .map(
          (row) => {
            'op_id': row['op_id'],
            'idempotency_key': row['idempotency_key'],
            'type': row['type'],
            'status': row['status'],
            'retries': row['retries'],
            'created_at': row['created_at'],
            'next_attempt_at': row['next_attempt_at'],
          },
        )
        .toList();
  }

  void updateOperationStatus(String opId, String status, int retries) {
    final stmt = _db.prepare(
      'UPDATE pending_operations SET status = ?, retries = ? WHERE op_id = ?;',
    );
    stmt.execute([status, retries, opId]);
    stmt.close();
  }

  void retryOperationNow(String opId) {
    final stmt = _db.prepare('''
      UPDATE pending_operations
      SET status = 'PENDING', retries = 0, next_attempt_at = ?
      WHERE op_id = ? AND status = 'FAILED';
    ''');
    stmt.execute([DateTime.now().millisecondsSinceEpoch, opId]);
    stmt.close();
  }

  /// Persist the next retry deadline for an operation.
  /// [nextAttemptAt] is milliseconds since epoch; caller computes backoff + jitter.
  void scheduleNextOperationAttempt(String opId, int nextAttemptAt) {
    final stmt = _db.prepare(
      'UPDATE pending_operations SET next_attempt_at = ? WHERE op_id = ?;',
    );
    stmt.execute([nextAttemptAt, opId]);
    stmt.close();
  }

  Map<String, int> purgeOperationalRecords({
    required int completedOperationsOlderThan,
    required int tombstonesOlderThan,
    required int quarantineOlderThan,
  }) {
    _db.execute('SAVEPOINT purge_operational_records;');
    try {
      final purgedOperations = _deleteWhereCount(
        'pending_operations',
        "status = 'COMPLETED' AND created_at < ?",
        [completedOperationsOlderThan],
      );
      final purgedTombstones = _deleteWhereCount(
        'tombstones',
        'deleted_at < ?',
        [tombstonesOlderThan],
      );
      final purgedQuarantine = _deleteWhereCount(
        'quarantine_events',
        'quarantined_at < ?',
        [quarantineOlderThan],
      );
      _db.execute('RELEASE SAVEPOINT purge_operational_records;');
      return {
        'pending_operations': purgedOperations,
        'tombstones': purgedTombstones,
        'quarantine_events': purgedQuarantine,
      };
    } catch (_) {
      _db.execute('ROLLBACK TO SAVEPOINT purge_operational_records;');
      _db.execute('RELEASE SAVEPOINT purge_operational_records;');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Tombstones
  // ---------------------------------------------------------------------------

  void saveTombstone(String itemId, String type) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO tombstones (item_id, type, deleted_at)
      VALUES (?, ?, ?);
    ''');
    stmt.execute([itemId, type, now]);
    stmt.close();
  }

  bool isTombstoned(String itemId, String type) {
    final stmt = _db.prepare(
      'SELECT 1 FROM tombstones WHERE item_id = ? AND type = ?;',
    );
    final res = stmt.select([itemId, type]);
    stmt.close();
    return res.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // Call history (P15-013)
  // ---------------------------------------------------------------------------

  void saveCallHistory({
    required String callId,
    required String peerId,
    required bool isVideo,
    required String direction,
    required int durationSeconds,
    required int timestamp,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO call_history (call_id, peer_id, is_video, direction, duration, timestamp)
      VALUES (?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      callId,
      peerId,
      isVideo ? 1 : 0,
      direction,
      durationSeconds,
      timestamp,
    ]);
    stmt.close();
  }

  List<Map<String, dynamic>> getCallHistory({int limit = 50}) {
    final stmt = _db.prepare('''
      SELECT * FROM call_history ORDER BY timestamp DESC LIMIT ?;
    ''');
    final res = stmt.select([limit]);
    stmt.close();
    return res
        .map(
          (row) => {
            'call_id': row['call_id'],
            'peer_id': row['peer_id'],
            'is_video': row['is_video'],
            'direction': row['direction'],
            'duration': row['duration'],
            'timestamp': row['timestamp'],
          },
        )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Active call marker for crash recovery (P15-008)
  // ---------------------------------------------------------------------------

  void setActiveCallMarker({
    required String callId,
    required String peerId,
    required bool isVideo,
    required int startedAt,
  }) {
    _db.execute('DELETE FROM active_call;');
    final stmt = _db.prepare('''
      INSERT INTO active_call (call_id, peer_id, is_video, started_at)
      VALUES (?, ?, ?, ?);
    ''');
    stmt.execute([callId, peerId, isVideo ? 1 : 0, startedAt]);
    stmt.close();
  }

  Map<String, dynamic>? getActiveCallMarker() {
    final res = _db.select('SELECT * FROM active_call LIMIT 1;');
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'call_id': row['call_id'],
      'peer_id': row['peer_id'],
      'is_video': row['is_video'],
      'started_at': row['started_at'],
    };
  }

  void clearActiveCallMarker() {
    _db.execute('DELETE FROM active_call;');
  }

  int _deleteWhereCount(String table, String where, List<Object?> args) {
    final before = _countRows(table);
    final stmt = _db.prepare('DELETE FROM $table WHERE $where;');
    stmt.execute(args);
    stmt.close();
    return before - _countRows(table);
  }

  int _countRows(String table) {
    final rows = _db.select('SELECT COUNT(*) AS count FROM $table;');
    return rows.first['count'] as int;
  }

  // ---------------------------------------------------------------------------
  // Group metadata (P16-001, P16-008)
  // ---------------------------------------------------------------------------

  void upsertGroupMetadata({
    required String groupId,
    required String name,
    required String creatorId,
    String? avatarUri,
    int epoch = 0,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO groups (group_id, name, owner_id, status, avatar_uri, creator_id, epoch)
      VALUES (?, ?, ?, 'ACTIVE', ?, ?, ?)
      ON CONFLICT(group_id) DO UPDATE SET
        name = excluded.name,
        avatar_uri = excluded.avatar_uri,
        epoch = excluded.epoch;
    ''');
    stmt.execute([groupId, name, creatorId, avatarUri, creatorId, epoch]);
    stmt.close();
  }

  Map<String, dynamic>? getGroupMetadata(String groupId) {
    final stmt = _db.prepare('SELECT * FROM groups WHERE group_id = ?;');
    final res = stmt.select([groupId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'group_id': row['group_id'],
      'name': row['name'],
      'creator_id': row['creator_id'] ?? row['owner_id'],
      'avatar_uri': row['avatar_uri'],
      'epoch': row['epoch'] ?? 0,
      'status': row['status'],
    };
  }

  /// P16-005: Increment the key epoch after a membership change.
  void updateGroupEpoch(String groupId, int epoch) {
    final stmt = _db.prepare('UPDATE groups SET epoch = ? WHERE group_id = ?;');
    stmt.execute([epoch, groupId]);
    stmt.close();
  }

  void saveGroupEpochKey({
    required String groupId,
    required int epoch,
    required String keyId,
    required String keyMaterial,
    required int createdAt,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO group_epoch_keys
        (group_id, epoch, key_id, key_material, created_at)
      VALUES (?, ?, ?, ?, ?);
    ''');
    stmt.execute([groupId, epoch, keyId, keyMaterial, createdAt]);
    stmt.close();
  }

  Map<String, dynamic>? getGroupEpochKey(String groupId, int epoch) {
    final stmt = _db.prepare('''
      SELECT * FROM group_epoch_keys
      WHERE group_id = ? AND epoch = ?;
    ''');
    final res = stmt.select([groupId, epoch]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'group_id': row['group_id'],
      'epoch': row['epoch'],
      'key_id': row['key_id'],
      'key_material': row['key_material'],
      'created_at': row['created_at'],
    };
  }

  List<Map<String, dynamic>> getGroupEpochKeys(String groupId) {
    final stmt = _db.prepare('''
      SELECT * FROM group_epoch_keys
      WHERE group_id = ?
      ORDER BY epoch ASC;
    ''');
    final res = stmt.select([groupId]);
    stmt.close();
    return res
        .map(
          (row) => {
            'group_id': row['group_id'],
            'epoch': row['epoch'],
            'key_id': row['key_id'],
            'key_material': row['key_material'],
            'created_at': row['created_at'],
          },
        )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Group invites (P16-003)
  // ---------------------------------------------------------------------------

  void upsertGroupInvite({
    required String inviteId,
    required String groupId,
    required String inviterId,
    required String status,
    required int createdAt,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO group_invites (invite_id, group_id, inviter_id, status, created_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(invite_id) DO UPDATE SET status = excluded.status;
    ''');
    stmt.execute([inviteId, groupId, inviterId, status, createdAt]);
    stmt.close();
  }

  Map<String, dynamic>? getGroupInvite(String inviteId) {
    final stmt = _db.prepare(
      'SELECT * FROM group_invites WHERE invite_id = ?;',
    );
    final res = stmt.select([inviteId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'invite_id': row['invite_id'],
      'group_id': row['group_id'],
      'inviter_id': row['inviter_id'],
      'status': row['status'],
      'created_at': row['created_at'],
    };
  }

  List<Map<String, dynamic>> getGroupInvites() {
    final stmt = _db.prepare(
      "SELECT * FROM group_invites WHERE status = 'PENDING' ORDER BY created_at DESC;",
    );
    final res = stmt.select();
    stmt.close();
    return res
        .map(
          (row) => {
            'invite_id': row['invite_id'],
            'group_id': row['group_id'],
            'inviter_id': row['inviter_id'],
            'status': row['status'],
            'created_at': row['created_at'],
          },
        )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Members with roles (P16-002)
  // ---------------------------------------------------------------------------

  List<Map<String, dynamic>> getGroupMembersWithRoles(String conversationId) {
    final stmt = _db.prepare(
      'SELECT account_id, role FROM members WHERE conversation_id = ?;',
    );
    final res = stmt.select([conversationId]);
    stmt.close();
    return res
        .map((row) => {'account_id': row['account_id'], 'role': row['role']})
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Backup / restore snapshots (P17-005, P17-008, P17-012, P17-014)
  // ---------------------------------------------------------------------------

  String exportBackupSnapshot({int version = 1}) {
    return jsonEncode({
      'version': version,
      'exported_at': DateTime.now().millisecondsSinceEpoch,
      'accounts': _selectAll('accounts'),
      'devices': _selectAll('devices'),
      'contacts': _selectAll('contacts'),
      'contact_requests': _selectAll('contact_requests'),
      'conversations': _selectAll('conversations'),
      'members': _selectAll('members'),
      'messages': _selectAll('messages'),
      'message_receipts': _selectAll('message_receipts'),
      'revisions': _selectAll('revisions'),
      'attachments': _selectAll('attachments'),
      'groups': _selectAll('groups'),
      'group_epoch_keys': _selectAll('group_epoch_keys'),
      'group_invites': _selectAll('group_invites'),
      'call_history': _selectAll('call_history'),
      'tombstones': _selectAll('tombstones'),
    });
  }

  void restoreBackupSnapshot(String snapshotJson) {
    final decoded = jsonDecode(snapshotJson) as Map<String, dynamic>;
    final version = decoded['version'] as int? ?? 0;
    if (version != 1) {
      throw UnsupportedError('Unsupported backup snapshot version: $version');
    }

    _db.execute('SAVEPOINT restore_backup_snapshot;');
    try {
      _restoreRows('accounts', decoded['accounts'] as List? ?? const []);
      _restoreRows('devices', decoded['devices'] as List? ?? const []);
      _restoreRows('contacts', decoded['contacts'] as List? ?? const []);
      _restoreRows(
        'contact_requests',
        decoded['contact_requests'] as List? ?? const [],
      );
      _restoreRows(
        'conversations',
        decoded['conversations'] as List? ?? const [],
      );
      _restoreRows('members', decoded['members'] as List? ?? const []);
      _restoreRows('messages', decoded['messages'] as List? ?? const []);
      _restoreRows(
        'message_receipts',
        decoded['message_receipts'] as List? ?? const [],
      );
      _restoreRows('revisions', decoded['revisions'] as List? ?? const []);
      _restoreRows('attachments', decoded['attachments'] as List? ?? const []);
      _restoreRows('groups', decoded['groups'] as List? ?? const []);
      _restoreRows(
        'group_epoch_keys',
        decoded['group_epoch_keys'] as List? ?? const [],
      );
      _restoreRows(
        'group_invites',
        decoded['group_invites'] as List? ?? const [],
      );
      _restoreRows(
        'call_history',
        decoded['call_history'] as List? ?? const [],
      );
      _restoreRows('tombstones', decoded['tombstones'] as List? ?? const []);
      _applyRestoredTombstones();
      _db.execute('RELEASE SAVEPOINT restore_backup_snapshot;');
    } catch (_) {
      _db.execute('ROLLBACK TO SAVEPOINT restore_backup_snapshot;');
      _db.execute('RELEASE SAVEPOINT restore_backup_snapshot;');
      rethrow;
    }
  }

  List<Map<String, dynamic>> getTombstones() => _selectAll('tombstones');

  List<Map<String, dynamic>> _selectAll(String table) {
    final res = _db.select('SELECT * FROM $table;');
    return res.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void _restoreRows(String table, List<dynamic> rows) {
    for (final row in rows.cast<Map<String, dynamic>>()) {
      if (row.isEmpty) continue;
      final columns = row.keys.toList();
      final placeholders = List.filled(columns.length, '?').join(', ');
      final columnList = columns.join(', ');
      final stmt = _db.prepare(
        'INSERT OR REPLACE INTO $table ($columnList) VALUES ($placeholders);',
      );
      stmt.execute(columns.map((column) => row[column]).toList());
      stmt.close();
    }
  }

  void _applyRestoredTombstones() {
    final tombstones = getTombstones();
    for (final tombstone in tombstones) {
      final itemId = tombstone['item_id'] as String;
      final type = tombstone['type'] as String;
      if (type == 'MESSAGE') {
        deleteMessage(itemId);
      } else if (type == 'GROUP') {
        final stmt = _db.prepare(
          "UPDATE groups SET status = 'DELETED' WHERE group_id = ?;",
        );
        stmt.execute([itemId]);
        stmt.close();
      }
    }
  }
}
