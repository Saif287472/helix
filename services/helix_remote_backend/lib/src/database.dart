import 'dart:convert';

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
          backup_id TEXT NOT NULL DEFAULT '',
          version INTEGER NOT NULL DEFAULT 1,
          kdf TEXT NOT NULL DEFAULT '',
          salt TEXT NOT NULL DEFAULT '',
          backup_key_hint TEXT NOT NULL DEFAULT '',
          backup_data TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          deletion_watermark INTEGER NOT NULL DEFAULT 0,
          requires_reupload INTEGER NOT NULL DEFAULT 0,
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

    if (version < 4) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS attachments (
          file_id TEXT PRIMARY KEY,
          file_size INTEGER NOT NULL,
          file_hash TEXT NOT NULL,
          uploaded_bytes INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL
        );
      ''');
      _db.execute('PRAGMA user_version = 4;');
    }

    if (version < 5) {
      _db.execute('DROP TABLE IF EXISTS attachments;');
      _db.execute('''
        CREATE TABLE attachments (
          file_id TEXT PRIMARY KEY,
          account_id TEXT NOT NULL,
          file_size INTEGER NOT NULL,
          file_hash TEXT NOT NULL,
          uploaded_bytes INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL,
          FOREIGN KEY(account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
        );
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS attachment_references (
          file_id TEXT NOT NULL,
          message_id TEXT NOT NULL,
          PRIMARY KEY(file_id, message_id),
          FOREIGN KEY(file_id) REFERENCES attachments(file_id) ON DELETE CASCADE
        );
      ''');
      _db.execute('PRAGMA user_version = 5;');
    }

    if (version < 6) {
      _db.execute('DROP TABLE IF EXISTS attachment_references;');
      _db.execute('DROP TABLE IF EXISTS attachments;');
      _db.execute('''
        CREATE TABLE attachments (
          file_id TEXT PRIMARY KEY,
          account_id TEXT NOT NULL,
          file_size INTEGER NOT NULL,
          file_hash TEXT NOT NULL,
          uploaded_bytes INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          FOREIGN KEY(account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
        );
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS attachment_references (
          file_id TEXT NOT NULL,
          message_id TEXT NOT NULL,
          PRIMARY KEY(file_id, message_id),
          FOREIGN KEY(file_id) REFERENCES attachments(file_id) ON DELETE CASCADE
        );
      ''');
      _db.execute('PRAGMA user_version = 6;');
    }

    if (version < 7) {
      // Tracks TURN credential issuance per account for quota enforcement (P15-005/P15-018).
      _db.execute('''
        CREATE TABLE IF NOT EXISTS turn_credential_log (
          log_id TEXT PRIMARY KEY,
          account_id TEXT NOT NULL,
          issued_at INTEGER NOT NULL,
          expires_at INTEGER NOT NULL,
          FOREIGN KEY(account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
        );
      ''');
      _db.execute('PRAGMA user_version = 7;');
    }

    if (version < 8) {
      // P16-001: Group metadata linked to conversations.
      _db.execute('''
        CREATE TABLE IF NOT EXISTS groups (
          group_id TEXT PRIMARY KEY,
          creator_id TEXT NOT NULL,
          encryption_key_id TEXT NOT NULL DEFAULT '',
          status TEXT NOT NULL DEFAULT 'ACTIVE',
          created_at INTEGER NOT NULL,
          FOREIGN KEY(group_id) REFERENCES conversations(conversation_id) ON DELETE CASCADE,
          FOREIGN KEY(creator_id) REFERENCES accounts(account_id) ON DELETE CASCADE
        );
      ''');

      // P16-003: Invite lifecycle (PENDING/ACCEPTED/REJECTED).
      _db.execute('''
        CREATE TABLE IF NOT EXISTS group_invites (
          invite_id TEXT PRIMARY KEY,
          group_id TEXT NOT NULL,
          inviter_id TEXT NOT NULL,
          invitee_id TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'PENDING',
          created_at INTEGER NOT NULL,
          FOREIGN KEY(group_id) REFERENCES conversations(conversation_id) ON DELETE CASCADE,
          FOREIGN KEY(inviter_id) REFERENCES accounts(account_id) ON DELETE CASCADE,
          FOREIGN KEY(invitee_id) REFERENCES accounts(account_id) ON DELETE CASCADE
        );
      ''');

      // P16-014: Rate-limit group creation per account (5 per day).
      _db.execute('''
        CREATE TABLE IF NOT EXISTS group_creation_log (
          log_id TEXT PRIMARY KEY,
          account_id TEXT NOT NULL,
          created_at INTEGER NOT NULL
        );
      ''');

      _db.execute('PRAGMA user_version = 8;');
    }

    if (version < 9) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS pending_device_links (
          link_id TEXT PRIMARY KEY,
          account_id TEXT NOT NULL,
          requested_by_device_id TEXT NOT NULL,
          new_device_id TEXT NOT NULL,
          new_device_public_key TEXT NOT NULL,
          new_device_name TEXT NOT NULL,
          verification_code_hash TEXT NOT NULL,
          status TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          approved_at INTEGER,
          FOREIGN KEY(account_id) REFERENCES accounts(account_id) ON DELETE CASCADE,
          FOREIGN KEY(requested_by_device_id) REFERENCES devices(device_id) ON DELETE CASCADE
        );
      ''');

      _db.execute('''
        CREATE TABLE IF NOT EXISTS device_revocations (
          revocation_id TEXT PRIMARY KEY,
          account_id TEXT NOT NULL,
          revoked_device_id TEXT NOT NULL,
          revoked_by_device_id TEXT,
          reason TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          FOREIGN KEY(account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
        );
      ''');

      for (final statement in [
        "ALTER TABLE backups ADD COLUMN backup_id TEXT NOT NULL DEFAULT '';",
        "ALTER TABLE backups ADD COLUMN version INTEGER NOT NULL DEFAULT 1;",
        "ALTER TABLE backups ADD COLUMN kdf TEXT NOT NULL DEFAULT '';",
        "ALTER TABLE backups ADD COLUMN salt TEXT NOT NULL DEFAULT '';",
        "ALTER TABLE backups ADD COLUMN backup_key_hint TEXT NOT NULL DEFAULT '';",
        "ALTER TABLE backups ADD COLUMN deletion_watermark INTEGER NOT NULL DEFAULT 0;",
        "ALTER TABLE backups ADD COLUMN requires_reupload INTEGER NOT NULL DEFAULT 0;",
      ]) {
        try {
          _db.execute(statement);
        } catch (_) {}
      }

      _db.execute('PRAGMA user_version = 9;');
    }

    if (version < 10) {
      // Phase 18 is policy/control focused. No new tables are required; the
      // version marks databases that have account export/delete helper support.
      _db.execute('PRAGMA user_version = 10;');
    }

    if (version < 11) {
      // Phase 19 adds operational health and aggregate metrics helpers. No new
      // tables are required.
      _db.execute('PRAGMA user_version = 11;');
    }

    if (version < 12) {
      // Stage 3: per-device event stream for proper cursor tracking
      _db.execute('''
        CREATE TABLE IF NOT EXISTS device_events (
          event_id TEXT NOT NULL,
          recipient_device_id TEXT NOT NULL,
          device_sequence INTEGER NOT NULL,
          schema_version INTEGER NOT NULL DEFAULT 1,
          event_type TEXT NOT NULL,
          timestamp INTEGER NOT NULL,
          payload TEXT NOT NULL,
          PRIMARY KEY(recipient_device_id, device_sequence),
          FOREIGN KEY(recipient_device_id) REFERENCES devices(device_id) ON DELETE CASCADE
        );
      ''');
      _db.execute('PRAGMA user_version = 12;');
    }
  }

  void close() {
    _db.close();
  }

  int get schemaVersion {
    final rows = _db.select('PRAGMA user_version;');
    return rows.first.columnAt(0) as int;
  }

  bool quickCheckOk() {
    final rows = _db.select('PRAGMA quick_check;');
    return rows.isNotEmpty && rows.first.columnAt(0) == 'ok';
  }

  Map<String, int> getOperationalTableCounts() {
    const tables = [
      'accounts',
      'devices',
      'conversations',
      'conversation_members',
      'messages',
      'attachments',
      'backups',
      'outbox',
      'audit_logs',
      'reports',
      'groups',
      'group_invites',
      'turn_credential_log',
    ];
    return {for (final table in tables) table: _countRows(table)};
  }

  Map<String, int> getOperationalMailboxStats() {
    final rows = _db.select('''
      SELECT
        COUNT(*) AS message_count,
        COALESCE(MAX(timestamp), 0) AS newest_message_at,
        COALESCE(MIN(timestamp), 0) AS oldest_message_at
      FROM messages;
    ''');
    final row = rows.first;
    return {
      'message_count': row['message_count'] as int,
      'newest_message_at': row['newest_message_at'] as int,
      'oldest_message_at': row['oldest_message_at'] as int,
    };
  }

  Map<String, int> getOperationalAttachmentStats() {
    final rows = _db.select('''
      SELECT
        COUNT(*) AS object_count,
        COALESCE(SUM(file_size), 0) AS total_bytes,
        SUM(CASE WHEN status = 'COMPLETED' THEN 1 ELSE 0 END) AS completed,
        SUM(CASE WHEN status != 'COMPLETED' THEN 1 ELSE 0 END) AS incomplete
      FROM attachments;
    ''');
    final row = rows.first;
    return {
      'object_count': row['object_count'] as int,
      'total_bytes': row['total_bytes'] as int,
      'completed': row['completed'] as int,
      'incomplete': row['incomplete'] as int,
    };
  }

  Map<String, int> getOutboxStatusCounts() {
    final rows = _db.select('''
      SELECT status, COUNT(*) AS count
      FROM outbox
      GROUP BY status;
    ''');
    final counts = <String, int>{
      'PENDING': 0,
      'FAILED': 0,
      'COMPLETED': 0,
      'DLQ': 0,
    };
    for (final row in rows) {
      counts[row['status'] as String] = row['count'] as int;
    }
    return counts;
  }

  Map<String, dynamic>? getOutboxEvent(String eventId) {
    final stmt = _db.prepare('SELECT * FROM outbox WHERE event_id = ?;');
    final rows = stmt.select([eventId]);
    stmt.close();
    if (rows.isEmpty) return null;
    final row = rows.first;
    return {
      'event_id': row['event_id'],
      'type': row['type'],
      'status': row['status'],
      'retries': row['retries'],
      'created_at': row['created_at'],
    };
  }

  int _countRows(String table) {
    final rows = _db.select('SELECT COUNT(*) AS count FROM $table;');
    return rows.first['count'] as int;
  }

  // ---------------------------------------------------------------------------
  // Attachment operations
  // ---------------------------------------------------------------------------

  void createAttachment({
    required String fileId,
    required String accountId,
    required int fileSize,
    required String fileHash,
    int? createdAt,
  }) {
    final time = createdAt ?? DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO attachments (file_id, account_id, file_size, file_hash, uploaded_bytes, status, created_at)
      VALUES (?, ?, ?, ?, 0, 'PENDING', ?);
    ''');
    stmt.execute([fileId, accountId, fileSize, fileHash, time]);
    stmt.close();
  }

  List<String> getOrphanAttachmentIds(int olderThanTimestamp) {
    final stmt = _db.prepare('''
      SELECT file_id FROM attachments 
      WHERE status != 'COMPLETED' AND created_at < ?;
    ''');
    final res = stmt.select([olderThanTimestamp]);
    stmt.close();
    return res.map((row) => row['file_id'] as String).toList();
  }

  List<String> getAttachmentsOlderThan(int olderThanTimestamp) {
    final stmt = _db.prepare('''
      SELECT file_id FROM attachments 
      WHERE status = 'COMPLETED' AND created_at < ?;
    ''');
    final res = stmt.select([olderThanTimestamp]);
    stmt.close();
    return res.map((row) => row['file_id'] as String).toList();
  }

  Map<String, dynamic>? getAttachment(String fileId) {
    final stmt = _db.prepare('SELECT * FROM attachments WHERE file_id = ?;');
    final result = stmt.select([fileId]);
    stmt.close();
    if (result.isEmpty) return null;
    final row = result.first;
    return {
      'file_id': row['file_id'],
      'account_id': row['account_id'],
      'file_size': row['file_size'],
      'file_hash': row['file_hash'],
      'uploaded_bytes': row['uploaded_bytes'],
      'status': row['status'],
    };
  }

  void updateAttachmentProgress(
    String fileId,
    int uploadedBytes,
    String status,
  ) {
    final stmt = _db.prepare('''
      UPDATE attachments SET uploaded_bytes = ?, status = ? WHERE file_id = ?;
    ''');
    stmt.execute([uploadedBytes, status, fileId]);
    stmt.close();
  }

  void registerAttachmentReference(String fileId, String messageId) {
    final stmt = _db.prepare('''
      INSERT OR IGNORE INTO attachment_references (file_id, message_id)
      VALUES (?, ?);
    ''');
    stmt.execute([fileId, messageId]);
    stmt.close();
  }

  int getAttachmentReferenceCount(String fileId) {
    final stmt = _db.prepare('''
      SELECT COUNT(*) FROM attachment_references WHERE file_id = ?;
    ''');
    final res = stmt.select([fileId]);
    stmt.close();
    if (res.isEmpty) return 0;
    return res.first.columnAt(0) as int;
  }

  void deleteAttachmentReferences(String messageId) {
    final stmt = _db.prepare(
      'DELETE FROM attachment_references WHERE message_id = ?;',
    );
    stmt.execute([messageId]);
    stmt.close();
  }

  List<String> getReferencedFileIds(String messageId) {
    final stmt = _db.prepare(
      'SELECT file_id FROM attachment_references WHERE message_id = ?;',
    );
    final res = stmt.select([messageId]);
    stmt.close();
    return res.map((row) => row['file_id'] as String).toList();
  }

  void deleteAttachmentRow(String fileId) {
    final stmt = _db.prepare('DELETE FROM attachments WHERE file_id = ?;');
    stmt.execute([fileId]);
    stmt.close();
  }

  int getAccountStorageUsage(String accountId) {
    final stmt = _db.prepare('''
      SELECT SUM(file_size) FROM attachments 
      WHERE account_id = ? AND status = 'COMPLETED';
    ''');
    final res = stmt.select([accountId]);
    stmt.close();
    if (res.isEmpty) return 0;
    final val = res.first.columnAt(0);
    return val is int ? val : 0;
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

  Map<String, dynamic> exportAccountData(String accountId) {
    final deviceIds = getDevices(
      accountId,
    ).map((device) => device['device_id'] as String).toList();

    return {
      'export_version': 1,
      'exported_at': DateTime.now().millisecondsSinceEpoch,
      'account': getAccount(accountId),
      'devices': getDevices(accountId),
      'device_revocations': _selectWhere(
        'device_revocations',
        'account_id = ?',
        [accountId],
      ),
      'pending_device_links': _selectWhere(
        'pending_device_links',
        'account_id = ?',
        [accountId],
      ),
      'public_prekeys': {
        'signed_prekeys': _selectWhere('signed_prekeys', 'account_id = ?', [
          accountId,
        ]),
        'one_time_prekeys': _selectWhere('one_time_prekeys', 'account_id = ?', [
          accountId,
        ]),
      },
      'contacts': getContacts(accountId),
      'contact_requests': getContactRequests(accountId),
      'privacy': getPrivacy(accountId),
      'conversations': _selectWhere(
        'conversations',
        'conversation_id IN (SELECT conversation_id FROM conversation_members WHERE account_id = ?)',
        [accountId],
      ),
      'memberships': _selectWhere('conversation_members', 'account_id = ?', [
        accountId,
      ]),
      'message_mailbox': deviceIds.isEmpty
          ? <Map<String, dynamic>>[]
          : _selectWhere(
              'messages',
              'recipient_device_id IN (${List.filled(deviceIds.length, '?').join(', ')}) OR sender_account_id = ?',
              [...deviceIds, accountId],
            ),
      'attachments': _selectWhere('attachments', 'account_id = ?', [accountId]),
      'backup': getBackup(accountId),
      'reports': [
        ..._selectWhere('reports', 'reporter_account_id = ?', [accountId]),
        ..._selectWhere('reports', 'subject_account_id = ?', [accountId]),
      ],
      'audit': _selectWhere('audit_logs', 'account_id = ?', [accountId]),
    };
  }

  void deleteAccountData(String accountId) {
    _db.execute('BEGIN TRANSACTION;');
    try {
      final devices = getDevices(
        accountId,
      ).map((device) => device['device_id'] as String).toList();
      for (final deviceId in devices) {
        deleteMessagesForDevice(deviceId);
      }

      for (final table in [
        'audit_logs',
        'group_creation_log',
        'turn_credential_log',
        'pending_device_links',
        'device_revocations',
      ]) {
        _deleteWhere(table, 'account_id = ?', [accountId]);
      }
      for (final table in ['reports']) {
        _deleteWhere(
          table,
          'reporter_account_id = ? OR subject_account_id = ?',
          [accountId, accountId],
        );
      }
      _deleteWhere('outbox', 'payload LIKE ?', ['%$accountId%']);

      final stmt = _db.prepare('DELETE FROM accounts WHERE account_id = ?;');
      stmt.execute([accountId]);
      stmt.close();
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
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

  bool isDeviceActive(String accountId, String deviceId) {
    final stmt = _db.prepare('''
      SELECT 1 FROM devices
      WHERE account_id = ? AND device_id = ? AND status = 'ACTIVE';
    ''');
    final res = stmt.select([accountId, deviceId]);
    stmt.close();
    return res.isNotEmpty;
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

  void createDeviceLinkRequest({
    required String linkId,
    required String accountId,
    required String requestedByDeviceId,
    required String newDeviceId,
    required String newDevicePublicKey,
    required String newDeviceName,
    required String verificationCodeHash,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO pending_device_links (
        link_id,
        account_id,
        requested_by_device_id,
        new_device_id,
        new_device_public_key,
        new_device_name,
        verification_code_hash,
        status,
        created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, 'PENDING', ?);
    ''');
    stmt.execute([
      linkId,
      accountId,
      requestedByDeviceId,
      newDeviceId,
      newDevicePublicKey,
      newDeviceName,
      verificationCodeHash,
      now,
    ]);
    stmt.close();
  }

  Map<String, dynamic>? getDeviceLinkRequest(String linkId) {
    final stmt = _db.prepare(
      'SELECT * FROM pending_device_links WHERE link_id = ?;',
    );
    final res = stmt.select([linkId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'link_id': row['link_id'],
      'account_id': row['account_id'],
      'requested_by_device_id': row['requested_by_device_id'],
      'new_device_id': row['new_device_id'],
      'new_device_public_key': row['new_device_public_key'],
      'new_device_name': row['new_device_name'],
      'verification_code_hash': row['verification_code_hash'],
      'status': row['status'],
      'created_at': row['created_at'],
      'approved_at': row['approved_at'],
    };
  }

  bool approveDeviceLinkRequest({
    required String linkId,
    required String accountId,
    required String verificationCodeHash,
  }) {
    final link = getDeviceLinkRequest(linkId);
    if (link == null ||
        link['account_id'] != accountId ||
        link['status'] != 'PENDING' ||
        link['verification_code_hash'] != verificationCodeHash) {
      return false;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      UPDATE pending_device_links
      SET status = 'APPROVED', approved_at = ?
      WHERE link_id = ?;
    ''');
    stmt.execute([now, linkId]);
    stmt.close();
    return true;
  }

  void completeDeviceLinkRequest(String linkId) {
    final stmt = _db.prepare(
      "UPDATE pending_device_links SET status = 'LINKED' WHERE link_id = ?;",
    );
    stmt.execute([linkId]);
    stmt.close();
  }

  void recordDeviceRevocation({
    required String revocationId,
    required String accountId,
    required String revokedDeviceId,
    required String reason,
    String? revokedByDeviceId,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO device_revocations (
        revocation_id,
        account_id,
        revoked_device_id,
        revoked_by_device_id,
        reason,
        created_at
      )
      VALUES (?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      revocationId,
      accountId,
      revokedDeviceId,
      revokedByDeviceId,
      reason,
      now,
    ]);
    stmt.close();
  }

  Map<String, dynamic>? getDeviceRevocation(String accountId, String deviceId) {
    final stmt = _db.prepare('''
      SELECT * FROM device_revocations
      WHERE account_id = ? AND revoked_device_id = ?
      ORDER BY created_at DESC
      LIMIT 1;
    ''');
    final res = stmt.select([accountId, deviceId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'revocation_id': row['revocation_id'],
      'account_id': row['account_id'],
      'revoked_device_id': row['revoked_device_id'],
      'revoked_by_device_id': row['revoked_by_device_id'],
      'reason': row['reason'],
      'created_at': row['created_at'],
    };
  }

  void deleteMessagesForDevice(String deviceId) {
    final stmt = _db.prepare(
      'DELETE FROM messages WHERE recipient_device_id = ?;',
    );
    stmt.execute([deviceId]);
    stmt.close();
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

  int writeDeviceEvent({
    required String eventId,
    required String recipientDeviceId,
    required String eventType,
    required String payload,
  }) {
    _db.execute('BEGIN TRANSACTION;');
    try {
      final seqStmt = _db.prepare(
        'SELECT COALESCE(MAX(device_sequence), 0) + 1 FROM device_events WHERE recipient_device_id = ?;',
      );
      final seqRes = seqStmt.select([recipientDeviceId]);
      seqStmt.close();
      final nextSeq = seqRes.first.columnAt(0) as int;

      final now = DateTime.now().millisecondsSinceEpoch;
      final stmt = _db.prepare('''
        INSERT INTO device_events (event_id, recipient_device_id, device_sequence, schema_version, event_type, timestamp, payload)
        VALUES (?, ?, ?, 1, ?, ?, ?);
      ''');
      stmt.execute([
        eventId,
        recipientDeviceId,
        nextSeq,
        eventType,
        now,
        payload,
      ]);
      stmt.close();
      _db.execute('COMMIT;');
      return nextSeq;
    } catch (e) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  List<Map<String, dynamic>> getDeviceEvents(
    String deviceId,
    int sinceSequence,
  ) {
    final stmt = _db.prepare('''
      SELECT * FROM device_events
      WHERE recipient_device_id = ? AND device_sequence > ?
      ORDER BY device_sequence ASC;
    ''');
    final res = stmt.select([deviceId, sinceSequence]);
    stmt.close();
    return res
        .map(
          (row) => {
            'event_id': row['event_id'],
            'recipient_device_id': row['recipient_device_id'],
            'device_sequence': row['device_sequence'],
            'schema_version': row['schema_version'],
            'event_type': row['event_type'],
            'timestamp': row['timestamp'],
            'payload': row['payload'],
          },
        )
        .toList();
  }

  int? getLastDeviceSequence(String deviceId) {
    final stmt = _db.prepare(
      'SELECT MAX(device_sequence) FROM device_events WHERE recipient_device_id = ?;',
    );
    final res = stmt.select([deviceId]);
    stmt.close();
    if (res.isEmpty) return null;
    final val = res.first.columnAt(0);
    return val as int?;
  }

  // Backup operations
  void setBackup(
    String accountId,
    String backupData, {
    required String backupId,
    required int version,
    required String kdf,
    required String salt,
    required String backupKeyHint,
    int deletionWatermark = 0,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO backups (
        account_id,
        backup_id,
        version,
        kdf,
        salt,
        backup_key_hint,
        backup_data,
        created_at,
        deletion_watermark,
        requires_reupload
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0);
    ''');
    stmt.execute([
      accountId,
      backupId,
      version,
      kdf,
      salt,
      backupKeyHint,
      backupData,
      now,
      deletionWatermark,
    ]);
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
      'backup_id': row['backup_id'],
      'version': row['version'],
      'kdf': row['kdf'],
      'salt': row['salt'],
      'backup_key_hint': row['backup_key_hint'],
      'backup_data': row['backup_data'],
      'created_at': row['created_at'],
      'deletion_watermark': row['deletion_watermark'],
      'requires_reupload': row['requires_reupload'],
    };
  }

  void markBackupNeedsReupload(String accountId, int deletionWatermark) {
    final stmt = _db.prepare('''
      UPDATE backups
      SET deletion_watermark = ?,
          requires_reupload = 1
      WHERE account_id = ?;
    ''');
    stmt.execute([deletionWatermark, accountId]);
    stmt.close();
  }

  // Outbox operations
  void enqueueOutbox(String eventId, String type, String payload) {
    if (type == 'PUSH_NOTIFICATION' && _containsForbiddenPayloadKey(payload)) {
      throw ArgumentError(
        'Push notification payload must not contain plaintext',
      );
    }
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
      "SELECT * FROM outbox WHERE status = 'PENDING' OR (status = 'FAILED' AND retries < 5);",
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
    stmt.execute([
      uuid,
      accountId,
      deviceId,
      action,
      _redactClientIp(clientIp),
      userAgent == null ? null : 'redacted',
      now,
    ]);
    stmt.close();
  }

  List<Map<String, dynamic>> getAuditLogs({String? accountId}) {
    final rows = accountId == null
        ? _db.select('SELECT * FROM audit_logs ORDER BY timestamp DESC;')
        : _db.select(
            'SELECT * FROM audit_logs WHERE account_id = ? ORDER BY timestamp DESC;',
            [accountId],
          );
    return rows
        .map(
          (row) => {
            'event_id': row['event_id'],
            'account_id': row['account_id'],
            'device_id': row['device_id'],
            'action': row['action'],
            'client_ip': row['client_ip'],
            'user_agent': row['user_agent'],
            'timestamp': row['timestamp'],
          },
        )
        .toList();
  }

  List<Map<String, dynamic>> _selectWhere(
    String table,
    String where,
    List<Object?> args,
  ) {
    final stmt = _db.prepare('SELECT * FROM $table WHERE $where;');
    final rows = stmt.select(args);
    stmt.close();
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void _deleteWhere(String table, String where, List<Object?> args) {
    final stmt = _db.prepare('DELETE FROM $table WHERE $where;');
    stmt.execute(args);
    stmt.close();
  }

  bool _containsForbiddenPayloadKey(String payload) {
    final decoded = jsonDecode(payload);
    const forbiddenKeys = {
      'plaintext',
      'message_text',
      'body',
      'content',
      'filename',
      'backup_key',
      'passphrase',
      'recovery_phrase',
      'token',
    };

    bool scan(Object? value) {
      if (value is Map) {
        for (final entry in value.entries) {
          final key = entry.key.toString().toLowerCase();
          if (forbiddenKeys.contains(key)) return true;
          if (scan(entry.value)) return true;
        }
      } else if (value is List) {
        return value.any(scan);
      }
      return false;
    }

    return scan(decoded);
  }

  String? _redactClientIp(String? clientIp) {
    if (clientIp == null || clientIp.isEmpty) return null;
    if (clientIp.contains(':')) return 'ipv6:redacted';
    final parts = clientIp.split('.');
    if (parts.length == 4) {
      return '${parts[0]}.${parts[1]}.${parts[2]}.0';
    }
    return 'redacted';
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

  // ---------------------------------------------------------------------------
  // TURN credential log (P15-004, P15-005, P15-018)
  // ---------------------------------------------------------------------------

  void logTurnCredential({
    required String logId,
    required String accountId,
    required int issuedAt,
    required int expiresAt,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO turn_credential_log (log_id, account_id, issued_at, expires_at)
      VALUES (?, ?, ?, ?);
    ''');
    stmt.execute([logId, accountId, issuedAt, expiresAt]);
    stmt.close();
  }

  /// Returns the number of TURN credentials issued to [accountId] in the last hour.
  int getTurnCredentialCountLastHour(String accountId) {
    final since = DateTime.now().millisecondsSinceEpoch - 3600000;
    final stmt = _db.prepare('''
      SELECT COUNT(*) FROM turn_credential_log
      WHERE account_id = ? AND issued_at >= ?;
    ''');
    final res = stmt.select([accountId, since]);
    stmt.close();
    if (res.isEmpty) return 0;
    return res.first.columnAt(0) as int;
  }

  // ---------------------------------------------------------------------------
  // Group operations (P16-001 to P16-014)
  // ---------------------------------------------------------------------------

  /// Creates a GROUP conversation, group metadata row, and sets creator to ADMIN.
  void createGroup({
    required String groupId,
    required String name,
    required String creatorId,
    required String encryptionKeyId,
    required List<String> initialMemberIds,
  }) {
    _db.execute('BEGIN TRANSACTION;');
    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      final convStmt = _db.prepare('''
        INSERT OR REPLACE INTO conversations (conversation_id, type, title, created_at, last_sequence)
        VALUES (?, 'GROUP', ?, ?, 0);
      ''');
      convStmt.execute([groupId, name, now]);
      convStmt.close();

      final clearStmt = _db.prepare(
        'DELETE FROM conversation_members WHERE conversation_id = ?;',
      );
      clearStmt.execute([groupId]);
      clearStmt.close();

      final memStmt = _db.prepare('''
        INSERT INTO conversation_members (conversation_id, account_id, role)
        VALUES (?, ?, ?);
      ''');
      final allMembers = [
        ...initialMemberIds,
        if (!initialMemberIds.contains(creatorId)) creatorId,
      ];
      for (final memberId in allMembers) {
        final role = memberId == creatorId ? 'ADMIN' : 'MEMBER';
        memStmt.execute([groupId, memberId, role]);
      }
      memStmt.close();

      final grpStmt = _db.prepare('''
        INSERT OR REPLACE INTO groups (group_id, creator_id, encryption_key_id, status, created_at)
        VALUES (?, ?, ?, 'ACTIVE', ?);
      ''');
      grpStmt.execute([groupId, creatorId, encryptionKeyId, now]);
      grpStmt.close();

      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Map<String, dynamic>? getGroup(String groupId) {
    final stmt = _db.prepare('''
      SELECT g.*, c.title AS name FROM groups g
      JOIN conversations c ON c.conversation_id = g.group_id
      WHERE g.group_id = ?;
    ''');
    final res = stmt.select([groupId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'group_id': row['group_id'],
      'name': row['name'],
      'creator_id': row['creator_id'],
      'encryption_key_id': row['encryption_key_id'],
      'status': row['status'],
      'created_at': row['created_at'],
    };
  }

  bool isGroupAdmin(String groupId, String accountId) {
    final stmt = _db.prepare('''
      SELECT 1 FROM conversation_members
      WHERE conversation_id = ? AND account_id = ? AND role = 'ADMIN';
    ''');
    final res = stmt.select([groupId, accountId]);
    stmt.close();
    return res.isNotEmpty;
  }

  String? getGroupMemberRole(String groupId, String accountId) {
    final stmt = _db.prepare('''
      SELECT role FROM conversation_members
      WHERE conversation_id = ? AND account_id = ?;
    ''');
    final res = stmt.select([groupId, accountId]);
    stmt.close();
    if (res.isEmpty) return null;
    return res.first['role'] as String;
  }

  /// P16-013: Paginated member list.
  List<Map<String, dynamic>> getGroupMembersPaginated(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) {
    final stmt = _db.prepare('''
      SELECT account_id, role FROM conversation_members
      WHERE conversation_id = ?
      ORDER BY role DESC, account_id ASC
      LIMIT ? OFFSET ?;
    ''');
    final res = stmt.select([groupId, limit, offset]);
    stmt.close();
    return res
        .map((row) => {'account_id': row['account_id'], 'role': row['role']})
        .toList();
  }

  // P16-003: Invite lifecycle

  void createGroupInvite({
    required String inviteId,
    required String groupId,
    required String inviterId,
    required String inviteeId,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO group_invites (invite_id, group_id, inviter_id, invitee_id, status, created_at)
      VALUES (?, ?, ?, ?, 'PENDING', ?);
    ''');
    stmt.execute([inviteId, groupId, inviterId, inviteeId, now]);
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
      'invitee_id': row['invitee_id'],
      'status': row['status'],
      'created_at': row['created_at'],
    };
  }

  bool hasOpenGroupInvite(String groupId, String inviteeId) {
    final stmt = _db.prepare('''
      SELECT 1 FROM group_invites
      WHERE group_id = ? AND invitee_id = ? AND status = 'PENDING';
    ''');
    final res = stmt.select([groupId, inviteeId]);
    stmt.close();
    return res.isNotEmpty;
  }

  /// Accepts invite: sets status=ACCEPTED, adds invitee as MEMBER.
  void acceptGroupInvite(String inviteId) {
    _db.execute('BEGIN TRANSACTION;');
    try {
      final invite = getGroupInvite(inviteId);
      if (invite == null) throw StateError('Invite not found: $inviteId');

      final updStmt = _db.prepare(
        "UPDATE group_invites SET status = 'ACCEPTED' WHERE invite_id = ?;",
      );
      updStmt.execute([inviteId]);
      updStmt.close();

      final memStmt = _db.prepare('''
        INSERT OR IGNORE INTO conversation_members (conversation_id, account_id, role)
        VALUES (?, ?, 'MEMBER');
      ''');
      memStmt.execute([invite['group_id'], invite['invitee_id']]);
      memStmt.close();

      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void rejectGroupInvite(String inviteId) {
    final stmt = _db.prepare(
      "UPDATE group_invites SET status = 'REJECTED' WHERE invite_id = ?;",
    );
    stmt.execute([inviteId]);
    stmt.close();
  }

  void updateGroupInfo(String groupId, {String? name}) {
    if (name != null) {
      final stmt = _db.prepare(
        'UPDATE conversations SET title = ? WHERE conversation_id = ?;',
      );
      stmt.execute([name, groupId]);
      stmt.close();
    }
  }

  void changeGroupMemberRole(String groupId, String accountId, String role) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO conversation_members (conversation_id, account_id, role)
      VALUES (?, ?, ?);
    ''');
    stmt.execute([groupId, accountId, role]);
    stmt.close();
  }

  void removeGroupMember(String groupId, String accountId) {
    final stmt = _db.prepare(
      'DELETE FROM conversation_members WHERE conversation_id = ? AND account_id = ?;',
    );
    stmt.execute([groupId, accountId]);
    stmt.close();
  }

  /// P16-010: Mark group DELETED and tombstone it.
  void deleteGroup(String groupId) {
    _db.execute('BEGIN TRANSACTION;');
    try {
      final updStmt = _db.prepare(
        "UPDATE groups SET status = 'DELETED' WHERE group_id = ?;",
      );
      updStmt.execute([groupId]);
      updStmt.close();

      saveTombstone(groupId, 'GROUP');

      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  // P16-014: Rate limits

  void logGroupCreation(String logId, String accountId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO group_creation_log (log_id, account_id, created_at)
      VALUES (?, ?, ?);
    ''');
    stmt.execute([logId, accountId, now]);
    stmt.close();
  }

  int countGroupCreationsLastDay(String accountId) {
    final since = DateTime.now().millisecondsSinceEpoch - 86400000;
    final stmt = _db.prepare('''
      SELECT COUNT(*) FROM group_creation_log
      WHERE account_id = ? AND created_at >= ?;
    ''');
    final res = stmt.select([accountId, since]);
    stmt.close();
    if (res.isEmpty) return 0;
    return res.first.columnAt(0) as int;
  }

  /// Returns the number of group invites sent by an inviter in the last hour.
  int countGroupInvitesLastHour(String inviterId) {
    final since = DateTime.now().millisecondsSinceEpoch - 3600000;
    final stmt = _db.prepare('''
      SELECT COUNT(*) FROM group_invites
      WHERE inviter_id = ? AND created_at >= ?;
    ''');
    final res = stmt.select([inviterId, since]);
    stmt.close();
    if (res.isEmpty) return 0;
    return res.first.columnAt(0) as int;
  }

  /// Builds a consistent envelope map for realtime delivery.
  /// All modules must use this method to ensure clients receive uniform
  /// RemoteRealtimeEnvelope-compatible payloads.
  static Map<String, dynamic> buildEnvelope({
    required String eventId,
    required String type,
    required Map<String, dynamic> payload,
    required int timestamp,
    int schemaVersion = 1,
    int? serverSequence,
  }) {
    return {
      'event_id': eventId,
      'schema_version': schemaVersion,
      'timestamp': timestamp,
      'type': type,
      'payload': payload,
      'server_sequence': ?serverSequence,
    };
  }
}
