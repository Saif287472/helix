part of '../database.dart';

extension BackendGroupCallsRepository on BackendDatabase {
  // ---------------------------------------------------------------------------
  // Call rooms
  // ---------------------------------------------------------------------------

  void createCallRoom({
    required String roomId,
    required String hostAccountId,
    required String hostDeviceId,
    required bool isVideo,
    required int now,
  }) {
    _db.execute('BEGIN;');
    try {
      final roomStmt = _db.prepare('''
        INSERT INTO call_rooms
          (room_id, host_account_id, host_device_id, is_video, status, created_at)
        VALUES (?, ?, ?, ?, 'WAITING', ?);
      ''');
      roomStmt.execute([
        roomId,
        hostAccountId,
        hostDeviceId,
        isVideo ? 1 : 0,
        now,
      ]);
      roomStmt.close();
      final partStmt = _db.prepare('''
        INSERT INTO call_room_participants
          (room_id, account_id, device_id, role, status, joined_at)
        VALUES (?, ?, ?, 'HOST', 'JOINED', ?);
      ''');
      partStmt.execute([roomId, hostAccountId, hostDeviceId, now]);
      partStmt.close();
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Map<String, dynamic>? getCallRoom(String roomId) {
    final stmt = _db.prepare('SELECT * FROM call_rooms WHERE room_id = ?;');
    final rows = stmt.select([roomId]);
    stmt.close();
    if (rows.isEmpty) return null;
    final r = rows.first;
    return {
      'room_id': r['room_id'],
      'host_account_id': r['host_account_id'],
      'host_device_id': r['host_device_id'],
      'status': r['status'],
      'is_video': r['is_video'],
      'max_participants': r['max_participants'],
      'room_key_id': r['room_key_id'],
      'room_key_epoch': r['room_key_epoch'],
      'created_at': r['created_at'],
      'started_at': r['started_at'],
      'ended_at': r['ended_at'],
    };
  }

  List<Map<String, dynamic>> getCallRoomParticipants(String roomId) {
    final stmt = _db.prepare('''
      SELECT * FROM call_room_participants
      WHERE room_id = ?
      ORDER BY joined_at ASC;
    ''');
    final rows = stmt.select([roomId]);
    stmt.close();
    return rows
        .map(
          (r) => {
            'room_id': r['room_id'],
            'account_id': r['account_id'],
            'device_id': r['device_id'],
            'role': r['role'],
            'status': r['status'],
            'is_screen_sharing': r['is_screen_sharing'],
            'joined_at': r['joined_at'],
            'left_at': r['left_at'],
          },
        )
        .toList();
  }

  int countActiveParticipants(String roomId) {
    final stmt = _db.prepare('''
      SELECT COUNT(*) AS c FROM call_room_participants
      WHERE room_id = ? AND status = 'JOINED';
    ''');
    final rows = stmt.select([roomId]);
    stmt.close();
    return rows.first['c'] as int;
  }

  bool isRoomParticipant(String roomId, String deviceId) {
    final stmt = _db.prepare('''
      SELECT 1 FROM call_room_participants
      WHERE room_id = ? AND device_id = ? AND status IN ('INVITED','JOINED');
    ''');
    final rows = stmt.select([roomId, deviceId]);
    stmt.close();
    return rows.isNotEmpty;
  }

  bool joinCallRoom({
    required String roomId,
    required String accountId,
    required String deviceId,
    required int now,
  }) {
    // A join is only legal against a room that has not ended. The SQL below
    // would silently update zero rows for an ended room and still report
    // success, which is the exact failure mode the transition tables exist
    // to stop.
    final roomStatus = getCallRoom(roomId)?['status'] as String?;
    if (roomStatus == null) return false;
    if (roomStatus == RemoteCallRoomStatus.waiting) {
      RemoteCallRoomStatus.validateTransition(
        roomStatus,
        RemoteCallRoomStatus.active,
      );
    } else if (roomStatus != RemoteCallRoomStatus.active) {
      throw RemoteIllegalStatusTransitionException(
        'Cannot join a call room in status $roomStatus',
        from: roomStatus,
        to: RemoteCallRoomStatus.active,
      );
    }

    _db.execute('BEGIN;');
    try {
      final upsert = _db.prepare('''
        INSERT INTO call_room_participants
          (room_id, account_id, device_id, role, status, joined_at)
        VALUES (?, ?, ?, 'PARTICIPANT', 'JOINED', ?)
        ON CONFLICT(room_id, device_id) DO UPDATE SET
          status    = 'JOINED',
          joined_at = excluded.joined_at
        WHERE status = 'INVITED';
      ''');
      upsert.execute([roomId, accountId, deviceId, now]);
      upsert.close();
      final activate = _db.prepare('''
        UPDATE call_rooms SET status = 'ACTIVE', started_at = ?
        WHERE room_id = ? AND status = 'WAITING';
      ''');
      activate.execute([now, roomId]);
      activate.close();
      _db.execute('COMMIT;');
      return true;
    } catch (_) {
      _db.execute('ROLLBACK;');
      return false;
    }
  }

  void inviteToRoom({
    required String roomId,
    required String accountId,
    required String deviceId,
  }) {
    final stmt = _db.prepare('''
      INSERT OR IGNORE INTO call_room_participants
        (room_id, account_id, device_id, role, status)
      VALUES (?, ?, ?, 'PARTICIPANT', 'INVITED');
    ''');
    stmt.execute([roomId, accountId, deviceId]);
    stmt.close();
  }

  void leaveCallRoom({
    required String roomId,
    required String deviceId,
    required int now,
  }) {
    final stmt = _db.prepare('''
      UPDATE call_room_participants
      SET status = 'LEFT', left_at = ?
      WHERE room_id = ? AND device_id = ?;
    ''');
    stmt.execute([now, roomId, deviceId]);
    stmt.close();
    _maybeEndRoom(roomId, now);
  }

  void kickFromRoom({
    required String roomId,
    required String deviceId,
    required int now,
  }) {
    final stmt = _db.prepare('''
      UPDATE call_room_participants
      SET status = 'KICKED', left_at = ?
      WHERE room_id = ? AND device_id = ?;
    ''');
    stmt.execute([now, roomId, deviceId]);
    stmt.close();
  }

  void endCallRoom(String roomId, int now) {
    final current = getCallRoom(roomId)?['status'] as String?;
    // Ending an already-ended room is idempotent by design: both the host's
    // explicit end and the last participant leaving can land here, and
    // whichever arrives second must not fail. That is a no-op, not an
    // illegal transition, so it is checked before validating.
    if (current == null || RemoteCallRoomStatus.isTerminal(current)) return;
    RemoteCallRoomStatus.validateTransition(
      current,
      RemoteCallRoomStatus.ended,
    );
    final stmt = _db.prepare('''
      UPDATE call_rooms SET status = 'ENDED', ended_at = ?
      WHERE room_id = ? AND status != 'ENDED';
    ''');
    stmt.execute([now, roomId]);
    stmt.close();
  }

  void _maybeEndRoom(String roomId, int now) {
    if (countActiveParticipants(roomId) == 0) endCallRoom(roomId, now);
  }

  void setScreenSharing({
    required String roomId,
    required String deviceId,
    required bool active,
  }) {
    final stmt = _db.prepare('''
      UPDATE call_room_participants
      SET is_screen_sharing = ?
      WHERE room_id = ? AND device_id = ? AND status = 'JOINED';
    ''');
    stmt.execute([active ? 1 : 0, roomId, deviceId]);
    stmt.close();
  }

  // ---------------------------------------------------------------------------
  // Room keys
  // ---------------------------------------------------------------------------

  void upsertRoomKeyId({
    required String roomId,
    required String keyId,
    required int epoch,
  }) {
    final stmt = _db.prepare('''
      UPDATE call_rooms SET room_key_id = ?, room_key_epoch = ?
      WHERE room_id = ?;
    ''');
    stmt.execute([keyId, epoch, roomId]);
    stmt.close();
  }

  void saveWrappedRoomKey({
    required String roomId,
    required int epoch,
    required String deviceId,
    required String wrappedKey,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO call_room_keys
        (room_id, epoch, device_id, wrapped_key)
      VALUES (?, ?, ?, ?);
    ''');
    stmt.execute([roomId, epoch, deviceId, wrappedKey]);
    stmt.close();
  }

  void markRoomKeyDelivered({
    required String roomId,
    required int epoch,
    required String deviceId,
    required int now,
  }) {
    final stmt = _db.prepare('''
      UPDATE call_room_keys SET delivered_at = ?
      WHERE room_id = ? AND epoch = ? AND device_id = ?;
    ''');
    stmt.execute([now, roomId, epoch, deviceId]);
    stmt.close();
  }

  Map<String, dynamic>? getWrappedRoomKey({
    required String roomId,
    required int epoch,
    required String deviceId,
  }) {
    final stmt = _db.prepare('''
      SELECT wrapped_key, delivered_at FROM call_room_keys
      WHERE room_id = ? AND epoch = ? AND device_id = ?;
    ''');
    final rows = stmt.select([roomId, epoch, deviceId]);
    stmt.close();
    if (rows.isEmpty) return null;
    return {
      'wrapped_key': rows.first['wrapped_key'],
      'delivered_at': rows.first['delivered_at'],
    };
  }

  // ---------------------------------------------------------------------------
  // Call links
  // ---------------------------------------------------------------------------

  void createCallLink({
    required String linkId,
    required String linkToken,
    String? roomId,
    required String createdBy,
    required bool requiresApproval,
    required int maxUses,
    required int createdAt,
    required int expiresAt,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO call_links
        (link_id, link_token, room_id, created_by, requires_approval,
         max_uses, use_count, created_at, expires_at)
      VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?);
    ''');
    stmt.execute([
      linkId,
      linkToken,
      roomId,
      createdBy,
      requiresApproval ? 1 : 0,
      maxUses,
      createdAt,
      expiresAt,
    ]);
    stmt.close();
  }

  Map<String, dynamic>? getCallLinkByToken(String token) {
    final stmt = _db.prepare('SELECT * FROM call_links WHERE link_token = ?;');
    final rows = stmt.select([token]);
    stmt.close();
    if (rows.isEmpty) return null;
    final r = rows.first;
    return {
      'link_id': r['link_id'],
      'link_token': r['link_token'],
      'room_id': r['room_id'],
      'created_by': r['created_by'],
      'requires_approval': r['requires_approval'],
      'max_uses': r['max_uses'],
      'use_count': r['use_count'],
      'created_at': r['created_at'],
      'expires_at': r['expires_at'],
      'revoked_at': r['revoked_at'],
    };
  }

  bool incrementLinkUseCount(String linkId) {
    final stmt = _db.prepare('''
      UPDATE call_links SET use_count = use_count + 1
      WHERE link_id = ?
        AND (max_uses = 0 OR use_count < max_uses)
        AND revoked_at IS NULL;
    ''');
    stmt.execute([linkId]);
    final changed = _db.updatedRows == 1;
    stmt.close();
    return changed;
  }

  void revokeCallLink(String linkId, int now) {
    final stmt = _db.prepare(
      'UPDATE call_links SET revoked_at = ? WHERE link_id = ?;',
    );
    stmt.execute([now, linkId]);
    stmt.close();
  }

  List<Map<String, dynamic>> getCallLinksForAccount(String accountId) {
    final stmt = _db.prepare('''
      SELECT * FROM call_links
      WHERE created_by = ? AND revoked_at IS NULL
      ORDER BY created_at DESC LIMIT 50;
    ''');
    final rows = stmt.select([accountId]);
    stmt.close();
    return rows
        .map(
          (r) => {
            'link_id': r['link_id'],
            'link_token': r['link_token'],
            'room_id': r['room_id'],
            'requires_approval': r['requires_approval'],
            'max_uses': r['max_uses'],
            'use_count': r['use_count'],
            'created_at': r['created_at'],
            'expires_at': r['expires_at'],
          },
        )
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Scheduled calls
  // ---------------------------------------------------------------------------

  void createScheduledCall({
    required String scheduledCallId,
    required String hostAccountId,
    required String title,
    required int scheduledAt,
    required int createdAt,
    List<String> attendeeIds = const [],
  }) {
    _db.execute('BEGIN;');
    try {
      final stmt = _db.prepare('''
        INSERT INTO scheduled_calls
          (scheduled_call_id, host_account_id, title, scheduled_at, created_at)
        VALUES (?, ?, ?, ?, ?);
      ''');
      stmt.execute([
        scheduledCallId,
        hostAccountId,
        title,
        scheduledAt,
        createdAt,
      ]);
      stmt.close();
      final attStmt = _db.prepare('''
        INSERT OR IGNORE INTO scheduled_call_attendees
          (scheduled_call_id, account_id, rsvp_status)
        VALUES (?, ?, 'PENDING');
      ''');
      for (final aid in attendeeIds) {
        attStmt.execute([scheduledCallId, aid]);
      }
      attStmt.close();
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  Map<String, dynamic>? getScheduledCall(String scheduledCallId) {
    final stmt = _db.prepare(
      'SELECT * FROM scheduled_calls WHERE scheduled_call_id = ?;',
    );
    final rows = stmt.select([scheduledCallId]);
    stmt.close();
    if (rows.isEmpty) return null;
    final r = rows.first;
    return {
      'scheduled_call_id': r['scheduled_call_id'],
      'room_id': r['room_id'],
      'host_account_id': r['host_account_id'],
      'title': r['title'],
      'scheduled_at': r['scheduled_at'],
      'created_at': r['created_at'],
      'cancelled_at': r['cancelled_at'],
    };
  }

  List<Map<String, dynamic>> getScheduledCallsForAccount(
    String accountId,
    int afterMs,
  ) {
    final stmt = _db.prepare('''
      SELECT DISTINCT sc.*
      FROM scheduled_calls sc
      LEFT JOIN scheduled_call_attendees sa
        ON sa.scheduled_call_id = sc.scheduled_call_id
       AND sa.account_id = ?
      WHERE (sc.host_account_id = ? OR sa.account_id IS NOT NULL)
        AND sc.cancelled_at IS NULL
        AND sc.scheduled_at > ?
      ORDER BY sc.scheduled_at ASC LIMIT 50;
    ''');
    final rows = stmt.select([accountId, accountId, afterMs]);
    stmt.close();
    return rows
        .map(
          (r) => {
            'scheduled_call_id': r['scheduled_call_id'],
            'room_id': r['room_id'],
            'host_account_id': r['host_account_id'],
            'title': r['title'],
            'scheduled_at': r['scheduled_at'],
            'created_at': r['created_at'],
          },
        )
        .toList();
  }

  List<Map<String, dynamic>> getScheduledCallAttendees(String scheduledCallId) {
    final stmt = _db.prepare('''
      SELECT * FROM scheduled_call_attendees
      WHERE scheduled_call_id = ?;
    ''');
    final rows = stmt.select([scheduledCallId]);
    stmt.close();
    return rows
        .map(
          (r) => {
            'account_id': r['account_id'],
            'rsvp_status': r['rsvp_status'],
            'notified_at': r['notified_at'],
          },
        )
        .toList();
  }

  void rsvpScheduledCall({
    required String scheduledCallId,
    required String accountId,
    required String rsvpStatus,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO scheduled_call_attendees
        (scheduled_call_id, account_id, rsvp_status)
      VALUES (?, ?, ?)
      ON CONFLICT(scheduled_call_id, account_id) DO UPDATE SET
        rsvp_status = excluded.rsvp_status;
    ''');
    stmt.execute([scheduledCallId, accountId, rsvpStatus]);
    stmt.close();
  }

  void cancelScheduledCall(String scheduledCallId, int now) {
    final stmt = _db.prepare('''
      UPDATE scheduled_calls SET cancelled_at = ?
      WHERE scheduled_call_id = ? AND cancelled_at IS NULL;
    ''');
    stmt.execute([now, scheduledCallId]);
    stmt.close();
  }

  void linkRoomToScheduledCall({
    required String scheduledCallId,
    required String roomId,
  }) {
    final stmt = _db.prepare('''
      UPDATE scheduled_calls SET room_id = ?
      WHERE scheduled_call_id = ?;
    ''');
    stmt.execute([roomId, scheduledCallId]);
    stmt.close();
  }
}
