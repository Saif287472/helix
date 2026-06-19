import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:helix_remote_domain/models.dart';

class HelixRemoteDatabase {
  final File file;
  final String? password;
  late final Database _db;

  HelixRemoteDatabase(this.file, {this.password});

  void initialize() {
    _db = sqlite3.open(file.path);
    try {
      if (password != null) {
        // BLOCKED (DEFECT-4): `PRAGMA key` is a no-op on the standard `sqlite3`
        // Dart package, which links the standard (non-SQLCipher) SQLite3
        // library. The database is stored in plaintext on disk.
        // This line is kept as a placeholder for a future SQLCipher-capable
        // library migration. Do NOT treat this as functional encryption.
        // See: docs/architecture/PHASE_9_11_CLOSURE.md DEFECT-4.
        _db.execute("PRAGMA key = '${_escapeSingleQuotes(password!)}';");
      }
      _db.execute('PRAGMA journal_mode = WAL;');
      _db.execute('PRAGMA foreign_keys = ON;');
      _onCreate();
      _applyMigrations();
    } catch (_) {
      _db.close();
      rethrow;
    }
  }

  // Minimal escape to prevent SQL injection via password string.
  // Remove if PRAGMA key is replaced with a parameterized SQLCipher call.
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
        device_id INTEGER NOT NULL,
        account_id TEXT NOT NULL,
        device_name TEXT NOT NULL,
        device_public_key TEXT NOT NULL,
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
        sender_device_id INTEGER NOT NULL,
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
        device_id INTEGER,
        receipt_type TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      );
    ''');

    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_conv_seq
      ON messages(conversation_id, server_sequence ASC);
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
      CREATE TABLE IF NOT EXISTS tombstones (
        item_id TEXT NOT NULL,
        type TEXT NOT NULL,
        deleted_at INTEGER NOT NULL,
        PRIMARY KEY (item_id, type)
      );
    ''');
  }

  void _applyMigrations() {
    final version = schemaVersion;
    if (version < 1) {
      // Rename messages.text → ciphertext_blob for schema clarity.
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
  }

  void close() => _db.close();

  /// Execute a raw SQL statement (e.g. BEGIN / COMMIT / ROLLBACK).
  void rawExecute(String sql) => _db.execute(sql);

  void deleteFiles() {
    _db.close();
    for (final suffix in ['', '-wal', '-shm']) {
      final f = File('${file.path}$suffix');
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
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
      INSERT INTO devices (device_id, account_id, device_name, device_public_key, status, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(account_id, device_id) DO UPDATE SET
        device_name = excluded.device_name,
        device_public_key = excluded.device_public_key,
        status = excluded.status;
    ''');
    stmt.execute([
      device.deviceId,
      accountId,
      device.deviceName,
      device.devicePublicKey,
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
            deviceId: row['device_id'] as int,
            deviceName: row['device_name'] as String,
            devicePublicKey: row['device_public_key'] as String,
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

  void deleteMessage(String messageId) {
    final stmt = _db.prepare('DELETE FROM messages WHERE message_id = ?;');
    stmt.execute([messageId]);
    stmt.close();
  }

  void saveMessageReceipt({
    required String receiptId,
    required String messageId,
    required String conversationId,
    required String accountId,
    required String receiptType,
    required int timestamp,
    int? deviceId,
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
  /// Useful for diagnostics and tests — does NOT filter by [next_attempt_at].
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

  void updateOperationStatus(String opId, String status, int retries) {
    final stmt = _db.prepare(
      'UPDATE pending_operations SET status = ?, retries = ? WHERE op_id = ?;',
    );
    stmt.execute([status, retries, opId]);
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
}
