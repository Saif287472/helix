part of '../database.dart';

extension BackendCallsRepository on BackendDatabase {
  void createPendingCall({
    required String callId,
    required String callerAccountId,
    required String callerDeviceId,
    required String calleeAccountId,
    required bool isVideo,
    String? offerSdp,
    required int createdAt,
    required int expiresAt,
    required List<String> targetDeviceIds,
  }) {
    _db.execute('BEGIN TRANSACTION;');
    try {
      final callStmt = _db.prepare('''
        INSERT INTO pending_calls (
          call_id,
          caller_account_id,
          caller_device_id,
          callee_account_id,
          is_video,
          offer_sdp,
          status,
          created_at,
          expires_at
        )
        VALUES (?, ?, ?, ?, ?, ?, 'RINGING', ?, ?);
      ''');
      callStmt.execute([
        callId,
        callerAccountId,
        callerDeviceId,
        calleeAccountId,
        isVideo ? 1 : 0,
        offerSdp,
        createdAt,
        expiresAt,
      ]);
      callStmt.close();

      final deviceStmt = _db.prepare('''
        INSERT INTO pending_call_devices (
          call_id,
          target_device_id,
          status,
          created_at,
          updated_at
        )
        VALUES (?, ?, 'RINGING', ?, ?);
      ''');
      for (final deviceId in targetDeviceIds) {
        deviceStmt.execute([callId, deviceId, createdAt, createdAt]);
      }
      deviceStmt.close();
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Map<String, dynamic>? getPendingCall(String callId) {
    final stmt = _db.prepare('SELECT * FROM pending_calls WHERE call_id = ?;');
    final res = stmt.select([callId]);
    stmt.close();
    if (res.isEmpty) return null;
    final row = res.first;
    return {
      'call_id': row['call_id'],
      'caller_account_id': row['caller_account_id'],
      'caller_device_id': row['caller_device_id'],
      'callee_account_id': row['callee_account_id'],
      'is_video': row['is_video'],
      'offer_sdp': row['offer_sdp'],
      'status': row['status'],
      'created_at': row['created_at'],
      'expires_at': row['expires_at'],
      'answered_by_device_id': row['answered_by_device_id'],
    };
  }

  List<String> getPendingCallTargetDevices(String callId) {
    final stmt = _db.prepare('''
      SELECT target_device_id FROM pending_call_devices
      WHERE call_id = ?
      ORDER BY target_device_id ASC;
    ''');
    final res = stmt.select([callId]);
    stmt.close();
    return res.map((row) => row['target_device_id'] as String).toList();
  }

  List<Map<String, dynamic>> getPendingCallsForDevice({
    required String accountId,
    required String deviceId,
    required int now,
  }) {
    final stmt = _db.prepare('''
      SELECT c.*
      FROM pending_calls c
      JOIN pending_call_devices d ON d.call_id = c.call_id
      WHERE c.callee_account_id = ?
        AND d.target_device_id = ?
        AND c.status = 'RINGING'
        AND d.status = 'RINGING'
        AND c.expires_at > ?
      ORDER BY c.created_at ASC;
    ''');
    final res = stmt.select([accountId, deviceId, now]);
    stmt.close();
    return res
        .map(
          (row) => {
            'call_id': row['call_id'],
            'caller_account_id': row['caller_account_id'],
            'caller_device_id': row['caller_device_id'],
            'callee_account_id': row['callee_account_id'],
            'is_video': row['is_video'],
            'offer_sdp': row['offer_sdp'],
            'status': row['status'],
            'created_at': row['created_at'],
            'expires_at': row['expires_at'],
            'answered_by_device_id': row['answered_by_device_id'],
          },
        )
        .toList();
  }

  int countActivePendingCallsForAccount({
    required String accountId,
    required int now,
  }) {
    final stmt = _db.prepare('''
      SELECT COUNT(*) AS count
      FROM pending_calls
      WHERE (caller_account_id = ? OR callee_account_id = ?)
        AND status IN ('RINGING', 'ANSWERED')
        AND expires_at > ?;
    ''');
    final res = stmt.select([accountId, accountId, now]);
    stmt.close();
    return res.first['count'] as int;
  }

  bool markPendingCallAnswered({
    required String callId,
    required String targetDeviceId,
    required int now,
  }) {
    final call = getPendingCall(callId);
    if (call == null ||
        call['status'] != 'RINGING' ||
        (call['expires_at'] as int) <= now ||
        !getPendingCallTargetDevices(callId).contains(targetDeviceId)) {
      return false;
    }

    _db.execute('BEGIN TRANSACTION;');
    try {
      final updateCall = _db.prepare('''
        UPDATE pending_calls
        SET status = 'ANSWERED', answered_by_device_id = ?
        WHERE call_id = ? AND status = 'RINGING' AND expires_at > ?;
      ''');
      updateCall.execute([targetDeviceId, callId, now]);
      final changed = _db.updatedRows;
      updateCall.close();
      if (changed != 1) {
        _db.execute('ROLLBACK;');
        return false;
      }

      final accepted = _db.prepare('''
        UPDATE pending_call_devices
        SET status = 'ANSWERED', updated_at = ?
        WHERE call_id = ? AND target_device_id = ?;
      ''');
      accepted.execute([now, callId, targetDeviceId]);
      accepted.close();

      final siblings = _db.prepare('''
        UPDATE pending_call_devices
        SET status = 'ANSWERED_ELSEWHERE', updated_at = ?
        WHERE call_id = ? AND target_device_id != ?;
      ''');
      siblings.execute([now, callId, targetDeviceId]);
      siblings.close();

      _db.execute('COMMIT;');
      return true;
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  void markPendingCallTerminal({
    required String callId,
    required String status,
    required int now,
  }) {
    final callStmt = _db.prepare('''
      UPDATE pending_calls
      SET status = ?, offer_sdp = NULL
      WHERE call_id = ?;
    ''');
    callStmt.execute([status, callId]);
    callStmt.close();

    final deviceStmt = _db.prepare('''
      UPDATE pending_call_devices
      SET status = ?, updated_at = ?
      WHERE call_id = ?;
    ''');
    deviceStmt.execute([status, now, callId]);
    deviceStmt.close();
  }

  int purgeTerminalPendingCalls(int olderThan) {
    final stmt = _db.prepare('''
      DELETE FROM pending_calls
      WHERE status NOT IN ('RINGING', 'ANSWERED') AND expires_at < ?;
    ''');
    stmt.execute([olderThan]);
    final count = _db.updatedRows;
    stmt.close();
    return count;
  }

  bool rememberCallSignalRequest({
    required String callId,
    required String senderDeviceId,
    required String requestId,
    required int createdAt,
  }) {
    final stmt = _db.prepare('''
      INSERT OR IGNORE INTO call_signal_requests (
        call_id,
        sender_device_id,
        request_id,
        created_at
      )
      VALUES (?, ?, ?, ?);
    ''');
    stmt.execute([callId, senderDeviceId, requestId, createdAt]);
    final inserted = _db.updatedRows == 1;
    stmt.close();
    return inserted;
  }

  int expirePendingCalls(int now) {
    final stmt = _db.prepare('''
      UPDATE pending_calls
      SET status = 'EXPIRED'
      WHERE status = 'RINGING' AND expires_at <= ?;
    ''');
    stmt.execute([now]);
    final count = _db.updatedRows;
    stmt.close();

    final deviceStmt = _db.prepare('''
      UPDATE pending_call_devices
      SET status = 'EXPIRED', updated_at = ?
      WHERE call_id IN (
        SELECT call_id FROM pending_calls WHERE status = 'EXPIRED'
      ) AND status = 'RINGING';
    ''');
    deviceStmt.execute([now]);
    deviceStmt.close();
    return count;
  }

  int purgeOldCallSignalRequests(int olderThan) {
    final stmt = _db.prepare('''
      DELETE FROM call_signal_requests
      WHERE created_at < ?;
    ''');
    stmt.execute([olderThan]);
    final count = _db.updatedRows;
    stmt.close();
    return count;
  }

  // ---------------------------------------------------------------------------
  // F7: Push token management
  // ---------------------------------------------------------------------------

  void upsertPushToken({
    required String tokenId,
    required String accountId,
    required String deviceId,
    required String pushToken,
    required String tokenType,
    required int now,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO device_push_tokens
        (token_id, account_id, device_id, push_token, token_type, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(device_id) DO UPDATE SET
        push_token = excluded.push_token,
        token_type = excluded.token_type,
        updated_at = excluded.updated_at;
    ''');
    stmt.execute([tokenId, accountId, deviceId, pushToken, tokenType, now, now]);
    stmt.close();
  }

  void deletePushToken({required String deviceId}) {
    final stmt = _db.prepare(
      'DELETE FROM device_push_tokens WHERE device_id = ?;',
    );
    stmt.execute([deviceId]);
    stmt.close();
  }

  List<Map<String, dynamic>> getPushTokensForAccount(String accountId) {
    final stmt = _db.prepare('''
      SELECT token_id, device_id, push_token, token_type, updated_at
      FROM device_push_tokens
      WHERE account_id = ?
      ORDER BY updated_at DESC;
    ''');
    final rows = stmt.select([accountId]);
    stmt.close();
    return rows
        .map(
          (r) => {
            'token_id': r['token_id'],
            'device_id': r['device_id'],
            'push_token': r['push_token'],
            'token_type': r['token_type'],
            'updated_at': r['updated_at'],
          },
        )
        .toList();
  }

  Map<String, dynamic>? getPushTokenForDevice(String deviceId) {
    final stmt = _db.prepare('''
      SELECT token_id, push_token, token_type, updated_at
      FROM device_push_tokens WHERE device_id = ?;
    ''');
    final rows = stmt.select([deviceId]);
    stmt.close();
    if (rows.isEmpty) return null;
    final r = rows.first;
    return {
      'token_id': r['token_id'],
      'push_token': r['push_token'],
      'token_type': r['token_type'],
      'updated_at': r['updated_at'],
    };
  }

  // ---------------------------------------------------------------------------
  // F7: Privacy-safe call metrics
  // ---------------------------------------------------------------------------

  void saveCallMetrics({
    required String metricId,
    required String callId,
    required String accountId,
    required String deviceId,
    String? connectionType,
    int? setupTimeMs,
    int reconnectCount = 0,
    double? packetLossPercent,
    double? peerRttMs,
    String? callOutcome,
    int durationSeconds = 0,
    required int recordedAt,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO call_metrics (
        metric_id, call_id, account_id, device_id,
        connection_type, setup_time_ms, reconnect_count,
        packet_loss_percent, peer_rtt_ms, call_outcome,
        duration_seconds, recorded_at
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?);
    ''');
    stmt.execute([
      metricId,
      callId,
      accountId,
      deviceId,
      connectionType,
      setupTimeMs,
      reconnectCount,
      packetLossPercent,
      peerRttMs,
      callOutcome,
      durationSeconds,
      recordedAt,
    ]);
    stmt.close();
  }
}
