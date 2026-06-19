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

    if (version < 2) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS refresh_tokens (
          token_hash TEXT PRIMARY KEY,
          account_id TEXT NOT NULL,
          device_id TEXT NOT NULL,
          expires_at INTEGER NOT NULL,
          revoked INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY(account_id) REFERENCES accounts(account_id) ON DELETE CASCADE,
          FOREIGN KEY(device_id) REFERENCES devices(device_id) ON DELETE CASCADE
        );
      ''');

      _db.execute('''
        CREATE TABLE IF NOT EXISTS tombstones (
          item_id TEXT PRIMARY KEY,
          type TEXT NOT NULL,
          deleted_at INTEGER NOT NULL
        );
      ''');

      _db.execute('PRAGMA user_version = 2;');
    }

    if (version < 3) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS contact_requests (
          request_id TEXT PRIMARY KEY,
          requester_account_id TEXT NOT NULL,
          target_account_id TEXT NOT NULL,
          status TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          FOREIGN KEY(requester_account_id) REFERENCES accounts(account_id) ON DELETE CASCADE,
          FOREIGN KEY(target_account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
        );
      ''');

      _db.execute('''
        CREATE TABLE IF NOT EXISTS account_privacy (
          account_id TEXT PRIMARY KEY,
          search_discoverable INTEGER NOT NULL DEFAULT 1,
          presence_visibility TEXT NOT NULL DEFAULT 'CONTACTS',
          last_seen_visibility TEXT NOT NULL DEFAULT 'CONTACTS',
          profile_version INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY(account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
        );
      ''');

      _db.execute('''
        CREATE TABLE IF NOT EXISTS reports (
          report_id TEXT PRIMARY KEY,
          reporter_account_id TEXT NOT NULL,
          subject_account_id TEXT NOT NULL,
          category TEXT NOT NULL,
          reason_code TEXT NOT NULL,
          context_hash TEXT,
          status TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          FOREIGN KEY(reporter_account_id) REFERENCES accounts(account_id) ON DELETE CASCADE,
          FOREIGN KEY(subject_account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
        );
      ''');

      _db.execute('''
        CREATE TABLE IF NOT EXISTS safety_actions (
          action_id TEXT PRIMARY KEY,
          report_id TEXT NOT NULL,
          actor_account_id TEXT NOT NULL,
          action TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          FOREIGN KEY(report_id) REFERENCES reports(report_id) ON DELETE CASCADE
        );
      ''');

      _db.execute('PRAGMA user_version = 3;');
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

  void updateUsername(String accountId, String username) {
    final stmt = _db.prepare(
      'UPDATE accounts SET username = ? WHERE account_id = ?;',
    );
    stmt.execute([username, accountId]);
    stmt.close();
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

  void updateDeviceLastSeen(String accountId, String deviceId, int timestamp) {
    final stmt = _db.prepare('''
      UPDATE devices SET last_seen_at = ?
      WHERE account_id = ? AND device_id = ?;
    ''');
    stmt.execute([timestamp, accountId, deviceId]);
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
  void createContactRequest({
    required String requestId,
    required String requesterAccountId,
    required String targetAccountId,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute('BEGIN TRANSACTION;');
    try {
      final requestStmt = _db.prepare('''
        INSERT INTO contact_requests (
          request_id,
          requester_account_id,
          target_account_id,
          status,
          created_at,
          updated_at
        )
        VALUES (?, ?, ?, 'PENDING', ?, ?);
      ''');
      requestStmt.execute([
        requestId,
        requesterAccountId,
        targetAccountId,
        now,
        now,
      ]);
      requestStmt.close();

      _upsertContactInTransaction(
        requesterAccountId,
        targetAccountId,
        null,
        'PENDING_SENT',
      );
      _upsertContactInTransaction(
        targetAccountId,
        requesterAccountId,
        null,
        'PENDING_RECEIVED',
      );
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Map<String, dynamic>? getContactRequest(String requestId) {
    final stmt = _db.prepare(
      'SELECT * FROM contact_requests WHERE request_id = ?;',
    );
    final res = stmt.select([requestId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'request_id': row['request_id'],
      'requester_account_id': row['requester_account_id'],
      'target_account_id': row['target_account_id'],
      'status': row['status'],
      'created_at': row['created_at'],
      'updated_at': row['updated_at'],
    };
  }

  List<Map<String, dynamic>> getContactRequests(String accountId) {
    final stmt = _db.prepare('''
      SELECT * FROM contact_requests
      WHERE requester_account_id = ? OR target_account_id = ?
      ORDER BY created_at DESC;
    ''');
    final res = stmt.select([accountId, accountId]);
    stmt.close();
    return res
        .map(
          (row) => {
            'request_id': row['request_id'],
            'requester_account_id': row['requester_account_id'],
            'target_account_id': row['target_account_id'],
            'status': row['status'],
            'created_at': row['created_at'],
            'updated_at': row['updated_at'],
          },
        )
        .toList();
  }

  int countContactRequestsSince(String accountId, int sinceTimestamp) {
    final stmt = _db.prepare('''
      SELECT COUNT(*) AS count FROM contact_requests
      WHERE requester_account_id = ? AND created_at >= ?;
    ''');
    final res = stmt.select([accountId, sinceTimestamp]);
    stmt.close();
    return res.first['count'] as int;
  }

  bool hasOpenContactRequest(
    String requesterAccountId,
    String targetAccountId,
  ) {
    final stmt = _db.prepare('''
      SELECT 1 FROM contact_requests
      WHERE requester_account_id = ?
        AND target_account_id = ?
        AND status = 'PENDING';
    ''');
    final res = stmt.select([requesterAccountId, targetAccountId]);
    stmt.close();
    return res.isNotEmpty;
  }

  void acceptContactRequest(String requestId) {
    final request = getContactRequest(requestId);
    if (request == null) {
      throw StateError('Contact request not found');
    }
    final requester = request['requester_account_id'] as String;
    final target = request['target_account_id'] as String;
    final now = DateTime.now().millisecondsSinceEpoch;

    _db.execute('BEGIN TRANSACTION;');
    try {
      final stmt = _db.prepare('''
        UPDATE contact_requests
        SET status = 'ACCEPTED', updated_at = ?
        WHERE request_id = ?;
      ''');
      stmt.execute([now, requestId]);
      stmt.close();
      _upsertContactInTransaction(requester, target, null, 'ACCEPTED');
      _upsertContactInTransaction(target, requester, null, 'ACCEPTED');
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void closeContactRequest(String requestId, String status) {
    final request = getContactRequest(requestId);
    if (request == null) {
      throw StateError('Contact request not found');
    }
    final requester = request['requester_account_id'] as String;
    final target = request['target_account_id'] as String;
    final now = DateTime.now().millisecondsSinceEpoch;

    _db.execute('BEGIN TRANSACTION;');
    try {
      final stmt = _db.prepare('''
        UPDATE contact_requests
        SET status = ?, updated_at = ?
        WHERE request_id = ?;
      ''');
      stmt.execute([status, now, requestId]);
      stmt.close();
      _deleteContactInTransaction(requester, target, onlyPending: true);
      _deleteContactInTransaction(target, requester, onlyPending: true);
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void addContact(String accountId, String peerAccountId, String? nickname) {
    _upsertContact(accountId, peerAccountId, nickname, 'ACCEPTED');
  }

  void blockContact(String accountId, String peerAccountId) {
    _upsertContact(accountId, peerAccountId, null, 'BLOCKED');
  }

  void unblockContact(String accountId, String peerAccountId) {
    removeContact(accountId, peerAccountId, onlyStatus: 'BLOCKED');
  }

  void removeContact(
    String accountId,
    String peerAccountId, {
    String? onlyStatus,
  }) {
    final sql = onlyStatus == null
        ? 'DELETE FROM contacts WHERE account_id = ? AND peer_account_id = ?;'
        : 'DELETE FROM contacts WHERE account_id = ? AND peer_account_id = ? AND status = ?;';
    final stmt = _db.prepare(sql);
    stmt.execute(
      onlyStatus == null
          ? [accountId, peerAccountId]
          : [accountId, peerAccountId, onlyStatus],
    );
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

  bool areContacts(String accountId, String peerAccountId) {
    final stmt = _db.prepare(
      "SELECT 1 FROM contacts WHERE account_id = ? AND peer_account_id = ? AND status = 'ACCEPTED';",
    );
    final res = stmt.select([accountId, peerAccountId]);
    stmt.close();
    return res.isNotEmpty;
  }

  void _upsertContact(
    String accountId,
    String peerAccountId,
    String? nickname,
    String status,
  ) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO contacts (account_id, peer_account_id, nickname, status)
      VALUES (?, ?, ?, ?);
    ''');
    stmt.execute([accountId, peerAccountId, nickname, status]);
    stmt.close();
  }

  void _upsertContactInTransaction(
    String accountId,
    String peerAccountId,
    String? nickname,
    String status,
  ) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO contacts (account_id, peer_account_id, nickname, status)
      VALUES (?, ?, ?, ?);
    ''');
    stmt.execute([accountId, peerAccountId, nickname, status]);
    stmt.close();
  }

  void _deleteContactInTransaction(
    String accountId,
    String peerAccountId, {
    bool onlyPending = false,
  }) {
    final stmt = _db.prepare(
      onlyPending
          ? "DELETE FROM contacts WHERE account_id = ? AND peer_account_id = ? AND status IN ('PENDING_SENT', 'PENDING_RECEIVED');"
          : 'DELETE FROM contacts WHERE account_id = ? AND peer_account_id = ?;',
    );
    stmt.execute([accountId, peerAccountId]);
    stmt.close();
  }

  Map<String, dynamic> getPrivacy(String accountId) {
    _ensurePrivacyRow(accountId);
    final stmt = _db.prepare(
      'SELECT * FROM account_privacy WHERE account_id = ?;',
    );
    final res = stmt.select([accountId]);
    stmt.close();
    final row = res.first;
    return {
      'account_id': row['account_id'],
      'search_discoverable': row['search_discoverable'] == 1,
      'presence_visibility': row['presence_visibility'],
      'last_seen_visibility': row['last_seen_visibility'],
      'profile_version': row['profile_version'],
    };
  }

  void setPrivacy({
    required String accountId,
    required bool searchDiscoverable,
    required String presenceVisibility,
    required String lastSeenVisibility,
  }) {
    final current = getPrivacy(accountId);
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO account_privacy (
        account_id,
        search_discoverable,
        presence_visibility,
        last_seen_visibility,
        profile_version
      )
      VALUES (?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      accountId,
      searchDiscoverable ? 1 : 0,
      presenceVisibility,
      lastSeenVisibility,
      (current['profile_version'] as int) + 1,
    ]);
    stmt.close();
  }

  List<Map<String, dynamic>> searchAccounts(
    String requesterAccountId,
    String query, {
    int limit = 20,
  }) {
    final stmt = _db.prepare('''
      SELECT a.account_id, a.username
      FROM accounts a
      LEFT JOIN account_privacy p ON p.account_id = a.account_id
      WHERE a.account_id != ?
        AND (p.search_discoverable IS NULL OR p.search_discoverable = 1)
        AND a.username LIKE ?
      ORDER BY a.username ASC
      LIMIT ?;
    ''');
    final res = stmt.select([requesterAccountId, '$query%', limit]);
    stmt.close();
    return res
        .where(
          (row) =>
              !isBlocked(row['account_id'] as String, requesterAccountId) &&
              !isBlocked(requesterAccountId, row['account_id'] as String),
        )
        .map(
          (row) => {
            'account_id': row['account_id'],
            'username': row['username'],
          },
        )
        .toList();
  }

  Map<String, dynamic>? getPresenceForViewer(
    String viewerAccountId,
    String targetAccountId,
  ) {
    final privacy = getPrivacy(targetAccountId);
    final visibility = privacy['presence_visibility'] as String;
    if (visibility == 'NOBODY') return null;
    if (visibility == 'CONTACTS' &&
        !areContacts(targetAccountId, viewerAccountId)) {
      return null;
    }

    final stmt = _db.prepare('''
      SELECT MAX(last_seen_at) AS last_seen_at
      FROM devices
      WHERE account_id = ? AND status = 'ACTIVE';
    ''');
    final res = stmt.select([targetAccountId]);
    stmt.close();
    final lastSeen = res.first['last_seen_at'];
    if (lastSeen == null) return null;

    return {
      'account_id': targetAccountId,
      'presence': 'RECENTLY_ACTIVE',
      'last_seen_at': privacy['last_seen_visibility'] == 'NOBODY'
          ? null
          : lastSeen,
    };
  }

  String createReport({
    required String reportId,
    required String reporterAccountId,
    required String subjectAccountId,
    required String category,
    required String reasonCode,
    String? contextHash,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO reports (
        report_id,
        reporter_account_id,
        subject_account_id,
        category,
        reason_code,
        context_hash,
        status,
        created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, 'OPEN', ?);
    ''');
    stmt.execute([
      reportId,
      reporterAccountId,
      subjectAccountId,
      category,
      reasonCode,
      contextHash,
      now,
    ]);
    stmt.close();
    return reportId;
  }

  List<Map<String, dynamic>> getReports() {
    final stmt = _db.prepare('SELECT * FROM reports ORDER BY created_at DESC;');
    final res = stmt.select();
    stmt.close();
    return res
        .map(
          (row) => {
            'report_id': row['report_id'],
            'reporter_account_id': row['reporter_account_id'],
            'subject_account_id': row['subject_account_id'],
            'category': row['category'],
            'reason_code': row['reason_code'],
            'context_hash': row['context_hash'],
            'status': row['status'],
            'created_at': row['created_at'],
          },
        )
        .toList();
  }

  void addSafetyAction({
    required String actionId,
    required String reportId,
    required String actorAccountId,
    required String action,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute('BEGIN TRANSACTION;');
    try {
      final actionStmt = _db.prepare('''
        INSERT INTO safety_actions (action_id, report_id, actor_account_id, action, created_at)
        VALUES (?, ?, ?, ?, ?);
      ''');
      actionStmt.execute([actionId, reportId, actorAccountId, action, now]);
      actionStmt.close();

      final statusStmt = _db.prepare(
        "UPDATE reports SET status = 'ACTIONED' WHERE report_id = ?;",
      );
      statusStmt.execute([reportId]);
      statusStmt.close();
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void _ensurePrivacyRow(String accountId) {
    final stmt = _db.prepare('''
      INSERT OR IGNORE INTO account_privacy (account_id)
      VALUES (?);
    ''');
    stmt.execute([accountId]);
    stmt.close();
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

  Map<String, dynamic>? getMessage(String messageId) {
    final stmt = _db.prepare(
      'SELECT * FROM messages WHERE message_id = ? LIMIT 1;',
    );
    final res = stmt.select([messageId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'message_id': row['message_id'],
      'conversation_id': row['conversation_id'],
      'sender_account_id': row['sender_account_id'],
      'sender_device_id': row['sender_device_id'],
    };
  }

  void deleteMessage(String messageId) {
    final stmt = _db.prepare('DELETE FROM messages WHERE message_id = ?;');
    stmt.execute([messageId]);
    stmt.close();
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

  // Refresh Tokens (P10-003)
  void saveRefreshToken({
    required String tokenHash,
    required String accountId,
    required String deviceId,
    required int expiresAt,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO refresh_tokens (token_hash, account_id, device_id, expires_at, revoked)
      VALUES (?, ?, ?, ?, 0);
    ''');
    stmt.execute([tokenHash, accountId, deviceId, expiresAt]);
    stmt.close();
  }

  Map<String, dynamic>? getRefreshToken(String tokenHash) {
    final stmt = _db.prepare(
      'SELECT * FROM refresh_tokens WHERE token_hash = ?;',
    );
    final res = stmt.select([tokenHash]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'token_hash': row['token_hash'],
      'account_id': row['account_id'],
      'device_id': row['device_id'],
      'expires_at': row['expires_at'],
      'revoked': row['revoked'],
    };
  }

  void revokeRefreshToken(String tokenHash) {
    final stmt = _db.prepare(
      'UPDATE refresh_tokens SET revoked = 1 WHERE token_hash = ?;',
    );
    stmt.execute([tokenHash]);
    stmt.close();
  }

  void revokeAllRefreshTokensForDevice(String accountId, String deviceId) {
    final stmt = _db.prepare(
      'UPDATE refresh_tokens SET revoked = 1 WHERE account_id = ? AND device_id = ?;',
    );
    stmt.execute([accountId, deviceId]);
    stmt.close();
  }

  // Tombstones (P10-018)
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

  // Quotas / Backpressure (P10-021)
  int getMessageCountForDevice(String deviceId) {
    final stmt = _db.prepare(
      'SELECT COUNT(*) FROM messages WHERE recipient_device_id = ?;',
    );
    final res = stmt.select([deviceId]);
    stmt.close();
    if (res.isEmpty) return 0;
    return res.first.columnAt(0) as int;
  }
}
