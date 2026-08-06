part of '../database.dart';

extension BackendAccountsDevicesRepository on BackendDatabase {
  // Account operations
  //
  // `username` remains a required, unique DB column for now: it predates
  // phone-based identity and is deeply referenced by foreign keys from many
  // other tables, so dropping it outright would require rebuilding every
  // dependent table (see the phone_hash migration notes). Phone-based
  // registrations satisfy the column with a reserved, never-user-visible
  // value (see AuthRegistrationHandlers) and identify accounts by
  // `phone_hash` everywhere that matters instead.
  void createAccount(
    String accountId,
    String username,
    String identityPublicKey, {
    String? phoneHash,
    String phoneLast4 = '',
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO accounts (account_id, username, identity_public_key, phone_hash, phone_last4, created_at, status)
      VALUES (?, ?, ?, ?, ?, ?, 'ACTIVE');
    ''');
    stmt.execute([
      accountId,
      username,
      identityPublicKey,
      phoneHash,
      phoneLast4,
      now,
    ]);
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
      'phone_hash': row['phone_hash'],
      'phone_last4': row['phone_last4'],
      'identity_public_key': row['identity_public_key'],
      'created_at': row['created_at'],
      'status': row['status'],
    };
  }

  bool accountExists(String accountId) => getAccount(accountId) != null;

  /// Admin-triggered temporary revoke: an account with status SUSPENDED is
  /// rejected by every authenticated request (see BackendServer's auth
  /// middleware), the same way a revoked device already is - but unlike
  /// device revocation this is reversible by setting status back to
  /// ACTIVE, with no re-registration needed.
  void setAccountStatus(String accountId, String status) {
    final stmt = _db.prepare(
      'UPDATE accounts SET status = ? WHERE account_id = ?;',
    );
    stmt.execute([status, accountId]);
    stmt.close();
  }

  bool isAccountSuspended(String accountId) {
    final stmt = _db.prepare('''
      SELECT 1 FROM accounts WHERE account_id = ? AND status = 'SUSPENDED';
    ''');
    final res = stmt.select([accountId]);
    stmt.close();
    return res.isNotEmpty;
  }

  /// Whether this account holds the operator capability.
  ///
  /// Authoritative source for admin authorization on JWT-authenticated
  /// requests. An account id is just an id - it grants nothing on its own.
  /// A missing row reads as false, so an unknown account is never an admin.
  bool isAccountAdmin(String accountId) {
    final stmt = _db.prepare('''
      SELECT 1 FROM accounts WHERE account_id = ? AND is_admin = 1;
    ''');
    final res = stmt.select([accountId]);
    stmt.close();
    return res.isNotEmpty;
  }

  /// Grants or revokes the operator capability. There is no HTTP route to
  /// this: promotion is an out-of-band action by whoever administers the
  /// database, so a compromised account cannot promote itself.
  void setAccountAdmin(String accountId, {required bool isAdmin}) {
    final stmt = _db.prepare(
      'UPDATE accounts SET is_admin = ? WHERE account_id = ?;',
    );
    stmt.execute([isAdmin ? 1 : 0, accountId]);
    stmt.close();
  }

  /// Account ids in the table that are now reserved and unregisterable.
  ///
  /// Used by the startup guard: such a row can only predate the reserved-id
  /// check, and under the old name-based operator gate it would have held
  /// admin. Comparison is case-insensitive and whitespace-trimmed to match
  /// [isReservedAccountId].
  List<String> findAccountsWithReservedIds() {
    final rows = _db.select('SELECT account_id FROM accounts;');
    return [
      for (final row in rows)
        if (isReservedAccountId(row['account_id'] as String))
          row['account_id'] as String,
    ];
  }

  /// Looks up an account by its salted phone-number hash (see
  /// `phone_hash.dart`). This is the identity lookup used by phone-based
  /// registration and login; the server never sees a raw phone number.
  Map<String, dynamic>? getAccountByPhoneHash(String phoneHash) {
    final stmt = _db.prepare('SELECT * FROM accounts WHERE phone_hash = ?;');
    final result = stmt.select([phoneHash]);
    stmt.close();
    if (result.isEmpty) return null;
    final row = result.first;
    return {
      'account_id': row['account_id'],
      'username': row['username'],
      'phone_hash': row['phone_hash'],
      'identity_public_key': row['identity_public_key'],
      'created_at': row['created_at'],
      'status': row['status'],
    };
  }

  /// [recordDisplayNameChange] stamps `display_name_changed_at` to now -
  /// only pass true for a user's own explicit change (see
  /// AuthProfileHandlers._updateProfileHandler), which is what the monthly
  /// rate limit is measured from. Registration's initial profile write
  /// (whatever name it's given, including the phone-number default from
  /// skipping) must never pass true here, or a user would start their
  /// cooldown before ever making a real change.
  ///
  /// [now] defaults to the real clock, but callers that already have an
  /// injectable clock (see AuthModuleBase._now, used for testability) must
  /// pass it explicitly - otherwise this timestamp and the rate-limit
  /// check comparing against it can disagree under a mocked clock.
  Map<String, dynamic> upsertAccountProfile({
    required String accountId,
    required String displayName,
    bool recordDisplayNameChange = false,
    DateTime? now,
  }) {
    final current = getAccountProfile(accountId);
    final nextVersion = ((current?['profile_version'] as int?) ?? 0) + 1;
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final changedAt = recordDisplayNameChange
        ? nowMs
        : current?['display_name_changed_at'] as int?;
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO account_profiles (
        account_id,
        display_name,
        updated_at,
        profile_version,
        display_name_changed_at
      )
      VALUES (?, ?, ?, ?, ?);
    ''');
    stmt.execute([accountId, displayName, nowMs, nextVersion, changedAt]);
    stmt.close();
    return {
      'account_id': accountId,
      'display_name': displayName,
      'updated_at': nowMs,
      'profile_version': nextVersion,
      'display_name_changed_at': changedAt,
    };
  }

