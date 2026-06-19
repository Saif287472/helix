import 'package:sqlite3/sqlite3.dart';

class BackendDatabase {
  final Database _db;

  BackendDatabase(this._db) {
    _initializeSchema();
  }

  void _initializeSchema() {
    _db.execute('PRAGMA foreign_keys = ON;');

    final versionRow = _db.select('PRAGMA user_version;');
    final version = versionRow.first.columnAt(0) as int;

    if (version < 1) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS accounts (
          account_id TEXT PRIMARY KEY,
          username TEXT UNIQUE NOT NULL,
          identity_public_key TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          status TEXT NOT NULL
        );
      ''');

      _db.execute('''
        CREATE TABLE IF NOT EXISTS devices (
          device_id TEXT PRIMARY KEY,
          account_id TEXT NOT NULL,
          device_public_key TEXT NOT NULL,
          device_name TEXT NOT NULL,
          status TEXT NOT NULL,
          push_token TEXT,
          created_at INTEGER NOT NULL,
          last_seen_at INTEGER NOT NULL,
          FOREIGN KEY(account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
        );
      ''');

      _db.execute('''
        CREATE TABLE IF NOT EXISTS signed_prekeys (
          account_id TEXT NOT NULL,
          device_id TEXT NOT NULL,
          key_id INTEGER NOT NULL,
          public_key TEXT NOT NULL,
          signature TEXT NOT NULL,
          PRIMARY KEY(account_id, device_id),
          FOREIGN KEY(account_id) REFERENCES accounts(account_id) ON DELETE CASCADE,
          FOREIGN KEY(device_id) REFERENCES devices(device_id) ON DELETE CASCADE
        );
      ''');

      _db.execute('''
        CREATE TABLE IF NOT EXISTS one_time_prekeys (
          account_id TEXT NOT NULL,
          device_id TEXT NOT NULL,
          key_id INTEGER NOT NULL,
          public_key TEXT NOT NULL,
          PRIMARY KEY(account_id, device_id, key_id),
          FOREIGN KEY(account_id) REFERENCES accounts(account_id) ON DELETE CASCADE,
          FOREIGN KEY(device_id) REFERENCES devices(device_id) ON DELETE CASCADE
        );
      ''');

      _db.execute('''
        CREATE TABLE IF NOT EXISTS contacts (
          account_id TEXT NOT NULL,
          peer_account_id TEXT NOT NULL,
          nickname TEXT,
          status TEXT NOT NULL,
          PRIMARY KEY(account_id, peer_account_id),
          FOREIGN KEY(account_id) REFERENCES accounts(account_id) ON DELETE CASCADE,
          FOREIGN KEY(peer_account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
        );
      ''');

      _db.execute('''
        CREATE TABLE IF NOT EXISTS conversations (
          conversation_id TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          title TEXT,
          created_at INTEGER NOT NULL,
          last_sequence INTEGER NOT NULL DEFAULT 0
        );
      ''');

      _db.execute('''
        CREATE TABLE IF NOT EXISTS conversation_members (
          conversation_id TEXT NOT NULL,
          account_id TEXT NOT NULL,
          role TEXT NOT NULL DEFAULT 'MEMBER',
          PRIMARY KEY(conversation_id, account_id),
          FOREIGN KEY(conversation_id) REFERENCES conversations(conversation_id) ON DELETE CASCADE,
          FOREIGN KEY(account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
        );
      ''');

      _db.execute('''
        CREATE TABLE IF NOT EXISTS messages (
          message_id TEXT NOT NULL,
          conversation_id TEXT NOT NULL,
          sender_account_id TEXT NOT NULL,
          sender_device_id TEXT NOT NULL,
          recipient_device_id TEXT NOT NULL,
          ciphertext TEXT NOT NULL,
          server_sequence INTEGER NOT NULL,
          timestamp INTEGER NOT NULL,
          PRIMARY KEY(conversation_id, recipient_device_id, server_sequence),
          FOREIGN KEY(conversation_id) REFERENCES conversations(conversation_id) ON DELETE CASCADE,
          FOREIGN KEY(sender_account_id) REFERENCES accounts(account_id) ON DELETE CASCADE,
          FOREIGN KEY(sender_device_id) REFERENCES devices(device_id) ON DELETE CASCADE,
          FOREIGN KEY(recipient_device_id) REFERENCES devices(device_id) ON DELETE CASCADE
        );
      ''');

      _db.execute('''
        CREATE TABLE IF NOT EXISTS sync_cursors (
          account_id TEXT NOT NULL,
          device_id TEXT NOT NULL,
          conversation_id TEXT NOT NULL,
          last_sequence INTEGER NOT NULL,
          PRIMARY KEY(account_id, device_id, conversation_id),
          FOREIGN KEY(account_id) REFERENCES accounts(account_id) ON DELETE CASCADE,
          FOREIGN KEY(device_id) REFERENCES devices(device_id) ON DELETE CASCADE,
          FOREIGN KEY(conversation_id) REFERENCES conversations(conversation_id) ON DELETE CASCADE
        );
      ''');

      _db.execute('''
        CREATE TABLE IF NOT EXISTS outbox (
          event_id TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          payload TEXT NOT NULL,
          status TEXT NOT NULL,
          retries INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        );
      ''');

      _db.execute('''
        CREATE TABLE IF NOT EXISTS backups (
          account_id TEXT PRIMARY KEY,
          backup_data TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          FOREIGN KEY(account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
        );
      ''');

      _db.execute('''
        CREATE TABLE IF NOT EXISTS audit_logs (
          event_id TEXT PRIMARY KEY,
          account_id TEXT,
          device_id TEXT,
          action TEXT NOT NULL,
          client_ip TEXT,
          user_agent TEXT,
          timestamp INTEGER NOT NULL
        );
      ''');

      _db.execute('PRAGMA user_version = 1;');
    }
  }

  void close() {
    _db.close();
  }

  // Account operations
  void createAccount(
    String accountId,
    String username,
    String identityPublicKey,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO accounts (account_id, username, identity_public_key, created_at, status)
      VALUES (?, ?, ?, ?, 'ACTIVE');
    ''');
    stmt.execute([accountId, username, identityPublicKey, now]);
    stmt.close();
  }

  Map<String, dynamic>? getAccount(String accountId) {
    final stmt = _db.prepare('SELECT * FROM accounts WHERE account_id = ?;');
    final result = stmt.select([accountId]);
    stmt.close();
    if (result.isEmpty) return null;
    final row = result.first;
    return {
      'account_id': row['account_id'],
      'username': row['username'],
      'identity_public_key': row['identity_public_key'],
      'created_at': row['created_at'],
      'status': row['status'],
    };
  }

  Map<String, dynamic>? getAccountByUsername(String username) {
    final stmt = _db.prepare('SELECT * FROM accounts WHERE username = ?;');
    final result = stmt.select([username]);
    stmt.close();
    if (result.isEmpty) return null;
    final row = result.first;
    return {
      'account_id': row['account_id'],
      'username': row['username'],
      'identity_public_key': row['identity_public_key'],
      'created_at': row['created_at'],
      'status': row['status'],
    };
  }

  // Device operations
  void registerDevice(
    String deviceId,
    String accountId,
    String devicePublicKey,
    String deviceName,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO devices (device_id, account_id, device_public_key, device_name, status, created_at, last_seen_at)
      VALUES (?, ?, ?, ?, 'ACTIVE', ?, ?);
    ''');
    stmt.execute([deviceId, accountId, devicePublicKey, deviceName, now, now]);
    stmt.close();
  }

  List<Map<String, dynamic>> getDevices(String accountId) {
    final stmt = _db.prepare(
      "SELECT * FROM devices WHERE account_id = ? AND status = 'ACTIVE';",
    );
    final result = stmt.select([accountId]);
    stmt.close();
    return result
        .map(
          (row) => {
            'device_id': row['device_id'],
            'account_id': row['account_id'],
            'device_public_key': row['device_public_key'],
            'device_name': row['device_name'],
            'status': row['status'],
            'push_token': row['push_token'],
            'created_at': row['created_at'],
            'last_seen_at': row['last_seen_at'],
          },
        )
        .toList();
  }

  void revokeDevice(String accountId, String deviceId) {
    final stmt = _db.prepare(
      "UPDATE devices SET status = 'REVOKED' WHERE account_id = ? AND device_id = ?;",
    );
    stmt.execute([accountId, deviceId]);
    stmt.close();
  }

  void updateDevicePushToken(
    String accountId,
    String deviceId,
    String pushToken,
  ) {
    final stmt = _db.prepare(
      'UPDATE devices SET push_token = ? WHERE account_id = ? AND device_id = ?;',
    );
    stmt.execute([pushToken, accountId, deviceId]);
    stmt.close();
  }

  List<Map<String, dynamic>> getDevicesOfDevice(String deviceId) {
    final stmt = _db.prepare('SELECT * FROM devices WHERE device_id = ?;');
    final result = stmt.select([deviceId]);
    stmt.close();
    return result
        .map(
          (row) => {
            'device_id': row['device_id'],
            'account_id': row['account_id'],
          },
        )
        .toList();
  }

  // Prekey operations
  void publishPrekeys({
    required String accountId,
    required String deviceId,
    required int signedPrekeyId,
    required String signedPrekey,
    required String signature,
    required List<Map<String, dynamic>> oneTimePrekeys,
  }) {
    _db.execute('BEGIN TRANSACTION;');
    try {
      final signedStmt = _db.prepare('''
        INSERT OR REPLACE INTO signed_prekeys (account_id, device_id, key_id, public_key, signature)
        VALUES (?, ?, ?, ?, ?);
      ''');
      signedStmt.execute([
        accountId,
        deviceId,
        signedPrekeyId,
        signedPrekey,
        signature,
      ]);
      signedStmt.close();

      // For simplicity, we overwrite Bob's OTKs or append. Let's delete existing OTKs and insert new ones.
      final clearOtkStmt = _db.prepare(
        'DELETE FROM one_time_prekeys WHERE account_id = ? AND device_id = ?;',
      );
      clearOtkStmt.execute([accountId, deviceId]);
      clearOtkStmt.close();

      final otkStmt = _db.prepare('''
        INSERT INTO one_time_prekeys (account_id, device_id, key_id, public_key)
        VALUES (?, ?, ?, ?);
      ''');
      for (final otk in oneTimePrekeys) {
        otkStmt.execute([
          accountId,
          deviceId,
          otk['key_id'],
          otk['public_key'],
        ]);
      }
      otkStmt.close();

      _db.execute('COMMIT;');
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Map<String, dynamic>? getPrekeyBundleForDevice(
    String accountId,
    String deviceId,
  ) {
    // 1. Get account identity key
    final acc = getAccount(accountId);
    if (acc == null) return null;

    // 2. Get device identity key
    final devStmt = _db.prepare(
      "SELECT * FROM devices WHERE account_id = ? AND device_id = ? AND status = 'ACTIVE';",
    );
    final devRes = devStmt.select([accountId, deviceId]);
    devStmt.close();
    if (devRes.isEmpty) return null;
    final devRow = devRes.first;

    // 3. Get signed prekey
    final spkStmt = _db.prepare(
      'SELECT * FROM signed_prekeys WHERE account_id = ? AND device_id = ?;',
    );
    final spkRes = spkStmt.select([accountId, deviceId]);
    spkStmt.close();
    if (spkRes.isEmpty) return null;
    final spkRow = spkRes.first;

    // 4. Get one OTK (atomic retrieval - fetch and delete)
    Map<String, dynamic>? otkData;
    _db.execute('BEGIN TRANSACTION;');
    try {
      final otkStmt = _db.prepare(
        'SELECT * FROM one_time_prekeys WHERE account_id = ? AND device_id = ? LIMIT 1;',
      );
      final otkRes = otkStmt.select([accountId, deviceId]);
      otkStmt.close();

      if (otkRes.isNotEmpty) {
        final otkRow = otkRes.first;
        otkData = {
          'key_id': otkRow['key_id'],
          'public_key': otkRow['public_key'],
        };
        // Delete this OTK
        final delStmt = _db.prepare(
          'DELETE FROM one_time_prekeys WHERE account_id = ? AND device_id = ? AND key_id = ?;',
        );
        delStmt.execute([accountId, deviceId, otkRow['key_id']]);
        delStmt.close();
      }
      _db.execute('COMMIT;');
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }

    return {
      'identity_key': acc['identity_public_key'],
      'device_id': deviceId,
      'device_key': devRow['device_public_key'],
      'signed_prekey': {
        'key_id': spkRow['key_id'],
        'public_key': spkRow['public_key'],
        'signature': spkRow['signature'],
      },
      'one_time_prekey': otkData,
    };
  }

  // Contacts
  void addContact(String accountId, String peerAccountId, String? nickname) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO contacts (account_id, peer_account_id, nickname, status)
      VALUES (?, ?, ?, 'ACCEPTED');
    ''');
    stmt.execute([accountId, peerAccountId, nickname]);
    stmt.close();
  }

  void blockContact(String accountId, String peerAccountId) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO contacts (account_id, peer_account_id, nickname, status)
      VALUES (?, ?, NULL, 'BLOCKED');
    ''');
    stmt.execute([accountId, peerAccountId]);
    stmt.close();
  }

  void unblockContact(String accountId, String peerAccountId) {
    final stmt = _db.prepare('''
      DELETE FROM contacts WHERE account_id = ? AND peer_account_id = ? AND status = 'BLOCKED';
    ''');
    stmt.execute([accountId, peerAccountId]);
    stmt.close();
  }

  List<Map<String, dynamic>> getContacts(String accountId) {
    final stmt = _db.prepare('SELECT * FROM contacts WHERE account_id = ?;');
    final result = stmt.select([accountId]);
    stmt.close();
    return result
        .map(
          (row) => {
            'peer_account_id': row['peer_account_id'],
            'nickname': row['nickname'],
            'status': row['status'],
          },
        )
        .toList();
  }

  bool isBlocked(String accountId, String peerAccountId) {
    final stmt = _db.prepare(
      "SELECT 1 FROM contacts WHERE account_id = ? AND peer_account_id = ? AND status = 'BLOCKED';",
    );
    final res = stmt.select([accountId, peerAccountId]);
    stmt.close();
    return res.isNotEmpty;
  }

  // Conversations
  void createConversation(
    String conversationId,
    String type,
    String? title,
    List<String> memberAccountIds,
  ) {
    _db.execute('BEGIN TRANSACTION;');
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final convStmt = _db.prepare('''
        INSERT OR REPLACE INTO conversations (conversation_id, type, title, created_at, last_sequence)
        VALUES (?, ?, ?, ?, 0);
      ''');
      convStmt.execute([conversationId, type, title, now]);
      convStmt.close();

      // Clear existing members if replacing
      final clearMemStmt = _db.prepare(
        'DELETE FROM conversation_members WHERE conversation_id = ?;',
      );
      clearMemStmt.execute([conversationId]);
      clearMemStmt.close();

      final memStmt = _db.prepare('''
        INSERT INTO conversation_members (conversation_id, account_id, role)
        VALUES (?, ?, 'MEMBER');
      ''');
      for (final memberId in memberAccountIds) {
        memStmt.execute([conversationId, memberId]);
      }
      memStmt.close();

      _db.execute('COMMIT;');
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  bool isConversationMember(String conversationId, String accountId) {
    final stmt = _db.prepare(
      'SELECT 1 FROM conversation_members WHERE conversation_id = ? AND account_id = ?;',
    );
    final res = stmt.select([conversationId, accountId]);
    stmt.close();
    return res.isNotEmpty;
  }

  List<String> getConversationMembers(String conversationId) {
    final stmt = _db.prepare(
      'SELECT account_id FROM conversation_members WHERE conversation_id = ?;',
    );
    final res = stmt.select([conversationId]);
    stmt.close();
    return res.map((row) => row['account_id'] as String).toList();
  }

  // Messaging operations
  int saveMessage({
    required String messageId,
    required String conversationId,
    required String senderAccountId,
    required String senderDeviceId,
    required String recipientDeviceId,
    required String ciphertext,
  }) {
    _db.execute('BEGIN TRANSACTION;');
    try {
      // 1. Get and increment last_sequence for the conversation
      final seqStmt = _db.prepare(
        'SELECT last_sequence FROM conversations WHERE conversation_id = ?;',
      );
      final seqRes = seqStmt.select([conversationId]);
      seqStmt.close();

      int nextSeq = 1;
      if (seqRes.isNotEmpty) {
        nextSeq = (seqRes.first['last_sequence'] as int) + 1;
      }

      final updateSeqStmt = _db.prepare(
        'UPDATE conversations SET last_sequence = ? WHERE conversation_id = ?;',
      );
      updateSeqStmt.execute([nextSeq, conversationId]);
      updateSeqStmt.close();

      // 2. Insert message envelope
      final now = DateTime.now().millisecondsSinceEpoch;
      final msgStmt = _db.prepare('''
        INSERT INTO messages (message_id, conversation_id, sender_account_id, sender_device_id, recipient_device_id, ciphertext, server_sequence, timestamp)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
      ''');
      msgStmt.execute([
        messageId,
        conversationId,
        senderAccountId,
        senderDeviceId,
        recipientDeviceId,
        ciphertext,
        nextSeq,
        now,
      ]);
      msgStmt.close();

      _db.execute('COMMIT;');
      return nextSeq;
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  List<Map<String, dynamic>> getMessagesForDevice(
    String deviceId,
    String conversationId,
    int sinceSequence,
  ) {
    final stmt = _db.prepare('''
      SELECT * FROM messages 
      WHERE recipient_device_id = ? AND conversation_id = ? AND server_sequence > ?
      ORDER BY server_sequence ASC;
    ''');
    final res = stmt.select([deviceId, conversationId, sinceSequence]);
    stmt.close();
    return res
        .map(
          (row) => {
            'message_id': row['message_id'],
            'conversation_id': row['conversation_id'],
            'sender_account_id': row['sender_account_id'],
            'sender_device_id': row['sender_device_id'],
            'recipient_device_id': row['recipient_device_id'],
            'ciphertext': row['ciphertext'],
            'server_sequence': row['server_sequence'],
            'timestamp': row['timestamp'],
          },
        )
        .toList();
  }

  // Retrieve messages across all conversations for offline delivery
  List<Map<String, dynamic>> getOfflineMessagesForDevice(String deviceId) {
    final stmt = _db.prepare('''
      SELECT m.* FROM messages m
      LEFT JOIN sync_cursors c ON c.device_id = m.recipient_device_id AND c.conversation_id = m.conversation_id
      WHERE m.recipient_device_id = ? AND (c.last_sequence IS NULL OR m.server_sequence > c.last_sequence)
      ORDER BY m.server_sequence ASC;
    ''');
    final res = stmt.select([deviceId]);
    stmt.close();
    return res
        .map(
          (row) => {
            'message_id': row['message_id'],
            'conversation_id': row['conversation_id'],
            'sender_account_id': row['sender_account_id'],
            'sender_device_id': row['sender_device_id'],
            'recipient_device_id': row['recipient_device_id'],
            'ciphertext': row['ciphertext'],
            'server_sequence': row['server_sequence'],
            'timestamp': row['timestamp'],
          },
        )
        .toList();
  }

  void updateSyncCursor(
    String accountId,
    String deviceId,
    String conversationId,
    int sequence,
  ) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO sync_cursors (account_id, device_id, conversation_id, last_sequence)
      VALUES (?, ?, ?, ?);
    ''');
    stmt.execute([accountId, deviceId, conversationId, sequence]);
    stmt.close();
  }

