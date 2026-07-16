part of '../database.dart';

mixin RemoteTombstonesCallsRepository on HelixRemoteDatabaseBase {
  // ---------------------------------------------------------------------------
  // Tombstones
  // ---------------------------------------------------------------------------

  @override
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

  // ---------------------------------------------------------------------------
  // Call history (P15-013)
  // ---------------------------------------------------------------------------

  void saveCallHistory({
    required String callId,
    required String peerId,
    String? peerAccountId,
    String? peerDeviceId,
    required bool isVideo,
    required String direction,
    String? outcome,
    required int durationSeconds,
    required int timestamp,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO call_history (
        call_id,
        peer_id,
        peer_account_id,
        peer_device_id,
        is_video,
        direction,
        outcome,
        duration,
        timestamp
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      callId,
      peerId,
      peerAccountId ?? peerId,
      peerDeviceId,
      isVideo ? 1 : 0,
      direction,
      outcome ?? _defaultCallOutcome(direction, durationSeconds),
      durationSeconds,
      timestamp,
    ]);
    stmt.close();
  }

  List<Map<String, dynamic>> getCallHistory({int limit = 50}) {
    final stmt = _db.prepare('''
      SELECT * FROM call_history ORDER BY timestamp DESC LIMIT ?;
    ''');
    final res = stmt.select([limit]);
    stmt.close();
    return res
        .map(
          (row) => {
            'call_id': row['call_id'],
            'peer_id': row['peer_id'],
            'peer_account_id': row['peer_account_id'],
            'peer_device_id': row['peer_device_id'],
            'is_video': row['is_video'],
            'direction': row['direction'],
            'outcome': row['outcome'],
            'duration': row['duration'],
            'timestamp': row['timestamp'],
          },
        )
        .toList();
  }

  void clearCallHistory() {
    _db.execute('DELETE FROM call_history');
  }

  String _defaultCallOutcome(String direction, int durationSeconds) {
    if (durationSeconds > 0) return 'completed';
    if (direction == 'MISSED') return 'missed';
    return direction.toLowerCase();
  }

  // ---------------------------------------------------------------------------
  // Active call marker for crash recovery (P15-008)
  // ---------------------------------------------------------------------------

  void setActiveCallMarker({
    required String callId,
    required String peerId,
    String? peerAccountId,
    String? peerDeviceId,
    required bool isVideo,
    required int startedAt,
  }) {
    _db.execute('DELETE FROM active_call;');
    final stmt = _db.prepare('''
      INSERT INTO active_call (
        call_id,
        peer_id,
        peer_account_id,
        peer_device_id,
        is_video,
        started_at
      )
      VALUES (?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      callId,
      peerId,
      peerAccountId ?? peerId,
      peerDeviceId,
      isVideo ? 1 : 0,
      startedAt,
    ]);
    stmt.close();
  }

  Map<String, dynamic>? getActiveCallMarker() {
    final res = _db.select('SELECT * FROM active_call LIMIT 1;');
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'call_id': row['call_id'],
      'peer_id': row['peer_id'],
      'peer_account_id': row['peer_account_id'],
      'peer_device_id': row['peer_device_id'],
      'is_video': row['is_video'],
      'started_at': row['started_at'],
    };
  }

  void clearActiveCallMarker() {
    _db.execute('DELETE FROM active_call;');
  }
}
