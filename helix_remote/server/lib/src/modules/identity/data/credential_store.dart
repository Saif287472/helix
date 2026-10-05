import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

/// SQL for refresh tokens, passwords, invites, recovery codes, phone
/// challenges and phone bans. Secrets are stored only as hashes.
final class CredentialStore {
  CredentialStore(this.s);

  final String s;

  // ---------------------------------------------------------- refresh tokens

  Future<void> insertRefresh(
    SqlSession db, {
    required String id,
    required String deviceId,
    required Uint8List secretHash,
    required DateTime expiresAt,
  }) async {
    await db.execute(
      'INSERT INTO $s.refresh_tokens (id, device_id, secret_hash, expires_at) '
      'VALUES (@id:uuid, @d:uuid, @h:bytea, @e:timestamptz)',
      {'id': id, 'd': deviceId, 'h': secretHash, 'e': expiresAt},
    );
  }

  /// Locks and returns a refresh token row.
  Future<Row?> refreshForUpdate(Tx tx, String id) => tx.queryOne(
    'SELECT id, device_id, secret_hash, expires_at, used_at, revoked_at '
    'FROM $s.refresh_tokens WHERE id = @id:uuid FOR UPDATE',
    {'id': id},
  );

  Future<void> markRefreshUsed(Tx tx, String id) async {
    await tx.execute(
      'UPDATE $s.refresh_tokens SET used_at = now() WHERE id = @id:uuid',
      {'id': id},
    );
  }

  Future<void> revokeDeviceRefresh(SqlSession db, String deviceId) async {
    await db.execute(
      'UPDATE $s.refresh_tokens SET revoked_at = now() WHERE device_id = @d:uuid AND revoked_at IS NULL',
      {'d': deviceId},
    );
  }

  Future<int> purgeExpiredRefresh(SqlSession db) => db.execute(
    "DELETE FROM $s.refresh_tokens WHERE expires_at < now() - interval '7 days'",
  );

  // --------------------------------------------------------------- passwords

  Future<Row?> password(
    SqlSession db,
    String accountId, {
    bool forUpdate = false,
  }) => db.queryOne(
    'SELECT account_id, kdf, salt, verifier_salt, verifier, wrapped_identity_key, '
    'failed_attempts, locked_until, updated_at FROM $s.passwords WHERE account_id = @a:uuid'
    '${forUpdate ? ' FOR UPDATE' : ''}',
    {'a': accountId},
  );

  Future<void> upsertPassword(
    SqlSession db, {
    required String accountId,
    required KdfParams kdf,
    required Uint8List salt,
    required Uint8List verifierSalt,
    required Uint8List verifier,
    required WrappedKey wrapped,
  }) async {
    await db.execute(
      'INSERT INTO $s.passwords (account_id, kdf, salt, verifier_salt, verifier, wrapped_identity_key) '
      'VALUES (@a:uuid, @k:jsonb, @s:bytea, @vs:bytea, @v:bytea, @w:jsonb) '
      'ON CONFLICT (account_id) DO UPDATE SET kdf = excluded.kdf, salt = excluded.salt, '
      'verifier_salt = excluded.verifier_salt, verifier = excluded.verifier, '
      'wrapped_identity_key = excluded.wrapped_identity_key, failed_attempts = 0, '
      'locked_until = NULL, updated_at = now()',
      {
        'a': accountId,
        'k': jsonEncode(kdf.toJson()),
        's': salt,
        'vs': verifierSalt,
        'v': verifier,
        'w': jsonEncode(wrapped.toJson()),
      },
    );
  }

  Future<void> deletePassword(SqlSession db, String accountId) async {
    await db.execute('DELETE FROM $s.passwords WHERE account_id = @a:uuid', {
      'a': accountId,
    });
  }

  Future<void> recordPasswordFailure(
    Tx tx,
    String accountId,
    int attempts,
    DateTime? lockedUntil,
  ) async {
    await tx.execute(
      'UPDATE $s.passwords SET failed_attempts = @n:int4, locked_until = @l:timestamptz '
      'WHERE account_id = @a:uuid',
      {'a': accountId, 'n': attempts, 'l': lockedUntil},
    );
  }

  Future<void> clearPasswordFailures(Tx tx, String accountId) async {
    await tx.execute(
      'UPDATE $s.passwords SET failed_attempts = 0, locked_until = NULL WHERE account_id = @a:uuid',
      {'a': accountId},
    );
  }

  // ----------------------------------------------------------------- invites

  Future<void> insertInvite(
    SqlSession db, {
    required String id,
    required Uint8List codeHash,
    required String issuer,
    required DateTime expiresAt,
  }) async {
    await db.execute(
      'INSERT INTO $s.invites (id, code_hash, issuer, expires_at) '
      'VALUES (@id:uuid, @h:bytea, @i:text, @e:timestamptz)',
      {'id': id, 'h': codeHash, 'i': issuer, 'e': expiresAt},
    );
  }