  Map<String, dynamic>? getAccountProfile(String accountId) {
    final stmt = _db.prepare(
      'SELECT * FROM account_profiles WHERE account_id = ?;',
    );
    final res = stmt.select([accountId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'account_id': row['account_id'],
      'display_name': row['display_name'],
      'updated_at': row['updated_at'],
      'profile_version': row['profile_version'],
      'display_name_changed_at': row['display_name_changed_at'],
    };
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

  Future<void> deleteAccountData(String accountId) async {
    // Drain the account's message mailboxes in bounded, yielding chunks
    // BEFORE the cascade transaction. A large mailbox deleted purely via
    // ON DELETE CASCADE holds SQLite's single writer lock for the whole
    // delete, starving every other request (WS heartbeats included) for
    // seconds. After the drains, the final cascade only sweeps stragglers
    // that arrived in between, so the transaction below stays short.
    await _deleteMessagesChunked(
      'recipient_device_id IN (SELECT device_id FROM devices WHERE account_id = ?)',
      [accountId],
    );
    await _deleteMessagesChunked('sender_account_id = ?', [accountId]);

    _db.execute('BEGIN TRANSACTION;');
    try {
      // No explicit message cleanup here: `messages.recipient_device_id`
      // cascades from `devices`, which cascades from `accounts` (foreign_keys
      // is ON), so the DELETE FROM accounts below already removes every
      // remaining message for this account as part of the same atomic
      // transaction — the chunked drains above are a performance measure,
      // not a correctness requirement, and must never run inside this
      // transaction (see _deleteMessagesChunked's doc comment).
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

  // Phone-number blocking - permanently bans a phone_hash from ever
  // registering again, independent of whether any account currently exists
  // for it. Distinct from deleteAccountData: deleting alone frees a phone
  // number for reuse, blocking alone does not touch any existing account.
  // Admin-facing "Block" combines both (see OperabilityModule._blockUser).

  void blockPhoneHash(String phoneHash, {String? blockedByAccountId}) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO blocked_phone_hashes (phone_hash, blocked_at, blocked_by_account_id)
      VALUES (?, ?, ?);
    ''');
    stmt.execute([
      phoneHash,
      DateTime.now().millisecondsSinceEpoch,
      blockedByAccountId,
    ]);
    stmt.close();
  }

  void unblockPhoneHash(String phoneHash) {
    _deleteWhere('blocked_phone_hashes', 'phone_hash = ?', [phoneHash]);
  }

  bool isPhoneHashBlocked(String phoneHash) {
    final stmt = _db.prepare(
      'SELECT 1 FROM blocked_phone_hashes WHERE phone_hash = ?;',
    );
    final res = stmt.select([phoneHash]);
    stmt.close();
    return res.isNotEmpty;
  }

  // Device operations
  void registerDevice(
    String deviceId,
    String accountId,
    String deviceSigningPublicKey,
    String deviceAgreementPublicKeyOrName, [
    String? deviceName,
  ]) {
    final resolvedDeviceName = deviceName ?? deviceAgreementPublicKeyOrName;
    final resolvedAgreementPublicKey = deviceName == null
        ? deviceSigningPublicKey
        : deviceAgreementPublicKeyOrName;
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO devices (device_id, account_id, device_signing_public_key, device_agreement_public_key, device_name, status, created_at, last_seen_at)
      VALUES (?, ?, ?, ?, ?, 'ACTIVE', ?, ?);
    ''');
    stmt.execute([
      deviceId,
      accountId,
      deviceSigningPublicKey,
      resolvedAgreementPublicKey,
      resolvedDeviceName,
      now,
      now,
    ]);
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
            'device_signing_public_key': row['device_signing_public_key'],
            'device_agreement_public_key': row['device_agreement_public_key'],
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

  void renameDevice(String accountId, String deviceId, String deviceName) {
    final stmt = _db.prepare('''
      UPDATE devices SET device_name = ?
      WHERE account_id = ? AND device_id = ? AND status = 'ACTIVE';
    ''');
    stmt.execute([deviceName, accountId, deviceId]);
    stmt.close();
  }

  int activeDeviceCount(String accountId) {
    final stmt = _db.prepare(
      "SELECT COUNT(*) AS count FROM devices WHERE account_id = ? AND status = 'ACTIVE';",
    );
    final res = stmt.select([accountId]);
    stmt.close();
    return res.first['count'] as int;
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

  String? getDevicePushToken(String deviceId) {
    final stmt = _db.prepare('''
      SELECT COALESCE(
        NULLIF(p.push_token, ''),
        NULLIF(d.push_token, '')
      ) AS push_token
      FROM devices d
      LEFT JOIN device_push_tokens p ON p.device_id = d.device_id
      WHERE d.device_id = ? AND d.status = 'ACTIVE';
    ''');
    final res = stmt.select([deviceId]);
    stmt.close();
    if (res.isEmpty) return null;
    return res.first['push_token'] as String?;
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
    String? newDeviceSigningPublicKey,
    String? newDeviceAgreementPublicKey,
    String requestNonce = '',
    int expiresAt = 0,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final signingKey = newDeviceSigningPublicKey ?? newDevicePublicKey;
    final agreementKey = newDeviceAgreementPublicKey ?? newDevicePublicKey;
    final stmt = _db.prepare('''
      INSERT INTO pending_device_links (
        link_id,
        account_id,
        requested_by_device_id,
        new_device_id,
        new_device_public_key,
        new_device_signing_public_key,
        new_device_agreement_public_key,
        new_device_name,
        verification_code_hash,
        status,
        created_at,
        request_nonce,
        expires_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'PENDING', ?, ?, ?);
    ''');
    stmt.execute([
      linkId,
      accountId,
      requestedByDeviceId,
      newDeviceId,
      newDevicePublicKey,
      signingKey,
      agreementKey,
      newDeviceName,
      verificationCodeHash,
      now,
      requestNonce,
      expiresAt,
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
      'new_device_signing_public_key':
          row['new_device_signing_public_key'] ?? row['new_device_public_key'],
      'new_device_agreement_public_key':
          row['new_device_agreement_public_key'] ??
          row['new_device_public_key'],
      'new_device_name': row['new_device_name'],
      'verification_code_hash': row['verification_code_hash'],
      'status': row['status'],
      'created_at': row['created_at'],
      'approved_at': row['approved_at'],
      'expires_at': row['expires_at'] ?? 0,
      'request_nonce': row['request_nonce'] ?? '',
      'approved_by_device_id': row['approved_by_device_id'],
      'approval_transcript_hash': row['approval_transcript_hash'] ?? '',
      'rejected_at': row['rejected_at'],
      'completed_at': row['completed_at'],
    };
  }

  bool approveDeviceLinkRequest({
    required String linkId,
    required String accountId,
    required String verificationCodeHash,
    String? approvedByDeviceId,
    String approvalTranscriptHash = '',
    int? now,
  }) {
    final link = getDeviceLinkRequest(linkId);
    final currentTime = now ?? DateTime.now().millisecondsSinceEpoch;
    final expiresAt = (link?['expires_at'] as int?) ?? 0;
    if (link == null ||
        link['account_id'] != accountId ||
        link['status'] != 'PENDING' ||
        link['verification_code_hash'] != verificationCodeHash ||
        (expiresAt > 0 && currentTime >= expiresAt) ||
        (approvedByDeviceId != null &&
            link['new_device_id'] == approvedByDeviceId)) {
      return false;
    }

    final stmt = _db.prepare('''
      UPDATE pending_device_links
      SET status = 'APPROVED',
          approved_at = ?,
          approved_by_device_id = ?,
          approval_transcript_hash = ?
      WHERE link_id = ? AND status = 'PENDING';
    ''');
    stmt.execute([
      currentTime,
      approvedByDeviceId,
      approvalTranscriptHash,
      linkId,
    ]);
    final changed = _db.updatedRows;
    stmt.close();
    return changed == 1;
  }

  bool rejectDeviceLinkRequest({
    required String linkId,
    required String accountId,
    required String verificationCodeHash,
    required String rejectedByDeviceId,
    int? now,
  }) {
    final link = getDeviceLinkRequest(linkId);
    final currentTime = now ?? DateTime.now().millisecondsSinceEpoch;
    if (link == null ||
        link['account_id'] != accountId ||
        link['status'] != 'PENDING' ||
        link['verification_code_hash'] != verificationCodeHash ||
        link['new_device_id'] == rejectedByDeviceId) {
      return false;
    }

    final stmt = _db.prepare('''
      UPDATE pending_device_links
      SET status = 'REJECTED',
          rejected_at = ?,
          approved_by_device_id = ?
      WHERE link_id = ? AND status = 'PENDING';
    ''');
    stmt.execute([currentTime, rejectedByDeviceId, linkId]);
    final changed = _db.updatedRows;
    stmt.close();
    return changed == 1;
  }

  bool completeDeviceLinkRequest(String linkId, {int? now}) {
    final stmt = _db.prepare(
      "UPDATE pending_device_links SET status = 'LINKED', completed_at = ? WHERE link_id = ? AND status = 'APPROVED';",
    );
    stmt.execute([now ?? DateTime.now().millisecondsSinceEpoch, linkId]);
    final changed = _db.updatedRows;
    stmt.close();
    return changed == 1;
  }

  void deletePrekeysForDevice(String accountId, String deviceId) {
    _db.execute('BEGIN TRANSACTION;');
    try {
      var stmt = _db.prepare(
        'DELETE FROM one_time_prekeys WHERE account_id = ? AND device_id = ?;',
      );
      stmt.execute([accountId, deviceId]);
      stmt.close();

      stmt = _db.prepare(
        'DELETE FROM signed_prekeys WHERE account_id = ? AND device_id = ?;',
      );
      stmt.execute([accountId, deviceId]);
      stmt.close();
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void expirePendingDeviceLinksForDevice(
    String accountId,
    String deviceId, {
    int? now,
  }) {
    final stmt = _db.prepare('''
      UPDATE pending_device_links
      SET status = 'REJECTED', rejected_at = ?
      WHERE account_id = ?
        AND status IN ('PENDING', 'APPROVED')
        AND (new_device_id = ? OR requested_by_device_id = ? OR approved_by_device_id = ?);
    ''');
    stmt.execute([
      now ?? DateTime.now().millisecondsSinceEpoch,
      accountId,
      deviceId,
      deviceId,
      deviceId,
    ]);
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

  List<Map<String, dynamic>> getDeviceSecurityHistory(
    String accountId,
    String deviceId,
  ) {
    final audit = _selectWhere(
      'audit_logs',
      "account_id = ? AND (device_id = ? OR action IN ('DEVICE_LINK_REQUESTED', 'DEVICE_LINK_APPROVED', 'DEVICE_LINK_REJECTED', 'DEVICE_LINK_COMPLETED', 'DEVICE_LINK_COMPLETION_REPLAYED'))",
      [accountId, deviceId],
    );
    final revocations = _selectWhere(
      'device_revocations',
      'account_id = ? AND revoked_device_id = ?',
      [accountId, deviceId],
    );
    return [
      ...audit.map(
        (row) => {
          'type': row['action'],
          'device_id': row['device_id'],
          'timestamp': row['timestamp'],
        },
      ),
      ...revocations.map(
        (row) => {
          'type': 'DEVICE_REVOKED',
          'device_id': row['revoked_device_id'],
          'reason': row['reason'],
          'timestamp': row['created_at'],
        },
      ),
    ]..sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
  }

  // Deletes in bounded chunks and yields between them so a device with a
  // very large mailbox (e.g. long-offline before revocation) doesn't hold
  // SQLite's single writer lock for the entire delete, starving every other
  // account's writes for its duration.
  Future<void> deleteMessagesForDevice(String deviceId) =>
      _deleteMessagesChunked('recipient_device_id = ?', [deviceId]);

  // Chunked, yielding delete over `messages`. Standard SQLite has no
  // `DELETE ... LIMIT` (that requires a non-default compile flag), so the
  // chunk is selected via a `rowid IN (SELECT ... LIMIT ?)` subquery
  // instead — the portable equivalent. Must never be called from within an
  // existing transaction: the `await` between chunks would let other
  // requests interleave their own writes into that transaction.
  Future<void> _deleteMessagesChunked(
    String where,
    List<Object?> params,
  ) async {
    const chunkSize = 500;
    while (true) {
      final stmt = _db.prepare('''
        DELETE FROM messages WHERE rowid IN (
          SELECT rowid FROM messages WHERE $where LIMIT ?
        );
      ''');
      stmt.execute([...params, chunkSize]);
      stmt.close();
      if (_db.updatedRows == 0) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
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
      'device_key': devRow['device_agreement_public_key'],
      'signed_prekey': {
        'key_id': spkRow['key_id'],
        'public_key': spkRow['public_key'],
        'signature': spkRow['signature'],
      },
      'one_time_prekey': otkData,
    };
  }
}
