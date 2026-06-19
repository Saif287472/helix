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
        _db.execute("PRAGMA key = '$password';");
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
        text TEXT NOT NULL,
        server_sequence INTEGER NOT NULL,
        timestamp INTEGER NOT NULL,
        status TEXT NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES conversations(conversation_id) ON DELETE CASCADE
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
        last_sequence INTEGER NOT NULL,
        FOREIGN KEY (conversation_id) REFERENCES conversations(conversation_id) ON DELETE CASCADE
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS pending_operations (
        op_id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        payload TEXT NOT NULL,
        status TEXT NOT NULL,
        retries INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
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
      _db.execute('PRAGMA user_version = 1;');
    }
  }

  void close() => _db.close();

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

  // Account operations
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

  // Device operations
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
    return res.map((row) => RemoteDevice(
      deviceId: row['device_id'] as int,
      deviceName: row['device_name'] as String,
      devicePublicKey: row['device_public_key'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      status: row['status'] as String,
    )).toList();
  }

  // Contact operations
  void upsertContact(RemoteContact contact) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO contacts (peer_account_id, nickname, status)
      VALUES (?, ?, ?);
    ''');
    stmt.execute([
      contact.peerAccountId,
      contact.nickname,
      contact.status,
    ]);
    stmt.close();
  }

  List<RemoteContact> getContacts() {
    final stmt = _db.prepare('SELECT * FROM contacts;');
    final res = stmt.select();
    stmt.close();
    return res.map((row) => RemoteContact(
      peerAccountId: row['peer_account_id'] as String,
      nickname: row['nickname'] as String,
      status: row['status'] as String,
    )).toList();
  }

  // Conversation operations
  void upsertConversation(RemoteConversation conversation, List<String> memberIds) {
    _db.execute('BEGIN TRANSACTION;');
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

      final clearStmt = _db.prepare('DELETE FROM members WHERE conversation_id = ?;');
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

      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  List<RemoteConversation> getConversations() {
    final stmt = _db.prepare('SELECT * FROM conversations;');
    final res = stmt.select();
    stmt.close();
    return res.map((row) => RemoteConversation(
      conversationId: row['conversation_id'] as String,
      title: row['title'] as String? ?? '',
      type: row['type'] as String,
      lastActivitySequence: row['last_sequence'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
    )).toList();
  }

  List<String> getConversationMembers(String conversationId) {
    final stmt = _db.prepare('SELECT account_id FROM members WHERE conversation_id = ?;');
    final res = stmt.select([conversationId]);
    stmt.close();
    return res.map((row) => row['account_id'] as String).toList();
  }

  // Message operations
  void saveMessage(RemoteMessage message, int sequence, int timestamp, String status) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO messages (message_id, conversation_id, sender_account_id, sender_device_id, text, server_sequence, timestamp, status)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      message.messageId,
      message.conversationId,
      message.senderAccountId,
      message.senderDeviceId,
      message.ciphertext, // Maps decrypted text to ciphertext property for model parity
      sequence,
      timestamp,
      status,
    ]);
    stmt.close();
  }

  List<Map<String, dynamic>> getMessages(String conversationId, {int limit = 50, int offset = 0}) {
    final stmt = _db.prepare('''
      SELECT * FROM messages 
      WHERE conversation_id = ? 
      ORDER BY server_sequence DESC 
      LIMIT ? OFFSET ?;
    ''');
    final res = stmt.select([conversationId, limit, offset]);
    stmt.close();
    return res.map((row) => {
      'message_id': row['message_id'],
      'conversation_id': row['conversation_id'],
      'sender_account_id': row['sender_account_id'],
      'sender_device_id': row['sender_device_id'],
      'text': row['text'],
      'server_sequence': row['server_sequence'],
      'timestamp': row['timestamp'],
      'status': row['status'],
    }).toList();
  }

  // Cursors
  void updateSyncCursor(String conversationId, int lastSequence) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO sync_cursors (conversation_id, last_sequence)
      VALUES (?, ?);
    ''');
    stmt.execute([conversationId, lastSequence]);
    stmt.close();
  }

  int getSyncCursor(String conversationId) {
    final stmt = _db.prepare('SELECT last_sequence FROM sync_cursors WHERE conversation_id = ?;');
    final res = stmt.select([conversationId]);
    stmt.close();
    if (res.isEmpty) return 0;
    return res.first['last_sequence'] as int;
  }

  // Queue Operations
  void enqueueOperation(String opId, String type, String payload) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO pending_operations (op_id, type, payload, status, retries, created_at)
      VALUES (?, ?, ?, 'PENDING', 0, ?);
    ''');
    stmt.execute([opId, type, payload, now]);
    stmt.close();
  }

  List<Map<String, dynamic>> getPendingOperations() {
    final stmt = _db.prepare('''
      SELECT * FROM pending_operations 
      WHERE status = 'PENDING' OR status = 'FAILED' AND retries < 5
      ORDER BY created_at ASC;
    ''');
    final res = stmt.select();
    stmt.close();
    return res.map((row) => {
      'op_id': row['op_id'],
      'type': row['type'],
      'payload': row['payload'],
      'status': row['status'],
      'retries': row['retries'],
      'created_at': row['created_at'],
    }).toList();
  }

  void updateOperationStatus(String opId, String status, int retries) {
    final stmt = _db.prepare('UPDATE pending_operations SET status = ?, retries = ? WHERE op_id = ?;');
    stmt.execute([status, retries, opId]);
    stmt.close();
  }

  // Tombstones
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
    final stmt = _db.prepare('SELECT 1 FROM tombstones WHERE item_id = ? AND type = ?;');
    final res = stmt.select([itemId, type]);
    stmt.close();
    return res.isNotEmpty;
  }
}
