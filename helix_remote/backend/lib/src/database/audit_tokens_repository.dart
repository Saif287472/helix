part of '../database.dart';

int _auditLogNonce = 0;

extension BackendAuditTokensRepository on BackendDatabase {
  // Audit Logs
  void logAudit(
    String? accountId,
    String? deviceId,
    String action,
    String? clientIp,
    String? userAgent,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final uuid =
        '${DateTime.now().microsecondsSinceEpoch}_${_auditLogNonce++}_${action.hashCode}_${(accountId ?? "system").hashCode}';
    final stmt = _db.prepare('''
      INSERT INTO audit_logs (event_id, account_id, device_id, action, client_ip, user_agent, timestamp)
      VALUES (?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      uuid,
      accountId,
      deviceId,
      action,
      _redactClientIp(clientIp),
      userAgent == null ? null : 'redacted',
      now,
    ]);
    stmt.close();
  }

  List<Map<String, dynamic>> getAuditLogs({String? accountId}) {
    final rows = accountId == null
        ? _db.select('SELECT * FROM audit_logs ORDER BY timestamp DESC;')
        : _db.select(
            'SELECT * FROM audit_logs WHERE account_id = ? ORDER BY timestamp DESC;',
            [accountId],
          );
    return rows
        .map(
          (row) => {
            'event_id': row['event_id'],
            'account_id': row['account_id'],
            'device_id': row['device_id'],
            'action': row['action'],
            'client_ip': row['client_ip'],
            'user_agent': row['user_agent'],
            'timestamp': row['timestamp'],
          },
        )
        .toList();
  }

  List<Map<String, dynamic>> _selectWhere(
    String table,
    String where,
    List<Object?> args,
  ) {
    final stmt = _db.prepare('SELECT * FROM $table WHERE $where;');
    final rows = stmt.select(args);
    stmt.close();
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void _deleteWhere(String table, String where, List<Object?> args) {
    final stmt = _db.prepare('DELETE FROM $table WHERE $where;');
    stmt.execute(args);
    stmt.close();
  }

  int _deleteWhereCount(String table, String where, List<Object?> args) {
    final before = _countRows(table);
    _deleteWhere(table, where, args);
    return before - _countRows(table);
  }

  bool _containsForbiddenPayloadKey(String payload) {
    final decoded = jsonDecode(payload);
    const forbiddenKeys = {
      'plaintext',
      'message_text',
      'body',
      'content',
      'filename',
      'backup_key',
      'passphrase',
      'recovery_phrase',
      'token',
    };

    bool scan(Object? value) {
      if (value is Map) {
        for (final entry in value.entries) {
          final key = entry.key.toString().toLowerCase();
          if (forbiddenKeys.contains(key)) return true;
          if (scan(entry.value)) return true;
        }
      } else if (value is List) {
        return value.any(scan);
      }
      return false;
    }

    return scan(decoded);
  }

  String? _redactClientIp(String? clientIp) {
    if (clientIp == null || clientIp.isEmpty) return null;
    if (clientIp.contains(':')) return 'ipv6:redacted';
    final parts = clientIp.split('.');
    if (parts.length == 4) {
      return '${parts[0]}.${parts[1]}.${parts[2]}.0';
    }
    return 'redacted';
  }

  // Refresh Tokens (P10-003)
  void saveRefreshToken({
    required String tokenHash,
    required String accountId,
    required String deviceId,
    required int expiresAt,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO refresh_tokens (token_hash, account_id, device_id, expires_at, revoked)
      VALUES (?, ?, ?, ?, 0);
    ''');
    stmt.execute([tokenHash, accountId, deviceId, expiresAt]);
    stmt.close();
  }

  Map<String, dynamic>? getRefreshToken(String tokenHash) {
    final stmt = _db.prepare(
      'SELECT * FROM refresh_tokens WHERE token_hash = ?;',
    );
    final res = stmt.select([tokenHash]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'token_hash': row['token_hash'],
      'account_id': row['account_id'],
      'device_id': row['device_id'],
      'expires_at': row['expires_at'],
      'revoked': row['revoked'],
    };
  }

  void revokeRefreshToken(String tokenHash) {
    final stmt = _db.prepare(
      'UPDATE refresh_tokens SET revoked = 1 WHERE token_hash = ?;',
    );
    stmt.execute([tokenHash]);
    stmt.close();
  }

  void revokeAllRefreshTokensForDevice(String accountId, String deviceId) {
    final stmt = _db.prepare(
      'UPDATE refresh_tokens SET revoked = 1 WHERE account_id = ? AND device_id = ?;',
    );
    stmt.execute([accountId, deviceId]);
    stmt.close();
  }

  // Tombstones (P10-018)
  void saveTombstone(String itemId, String type) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO tombstones (item_id, type, deleted_at)
      VALUES (?, ?, ?);
    ''');
    stmt.execute([itemId, type, now]);
    stmt.close();
  }

  bool isTombstoned(String itemId, String type) {
    final stmt = _db.prepare(
      'SELECT 1 FROM tombstones WHERE item_id = ? AND type = ?;',
    );
    final res = stmt.select([itemId, type]);
    stmt.close();
    return res.isNotEmpty;
  }

  // Quotas / Backpressure (P10-021)
  int getMessageCountForDevice(String deviceId) {
    final stmt = _db.prepare(
      'SELECT COUNT(*) FROM messages WHERE recipient_device_id = ?;',
    );
    final res = stmt.select([deviceId]);
    stmt.close();
    if (res.isEmpty) return 0;
    return res.first.columnAt(0) as int;
  }

  // ---------------------------------------------------------------------------
  // TURN credential log (P15-004, P15-005, P15-018)
  // ---------------------------------------------------------------------------

  void logTurnCredential({
    required String logId,
    required String accountId,
    String? deviceId,
    required int issuedAt,
    required int expiresAt,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO turn_credential_log (log_id, account_id, device_id, issued_at, expires_at)
      VALUES (?, ?, ?, ?, ?);
    ''');
    stmt.execute([logId, accountId, deviceId, issuedAt, expiresAt]);
    stmt.close();
  }

  /// Returns the number of TURN credentials issued to [accountId] in the last hour.
  int getTurnCredentialCountLastHour(String accountId) {
    final since = DateTime.now().millisecondsSinceEpoch - 3600000;
    final stmt = _db.prepare('''
      SELECT COUNT(*) FROM turn_credential_log
      WHERE account_id = ? AND issued_at >= ?;
    ''');
    final res = stmt.select([accountId, since]);
    stmt.close();
    if (res.isEmpty) return 0;
    return res.first.columnAt(0) as int;
  }

  int getTurnCredentialCountLastHourForDevice(String deviceId) {
    final since = DateTime.now().millisecondsSinceEpoch - 3600000;
    final stmt = _db.prepare('''
      SELECT COUNT(*) FROM turn_credential_log
      WHERE device_id = ? AND issued_at >= ?;
    ''');
    final res = stmt.select([deviceId, since]);
    stmt.close();
    if (res.isEmpty) return 0;
    return res.first.columnAt(0) as int;
  }

  int purgeExpiredTurnCredentialLogs(int now) {
    final before = _countRows('turn_credential_log');
    _deleteWhere('turn_credential_log', 'expires_at < ?', [now]);
    return before - _countRows('turn_credential_log');
  }

  // ---------------------------------------------------------------------------
}
