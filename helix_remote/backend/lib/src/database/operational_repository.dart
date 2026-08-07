part of '../database.dart';

extension BackendOperationalRepository on BackendDatabase {
  T runInTransaction<T>(T Function() operation) {
    final name = 'helix_tx_${_transactionDepth++}';
    _db.execute('SAVEPOINT $name;');
    try {
      final result = operation();
      _db.execute('RELEASE SAVEPOINT $name;');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK TO SAVEPOINT $name;');
      _db.execute('RELEASE SAVEPOINT $name;');
      rethrow;
    } finally {
      _transactionDepth--;
    }
  }

  void close() {
    _db.close();
  }

  int get schemaVersion {
    final rows = _db.select('PRAGMA user_version;');
    return rows.first.columnAt(0) as int;
  }

  Set<String> _tableColumns(String table) {
    return _db
        .select("PRAGMA table_info('$table');")
        .map((row) => row['name'] as String)
        .toSet();
  }

  bool quickCheckOk() {
    final rows = _db.select('PRAGMA quick_check;');
    return rows.isNotEmpty && rows.first.columnAt(0) == 'ok';
  }

  Map<String, int> getOperationalTableCounts() {
    const tables = [
      'accounts',
      'devices',
      'conversations',
      'conversation_members',
      'messages',
      'attachments',
      'backups',
      'audit_logs',
      'reports',
      'groups',
      'group_invites',
      'turn_credential_log',
    ];
    return {
      for (final table in tables) table: _countRows(table),
      'outbox': _retryableOutboxCount(),
    };
  }

  int _retryableOutboxCount() {
    final rows = _db.select('''
      SELECT COUNT(*) AS count
      FROM outbox
      WHERE status = 'PENDING' OR (status = 'FAILED' AND retries < 5);
    ''');
    return rows.first['count'] as int;
  }

  Map<String, int> getOperationalMailboxStats() {
    final rows = _db.select('''
      SELECT
        COUNT(*) AS message_count,
        COALESCE(MAX(timestamp), 0) AS newest_message_at,
        COALESCE(MIN(timestamp), 0) AS oldest_message_at
      FROM messages;
    ''');
    final row = rows.first;
    return {
      'message_count': row['message_count'] as int,
      'newest_message_at': row['newest_message_at'] as int,
      'oldest_message_at': row['oldest_message_at'] as int,
    };
  }

  Map<String, int> getOperationalAttachmentStats() {
    final rows = _db.select('''
      SELECT
        COUNT(*) AS object_count,
        COALESCE(SUM(file_size), 0) AS total_bytes,
        COALESCE(SUM(CASE WHEN status = 'COMPLETED' THEN 1 ELSE 0 END), 0)
          AS completed,
        COALESCE(SUM(CASE WHEN status != 'COMPLETED' THEN 1 ELSE 0 END), 0)
          AS incomplete
      FROM attachments;
    ''');
    final row = rows.first;
    return {
      'object_count': row['object_count'] as int,
      'total_bytes': row['total_bytes'] as int,
      'completed': row['completed'] as int,
      'incomplete': row['incomplete'] as int,
    };
  }

  Map<String, int> getOutboxStatusCounts() {
    final rows = _db.select('''
      SELECT status, COUNT(*) AS count
      FROM outbox
      GROUP BY status;
    ''');
    final counts = <String, int>{
      'PENDING': 0,
      'FAILED': 0,
      'COMPLETED': 0,
      'DLQ': 0,
    };
    for (final row in rows) {
      counts[row['status'] as String] = row['count'] as int;
    }
    return counts;
  }

  Map<String, int> purgeOperationalRecords({
    required int completedOutboxOlderThan,
    required int auditOlderThan,
    required int tombstonesOlderThan,
  }) {
    return runInTransaction(() {
      final purgedOutbox = _deleteWhereCount(
        'outbox',
        "status = 'COMPLETED' AND created_at < ?",
        [completedOutboxOlderThan],
      );
      final purgedAudit = _deleteWhereCount('audit_logs', 'timestamp < ?', [
        auditOlderThan,
      ]);
      final purgedTombstones = _deleteWhereCount(
        'tombstones',
        'deleted_at < ?',
        [tombstonesOlderThan],
      );
      return {
        'outbox': purgedOutbox,
        'audit_logs': purgedAudit,
        'tombstones': purgedTombstones,
      };
    });
  }

  Map<String, dynamic>? getOutboxEvent(String eventId) {
    final stmt = _db.prepare('SELECT * FROM outbox WHERE event_id = ?;');
    final rows = stmt.select([eventId]);
    stmt.close();
    if (rows.isEmpty) return null;
    final row = rows.first;
    return {
      'event_id': row['event_id'],
      'type': row['type'],
      'status': row['status'],
      'retries': row['retries'],
      'created_at': row['created_at'],
    };
  }

  int _countRows(String table) {
    final rows = _db.select('SELECT COUNT(*) AS count FROM $table;');
    return rows.first['count'] as int;
  }
}