  Future<Row?> inviteByHash(SqlSession db, Uint8List codeHash) => db.queryOne(
    'SELECT id, expires_at, redeemed_at, cancelled_at FROM $s.invites WHERE code_hash = @h:bytea',
    {'h': codeHash},
  );

  /// Redeems atomically; false if it was used, cancelled, expired or unknown.
  Future<bool> redeemInvite(Tx tx, Uint8List codeHash, String accountId) async {
    final n = await tx.execute(
      'UPDATE $s.invites SET redeemed_at = now(), redeemed_by = @a:uuid '
      'WHERE code_hash = @h:bytea AND redeemed_at IS NULL AND cancelled_at IS NULL '
      'AND expires_at > now()',
      {'h': codeHash, 'a': accountId},
    );
    return n == 1;
  }

  // ---------------------------------------------------------- recovery codes

  Future<void> insertRecoveryCode(
    Tx tx, {
    required String id,
    required String accountId,
    required Uint8List codeHash,
    required DateTime expiresAt,
  }) async {
    await tx.execute(
      'UPDATE $s.recovery_codes SET used_at = now() WHERE account_id = @a:uuid AND used_at IS NULL',
      {'a': accountId},
    );
    await tx.execute(
      'INSERT INTO $s.recovery_codes (id, account_id, code_hash, expires_at) '
      'VALUES (@id:uuid, @a:uuid, @h:bytea, @e:timestamptz)',
      {'id': id, 'a': accountId, 'h': codeHash, 'e': expiresAt},
    );
  }

  Future<String?> validRecoveryAccount(
    SqlSession db,
    Uint8List codeHash,
  ) async {
    final r = await db.queryOne(
      'SELECT account_id FROM $s.recovery_codes WHERE code_hash = @h:bytea '
      'AND used_at IS NULL AND expires_at > now()',
      {'h': codeHash},
    );
    return r?.string('account_id');
  }

  Future<String?> consumeRecoveryCode(Tx tx, Uint8List codeHash) async {
    final r = await tx.queryOne(
      'UPDATE $s.recovery_codes SET used_at = now() WHERE code_hash = @h:bytea '
      'AND used_at IS NULL AND expires_at > now() RETURNING account_id',
      {'h': codeHash},
    );
    return r?.string('account_id');
  }

  Future<void> deleteRecoveryCodes(Tx tx, String accountId) async {
    await tx.execute(
      'DELETE FROM $s.recovery_codes WHERE account_id = @a:uuid',
      {'a': accountId},
    );
  }

  // -------------------------------------------------------- phone challenges

  Future<DateTime?> lastChallengeAt(SqlSession db, Uint8List phoneHash) async {
    final r = await db.queryOne(
      'SELECT max(created_at) AS at FROM $s.phone_challenges WHERE phone_hash = @h:bytea',
      {'h': phoneHash},
    );
    return r?.optTime('at');
  }

  Future<void> insertChallenge(
    SqlSession db, {
    required String id,
    required Uint8List phoneHash,
    required String purpose,
    required Uint8List codeHash,
    required String discoveryIndex,
    required String last4,
    required DateTime expiresAt,
  }) async {
    await db.execute(
      'INSERT INTO $s.phone_challenges (id, phone_hash, purpose, code_hash, discovery_index, '
      'last4, expires_at) VALUES (@id:uuid, @h:bytea, @p:text, @c:bytea, @dh:text, @l4:text, '
      '@e:timestamptz)',
      {
        'id': id,
        'h': phoneHash,
        'p': purpose,
        'c': codeHash,
        'dh': discoveryIndex,
        'l4': last4,
        'e': expiresAt,
      },
    );
  }

  Future<Row?> challengeForUpdate(Tx tx, String id) => tx.queryOne(
    'SELECT id, phone_hash, purpose, code_hash, discovery_index, last4, attempts, '
    'expires_at, consumed_at '
    'FROM $s.phone_challenges WHERE id = @id:uuid FOR UPDATE',
    {'id': id},
  );

  Future<void> challengeAttempt(
    Tx tx,
    String id, {
    required bool consumed,
  }) async {
    await tx.execute(
      'UPDATE $s.phone_challenges SET attempts = attempts + 1'
      '${consumed ? ', consumed_at = now()' : ''} WHERE id = @id:uuid',
      {'id': id},
    );
  }

  Future<int> purgeChallenges(SqlSession db) => db.execute(
    "DELETE FROM $s.phone_challenges WHERE created_at < now() - interval '2 days'",
  );

  // -------------------------------------------------------------- phone bans

  Future<bool> isBanned(SqlSession db, Uint8List phoneHash) async =>
      await db.queryOne(
        'SELECT 1 FROM $s.banned_phones WHERE phone_hash = @h:bytea',
        {'h': phoneHash},
      ) !=
      null;

  Future<void> ban(SqlSession db, Uint8List phoneHash) async {
    await db.execute(
      'INSERT INTO $s.banned_phones (phone_hash) VALUES (@h:bytea) ON CONFLICT DO NOTHING',
      {'h': phoneHash},
    );
  }
}
