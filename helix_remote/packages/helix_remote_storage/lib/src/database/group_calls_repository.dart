part of '../database.dart';

mixin RemoteGroupCallsRepository on HelixRemoteDatabaseBase {
  // ---------------------------------------------------------------------------
  // Call rooms
  // ---------------------------------------------------------------------------

  void upsertGroupCallRoom(CallRoom room) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO group_call_rooms
        (room_id, host_account_id, status, is_video, room_key_id,
         room_key_epoch, started_at, ended_at, synced_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(room_id) DO UPDATE SET
        status        = excluded.status,
        is_video      = excluded.is_video,
        room_key_id   = excluded.room_key_id,
        room_key_epoch= excluded.room_key_epoch,
        started_at    = excluded.started_at,
        ended_at      = excluded.ended_at,
        synced_at     = excluded.synced_at;
    ''');
    stmt.execute([
      room.roomId,
      room.hostAccountId,
      room.status.name.toUpperCase(),
      room.isVideo ? 1 : 0,
      room.roomKeyId,
      room.roomKeyEpoch,
      room.startedAt?.millisecondsSinceEpoch,
      room.endedAt?.millisecondsSinceEpoch,
      now,
    ]);
    stmt.close();

    // Upsert participants.
    final pStmt = _db.prepare('''
      INSERT INTO group_call_participants
        (room_id, account_id, device_id, role, status, is_screen_sharing, joined_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(room_id, device_id) DO UPDATE SET
        status           = excluded.status,
        is_screen_sharing= excluded.is_screen_sharing,
        joined_at        = excluded.joined_at;
    ''');
    for (final p in room.participants) {
      pStmt.execute([
        room.roomId,
        p.accountId,
        p.deviceId,
        p.role,
        p.status,
        p.isScreenSharing ? 1 : 0,
        p.joinedAt?.millisecondsSinceEpoch,
      ]);
    }
    pStmt.close();
  }

  CallRoom? getGroupCallRoom(String roomId) {
    final stmt = _db.prepare(
      'SELECT * FROM group_call_rooms WHERE room_id = ?;',
    );
    final rows = stmt.select([roomId]);
    stmt.close();
    if (rows.isEmpty) return null;
    final r = rows.first;

    final pStmt = _db.prepare(
      'SELECT * FROM group_call_participants WHERE room_id = ?;',
    );
    final pRows = pStmt.select([roomId]);
    pStmt.close();

    final participants = pRows.map((p) => CallRoomParticipant.fromJson({
      'account_id': p['account_id'],
      'device_id': p['device_id'],
      'role': p['role'],
      'status': p['status'],
      'is_screen_sharing': p['is_screen_sharing'],
      'joined_at': p['joined_at'],
    })).toList();

    return CallRoom.fromJson({
      'room_id': r['room_id'],
      'host_account_id': r['host_account_id'],
      'status': r['status'],
      'is_video': r['is_video'],
      'room_key_id': r['room_key_id'],
      'room_key_epoch': r['room_key_epoch'],
      'started_at': r['started_at'],
      'ended_at': r['ended_at'],
      'participants': participants.map((p) => {
        'account_id': p.accountId,
        'device_id': p.deviceId,
        'role': p.role,
        'status': p.status,
        'is_screen_sharing': p.isScreenSharing ? 1 : 0,
        'joined_at': p.joinedAt?.millisecondsSinceEpoch,
      }).toList(),
    });
  }

  void deleteGroupCallRoom(String roomId) {
    final stmt = _db.prepare(
      'DELETE FROM group_call_rooms WHERE room_id = ?;',
    );
    stmt.execute([roomId]);
    stmt.close();
    final pStmt = _db.prepare(
      'DELETE FROM group_call_participants WHERE room_id = ?;',
    );
    pStmt.execute([roomId]);
    pStmt.close();
  }

  // ---------------------------------------------------------------------------
  // Wrapped room keys (for local decryption)
  // ---------------------------------------------------------------------------

  void saveGroupCallWrappedKey({
    required String roomId,
    required int epoch,
    required String wrappedKey,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO group_call_wrapped_keys
        (room_id, epoch, wrapped_key, received_at)
      VALUES (?, ?, ?, ?);
    ''');
    stmt.execute([roomId, epoch, wrappedKey, now]);
    stmt.close();
  }

  String? getGroupCallWrappedKey({required String roomId, required int epoch}) {
    final stmt = _db.prepare(
      'SELECT wrapped_key FROM group_call_wrapped_keys WHERE room_id = ? AND epoch = ?;',
    );
    final rows = stmt.select([roomId, epoch]);
    stmt.close();
    if (rows.isEmpty) return null;
    return rows.first['wrapped_key'] as String?;
  }

  // ---------------------------------------------------------------------------
  // Call links
  // ---------------------------------------------------------------------------

  void upsertCallLink(CallLink link) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      INSERT INTO call_links_cache
        (link_id, link_token, room_id, requires_approval,
         max_uses, use_count, created_at, expires_at, synced_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(link_id) DO UPDATE SET
        room_id          = excluded.room_id,
        requires_approval= excluded.requires_approval,
        max_uses         = excluded.max_uses,
        use_count        = excluded.use_count,
        expires_at       = excluded.expires_at,
        synced_at        = excluded.synced_at;
    ''');
    stmt.execute([
      link.linkId,
      link.linkToken,
      link.roomId,
      link.requiresApproval ? 1 : 0,
      link.maxUses,
      link.useCount,
      link.createdAt.millisecondsSinceEpoch,
      link.expiresAt.millisecondsSinceEpoch,
      now,
    ]);
    stmt.close();
  }

  CallLink? getCallLink(String linkId) {
    final stmt = _db.prepare(
      'SELECT * FROM call_links_cache WHERE link_id = ?;',
    );
    final rows = stmt.select([linkId]);
    stmt.close();
    if (rows.isEmpty) return null;
    return _callLinkFromRow(rows.first);
  }

  List<CallLink> getActiveCallLinks() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      SELECT * FROM call_links_cache
      WHERE expires_at > ?
      ORDER BY created_at DESC;
    ''');
    final rows = stmt.select([now]);
    stmt.close();
    return rows.map(_callLinkFromRow).toList();
  }

  void deleteCallLink(String linkId) {
    final stmt = _db.prepare(
      'DELETE FROM call_links_cache WHERE link_id = ?;',
    );
    stmt.execute([linkId]);
    stmt.close();
  }

  CallLink _callLinkFromRow(Row r) => CallLink.fromJson({
    'link_id': r['link_id'],
    'link_token': r['link_token'],
    'room_id': r['room_id'],
    'requires_approval': r['requires_approval'],
    'max_uses': r['max_uses'],
    'use_count': r['use_count'],
    'created_at': r['created_at'],
    'expires_at': r['expires_at'],
  });

  // ---------------------------------------------------------------------------
  // Scheduled calls
  // ---------------------------------------------------------------------------

  void upsertScheduledCall(ScheduledCall sc, {String myRsvp = 'PENDING'}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final attendeesJson = jsonEncode(
      sc.attendees.map((a) => {
        'account_id': a.accountId,
        'rsvp_status': a.rsvpStatus.name.toUpperCase(),
      }).toList(),
    );
    final stmt = _db.prepare('''
      INSERT INTO scheduled_calls_cache
        (scheduled_call_id, host_account_id, title, room_id,
         scheduled_at, created_at, cancelled_at, my_rsvp, attendees_json, synced_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(scheduled_call_id) DO UPDATE SET
        title         = excluded.title,
        room_id       = excluded.room_id,
        scheduled_at  = excluded.scheduled_at,
        cancelled_at  = excluded.cancelled_at,
        my_rsvp       = excluded.my_rsvp,
        attendees_json= excluded.attendees_json,
        synced_at     = excluded.synced_at;
    ''');
    stmt.execute([
      sc.scheduledCallId,
      sc.hostAccountId,
      sc.title,
      sc.roomId,
      sc.scheduledAt.millisecondsSinceEpoch,
      sc.createdAt.millisecondsSinceEpoch,
      null,
      myRsvp,
      attendeesJson,
      now,
    ]);
    stmt.close();
  }

  ScheduledCall? getScheduledCall(String scheduledCallId) {
    final stmt = _db.prepare(
      'SELECT * FROM scheduled_calls_cache WHERE scheduled_call_id = ?;',
    );
    final rows = stmt.select([scheduledCallId]);
    stmt.close();
    if (rows.isEmpty) return null;
    return _scheduledCallFromRow(rows.first);
  }

  List<ScheduledCall> getUpcomingScheduledCalls() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      SELECT * FROM scheduled_calls_cache
      WHERE scheduled_at > ? AND cancelled_at IS NULL
      ORDER BY scheduled_at ASC
      LIMIT 50;
    ''');
    final rows = stmt.select([now]);
    stmt.close();
    return rows.map(_scheduledCallFromRow).toList();
  }

  void cancelScheduledCall(String scheduledCallId) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final stmt = _db.prepare('''
      UPDATE scheduled_calls_cache
      SET cancelled_at = ?
      WHERE scheduled_call_id = ?;
    ''');
    stmt.execute([now, scheduledCallId]);
    stmt.close();
  }

  void updateScheduledCallRsvp(String scheduledCallId, String rsvp) {
    final stmt = _db.prepare('''
      UPDATE scheduled_calls_cache
      SET my_rsvp = ?
      WHERE scheduled_call_id = ?;
    ''');
    stmt.execute([rsvp, scheduledCallId]);
    stmt.close();
  }

  ScheduledCall _scheduledCallFromRow(Row r) {
    final List<dynamic> rawAttendees =
        jsonDecode(r['attendees_json'] as String? ?? '[]') as List<dynamic>;
    final attendees = rawAttendees
        .whereType<Map<String, dynamic>>()
        .map(ScheduledCallAttendee.fromJson)
        .toList();
    return ScheduledCall(
      scheduledCallId: r['scheduled_call_id'] as String,
      hostAccountId: r['host_account_id'] as String,
      title: r['title'] as String,
      roomId: r['room_id'] as String?,
      scheduledAt: DateTime.fromMillisecondsSinceEpoch(r['scheduled_at'] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
      attendees: attendees,
    );
  }
}
