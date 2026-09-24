part of '../database.dart';

extension BackendRecoveryRepository on BackendDatabase {
  void createRecoveryCode({
    required String recoveryId,
    required String accountId,
    required String codeHash,
    required String salt,
    required int createdAt,
    required int expiresAt,
  }) {
    // Invalidate any previously unredeemed recovery codes for this account
    final revokeStmt = _db.prepare('''
      UPDATE account_recovery_codes
      SET redeemed_at = ?
      WHERE account_id = ? AND redeemed_at IS NULL;
    ''');
    revokeStmt.execute([createdAt, accountId]);
    revokeStmt.close();

    final stmt = _db.prepare('''
      INSERT INTO account_recovery_codes (
        recovery_id, account_id, code_hash, salt, created_at, expires_at, redeemed_at
      ) VALUES (?, ?, ?, ?, ?, ?, NULL);
    ''');
    stmt.execute([
      recoveryId,
      accountId,
      codeHash,
      salt,
      createdAt,
      expiresAt,
    ]);
    stmt.close();
  }

  Map<String, dynamic>? getValidRecoveryCodeForAccount(String accountId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      SELECT * FROM account_recovery_codes
      WHERE account_id = ? AND redeemed_at IS NULL AND expires_at > ?
      ORDER BY created_at DESC LIMIT 1;
    ''');
    final rows = stmt.select([accountId, now]);
    stmt.close();
    if (rows.isEmpty) return null;
    final row = rows.first;
    return {
      'recovery_id': row['recovery_id'],
      'account_id': row['account_id'],
      'code_hash': row['code_hash'],
      'salt': row['salt'],
      'created_at': row['created_at'],
      'expires_at': row['expires_at'],
      'redeemed_at': row['redeemed_at'],
    };
  }

  void markRecoveryCodeRedeemed(String recoveryId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      UPDATE account_recovery_codes
      SET redeemed_at = ?
      WHERE recovery_id = ?;
    ''');
    stmt.execute([now, recoveryId]);
    stmt.close();
  }
}
