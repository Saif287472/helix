part of '../database.dart';

class RemotePollResults {
  const RemotePollResults({required this.pollId, required this.counts});

  final String pollId;
  final Map<String, int> counts;
}

class RemoteEventReminder {
  const RemoteEventReminder({
    required this.reminderId,
    required this.eventId,
    required this.conversationId,
    required this.remindAt,
    required this.encryptedNote,
    required this.status,
    required this.updatedAt,
  });

  final String reminderId;
  final String eventId;
  final String conversationId;
  final int remindAt;
  final String encryptedNote;
  final String status;
  final int updatedAt;
}

class RemoteLiveLocationSession {
  const RemoteLiveLocationSession({
    required this.sessionId,
    required this.conversationId,
    required this.messageId,
    required this.startedAt,
    required this.expiresAt,
    required this.updateIntervalMs,
    required this.status,
    required this.lastUpdateAt,
  });

  final String sessionId;
  final String conversationId;
  final String messageId;
  final int startedAt;
  final int expiresAt;
  final int updateIntervalMs;
  final String status;
  final int lastUpdateAt;
}

mixin RemoteCollaborationRepository on HelixRemoteDatabaseBase {
  void savePollVote({
    required String pollId,
    required String accountId,
    required List<String> optionIds,
    required String encryptedPayload,
    required String signature,
    required int updatedAt,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO poll_votes (
        poll_id,
        account_id,
        option_ids_json,
        encrypted_payload,
        signature,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      pollId,
      accountId,
      jsonEncode(optionIds),
      encryptedPayload,
      signature,
      updatedAt,
    ]);
    stmt.close();
  }

  List<String> pollVoteForAccount(String pollId, String accountId) {
    final rows = _db.select(
      'SELECT option_ids_json FROM poll_votes WHERE poll_id = ? AND account_id = ?;',
      [pollId, accountId],
    );
    if (rows.isEmpty) return const [];
    try {
      final decoded = jsonDecode(rows.first['option_ids_json'] as String);
      if (decoded is List) return decoded.whereType<String>().toList();
    } catch (_) {}
    return const [];
  }

  RemotePollResults pollResults(String pollId) {
    final counts = <String, int>{};
    final rows = _db.select(
      'SELECT option_ids_json FROM poll_votes WHERE poll_id = ?;',
      [pollId],
    );
    for (final row in rows) {
      try {
        final decoded = jsonDecode(row['option_ids_json'] as String);
        if (decoded is! List) continue;
        for (final optionId in decoded.whereType<String>()) {
          counts[optionId] = (counts[optionId] ?? 0) + 1;
        }
      } catch (_) {}
    }
    return RemotePollResults(pollId: pollId, counts: counts);
  }

  void saveEventRsvp({
    required String eventId,
    required String accountId,
    required String state,
    required bool plusOne,
    required String encryptedPayload,
    required int updatedAt,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO event_rsvps (
        event_id,
        account_id,
        state,
        plus_one,
        encrypted_payload,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      eventId,
      accountId,
      state,
      plusOne ? 1 : 0,
      encryptedPayload,
      updatedAt,
    ]);
    stmt.close();
  }

  Map<String, String> eventRsvpStates(String eventId) {
    final rows = _db.select(
      'SELECT account_id, state FROM event_rsvps WHERE event_id = ?;',
      [eventId],
    );
    return {
      for (final row in rows)
        row['account_id'] as String: row['state'] as String,
    };
  }

  void saveEventReminder(RemoteEventReminder reminder) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO event_reminders (
        reminder_id,
        event_id,
        conversation_id,
        remind_at,
        encrypted_note,
        status,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      reminder.reminderId,
      reminder.eventId,
      reminder.conversationId,
      reminder.remindAt,
      reminder.encryptedNote,
      reminder.status,
      reminder.updatedAt,
    ]);
    stmt.close();
  }

  List<RemoteEventReminder> dueEventReminders(int nowMs) {
    final rows = _db.select(
      '''
      SELECT * FROM event_reminders
      WHERE status = 'scheduled' AND remind_at <= ?
      ORDER BY remind_at ASC;
      ''',
      [nowMs],
    );
    return rows.map(_reminderFromRow).toList();
  }

  void updateEventReminderStatus(
    String reminderId,
    String status,
    int updatedAt,
  ) {
    final stmt = _db.prepare(
      'UPDATE event_reminders SET status = ?, updated_at = ? WHERE reminder_id = ?;',
    );
    stmt.execute([status, updatedAt, reminderId]);
    stmt.close();
  }

  void saveLiveLocationSession(RemoteLiveLocationSession session) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO live_location_sessions (
        session_id,
        conversation_id,
        message_id,
        started_at,
        expires_at,
        update_interval_ms,
        status,
        last_update_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      session.sessionId,
      session.conversationId,
      session.messageId,
      session.startedAt,
      session.expiresAt,
      session.updateIntervalMs,
      session.status,
      session.lastUpdateAt,
    ]);
    stmt.close();
  }

  RemoteLiveLocationSession? liveLocationSession(String sessionId) {
    final rows = _db.select(
      'SELECT * FROM live_location_sessions WHERE session_id = ?;',
      [sessionId],
    );
    if (rows.isEmpty) return null;
    return _sessionFromRow(rows.first);
  }

  void saveLiveLocationUpdate({
    required String sessionId,
    required int latitudeE7,
    required int longitudeE7,
    required int accuracyMeters,
    required int createdAt,
    required String encryptedPayload,
  }) {
    final stmt = _db.prepare('''
      INSERT INTO live_location_updates (
        session_id,
        latitude_e7,
        longitude_e7,
        accuracy_meters,
        created_at,
        encrypted_payload
      )
      VALUES (?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      sessionId,
      latitudeE7,
      longitudeE7,
      accuracyMeters,
      createdAt,
      encryptedPayload,
    ]);
    stmt.close();
    final updateSession = _db.prepare(
      'UPDATE live_location_sessions SET last_update_at = ? WHERE session_id = ?;',
    );
    updateSession.execute([createdAt, sessionId]);
    updateSession.close();
  }

  List<Map<String, dynamic>> liveLocationUpdates(String sessionId) {
    final rows = _db.select(
      '''
      SELECT * FROM live_location_updates
      WHERE session_id = ?
      ORDER BY created_at ASC;
      ''',
      [sessionId],
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void stopLiveLocationSession(String sessionId, int stoppedAt) {
    final stmt = _db.prepare('''
      UPDATE live_location_sessions
      SET status = 'stopped', last_update_at = ?
      WHERE session_id = ?;
    ''');
    stmt.execute([stoppedAt, sessionId]);
    stmt.close();
  }

  int expireLiveLocationSessions(int nowMs) {
    final stmt = _db.prepare('''
      UPDATE live_location_sessions
      SET status = 'expired'
      WHERE status = 'active' AND expires_at <= ?;
    ''');
    stmt.execute([nowMs]);
    final count = _db.updatedRows;
    stmt.close();
    return count;
  }

  RemoteEventReminder _reminderFromRow(Map<String, dynamic> row) {
    return RemoteEventReminder(
      reminderId: row['reminder_id'] as String,
      eventId: row['event_id'] as String,
      conversationId: row['conversation_id'] as String,
      remindAt: row['remind_at'] as int,
      encryptedNote: row['encrypted_note'] as String,
      status: row['status'] as String,
      updatedAt: row['updated_at'] as int,
    );
  }

  RemoteLiveLocationSession _sessionFromRow(Map<String, dynamic> row) {
    return RemoteLiveLocationSession(
      sessionId: row['session_id'] as String,
      conversationId: row['conversation_id'] as String,
      messageId: row['message_id'] as String,
      startedAt: row['started_at'] as int,
      expiresAt: row['expires_at'] as int,
      updateIntervalMs: row['update_interval_ms'] as int,
      status: row['status'] as String,
      lastUpdateAt: row['last_update_at'] as int,
    );
  }
}
