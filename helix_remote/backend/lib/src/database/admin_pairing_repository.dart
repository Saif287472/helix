part of '../database.dart';

extension BackendAdminPairingRepository on BackendDatabase {
  void createAdminPairingCode({
    required String codeHash,
    required int createdAt,
    required int expiresAt,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO admin_pairing_codes (code_hash, created_at, expires_at)
      VALUES (?, ?, ?);
    ''');
    stmt.execute([codeHash, createdAt, expiresAt]);
    stmt.close();
  }

  /// Atomically marks the code redeemed iff it exists, hasn't already been
  /// redeemed, and hasn't expired - returns whether the redemption took
  /// effect, so two concurrent redeem attempts for the same code can't both
  /// succeed.
  bool redeemAdminPairingCode({required String codeHash, required int now}) {
    final stmt = _db.prepare('''
      UPDATE admin_pairing_codes
      SET redeemed_at = ?
      WHERE code_hash = ? AND redeemed_at IS NULL AND expires_at > ?;
    ''');
    stmt.execute([now, codeHash, now]);
    final changed = _db.updatedRows;
    stmt.close();
    return changed == 1;
  }
}
