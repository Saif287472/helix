part of '../database.dart';

extension BackendPasswordsRepository on BackendDatabase {
  Map<String, dynamic>? getAccountPassword(String accountId) {
    final stmt = _db.prepare(
      'SELECT * FROM account_passwords WHERE account_id = ?;',
    );
    final rows = stmt.select([accountId]);
    stmt.close();
    if (rows.isEmpty) return null;
    final row = rows.first;
    return {
      'account_id': row['account_id'],
      'kdf_params': row['kdf_params'],
      'kdf_salt': row['kdf_salt'],
      'auth_hash': row['auth_hash'],
      'auth_hash_salt': row['auth_hash_salt'],
      'wrapped_identity_key': row['wrapped_identity_key'],
      'identity_public_key': row['identity_public_key'],
      'failed_attempts': row['failed_attempts'],
      'locked_until': row['locked_until'],
      'created_at': row['created_at'],
      'updated_at': row['updated_at'],
    };
  }

  bool accountHasPassword(String accountId) {
    final stmt = _db.prepare(
      'SELECT 1 FROM account_passwords WHERE account_id = ?;',
    );
    final rows = stmt.select([accountId]);
    stmt.close();
    return rows.isNotEmpty;
  }

  /// Creates or replaces the account's password. Clears any lockout: the
  /// caller has just proven itself another way (a signed-in device, and the
  /// current password when one existed).
  void setAccountPassword({
    required String accountId,
    required String kdfParams,
    required String kdfSalt,
    required String authHash,
    required String authHashSalt,
    required String wrappedIdentityKey,
    required String identityPublicKey,
    required int now,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO account_passwords (
        account_id, kdf_params, kdf_salt, auth_hash, auth_hash_salt,
        wrapped_identity_key, identity_public_key, failed_attempts,
        locked_until, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?)
      ON CONFLICT(account_id) DO UPDATE SET
        kdf_params = excluded.kdf_params,
        kdf_salt = excluded.kdf_salt,
        auth_hash = excluded.auth_hash,
        auth_hash_salt = excluded.auth_hash_salt,
        wrapped_identity_key = excluded.wrapped_identity_key,
        identity_public_key = excluded.identity_public_key,
        failed_attempts = 0,
        locked_until = 0,
        updated_at = excluded.updated_at;
    ''');
    stmt.execute([
      accountId,
      kdfParams,
      kdfSalt,
      authHash,
      authHashSalt,
      wrappedIdentityKey,
      identityPublicKey,
      now,
      now,
    ]);
    stmt.close();
  }

  void recordPasswordFailure(
    String accountId, {
    required int failedAttempts,
    required int lockedUntil,
  }) {
    final stmt = _db.prepare('''
      UPDATE account_passwords
      SET failed_attempts = ?, locked_until = ?
      WHERE account_id = ?;
    ''');
    stmt.execute([failedAttempts, lockedUntil, accountId]);
    stmt.close();
  }

  void clearPasswordFailures(String accountId) {
    final stmt = _db.prepare('''
      UPDATE account_passwords
      SET failed_attempts = 0, locked_until = 0
      WHERE account_id = ?;
    ''');
    stmt.execute([accountId]);
    stmt.close();
  }

  void deleteAccountPassword(String accountId) {
    final stmt = _db.prepare(
      'DELETE FROM account_passwords WHERE account_id = ?;',
    );
    stmt.execute([accountId]);
    stmt.close();
  }

  Map<String, dynamic>? getHistoryBackup(String accountId) {
    final rows = _db.select(
      'SELECT * FROM history_backups WHERE account_id = ?;',
      [accountId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return {
      'identity_public_key': row['identity_public_key'],
      'blob': row['blob'],
      'size_bytes': row['size_bytes'],
      'updated_at': row['updated_at'],
    };
  }

  void saveHistoryBackup({
    required String accountId,
    required String identityPublicKey,
    required String blob,
    required int now,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO history_backups (
        account_id, identity_public_key, blob, size_bytes, updated_at
      ) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(account_id) DO UPDATE SET
        identity_public_key = excluded.identity_public_key,
        blob = excluded.blob,
        size_bytes = excluded.size_bytes,
        updated_at = excluded.updated_at;
    ''');
    stmt.execute([accountId, identityPublicKey, blob, blob.length, now]);
    stmt.close();
  }
}
