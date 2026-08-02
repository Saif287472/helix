part of '../database.dart';

extension BackendServerConfigRepository on BackendDatabase {
  String? getServerConfig(String key) {
    final stmt = _db.prepare(
      'SELECT value FROM server_configuration WHERE key = ?;',
    );
    final result = stmt.select([key]);
    stmt.close();
    if (result.isEmpty) return null;
    return result.first['value'] as String?;
  }

  void setServerConfig(String key, String value) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO server_configuration (key, value)
      VALUES (?, ?);
    ''');
    stmt.execute([key, value]);
    stmt.close();
  }

  void deleteServerConfig(String key) {
    final stmt = _db.prepare('DELETE FROM server_configuration WHERE key = ?;');
    stmt.execute([key]);
    stmt.close();
  }

  // Deliberately does not select username or phone_hash: admin tooling
  // should never surface an account's identifier beyond account_id (phone
  // numbers are hashed server-side and must never be shown in the clear,
  // and username is a legacy, never-user-visible internal column).
  List<Map<String, dynamic>> getAllUsersPaginated({
    required int limit,
    required int offset,
  }) {
    final stmt = _db.prepare('''
      SELECT account_id, created_at, status
      FROM accounts
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?;
    ''');
    final result = stmt.select([limit, offset]);
    stmt.close();
    return result
        .map(
          (row) => {
            'account_id': row['account_id'] as String,
            'created_at': row['created_at'] as int,
            'status': row['status'] as String,
          },
        )
        .toList();
  }

  /// Richer per-user view for the admin console's Users screen: account_id,
  /// display name, the invite they redeemed (if any), and phone_last4 - the
  /// last 2-4 digits of the phone number submitted at registration
  /// specifically as a display hint (see AuthRegistrationHandlers). Still
  /// never selects username or phone_hash, for the same reason as
  /// getAllUsersPaginated above; phone_last4 is the one intentional,
  /// narrow exception to "no phone data leaves the hash," since it cannot
  /// be used to recover the full number or to identify/match an account.
  List<Map<String, dynamic>> getAllUsersDetailedPaginated({
    required int limit,
    required int offset,
  }) {
    final stmt = _db.prepare('''
      SELECT
        a.account_id,
        a.created_at,
        a.status,
        a.phone_last4,
        p.display_name,
        ic.invite_id,
        ic.issuer_label AS invite_issuer_label,
        ic.redeemed_at AS invite_redeemed_at
      FROM accounts a
      LEFT JOIN account_profiles p ON p.account_id = a.account_id
      LEFT JOIN invite_credentials ic ON ic.redeemed_by_account_id = a.account_id
      ORDER BY a.created_at DESC
      LIMIT ? OFFSET ?;
    ''');
    final result = stmt.select([limit, offset]);
    stmt.close();
    return result
        .map(
          (row) => {
            'account_id': row['account_id'] as String,
            'created_at': row['created_at'] as int,
            'status': row['status'] as String,
            'phone_last4': row['phone_last4'] as String? ?? '',
            'display_name': row['display_name'] as String? ?? '',
            'invite_id': row['invite_id'] as String?,
            'invite_issuer_label': row['invite_issuer_label'] as String?,
            'invite_redeemed_at': row['invite_redeemed_at'] as int?,
          },
        )
        .toList();
  }

  void vacuumInto(String path) {
    final stmt = _db.prepare('VACUUM INTO ?;');
    stmt.execute([path]);
    stmt.close();
  }
}
