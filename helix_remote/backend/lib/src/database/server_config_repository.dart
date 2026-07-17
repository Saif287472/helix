part of '../database.dart';

extension BackendServerConfigRepository on BackendDatabase {
  String? getServerConfig(String key) {
    final stmt = _db.prepare('SELECT value FROM server_configuration WHERE key = ?;');
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

  List<Map<String, dynamic>> getAllUsersPaginated({
    required int limit,
    required int offset,
  }) {
    final stmt = _db.prepare('''
      SELECT account_id, username, created_at, status
      FROM accounts
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?;
    ''');
    final result = stmt.select([limit, offset]);
    stmt.close();
    return result.map((row) => {
      'account_id': row['account_id'] as String,
      'username': row['username'] as String,
      'created_at': row['created_at'] as int,
      'status': row['status'] as String,
    }).toList();
  }
  void vacuumInto(String path) {
    final stmt = _db.prepare('VACUUM INTO ?;');
    stmt.execute([path]);
    stmt.close();
  }
}
