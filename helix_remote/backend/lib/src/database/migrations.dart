part of '../database.dart';

extension BackendDatabaseMigrations on BackendDatabase {
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
          device_signing_public_key TEXT NOT NULL,
          device_agreement_public_key TEXT NOT NULL,
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
          created_at INTEGER NOT NULL,
          next_attempt_at INTEGER NOT NULL DEFAULT 0
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
          device_id TEXT,
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

      _db.execute('''
        CREATE TABLE IF NOT EXISTS pending_calls (
          call_id TEXT PRIMARY KEY,
          caller_account_id TEXT NOT NULL,
          caller_device_id TEXT NOT NULL,
          callee_account_id TEXT NOT NULL,
          is_video INTEGER NOT NULL,
          offer_sdp TEXT,
          status TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          expires_at INTEGER NOT NULL,
          answered_by_device_id TEXT,
          FOREIGN KEY(caller_account_id) REFERENCES accounts(account_id) ON DELETE CASCADE,
          FOREIGN KEY(callee_account_id) REFERENCES accounts(account_id) ON DELETE CASCADE,
          FOREIGN KEY(caller_device_id) REFERENCES devices(device_id) ON DELETE CASCADE
        );
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS pending_call_devices (
          call_id TEXT NOT NULL,
          target_device_id TEXT NOT NULL,
          status TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY(call_id, target_device_id),
          FOREIGN KEY(call_id) REFERENCES pending_calls(call_id) ON DELETE CASCADE,
          FOREIGN KEY(target_device_id) REFERENCES devices(device_id) ON DELETE CASCADE
        );
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS call_signal_requests (
          call_id TEXT NOT NULL,
          sender_device_id TEXT NOT NULL,
          request_id TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          PRIMARY KEY(call_id, sender_device_id, request_id)
        );
      ''');
      _db.execute('PRAGMA user_version = 12;');
    }
    if (version < 13) {
      final columns = _tableColumns('devices');
      if (columns.contains('device_public_key')) {
        _db.execute('ALTER TABLE devices RENAME TO devices_v12;');
        _db.execute('''
          CREATE TABLE devices (
            device_id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL,
            device_signing_public_key TEXT NOT NULL,
            device_agreement_public_key TEXT NOT NULL,
            device_name TEXT NOT NULL,
            status TEXT NOT NULL,
            push_token TEXT,
            created_at INTEGER NOT NULL,
            last_seen_at INTEGER NOT NULL,
            FOREIGN KEY(account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
          );
        ''');
        _db.execute('''
          INSERT INTO devices (
            device_id,
            account_id,
            device_signing_public_key,
            device_agreement_public_key,
            device_name,
            status,
            push_token,
            created_at,
            last_seen_at
          )
          SELECT
            device_id,
            account_id,
            device_public_key,
            device_public_key,
            device_name,
            status,
            push_token,
            created_at,
            last_seen_at
          FROM devices_v12;
        ''');
        _db.execute('DROP TABLE devices_v12;');
      }
      _db.execute('PRAGMA user_version = 13;');
    }

    if (version < 14) {
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_outbox_status_created
        ON outbox(status, created_at);
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_audit_logs_account_timestamp
        ON audit_logs(account_id, timestamp DESC);
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_tombstones_type_deleted
        ON tombstones(type, deleted_at);
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_device_events_recipient_sequence
        ON device_events(recipient_device_id, device_sequence);
      ''');
      _db.execute('PRAGMA user_version = 14;');
    }

    if (version < 15) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS account_profiles (
          account_id TEXT PRIMARY KEY,
          display_name TEXT NOT NULL,
          updated_at INTEGER NOT NULL,
          profile_version INTEGER NOT NULL DEFAULT 1,
          FOREIGN KEY(account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
        );
      ''');
      _db.execute('PRAGMA user_version = 15;');
    }
    if (version < 16) {
      try {
        _db.execute(
          'ALTER TABLE turn_credential_log ADD COLUMN device_id TEXT;',
        );
      } catch (_) {}
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_turn_credential_log_account_issued
        ON turn_credential_log(account_id, issued_at);
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_turn_credential_log_device_issued
        ON turn_credential_log(device_id, issued_at);
      ''');
      _db.execute('PRAGMA user_version = 16;');
    }
    if (version < 17) {
      try {
        _db.execute('ALTER TABLE pending_calls ADD COLUMN offer_sdp TEXT;');
      } catch (_) {}
      _db.execute('PRAGMA user_version = 17;');
    }

    if (version < 18) {
      // Repair: pending_calls tables may be missing if the DB was already at
      // version >= 12 when call signaling was added to migration 12, causing
      // migration 12 to be skipped entirely on that DB.
      _db.execute('''
        CREATE TABLE IF NOT EXISTS pending_calls (
          call_id TEXT PRIMARY KEY,
          caller_account_id TEXT NOT NULL,
          caller_device_id TEXT NOT NULL,
          callee_account_id TEXT NOT NULL,
          is_video INTEGER NOT NULL,
          offer_sdp TEXT,
          status TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          expires_at INTEGER NOT NULL,
          answered_by_device_id TEXT,
          FOREIGN KEY(caller_account_id) REFERENCES accounts(account_id) ON DELETE CASCADE,
          FOREIGN KEY(callee_account_id) REFERENCES accounts(account_id) ON DELETE CASCADE,
          FOREIGN KEY(caller_device_id) REFERENCES devices(device_id) ON DELETE CASCADE
        );
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS pending_call_devices (
          call_id TEXT NOT NULL,
          target_device_id TEXT NOT NULL,
          status TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY(call_id, target_device_id),
          FOREIGN KEY(call_id) REFERENCES pending_calls(call_id) ON DELETE CASCADE,
          FOREIGN KEY(target_device_id) REFERENCES devices(device_id) ON DELETE CASCADE
        );
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS call_signal_requests (
          call_id TEXT NOT NULL,
          sender_device_id TEXT NOT NULL,
          request_id TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          PRIMARY KEY(call_id, sender_device_id, request_id)
        );
      ''');
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
      _db.execute('PRAGMA user_version = 18;');
    }
    if (version < 19) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS attachment_recipient_grants (
          file_id TEXT NOT NULL,
          account_id TEXT NOT NULL,
          granted_at INTEGER NOT NULL,
          PRIMARY KEY(file_id, account_id),
          FOREIGN KEY(file_id) REFERENCES attachments(file_id) ON DELETE CASCADE,
          FOREIGN KEY(account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
        );
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_attachment_recipient_grants_account
        ON attachment_recipient_grants(account_id, file_id);
      ''');
      _db.execute('PRAGMA user_version = 19;');
    }
    if (version < 20) {
      for (final statement in [
        "ALTER TABLE pending_device_links ADD COLUMN new_device_signing_public_key TEXT NOT NULL DEFAULT '';",
        "ALTER TABLE pending_device_links ADD COLUMN new_device_agreement_public_key TEXT NOT NULL DEFAULT '';",
        "ALTER TABLE pending_device_links ADD COLUMN request_nonce TEXT NOT NULL DEFAULT '';",
        "ALTER TABLE pending_device_links ADD COLUMN expires_at INTEGER NOT NULL DEFAULT 0;",
        "ALTER TABLE pending_device_links ADD COLUMN approved_by_device_id TEXT;",
        "ALTER TABLE pending_device_links ADD COLUMN approval_transcript_hash TEXT NOT NULL DEFAULT '';",
        "ALTER TABLE pending_device_links ADD COLUMN rejected_at INTEGER;",
        "ALTER TABLE pending_device_links ADD COLUMN completed_at INTEGER;",
      ]) {
        try {
          _db.execute(statement);
        } catch (_) {}
      }
      _db.execute('''
        UPDATE pending_device_links
        SET new_device_signing_public_key = new_device_public_key
        WHERE new_device_signing_public_key = '';
      ''');
      _db.execute('''
        UPDATE pending_device_links
        SET new_device_agreement_public_key = new_device_public_key
        WHERE new_device_agreement_public_key = '';
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_pending_device_links_account_status
        ON pending_device_links(account_id, status, expires_at);
      ''');
      _db.execute('PRAGMA user_version = 20;');
    }
    if (version < 21) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS backup_media_objects (
          object_id TEXT PRIMARY KEY,
          account_id TEXT NOT NULL,
          byte_size INTEGER NOT NULL,
          sha256 TEXT NOT NULL,
          uploaded_bytes INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          retention_until INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY(account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
        );
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_backup_media_account_status
        ON backup_media_objects(account_id, status, updated_at);
      ''');
      _db.execute('PRAGMA user_version = 21;');
    }
    if (version < 22) {
      // F6: Group-add privacy, join links, join requests, blocked members,
      // moderated messages, and creator-protection columns.
      for (final statement in [
        "ALTER TABLE groups ADD COLUMN add_policy TEXT NOT NULL DEFAULT 'EVERYONE';",
        'ALTER TABLE groups ADD COLUMN creator_protected INTEGER NOT NULL DEFAULT 1;',
        'ALTER TABLE groups ADD COLUMN history_sharing_enabled INTEGER NOT NULL DEFAULT 0;',
      ]) {
        try {
          _db.execute(statement);
        } catch (_) {}
      }
      _db.execute('''
        CREATE TABLE IF NOT EXISTS group_join_links (
          link_id TEXT PRIMARY KEY,
          group_id TEXT NOT NULL,
          creator_id TEXT NOT NULL,
          token TEXT NOT NULL UNIQUE,
          requires_approval INTEGER NOT NULL DEFAULT 0,
          expires_at INTEGER NOT NULL,
          revoked_at INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          FOREIGN KEY(group_id) REFERENCES conversations(conversation_id) ON DELETE CASCADE
        );
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_group_join_links_token
        ON group_join_links(token);
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS group_join_requests (
          request_id TEXT PRIMARY KEY,
          group_id TEXT NOT NULL,
          requester_id TEXT NOT NULL,
          link_id TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'PENDING',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          FOREIGN KEY(group_id) REFERENCES conversations(conversation_id) ON DELETE CASCADE,
          FOREIGN KEY(requester_id) REFERENCES accounts(account_id) ON DELETE CASCADE
        );
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_group_join_requests_group_status
        ON group_join_requests(group_id, status, created_at);
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS group_blocked_members (
          group_id TEXT NOT NULL,
          account_id TEXT NOT NULL,
          created_by TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          PRIMARY KEY(group_id, account_id),
          FOREIGN KEY(group_id) REFERENCES conversations(conversation_id) ON DELETE CASCADE,
          FOREIGN KEY(account_id) REFERENCES accounts(account_id) ON DELETE CASCADE
        );
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS group_moderated_messages (
          message_id TEXT PRIMARY KEY,
          group_id TEXT NOT NULL,
          moderated_by TEXT NOT NULL,
          moderated_at INTEGER NOT NULL,
          FOREIGN KEY(group_id) REFERENCES conversations(conversation_id) ON DELETE CASCADE
        );
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS group_history_packages (
          package_id TEXT PRIMARY KEY,
          group_id TEXT NOT NULL,
          for_account_id TEXT NOT NULL,
          from_sequence INTEGER NOT NULL,
          to_sequence INTEGER NOT NULL,
          encrypted_package TEXT NOT NULL,
          expires_at INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          FOREIGN KEY(group_id) REFERENCES conversations(conversation_id) ON DELETE CASCADE
        );
      ''');
      _db.execute('PRAGMA user_version = 22;');
    }

    if (version < 23) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS device_push_tokens (
          token_id   TEXT PRIMARY KEY,
          account_id TEXT NOT NULL REFERENCES accounts(account_id) ON DELETE CASCADE,
          device_id  TEXT NOT NULL REFERENCES devices(device_id)  ON DELETE CASCADE,
          push_token TEXT NOT NULL,
          token_type TEXT NOT NULL DEFAULT 'FCM',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          UNIQUE(device_id)
        );
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS call_metrics (
          metric_id           TEXT PRIMARY KEY,
          call_id             TEXT NOT NULL,
          account_id          TEXT NOT NULL,
          device_id           TEXT NOT NULL,
          connection_type     TEXT,
          setup_time_ms       INTEGER,
          reconnect_count     INTEGER NOT NULL DEFAULT 0,
          packet_loss_percent REAL,
          peer_rtt_ms         REAL,
          call_outcome        TEXT,
          duration_seconds    INTEGER NOT NULL DEFAULT 0,
          recorded_at         INTEGER NOT NULL
        );
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_call_metrics_account
          ON call_metrics(account_id, recorded_at DESC);
      ''');
      _db.execute('PRAGMA user_version = 23;');
    }

    if (version < 24) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS call_rooms (
          room_id          TEXT PRIMARY KEY,
          host_account_id  TEXT NOT NULL,
          host_device_id   TEXT NOT NULL,
          status           TEXT NOT NULL DEFAULT 'WAITING',
          is_video         INTEGER NOT NULL DEFAULT 0,
          max_participants INTEGER NOT NULL DEFAULT 4,
          room_key_id      TEXT,
          room_key_epoch   INTEGER NOT NULL DEFAULT 0,
          created_at       INTEGER NOT NULL,
          started_at       INTEGER,
          ended_at         INTEGER
        );
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS call_room_participants (
          room_id           TEXT NOT NULL REFERENCES call_rooms(room_id) ON DELETE CASCADE,
          account_id        TEXT NOT NULL,
          device_id         TEXT NOT NULL,
          role              TEXT NOT NULL DEFAULT 'PARTICIPANT',
          status            TEXT NOT NULL DEFAULT 'INVITED',
          is_screen_sharing INTEGER NOT NULL DEFAULT 0,
          joined_at         INTEGER,
          left_at           INTEGER,
          PRIMARY KEY (room_id, device_id)
        );
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_crp_account
          ON call_room_participants(account_id, status);
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS call_room_keys (
          room_id      TEXT NOT NULL REFERENCES call_rooms(room_id) ON DELETE CASCADE,
          epoch        INTEGER NOT NULL,
          device_id    TEXT NOT NULL,
          wrapped_key  TEXT NOT NULL,
          delivered_at INTEGER,
          PRIMARY KEY (room_id, epoch, device_id)
        );
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS call_links (
          link_id           TEXT PRIMARY KEY,
          link_token        TEXT NOT NULL UNIQUE,
          room_id           TEXT REFERENCES call_rooms(room_id) ON DELETE SET NULL,
          created_by        TEXT NOT NULL,
          requires_approval INTEGER NOT NULL DEFAULT 0,
          max_uses          INTEGER NOT NULL DEFAULT 0,
          use_count         INTEGER NOT NULL DEFAULT 0,
          created_at        INTEGER NOT NULL,
          expires_at        INTEGER NOT NULL,
          revoked_at        INTEGER
        );
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_call_links_token
          ON call_links(link_token);
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_call_links_owner
          ON call_links(created_by, created_at DESC);
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS scheduled_calls (
          scheduled_call_id TEXT PRIMARY KEY,
          room_id           TEXT REFERENCES call_rooms(room_id) ON DELETE SET NULL,
          host_account_id   TEXT NOT NULL,
          title             TEXT NOT NULL,
          scheduled_at      INTEGER NOT NULL,
          created_at        INTEGER NOT NULL,
          cancelled_at      INTEGER
        );
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_scheduled_calls_host
          ON scheduled_calls(host_account_id, scheduled_at);
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS scheduled_call_attendees (
          scheduled_call_id TEXT NOT NULL
            REFERENCES scheduled_calls(scheduled_call_id) ON DELETE CASCADE,
          account_id        TEXT NOT NULL,
          rsvp_status       TEXT NOT NULL DEFAULT 'PENDING',
          notified_at       INTEGER,
          PRIMARY KEY (scheduled_call_id, account_id)
        );
      ''');
      _db.execute('PRAGMA user_version = 24;');
    }

    if (version < 25) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS server_configuration (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL
        );
      ''');
      _db.execute('PRAGMA user_version = 25;');
    }

    if (version < 26) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS federation_servers (
          server_id TEXT PRIMARY KEY,
          domain TEXT UNIQUE,
          public_key TEXT NOT NULL,
          address TEXT,
          trust_source TEXT NOT NULL,
          updated_at INTEGER NOT NULL
        );
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS federated_conversation_members (
          conversation_id TEXT NOT NULL
            REFERENCES conversations(conversation_id) ON DELETE CASCADE,
          account_id TEXT NOT NULL,
          domain TEXT NOT NULL,
          role TEXT NOT NULL DEFAULT 'MEMBER',
          PRIMARY KEY(conversation_id, account_id)
        );
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_federated_members_domain
          ON federated_conversation_members(domain);
      ''');
      _db.execute('PRAGMA user_version = 26;');
    }

    if (version < 27) {
      // Milestone 4.1: federated group membership. A group's home server is
      // whichever server processed its creation; other servers hosting a
      // member keep a synced read-model in federated_groups /
      // federated_group_invites (same shadow-table pattern as
      // federated_conversation_members, v26).
      for (final statement in [
        'ALTER TABLE groups ADD COLUMN home_domain TEXT;',
      ]) {
        try {
          _db.execute(statement);
        } catch (_) {}
      }

      // group_invites.inviter_id/invitee_id originally had FKs to the local
      // accounts table, which reject a genuinely-external qualified id
      // (user@domain). A group's home server must be able to track an
      // invite whose invitee (or, if a federated admin sent it via S2S
      // proxy, whose inviter) lives on another server, so rebuild the table
      // without those two FKs (group_id -> conversations is kept). Follows
      // the same rename/create/copy/drop pattern as the v13 devices rebuild.
      _db.execute('ALTER TABLE group_invites RENAME TO group_invites_v8;');
      _db.execute('''
        CREATE TABLE group_invites (
          invite_id TEXT PRIMARY KEY,
          group_id TEXT NOT NULL,
          inviter_id TEXT NOT NULL,
          invitee_id TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'PENDING',
          created_at INTEGER NOT NULL,
          FOREIGN KEY(group_id) REFERENCES conversations(conversation_id) ON DELETE CASCADE
        );
      ''');
      _db.execute('''
        INSERT INTO group_invites (
          invite_id, group_id, inviter_id, invitee_id, status, created_at
        )
        SELECT invite_id, group_id, inviter_id, invitee_id, status, created_at
        FROM group_invites_v8;
      ''');
      _db.execute('DROP TABLE group_invites_v8;');

      _db.execute('''
        CREATE TABLE IF NOT EXISTS federated_groups (
          group_id TEXT PRIMARY KEY
            REFERENCES conversations(conversation_id) ON DELETE CASCADE,
          home_server_id TEXT NOT NULL,
          home_domain TEXT NOT NULL,
          creator_id TEXT NOT NULL,
          name TEXT,
          encryption_key_id TEXT NOT NULL DEFAULT '',
          status TEXT NOT NULL DEFAULT 'ACTIVE',
          add_policy TEXT NOT NULL DEFAULT 'EVERYONE',
          created_at INTEGER NOT NULL,
          synced_at INTEGER NOT NULL
        );
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_federated_groups_home
          ON federated_groups(home_server_id);
      ''');
      _db.execute('''
        CREATE TABLE IF NOT EXISTS federated_group_invites (
          invite_id TEXT PRIMARY KEY,
          group_id TEXT NOT NULL,
          home_server_id TEXT NOT NULL,
          home_domain TEXT NOT NULL,
          inviter_id TEXT NOT NULL,
          invitee_id TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'PENDING',
          created_at INTEGER NOT NULL,
          synced_at INTEGER NOT NULL
        );
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_federated_group_invites_invitee
          ON federated_group_invites(invitee_id, status);
      ''');
      _db.execute('PRAGMA user_version = 27;');
    }

    if (version < 28) {
      // Milestone 5.1: federated 1:1 call signaling. pending_calls'
      // caller/callee account+device FKs and pending_call_devices'
      // target_device_id FK all point at local-only tables, which reject a
      // genuinely-external qualified id (user@domain) or a remote device id
      // -- both legs of a federated call need to record the OTHER party's
      // identity locally. Same rename/create/copy/drop pattern as the v13
      // devices rebuild and the v27 group_invites rebuild.
      _db.execute('ALTER TABLE pending_calls RENAME TO pending_calls_v18;');
      _db.execute('''
        CREATE TABLE pending_calls (
          call_id TEXT PRIMARY KEY,
          caller_account_id TEXT NOT NULL,
          caller_device_id TEXT NOT NULL,
          callee_account_id TEXT NOT NULL,
          is_video INTEGER NOT NULL,
          offer_sdp TEXT,
          status TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          expires_at INTEGER NOT NULL,
          answered_by_device_id TEXT
        );
      ''');
      _db.execute('''
        INSERT INTO pending_calls (
          call_id, caller_account_id, caller_device_id, callee_account_id,
          is_video, offer_sdp, status, created_at, expires_at, answered_by_device_id
        )
        SELECT
          call_id, caller_account_id, caller_device_id, callee_account_id,
          is_video, offer_sdp, status, created_at, expires_at, answered_by_device_id
        FROM pending_calls_v18;
      ''');
      _db.execute('DROP TABLE pending_calls_v18;');

      _db.execute(
        'ALTER TABLE pending_call_devices RENAME TO pending_call_devices_v18;',
      );
      _db.execute('''
        CREATE TABLE pending_call_devices (
          call_id TEXT NOT NULL,
          target_device_id TEXT NOT NULL,
          status TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY(call_id, target_device_id),
          FOREIGN KEY(call_id) REFERENCES pending_calls(call_id) ON DELETE CASCADE
        );
      ''');
      _db.execute('''
        INSERT INTO pending_call_devices (
          call_id, target_device_id, status, created_at, updated_at
        )
        SELECT call_id, target_device_id, status, created_at, updated_at
        FROM pending_call_devices_v18;
      ''');
      _db.execute('DROP TABLE pending_call_devices_v18;');

      _db.execute('PRAGMA user_version = 28;');
    }

    if (version < 29) {
      _db.execute('ALTER TABLE accounts ADD COLUMN phone_hash TEXT;');
      _db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_phone_hash
          ON accounts(phone_hash) WHERE phone_hash IS NOT NULL;
      ''');

      _db.execute('PRAGMA user_version = 29;');
    }

    if (version < 30) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS phone_otp_challenges (
          challenge_id TEXT PRIMARY KEY,
          phone_hash   TEXT NOT NULL,
          code_hash    TEXT NOT NULL,
          purpose      TEXT NOT NULL,
          attempts     INTEGER NOT NULL DEFAULT 0,
          created_at   INTEGER NOT NULL,
          expires_at   INTEGER NOT NULL,
          consumed_at  INTEGER
        );
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_phone_otp_challenges_phone_hash
          ON phone_otp_challenges(phone_hash);
      ''');

      _db.execute('PRAGMA user_version = 30;');
    }

    if (version < 31) {
      // redeemed_by_account_id deliberately has no FK: it's a historical
      // audit reference, not a live relationship, and redemption happens
      // atomically before the account row exists (see
      // AuthRegistrationHandlers._registerHandler). It must also keep
      // showing which account redeemed an invite even if that account is
      // later deleted, which an ON DELETE SET NULL/CASCADE FK would erase.
      _db.execute('''
        CREATE TABLE IF NOT EXISTS invite_credentials (
          invite_id              TEXT PRIMARY KEY,
          invite_code_hash       TEXT NOT NULL,
          server_address         TEXT NOT NULL,
          issuer_type            TEXT NOT NULL,
          issuer_label           TEXT,
          status                 TEXT NOT NULL,
          created_at             INTEGER NOT NULL,
          expires_at             INTEGER NOT NULL,
          redeemed_at            INTEGER,
          redeemed_by_account_id TEXT
        );
      ''');
      _db.execute('''
        CREATE UNIQUE INDEX IF NOT EXISTS idx_invite_credentials_code_hash
          ON invite_credentials(invite_code_hash);
      ''');
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_invite_credentials_status
          ON invite_credentials(status);
      ''');

      _db.execute('PRAGMA user_version = 31;');
    }

    if (version < 32) {
      _db.execute('''
        ALTER TABLE account_privacy
          ADD COLUMN phone_discoverable INTEGER NOT NULL DEFAULT 1;
      ''');

      _db.execute('PRAGMA user_version = 32;');
    }

    if (version < 33) {
      // Short-lived, single-use codes an operator mints via a loopback-only
      // call on a running server and redeems from the admin app for a
      // freshly-rotated admin token - see AdminPairingModule. Only the hash
      // is stored, same as admin_token_hash; redeemed_at IS NULL means the
      // code is still live (until expires_at).
      _db.execute('''
        CREATE TABLE IF NOT EXISTS admin_pairing_codes (
          code_hash   TEXT PRIMARY KEY,
          created_at  INTEGER NOT NULL,
          expires_at  INTEGER NOT NULL,
          redeemed_at INTEGER
        );
      ''');

      _db.execute('PRAGMA user_version = 33;');
    }

    if (version < 34) {
      // Last few digits of the phone number used at registration, sent by
      // the client alongside (never instead of) phone_hash - deliberately
      // NOT the full number or anything reversible to it, just enough for
      // an admin to tell accounts apart on the Users screen. Optional: an
      // older client that doesn't send it yet leaves this empty, and
      // nothing server-side treats it as an identity/lookup key the way
      // phone_hash is - it is display-only.
      _db.execute(
        "ALTER TABLE accounts ADD COLUMN phone_last4 TEXT NOT NULL DEFAULT '';",
      );

      _db.execute('PRAGMA user_version = 34;');
    }

    if (version < 35) {
      // Supports the admin Users screen's reverse lookup (given a user,
      // which invite did they redeem) - without this, that join is a full
      // table scan of invite_credentials per user rendered.
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_invite_credentials_redeemed_by
          ON invite_credentials(redeemed_by_account_id);
      ''');

      _db.execute('PRAGMA user_version = 35;');
    }

    if (version < 36) {
      // Permanently bans a phone number from ever registering again -
      // distinct from deleting an account, which only removes that
      // account's data and leaves the phone number free to register a new
      // one. Keyed by phone_hash (never a raw phone number), same privacy
      // posture as everything else phone-identity-related. Outlives the
      // account it was created from: blocking then deleting an account
      // must still refuse that number afterward, so this cannot live on
      // the accounts row itself.
      _db.execute('''
        CREATE TABLE IF NOT EXISTS blocked_phone_hashes (
          phone_hash TEXT PRIMARY KEY,
          blocked_at INTEGER NOT NULL,
          blocked_by_account_id TEXT
        );
      ''');

      _db.execute('PRAGMA user_version = 36;');
    }

    if (version < 37) {
      // Tracks when a display name was last changed *by the user's own
      // request* (see AuthProfileHandlers._updateProfileHandler), separate
      // from account_profiles.updated_at - which registration also writes,
      // for the name given (or defaulted from the phone number) at signup.
      // Left NULL until the first explicit change so a user who skipped
      // setting a name at registration, or who hasn't touched it since, is
      // never blocked from their first real change by a cooldown they
      // never used.
      _db.execute(
        'ALTER TABLE account_profiles ADD COLUMN display_name_changed_at INTEGER;',
      );

      _db.execute('PRAGMA user_version = 37;');
    }

    if (version < 38) {
      // Contact-discovery budget, moved out of an in-memory Map.
      //
      // Two problems with the old `_matchAttempts` map: it reset on every
      // deploy, so a "daily" cap was not actually enforced across restarts,
      // and it grew one entry per account forever. Both matter here more
      // than for an ordinary rate limit, because this cap is the mitigation
      // for a real privacy risk - the endpoint is an oracle for "is phone
      // number X a Helix user".
      //
      // Meters *distinct hashes*, not requests. Metering requests made a
      // 2,100-contact phone book cost the entire daily budget in one sync
      // (5 requests x 500 hashes), leaving nothing for a retry, a second
      // device, or the next day - so chunking a large phone book could not
      // work at all. Charging per hash makes chunk size irrelevant to the
      // budget and bounds the actual enumeration exposure.
      _db.execute('''
        CREATE TABLE IF NOT EXISTS contacts_match_budget (
          account_id TEXT PRIMARY KEY,
          window_started_at INTEGER NOT NULL,
          hashes_used INTEGER NOT NULL DEFAULT 0,
          last_request_at INTEGER NOT NULL DEFAULT 0
        );
      ''');

      // Lets an unchanged phone book re-sync for free. A phone book changes
      // slowly, so without this the budget is spent re-asking the same
      // questions - and the answers are already on the device.
      _db.execute('''
        CREATE TABLE IF NOT EXISTS contacts_match_fingerprints (
          account_id TEXT PRIMARY KEY,
          fingerprint TEXT NOT NULL,
          matched_json TEXT NOT NULL,
          created_at INTEGER NOT NULL
        );
      ''');

      _db.execute('PRAGMA user_version = 38;');
    }

    if (version < 39) {
      // The call's negotiated IP-privacy policy, so the server can enforce
      // it on every frame rather than only on the one that declared it.
      //
      // This has to be persisted rather than held per-connection: a call's
      // frames arrive on several sockets (caller, each callee device) and
      // survive a reconnect, and the policy is agreed once on the
      // offer/answer pair but must constrain every ICE candidate that
      // follows. A restart between the offer and the candidates would
      // otherwise lose the agreement - and losing it is exactly the case
      // that must not fail open.
      //
      // Nullable with no default on purpose. A row written before this
      // migration has no recorded policy, and `CallMediaPolicy.fromWire`
      // maps null to relay-only, so in-flight calls across the upgrade are
      // relayed rather than exposed.
      final callColumns = _db
          .select('PRAGMA table_info(pending_calls);')
          .map((row) => row['name'] as String)
          .toSet();
      if (!callColumns.contains('ip_privacy')) {
        _db.execute('ALTER TABLE pending_calls ADD COLUMN ip_privacy TEXT;');
      }

      _db.execute('PRAGMA user_version = 39;');
    }

    if (version < 40) {
      // Admin as a stored capability rather than a magic account id.
      //
      // The gate used to be `adminAccountIds.contains(account_id)` over the
      // literal set {'admin'}, while `account_id` is chosen by the client at
      // registration - so the operator console belonged to whoever registered
      // the id 'admin' first. Nothing reserved it.
      //
      // Defaulting to 0 is the whole point: no existing account is silently
      // promoted by this migration. Operators keep using the admin token
      // (which carries the capability directly and needs no row), and a real
      // account is granted admin only by an explicit UPDATE.
      final accountColumns = _db
          .select('PRAGMA table_info(accounts);')
          .map((row) => row['name'] as String)
          .toSet();
      if (!accountColumns.contains('is_admin')) {
        _db.execute(
          'ALTER TABLE accounts ADD COLUMN is_admin INTEGER NOT NULL '
          'DEFAULT 0;',
        );
      }

      _db.execute('PRAGMA user_version = 40;');
    }

    if (version < 41) {
      final outboxColumns = _db
          .select('PRAGMA table_info(outbox);')
          .map((row) => row['name'] as String)
          .toSet();
      if (!outboxColumns.contains('next_attempt_at')) {
        _db.execute(
          'ALTER TABLE outbox ADD COLUMN next_attempt_at INTEGER NOT NULL '
          'DEFAULT 0;',
        );
      }
      _db.execute('''
        CREATE INDEX IF NOT EXISTS idx_outbox_due
        ON outbox(status, next_attempt_at, created_at);
      ''');

      _db.execute('PRAGMA user_version = 41;');
    }
  }
}
