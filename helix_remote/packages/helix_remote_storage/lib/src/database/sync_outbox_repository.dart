part of '../database.dart';

mixin RemoteSyncOutboxRepository on HelixRemoteDatabaseBase {
  // ---------------------------------------------------------------------------
  // Cursors
  // ---------------------------------------------------------------------------

  void updateSyncCursor(String conversationId, int lastSequence) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO sync_cursors (conversation_id, last_sequence)
      VALUES (?, ?);
    ''');
    stmt.execute([conversationId, lastSequence]);
    stmt.close();
  }

  int getSyncCursor(String conversationId) {
    final stmt = _db.prepare(
      'SELECT last_sequence FROM sync_cursors WHERE conversation_id = ?;',
    );
    final res = stmt.select([conversationId]);
    stmt.close();
    if (res.isEmpty) return 0;
    return res.first['last_sequence'] as int;
  }

  bool hasProcessedEventId(String eventId) {
    final stmt = _db.prepare(
      'SELECT 1 FROM processed_event_ids WHERE event_id = ?;',
    );
    final res = stmt.select([eventId]);
    stmt.close();
    return res.isNotEmpty;
  }

  void saveProcessedEvent({
    required String eventId,
    required int serverSequence,
    required String eventType,
    required String contentFingerprint,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO processed_event_ids (
        event_id,
        server_sequence,
        event_type,
        content_fingerprint,
        processed_at
      )
      VALUES (?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      eventId,
      serverSequence,
      eventType,
      contentFingerprint,
      DateTime.now().millisecondsSinceEpoch,
    ]);
    stmt.close();
  }

  // P4-04: Quarantine an inbound event that failed parsing or application.
  // The event is recorded so operators can inspect it; it does NOT advance
  // the sync cursor.
  void saveQuarantinedEvent({
    required String eventId,
    required int serverSequence,
    required String eventType,
    required String rawPayload,
    required String failureReason,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO quarantine_events (
        event_id,
        server_sequence,
        event_type,
        raw_payload,
        failure_reason,
        quarantined_at
      )
      VALUES (?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      eventId,
      serverSequence,
      eventType,
      rawPayload,
      failureReason,
      DateTime.now().millisecondsSinceEpoch,
    ]);
    stmt.close();
  }

  List<Map<String, dynamic>> getQuarantinedEvents() {
    final stmt = _db.prepare(
      'SELECT * FROM quarantine_events ORDER BY server_sequence ASC;',
    );
    final res = stmt.select();
    stmt.close();
    return res
        .map(
          (row) => {
            'event_id': row['event_id'],
            'server_sequence': row['server_sequence'],
            'event_type': row['event_type'],
            'raw_payload': row['raw_payload'],
            'failure_reason': row['failure_reason'],
            'quarantined_at': row['quarantined_at'],
          },
        )
        .toList();
  }

  bool isQuarantinedEventId(String eventId) {
    final stmt = _db.prepare(
      'SELECT 1 FROM quarantine_events WHERE event_id = ?;',
    );
    final res = stmt.select([eventId]);
    stmt.close();
    return res.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // Pending operation queue
  // ---------------------------------------------------------------------------

  /// Enqueue an outbound operation. [idempotencyKey] is a stable server-visible
  /// ID that prevents duplicate delivery if the same operation is retried.
  @override
  void enqueueOperation(
    String opId,
    String type,
    String payload, {
    String idempotencyKey = '',
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT OR IGNORE INTO pending_operations (op_id, idempotency_key, type, payload, status, retries, created_at, next_attempt_at)
      VALUES (?, ?, ?, ?, 'PENDING', 0, ?, ?);
    ''');
    stmt.execute([opId, idempotencyKey, type, payload, now, now]);
    stmt.close();
  }

  /// Returns operations that are due for execution now.
  List<Map<String, dynamic>> getPendingOperations() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      SELECT * FROM pending_operations
      WHERE (status = 'PENDING' OR status = 'FAILED')
        AND retries < 5
        AND next_attempt_at <= ?
      ORDER BY created_at ASC;
    ''');
    final res = stmt.select([now]);
    stmt.close();
    return res
        .map(
          (row) => {
            'op_id': row['op_id'],
            'idempotency_key': row['idempotency_key'],
            'type': row['type'],
            'payload': row['payload'],
            'status': row['status'],
            'retries': row['retries'],
            'created_at': row['created_at'],
            'next_attempt_at': row['next_attempt_at'],
          },
        )
        .toList();
  }

  /// Returns the raw state of a single pending operation, or null if not found.
  /// Useful for diagnostics and tests. Does NOT filter by [next_attempt_at].
  Map<String, dynamic>? getOperationById(String opId) {
    final stmt = _db.prepare(
      'SELECT * FROM pending_operations WHERE op_id = ?;',
    );
    final res = stmt.select([opId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'op_id': row['op_id'],
      'idempotency_key': row['idempotency_key'],
      'type': row['type'],
      'payload': row['payload'],
      'status': row['status'],
      'retries': row['retries'],
      'created_at': row['created_at'],
      'next_attempt_at': row['next_attempt_at'],
    };
  }

  List<Map<String, dynamic>> getOutboxOperations() {
    final stmt = _db.prepare('''
      SELECT * FROM pending_operations
      WHERE status != 'COMPLETED'
      ORDER BY created_at ASC;
    ''');
    final res = stmt.select();
    stmt.close();
    return res
        .map(
          (row) => {
            'op_id': row['op_id'],
            'idempotency_key': row['idempotency_key'],
            'type': row['type'],
            'status': row['status'],
            'retries': row['retries'],
            'created_at': row['created_at'],
            'next_attempt_at': row['next_attempt_at'],
          },
        )
        .toList();
  }

  void updateOperationStatus(String opId, String status, int retries) {
    final stmt = _db.prepare(
      'UPDATE pending_operations SET status = ?, retries = ? WHERE op_id = ?;',
    );
    stmt.execute([status, retries, opId]);
    stmt.close();
  }

  void retryOperationNow(String opId) {
    final stmt = _db.prepare('''
      UPDATE pending_operations
      SET status = 'PENDING', retries = 0, next_attempt_at = ?
      WHERE op_id = ? AND status = 'FAILED';
    ''');
    stmt.execute([DateTime.now().millisecondsSinceEpoch, opId]);
    stmt.close();
  }

  /// Persist the next retry deadline for an operation.
  /// [nextAttemptAt] is milliseconds since epoch; caller computes backoff + jitter.
  void scheduleNextOperationAttempt(String opId, int nextAttemptAt) {
    final stmt = _db.prepare(
      'UPDATE pending_operations SET next_attempt_at = ? WHERE op_id = ?;',
    );
    stmt.execute([nextAttemptAt, opId]);
    stmt.close();
  }

  /// Deletes all non-completed pending operations. Called on logout so stale
  /// outbox entries from a previous session do not surface on next sign-in.
  void clearPendingOperations() {
    _db.execute(
      "DELETE FROM pending_operations WHERE status IN ('PENDING', 'FAILED');",
    );
  }

  Map<String, int> purgeOperationalRecords({
    required int completedOperationsOlderThan,
    required int tombstonesOlderThan,
    required int quarantineOlderThan,
  }) {
    _db.execute('SAVEPOINT purge_operational_records;');
    try {
      final purgedOperations = _deleteWhereCount(
        'pending_operations',
        "status = 'COMPLETED' AND created_at < ?",
        [completedOperationsOlderThan],
      );
      final purgedTombstones = _deleteWhereCount(
        'tombstones',
        'deleted_at < ?',
        [tombstonesOlderThan],
      );
      final purgedQuarantine = _deleteWhereCount(
        'quarantine_events',
        'quarantined_at < ?',
        [quarantineOlderThan],
      );
      _db.execute('RELEASE SAVEPOINT purge_operational_records;');
      return {
        'pending_operations': purgedOperations,
        'tombstones': purgedTombstones,
        'quarantine_events': purgedQuarantine,
      };
    } catch (_) {
      _db.execute('ROLLBACK TO SAVEPOINT purge_operational_records;');
      _db.execute('RELEASE SAVEPOINT purge_operational_records;');
      rethrow;
    }
  }

  int _deleteWhereCount(String table, String where, List<Object?> args) {
    final before = _countRows(table);
    final stmt = _db.prepare('DELETE FROM $table WHERE $where;');
    stmt.execute(args);
    stmt.close();
    return before - _countRows(table);
  }

  int _countRows(String table) {
    final rows = _db.select('SELECT COUNT(*) AS count FROM $table;');
    return rows.first['count'] as int;
  }
}
