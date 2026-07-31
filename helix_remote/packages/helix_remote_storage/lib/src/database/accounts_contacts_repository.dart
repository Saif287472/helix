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
}