  List<Map<String, dynamic>> getSyncCursors(String accountId, String deviceId) {
    final stmt = _db.prepare(
      'SELECT * FROM sync_cursors WHERE account_id = ? AND device_id = ?;',
    );
    final res = stmt.select([accountId, deviceId]);
    stmt.close();
    return res
        .map(
          (row) => {
            'conversation_id': row['conversation_id'],
            'last_sequence': row['last_sequence'],
          },
        )
        .toList();
  }

  // Backup operations
  void setBackup(String accountId, String backupData) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO backups (account_id, backup_data, created_at)
      VALUES (?, ?, ?);
    ''');
    stmt.execute([accountId, backupData, now]);
    stmt.close();
  }

  Map<String, dynamic>? getBackup(String accountId) {
    final stmt = _db.prepare('SELECT * FROM backups WHERE account_id = ?;');
    final res = stmt.select([accountId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'account_id': row['account_id'],
      'backup_data': row['backup_data'],
      'created_at': row['created_at'],
    };
  }

  // Outbox operations
  void enqueueOutbox(String eventId, String type, String payload) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO outbox (event_id, type, payload, status, retries, created_at)
      VALUES (?, ?, ?, 'PENDING', 0, ?);
    ''');
    stmt.execute([eventId, type, payload, now]);
    stmt.close();
  }

  List<Map<String, dynamic>> getPendingOutbox() {
    final stmt = _db.prepare(
      "SELECT * FROM outbox WHERE status = 'PENDING' OR status = 'FAILED' AND retries < 5;",
    );
    final res = stmt.select();
    stmt.close();
    return res
        .map(
          (row) => {
            'event_id': row['event_id'],
            'type': row['type'],
            'payload': row['payload'],
            'status': row['status'],
            'retries': row['retries'],
            'created_at': row['created_at'],
          },
        )
        .toList();
  }

  void updateOutboxStatus(String eventId, String status, int retries) {
    final stmt = _db.prepare(
      'UPDATE outbox SET status = ?, retries = ? WHERE event_id = ?;',
    );
    stmt.execute([status, retries, eventId]);
    stmt.close();
  }

  // Audit Logs
  void logAudit(
    String? accountId,
    String? deviceId,
    String action,
    String? clientIp,
    String? userAgent,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final uuid =
        '${now}_${action.hashCode}_${(accountId ?? "system").hashCode}';
    final stmt = _db.prepare('''
      INSERT INTO audit_logs (event_id, account_id, device_id, action, client_ip, user_agent, timestamp)
      VALUES (?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([uuid, accountId, deviceId, action, clientIp, userAgent, now]);
    stmt.close();
  }
}
