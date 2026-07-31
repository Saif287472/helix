part of '../database.dart';

extension BackendPhoneOtpRepository on BackendDatabase {
  void createOtpChallenge({
    required String challengeId,
    required String phoneHash,
    required String codeHash,
    required String purpose,
    required int createdAt,
    required int expiresAt,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO phone_otp_challenges (
        challenge_id, phone_hash, code_hash, purpose, attempts,
        created_at, expires_at, consumed_at
      ) VALUES (?, ?, ?, ?, 0, ?, ?, NULL);
    ''');
    stmt.execute([
      challengeId,
      phoneHash,
      codeHash,
      purpose,
      createdAt,
      expiresAt,
    ]);
    stmt.close();
  }

  /// The most recently issued OTP challenge for a phone hash, regardless of
  /// whether it has already been consumed or has expired — callers are
  /// responsible for checking `consumed_at`/`expires_at`.
  Map<String, dynamic>? getLatestOtpChallenge(String phoneHash) {
    final stmt = _db.prepare('''
      SELECT challenge_id, phone_hash, code_hash, purpose, attempts,
             created_at, expires_at, consumed_at
      FROM phone_otp_challenges
      WHERE phone_hash = ?
      ORDER BY created_at DESC
      LIMIT 1;
    ''');
    final result = stmt.select([phoneHash]);
    stmt.close();
    if (result.isEmpty) return null;
    final row = result.first;
    return {
      'challenge_id': row['challenge_id'],
      'phone_hash': row['phone_hash'],
      'code_hash': row['code_hash'],
      'purpose': row['purpose'],
      'attempts': row['attempts'],
      'created_at': row['created_at'],
      'expires_at': row['expires_at'],
      'consumed_at': row['consumed_at'],
    };
  }

  void incrementOtpAttempts(String challengeId) {
    final stmt = _db.prepare(
      'UPDATE phone_otp_challenges SET attempts = attempts + 1 WHERE challenge_id = ?;',
    );
    stmt.execute([challengeId]);
    stmt.close();
  }

  void markOtpConsumed(String challengeId, int consumedAt) {
    final stmt = _db.prepare(
      'UPDATE phone_otp_challenges SET consumed_at = ? WHERE challenge_id = ?;',
    );
    stmt.execute([consumedAt, challengeId]);
    stmt.close();
  }
}
