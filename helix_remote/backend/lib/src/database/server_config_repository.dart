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

  void vacuumInto(String path) {
    final stmt = _db.prepare('VACUUM INTO ?;');
    stmt.execute([path]);
    stmt.close();
  }
}
