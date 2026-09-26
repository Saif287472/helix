part of '../database.dart';

mixin RemoteAccountsContactsRepository on HelixRemoteDatabaseBase {
  // ---------------------------------------------------------------------------
  // Account operations
  // ---------------------------------------------------------------------------

  void upsertAccount(RemoteAccount account) {
    final stmt = _db.prepare('''
      INSERT INTO accounts (account_id, identity_public_key, created_at, status)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(account_id) DO UPDATE SET
        identity_public_key = excluded.identity_public_key,
        status = excluded.status;
    ''');
    stmt.execute([
      account.accountId,
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

  /// Flags a device as revoked without touching its key material.
  ///
  /// Called when the server pushes `device_revoked`. The public keys stay put
  /// so the row is still renderable in the device list as a historical entry;
  /// only the status changes.
  ///
  /// Matched on `device_id` alone because the relay scopes this event to the
  /// recipient's own account and so sends no account id, and because the
  /// local mirror holds exactly one account (a single global sync cursor).
  /// Returns true when a row was updated.
  bool markDeviceRevokedByDeviceId(String deviceId) {
    final stmt = _db.prepare('''
      UPDATE devices SET status = 'REVOKED' WHERE device_id = ?;
    ''');
    stmt.execute([deviceId]);
    stmt.close();
    return _db.updatedRows > 0;
  }

  /// The local device id recorded for this account, if one is stored.
  String? getLocalDeviceId() {
    final stmt = _db.prepare(
      "SELECT device_id FROM devices WHERE status = 'ACTIVE' ORDER BY created_at DESC LIMIT 1;",
    );
    final res = stmt.select();
    stmt.close();
    if (res.isEmpty) return null;
    return res.first['device_id'] as String?;
  }

  // ---------------------------------------------------------------------------
  // Pending device-link requests
  // ---------------------------------------------------------------------------

  /// Records a `pending_device_link` push from the server.
  ///
  /// Holds no verification code: the 6-digit code the approving device has to
  /// confirm lives only on the *new* device, so approving means acting on
  /// that screen, not here.
  void upsertPendingDeviceLink({
    required String linkId,
    required String deviceId,
    required String deviceName,
    required int expiresAt,
    required int createdAt,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO pending_device_links
        (link_id, device_id, device_name, expires_at, created_at, status)
      VALUES (?, ?, ?, ?, ?, 'PENDING')
      ON CONFLICT(link_id) DO UPDATE SET
        device_id = excluded.device_id,
        device_name = excluded.device_name,
        expires_at = excluded.expires_at,
        created_at = excluded.created_at,
        status = 'PENDING';
    ''');
    stmt.execute([linkId, deviceId, deviceName, expiresAt, createdAt]);
    stmt.close();
  }

  /// Pending, unexpired link requests, newest first.
  List<Map<String, dynamic>> getPendingDeviceLinks({required int nowMs}) {
    final stmt = _db.prepare('''
      SELECT * FROM pending_device_links
      WHERE status = 'PENDING' AND expires_at > ?
      ORDER BY created_at DESC;
    ''');
    final res = stmt.select([nowMs]);
    stmt.close();
    return res
        .map(
          (row) => {
            'link_id': row['link_id'] as String,
            'device_id': row['device_id'] as String,
            'device_name': row['device_name'] as String,
            'expires_at': row['expires_at'] as int,
            'created_at': row['created_at'] as int,
            'status': row['status'] as String,
          },
        )
        .toList();
  }

  void markPendingDeviceLinkResolved(String linkId, {required String status}) {
    final stmt = _db.prepare('''
      UPDATE pending_device_links SET status = ?
      WHERE link_id = ?;
    ''');
    stmt.execute([status, linkId]);
    stmt.close();
  }

  /// Clears every pending request that named [deviceId].
  ///
  /// The `device_linked` completion frame does not carry the link id, so the
  /// only way to retire the matching prompt is by the device it named.
  void markPendingDeviceLinksForDeviceCompleted(String deviceId) {
    final stmt = _db.prepare('''
      UPDATE pending_device_links SET status = 'COMPLETED'
      WHERE device_id = ? AND status = 'PENDING';
    ''');
    stmt.execute([deviceId]);
    stmt.close();
  }

  /// Drops link requests the server has already expired, so they cannot
  /// accumulate in a list the operator can no longer act on.
  void purgeExpiredDeviceLinks({required int nowMs}) {
    final stmt = _db.prepare(
      "DELETE FROM pending_device_links WHERE status = 'PENDING' AND expires_at <= ?;",
    );
    stmt.execute([nowMs]);
    stmt.close();
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

  @override
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
  // Phone-book name override operations
  //
  // Local-only labels learned from matching the device's phone book against
  // the backend's /contacts/match endpoint. Independent of the `contacts`
  // table (a phone-book match may exist for an account that isn't a Helix
  // contact yet), and never synced - each device keeps its own.
  // ---------------------------------------------------------------------------

  void savePhoneContactName({
    required String peerAccountId,
    required String phoneBookName,
    required int updatedAt,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO phone_contact_names (
        peer_account_id,
        phone_book_name,
        updated_at
      )
      VALUES (?, ?, ?);
    ''');
    stmt.execute([peerAccountId, phoneBookName, updatedAt]);
    stmt.close();
  }

  String? phoneContactName(String peerAccountId) {
    final stmt = _db.prepare(
      'SELECT phone_book_name FROM phone_contact_names WHERE peer_account_id = ?;',
    );
    final res = stmt.select([peerAccountId]);
    stmt.close();
    if (res.isEmpty) return null;
    return res.first['phone_book_name'] as String;
  }

  Map<String, String> phoneContactNames() {
    final stmt = _db.prepare(
      'SELECT peer_account_id, phone_book_name FROM phone_contact_names;',
    );
    final res = stmt.select();
    stmt.close();
    return {
      for (final row in res)
        row['peer_account_id'] as String: row['phone_book_name'] as String,
    };
  }

  /// Replaces the whole "not on Helix yet" list in one transaction.
  ///
  /// Whole-list replacement, not a merge, and that is the point: a name that
  /// has since joined Helix is matched by the sync that produced [names], so
  /// it is simply not in the new set and disappears without needing to be
  /// tracked and promoted individually.
  ///
  /// Only ever called for a *complete* sync. A sync cut short by the
  /// server's discovery budget knows nothing about the contacts it never
  /// looked up, and writing its partial view here would delete names that
  /// were never actually checked.
  void replaceUnmatchedPhoneContacts({
    required List<String> phoneBookNames,
    required int syncedAt,
  }) {
    _db.execute('BEGIN TRANSACTION;');
    try {
      _db.execute('DELETE FROM unmatched_phone_contacts;');
      final stmt = _db.prepare(
        'INSERT OR REPLACE INTO unmatched_phone_contacts (phone_book_name) '
        'VALUES (?);',
      );
      for (final name in phoneBookNames) {
        final trimmed = name.trim();
        if (trimmed.isEmpty) continue;
        stmt.execute([trimmed]);
      }
      stmt.close();
      final syncStmt = _db.prepare(
        'INSERT OR REPLACE INTO unmatched_phone_contacts_sync '
        '(id, synced_at) VALUES (1, ?);',
      );
      syncStmt.execute([syncedAt]);
      syncStmt.close();
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  List<String> unmatchedPhoneContactNames() {
    final stmt = _db.prepare(
      'SELECT phone_book_name FROM unmatched_phone_contacts '
      'ORDER BY phone_book_name ASC;',
    );
    final res = stmt.select();
    stmt.close();
    return res
        .map((row) => row['phone_book_name'] as String)
        .toList(growable: false);
  }

  /// When the stored list was last written, or null if it never has been.
  ///
  /// Null is meaningfully different from "old": it means no complete sync
  /// has run on this device, so the contacts permission may never have been
  /// granted and a background refresh would surface a permission dialog the
  /// user did not ask for.
  int? unmatchedPhoneContactsSyncedAt() {
    final stmt = _db.prepare(
      'SELECT synced_at FROM unmatched_phone_contacts_sync WHERE id = 1;',
    );
    final res = stmt.select();
    stmt.close();
    if (res.isEmpty) return null;
    return res.first['synced_at'] as int?;
  }
}
