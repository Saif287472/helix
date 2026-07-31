part of '../database.dart';

extension BackendInvitesRepository on BackendDatabase {
  void createInviteCredential({
    required String inviteId,
    required String inviteCodeHash,
    required String serverAddress,
    required String issuerType,
    String? issuerLabel,
    required int createdAt,
    required int expiresAt,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO invite_credentials (
        invite_id, invite_code_hash, server_address, issuer_type,
        issuer_label, status, created_at, expires_at, redeemed_at,
        redeemed_by_account_id
      ) VALUES (?, ?, ?, ?, ?, 'PENDING', ?, ?, NULL, NULL);
    ''');
    stmt.execute([
      inviteId,
      inviteCodeHash,
      serverAddress,
      issuerType,
      issuerLabel,
      createdAt,
      expiresAt,
    ]);
    stmt.close();
  }

  Map<String, dynamic>? _rowToInvite(Row row) {
    return {
      'invite_id': row['invite_id'],
      'invite_code_hash': row['invite_code_hash'],
      'server_address': row['server_address'],
      'issuer_type': row['issuer_type'],
      'issuer_label': row['issuer_label'],
      'status': row['status'],
      'created_at': row['created_at'],
      'expires_at': row['expires_at'],
      'redeemed_at': row['redeemed_at'],
      'redeemed_by_account_id': row['redeemed_by_account_id'],
    };
  }

  Map<String, dynamic>? getInviteByCodeHash(String inviteCodeHash) {
    final stmt = _db.prepare(
      'SELECT * FROM invite_credentials WHERE invite_code_hash = ?;',
    );
    final result = stmt.select([inviteCodeHash]);
    stmt.close();
    if (result.isEmpty) return null;
    return _rowToInvite(result.first);
  }

  Map<String, dynamic>? getInviteById(String inviteId) {
    final stmt = _db.prepare(
      'SELECT * FROM invite_credentials WHERE invite_id = ?;',
    );
    final result = stmt.select([inviteId]);
    stmt.close();
    if (result.isEmpty) return null;
    return _rowToInvite(result.first);
  }

  /// Atomically marks an invite redeemed, but only if it is still
  /// `PENDING` and not expired as of `now` - callers must check `expires_at`
  /// themselves beforehand for user-facing error messages, but this
  /// re-checks under the same guard so two concurrent registrations can
  /// never both redeem the same invite. Returns false on any mismatch,
  /// including an invite_id that doesn't exist.
  bool redeemInviteCredential({
    required String inviteId,
    required String accountId,
    required int now,
  }) {
    final stmt = _db.prepare('''
      UPDATE invite_credentials
      SET status = 'REDEEMED', redeemed_at = ?, redeemed_by_account_id = ?
      WHERE invite_id = ? AND status = 'PENDING' AND expires_at > ?;
    ''');
    stmt.execute([now, accountId, inviteId, now]);
    final changed = _db.updatedRows;
    stmt.close();
    return changed == 1;
  }

  List<Map<String, dynamic>> getInviteCredentialsPaginated({
    required int limit,
    required int offset,
  }) {
    final stmt = _db.prepare('''
      SELECT * FROM invite_credentials
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?;
    ''');
    final result = stmt.select([limit, offset]);
    stmt.close();
    return result.map((row) => _rowToInvite(row)!).toList();
  }
}
