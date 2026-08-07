part of '../database.dart';

mixin RemoteDatabaseMigrations on HelixRemoteDatabaseBase {
  /// The version `_applyMigrations` brings a database up to. Named so tests
  /// assert against one source of truth instead of a literal that silently
  /// goes stale every time a migration is added - which is exactly what had
  /// happened: two tests still expected 18 after the schema reached 27.
  static const int latestSchemaVersion = 29;

  int get schemaVersion =>
      _db.select('PRAGMA user_version').first['user_version'] as int;

  void _onCreate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        account_id TEXT PRIMARY KEY,
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
    _createPhoneContactNamesTable();

    _db.execute('''
      CREATE TABLE IF NOT EXISTS conversations (
        conversation_id TEXT PRIMARY KEY,
        title TEXT,
        type TEXT NOT NULL,
        last_sequence INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        is_muted INTEGER NOT NULL DEFAULT 0,
        is_locked INTEGER NOT NULL DEFAULT 0,
        hidden_from_list INTEGER NOT NULL DEFAULT 0,
        secret_code_hint TEXT NOT NULL DEFAULT '',
        disappearing_seconds INTEGER NOT NULL DEFAULT 0,
        advanced_privacy_json TEXT NOT NULL DEFAULT '{}',
        is_favorite INTEGER NOT NULL DEFAULT 0
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
        expires_at INTEGER NOT NULL DEFAULT 0,
        retention_deadline INTEGER NOT NULL DEFAULT 0,
        view_once INTEGER NOT NULL DEFAULT 0,
        view_once_opened_at INTEGER NOT NULL DEFAULT 0,
        keep_in_chat INTEGER NOT NULL DEFAULT 0,
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
      CREATE INDEX IF NOT EXISTS idx_messages_conv_timestamp
      ON messages(conversation_id, timestamp DESC);
    ''');
    // `idx_messages_expiry` is deliberately NOT created here. It indexes
    // `expires_at` and `view_once_opened_at`, which the v16 migration adds -
    // and `_onCreate` runs *before* `_applyMigrations`. On an existing
    // pre-v16 database the CREATE TABLE above is a no-op (the table already
    // exists, without those columns), so creating the index here threw
    // "no such column: expires_at" and the app failed to open its own
    // database on upgrade. The v16 migration creates the index right after
    // adding the columns, which covers fresh databases too since they run
    // the full migration chain from user_version 0.

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
        peer_account_id TEXT NOT NULL DEFAULT '',
        peer_device_id TEXT,
        is_video INTEGER NOT NULL,
        direction TEXT NOT NULL,
        outcome TEXT NOT NULL DEFAULT '',
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
    _createPrivacyTables();
    _createProductivityTables();
    _createMediaTables();
    _createGroupsAdminTables();
    _createCollaborationTables();
    _createPersonalizationTables();
    _createRuntimeTables();
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
          peer_account_id TEXT NOT NULL DEFAULT '',
          peer_device_id TEXT,
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
    if (version < 13) {
      try {
        _db.execute(
          'ALTER TABLE conversations ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0;',
        );
      } catch (_) {}
      try {
        _db.execute(
          'ALTER TABLE conversations ADD COLUMN is_muted INTEGER NOT NULL DEFAULT 0;',
        );
      } catch (_) {}
      _db.execute('PRAGMA user_version = 13;');
    }
    if (version < 14) {
      for (final statement in const [
        "ALTER TABLE call_history ADD COLUMN peer_account_id TEXT NOT NULL DEFAULT '';",
        'ALTER TABLE call_history ADD COLUMN peer_device_id TEXT;',
        "ALTER TABLE active_call ADD COLUMN peer_account_id TEXT NOT NULL DEFAULT '';",
        'ALTER TABLE active_call ADD COLUMN peer_device_id TEXT;',
      ]) {
        try {
          _db.execute(statement);
        } catch (_) {}
      }
      try {
        _db.execute(
          "UPDATE call_history SET peer_account_id = peer_id WHERE peer_account_id = '';",
        );
      } catch (_) {}
      try {
        _db.execute(
          "UPDATE active_call SET peer_account_id = peer_id WHERE peer_account_id = '';",
        );
      } catch (_) {}
      _db.execute('PRAGMA user_version = 14;');
    }
    if (version < 15) {
      try {
        _db.execute(
          "ALTER TABLE call_history ADD COLUMN outcome TEXT NOT NULL DEFAULT '';",
        );
      } catch (_) {}
      try {
        _db.execute(
          "UPDATE call_history SET outcome = CASE WHEN duration > 0 THEN 'completed' WHEN direction = 'MISSED' THEN 'missed' ELSE lower(direction) END WHERE outcome = '';",
        );
      } catch (_) {}
      _db.execute('PRAGMA user_version = 15;');
    }
    if (version < 16) {
      for (final statement in const [
        'ALTER TABLE conversations ADD COLUMN is_locked INTEGER NOT NULL DEFAULT 0;',
        'ALTER TABLE conversations ADD COLUMN hidden_from_list INTEGER NOT NULL DEFAULT 0;',
        "ALTER TABLE conversations ADD COLUMN secret_code_hint TEXT NOT NULL DEFAULT '';",
        'ALTER TABLE conversations ADD COLUMN disappearing_seconds INTEGER NOT NULL DEFAULT 0;',
        "ALTER TABLE conversations ADD COLUMN advanced_privacy_json TEXT NOT NULL DEFAULT '{}';",
        'ALTER TABLE messages ADD COLUMN expires_at INTEGER NOT NULL DEFAULT 0;',
        'ALTER TABLE messages ADD COLUMN retention_deadline INTEGER NOT NULL DEFAULT 0;',
        'ALTER TABLE messages ADD COLUMN view_once INTEGER NOT NULL DEFAULT 0;',
        'ALTER TABLE messages ADD COLUMN view_once_opened_at INTEGER NOT NULL DEFAULT 0;',
        'ALTER TABLE messages ADD COLUMN keep_in_chat INTEGER NOT NULL DEFAULT 0;',
      ]) {
        try {
          _db.execute(statement);
        } catch (_) {}
      }
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_messages_expiry
        ON messages(expires_at, view_once_opened_at);
      ''');
      _createPrivacyTables();
      _db.execute('PRAGMA user_version = 16;');
    }
    if (version < 17) {
      try {
        _db.execute(
          'ALTER TABLE conversations ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0;',
        );
      } catch (_) {}
      _createProductivityTables();
      _db.execute('PRAGMA user_version = 17;');
    }
    if (version < 18) {
      _createMediaTables();
      _db.execute('PRAGMA user_version = 18;');
    }
    if (version < 19) {
      _createGroupsAdminTables();
      _db.execute('PRAGMA user_version = 19;');
    }
    if (version < 20) {
      _createGroupCallTables();
      _db.execute('PRAGMA user_version = 20;');
    }
    if (version < 21) {
      _createCollaborationTables();
      _db.execute('PRAGMA user_version = 21;');
    }
    if (version < 22) {
      _createPersonalizationTables();
      _db.execute('PRAGMA user_version = 22;');
    }
    if (version < 23) {
      _createRuntimeTables();
      _db.execute('PRAGMA user_version = 23;');
    }
    if (version < 24) {
      // DELIVERY_RECEIPT/READ_RECEIPT ops used to embed a microsecond
      // timestamp in their op_id, so re-rendering an already-acked message
      // (e.g. reopening a conversation) minted a brand-new outbox row every
      // time instead of being caught by INSERT OR IGNORE. Collapse whatever
      // duplicates already accumulated before the id became deterministic.
      _dedupeReceiptOutboxOperations();
      _db.execute('PRAGMA user_version = 24;');
    }
    if (version < 25) {
      // Accounts are now identified by a hashed phone number, not a
      // user-chosen username; the local mirror of the account row never
      // had a UNIQUE constraint on this column, so a plain DROP COLUMN is
      // safe (unlike the backend's `accounts` table).
      final hasUsername = _db
          .select("PRAGMA table_info(accounts);")
          .any((row) => row['name'] == 'username');
      if (hasUsername) {
        _db.execute('ALTER TABLE accounts DROP COLUMN username;');
      }
      _db.execute('PRAGMA user_version = 25;');
    }
    if (version < 26) {
      _createPhoneContactNamesTable();
      _db.execute('PRAGMA user_version = 26;');
    }
    if (version < 27) {
      // MARK_CONVERSATION_READ was never added to the client's outbound
      // operation registry, so every enqueued instance has always failed
      // permanently - there's no server endpoint for it to reach yet.
      // Opening a conversation used to also be able to re-trigger this
      // call in an unbounded loop (since fixed), so on an affected device
      // this could pile up into hundreds or thousands of rows that would
      // otherwise sit "failed" forever. markConversationRead() no longer
      // enqueues this operation at all; clear out whatever already
      // accumulated rather than leaving it stuck.
      _db.execute(
        "DELETE FROM pending_operations WHERE type = 'MARK_CONVERSATION_READ';",
      );
      _db.execute('PRAGMA user_version = 27;');
    }
    if (version < 28) {
      _createUnmatchedPhoneContactsTable();
      _db.execute('PRAGMA user_version = 28;');
    }
    if (version < 29) {
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_messages_conv_timestamp
        ON messages(conversation_id, timestamp DESC);
      ''');
      _db.execute('PRAGMA user_version = $latestSchemaVersion;');
    }
  }

  /// Phone-book contacts that matched no Helix account on the last complete
  /// sync - the "Not on Helix yet" list.
  ///
  /// Stored rather than held in the Contacts screen's state, which is what
  /// it used to be: leaving the tab destroyed the list, so it had to be
  /// re-synced by hand every single time to see it again.
  ///
  /// The original reason for not storing it was that a stored list goes
  /// stale - someone on it joins Helix later and keeps being offered an
  /// Invite button. That is handled by rewriting the whole table on every
  /// complete sync (see `replaceUnmatchedPhoneContacts`), so a name that
  /// has since joined is simply absent from the next write. `synced_at` is
  /// what makes that refresh automatic rather than manual.
  void _createUnmatchedPhoneContactsTable() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS unmatched_phone_contacts (
        phone_book_name TEXT PRIMARY KEY
      );
    ''');
    // The timestamp lives in its own single-row table rather than as a
    // column above, because "synced, and everyone in the phone book is on
    // Helix" is a legitimate result with no rows at all. Derived from the
    // rows it would be indistinguishable from "never synced", and the
    // screen would re-sync on every open forever.
    _db.execute('''
      CREATE TABLE IF NOT EXISTS unmatched_phone_contacts_sync (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        synced_at INTEGER NOT NULL
      );
    ''');
  }

  void _createPhoneContactNamesTable() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS phone_contact_names (
        peer_account_id TEXT PRIMARY KEY,
        phone_book_name TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
  }

  void _dedupeReceiptOutboxOperations() {
    final stmt = _db.prepare('''
      SELECT op_id, type, payload, status, created_at FROM pending_operations
      WHERE type IN ('DELIVERY_RECEIPT', 'READ_RECEIPT');
    ''');
    final rows = stmt.select();
    stmt.close();

    final groups = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      String? messageId;
      try {
        final payload =
            jsonDecode(row['payload'] as String) as Map<String, dynamic>;
        messageId = payload['message_id'] as String?;
      } catch (_) {
        messageId = null;
      }
      if (messageId == null) continue;
      final key = '${row['type']}|$messageId';
      (groups[key] ??= []).add({
        'op_id': row['op_id'],
        'status': row['status'],
        'created_at': row['created_at'],
      });
    }

    final toDelete = <String>[];
    for (final group in groups.values) {
      if (group.length <= 1) continue;
      // A completed copy means the server already has this receipt — every
      // other queued/failed duplicate for the same message is pure waste.
      final hasCompleted = group.any((op) => op['status'] == 'COMPLETED');
      if (hasCompleted) {
        toDelete.addAll(
          group
              .where((op) => op['status'] != 'COMPLETED')
              .map((op) => op['op_id'] as String),
        );
        continue;
      }
      group.sort(
        (a, b) => (a['created_at'] as int).compareTo(b['created_at'] as int),
      );
      toDelete.addAll(group.skip(1).map((op) => op['op_id'] as String));
    }

    if (toDelete.isEmpty) return;
    _db.execute('BEGIN;');
    try {
      final delStmt = _db.prepare(
        'DELETE FROM pending_operations WHERE op_id = ?;',
      );
      for (final opId in toDelete) {
        delStmt.execute([opId]);
      }
      delStmt.close();
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
    }
  }

  void _createPrivacyTables() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS local_privacy_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS secret_attempts (
        attempt_id INTEGER PRIMARY KEY AUTOINCREMENT,
        attempted_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_secret_attempts_attempted_at
      ON secret_attempts(attempted_at);
    ''');
  }

  void _createProductivityTables() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS conversation_read_state (
        conversation_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        last_read_sequence INTEGER NOT NULL DEFAULT 0,
        mention_count INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (conversation_id, device_id)
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS conversation_lists (
        list_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        kind TEXT NOT NULL,
        sort_order INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS conversation_list_members (
        list_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        sort_order INTEGER NOT NULL,
        PRIMARY KEY (list_id, conversation_id)
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS search_index (
        row_id INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id TEXT NOT NULL,
        message_id TEXT,
        section TEXT NOT NULL,
        text TEXT NOT NULL,
        metadata_json TEXT NOT NULL DEFAULT '{}',
        updated_at INTEGER NOT NULL,
        UNIQUE(message_id, section, text)
      );
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_search_index_text
      ON search_index(section, text);
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS link_previews (
        url TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        image_url TEXT NOT NULL DEFAULT '',
        fetched_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        status TEXT NOT NULL
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS contact_links (
        link_id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        nonce TEXT NOT NULL,
        expires_at INTEGER NOT NULL,
        signature TEXT NOT NULL,
        used_at INTEGER NOT NULL DEFAULT 0
      );
    ''');
  }

  void _createMediaTables() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS media_drafts (
        draft_id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        status TEXT NOT NULL,
        local_path TEXT NOT NULL,
        caption TEXT NOT NULL DEFAULT '',
        duration_ms INTEGER NOT NULL DEFAULT 0,
        waveform_json TEXT NOT NULL DEFAULT '[]',
        view_once INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_media_drafts_conversation
      ON media_drafts(conversation_id, updated_at DESC);
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS media_playback_state (
        message_id TEXT PRIMARY KEY,
        position_ms INTEGER NOT NULL DEFAULT 0,
        speed REAL NOT NULL DEFAULT 1.0,
        updated_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS media_transfer_policy (
        attachment_id TEXT PRIMARY KEY,
        background_allowed INTEGER NOT NULL DEFAULT 1,
        expires_at INTEGER NOT NULL DEFAULT 0,
        retry_count INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
  }

  void _createCollaborationTables() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS poll_votes (
        poll_id TEXT NOT NULL,
        account_id TEXT NOT NULL,
        option_ids_json TEXT NOT NULL,
        encrypted_payload TEXT NOT NULL,
        signature TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (poll_id, account_id)
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS event_rsvps (
        event_id TEXT NOT NULL,
        account_id TEXT NOT NULL,
        state TEXT NOT NULL,
        plus_one INTEGER NOT NULL DEFAULT 0,
        encrypted_payload TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (event_id, account_id)
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS event_reminders (
        reminder_id TEXT PRIMARY KEY,
        event_id TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        remind_at INTEGER NOT NULL,
        encrypted_note TEXT NOT NULL,
        status TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_event_reminders_due
      ON event_reminders(status, remind_at);
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS live_location_sessions (
        session_id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        update_interval_ms INTEGER NOT NULL,
        status TEXT NOT NULL,
        last_update_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS live_location_updates (
        update_id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        latitude_e7 INTEGER NOT NULL,
        longitude_e7 INTEGER NOT NULL,
        accuracy_meters INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        encrypted_payload TEXT NOT NULL
      );
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_live_location_updates_session
      ON live_location_updates(session_id, created_at);
    ''');
  }

  void _createPersonalizationTables() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS theme_preferences (
        scope TEXT NOT NULL,
        scope_id TEXT NOT NULL,
        mode TEXT NOT NULL,
        color_seed TEXT NOT NULL DEFAULT '',
        wallpaper_attachment_id TEXT NOT NULL DEFAULT '',
        high_contrast INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (scope, scope_id)
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS profile_about_notes (
        note_id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        encrypted_text TEXT NOT NULL,
        audience TEXT NOT NULL,
        expires_at INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS profile_images (
        account_id TEXT PRIMARY KEY,
        attachment_id TEXT NOT NULL,
        thumbnail_attachment_id TEXT NOT NULL,
        audience TEXT NOT NULL,
        cache_version INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS sticker_packs (
        pack_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        manifest_json TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS stickers (
        sticker_id TEXT PRIMARY KEY,
        pack_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        attachment_id TEXT NOT NULL,
        emoji TEXT NOT NULL DEFAULT '',
        tags TEXT NOT NULL DEFAULT '',
        size_bytes INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL DEFAULT 0,
        favorite INTEGER NOT NULL DEFAULT 0,
        recent_at INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_stickers_search
      ON stickers(emoji, tags, favorite, recent_at);
    ''');
  }

  void _createRuntimeTables() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS account_runtime_profiles (
        account_id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        database_path TEXT NOT NULL,
        secure_storage_namespace TEXT NOT NULL,
        attachment_cache_path TEXT NOT NULL,
        notification_channel_id TEXT NOT NULL,
        server_base_url TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        last_used_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_account_runtime_database_path
      ON account_runtime_profiles(database_path);
    ''');
    _db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_account_runtime_secure_namespace
      ON account_runtime_profiles(secure_storage_namespace);
    ''');
    _db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_account_runtime_attachment_cache
      ON account_runtime_profiles(attachment_cache_path);
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS proxy_profiles (
        profile_id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        mode TEXT NOT NULL,
        host TEXT NOT NULL,
        port INTEGER NOT NULL,
        username TEXT NOT NULL DEFAULT '',
        encrypted_password_ref TEXT NOT NULL DEFAULT '',
        allow_invalid_certificates INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_proxy_profiles_account
      ON proxy_profiles(account_id, updated_at DESC);
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS platform_capability_profiles (
        platform_id TEXT PRIMARY KEY,
        capabilities_json TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
  }

  void _createGroupsAdminTables() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS group_add_policy (
        group_id TEXT PRIMARY KEY,
        policy TEXT NOT NULL DEFAULT 'EVERYONE',
        contacts_except_json TEXT NOT NULL DEFAULT '[]',
        updated_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS group_join_links (
        link_id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        token TEXT NOT NULL,
        requires_approval INTEGER NOT NULL DEFAULT 0,
        expires_at INTEGER NOT NULL,
        revoked_at INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS group_join_requests (
        request_id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        requester_id TEXT NOT NULL,
        link_id TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS group_blocked_members (
        group_id TEXT NOT NULL,
        account_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (group_id, account_id)
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS group_epoch_key_deliveries (
        delivery_id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        epoch INTEGER NOT NULL,
        key_id TEXT NOT NULL,
        recipient_device_id TEXT NOT NULL,
        wrapped_key TEXT NOT NULL,
        delivered_at INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS group_mention_index (
        mention_id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        mentioned_account_id TEXT NOT NULL,
        server_sequence INTEGER NOT NULL,
        read_at INTEGER NOT NULL DEFAULT 0
      );
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_mention_index_conv
      ON group_mention_index(conversation_id, server_sequence ASC);
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS group_notification_policy (
        group_id TEXT PRIMARY KEY,
        policy TEXT NOT NULL DEFAULT 'ALL',
        updated_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS group_moderated_messages (
        message_id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        moderated_by TEXT NOT NULL,
        moderated_at INTEGER NOT NULL
      );
    ''');
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

  void _createGroupCallTables() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS group_call_rooms (
        room_id TEXT PRIMARY KEY,
        host_account_id TEXT NOT NULL,
        status TEXT NOT NULL,
        is_video INTEGER NOT NULL DEFAULT 1,
        room_key_id TEXT,
        room_key_epoch INTEGER NOT NULL DEFAULT 0,
        started_at INTEGER,
        ended_at INTEGER,
        synced_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS group_call_participants (
        room_id TEXT NOT NULL,
        account_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        role TEXT NOT NULL,
        status TEXT NOT NULL,
        is_screen_sharing INTEGER NOT NULL DEFAULT 0,
        joined_at INTEGER,
        PRIMARY KEY (room_id, device_id)
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS group_call_wrapped_keys (
        room_id TEXT NOT NULL,
        epoch INTEGER NOT NULL,
        wrapped_key TEXT NOT NULL,
        received_at INTEGER NOT NULL,
        PRIMARY KEY (room_id, epoch)
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS call_links_cache (
        link_id TEXT PRIMARY KEY,
        link_token TEXT NOT NULL,
        room_id TEXT,
        requires_approval INTEGER NOT NULL DEFAULT 0,
        max_uses INTEGER NOT NULL DEFAULT 0,
        use_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        synced_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS scheduled_calls_cache (
        scheduled_call_id TEXT PRIMARY KEY,
        host_account_id TEXT NOT NULL,
        title TEXT NOT NULL,
        room_id TEXT,
        scheduled_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        cancelled_at INTEGER,
        my_rsvp TEXT NOT NULL DEFAULT 'PENDING',
        attendees_json TEXT NOT NULL DEFAULT '[]',
        synced_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_scheduled_calls_cache_at
      ON scheduled_calls_cache(scheduled_at ASC);
    ''');
  }

  Set<String> _tableColumns(String table) {
    return _db
        .select("PRAGMA table_info('$table');")
        .map((row) => row['name'] as String)
        .toSet();
  }
}
