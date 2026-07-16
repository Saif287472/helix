part of '../database.dart';

class RemoteMediaDraft {
  const RemoteMediaDraft({
    required this.draftId,
    required this.conversationId,
    required this.kind,
    required this.status,
    required this.localPath,
    this.caption = '',
    this.durationMs = 0,
    this.waveform = const [],
    this.viewOnce = false,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  final String draftId;
  final String conversationId;
  final String kind;
  final String status;
  final String localPath;
  final String caption;
  final int durationMs;
  final List<int> waveform;
  final bool viewOnce;
  final int createdAt;
  final int updatedAt;
}

class RemoteMediaPlaybackState {
  const RemoteMediaPlaybackState({
    required this.messageId,
    required this.positionMs,
    required this.speed,
    required this.updatedAt,
  });

  final String messageId;
  final int positionMs;
  final double speed;
  final int updatedAt;
}

mixin RemoteMediaRepository on HelixRemoteDatabaseBase {
  void upsertMediaDraft(RemoteMediaDraft draft) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO media_drafts (
        draft_id,
        conversation_id,
        kind,
        status,
        local_path,
        caption,
        duration_ms,
        waveform_json,
        view_once,
        created_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      draft.draftId,
      draft.conversationId,
      draft.kind,
      draft.status,
      draft.localPath,
      draft.caption,
      draft.durationMs,
      jsonEncode(draft.waveform),
      draft.viewOnce ? 1 : 0,
      draft.createdAt,
      draft.updatedAt,
    ]);
    stmt.close();
  }

  List<RemoteMediaDraft> mediaDrafts(String conversationId) {
    final rows = _db.select(
      '''
      SELECT * FROM media_drafts
      WHERE conversation_id = ?
      ORDER BY updated_at DESC;
      ''',
      [conversationId],
    );
    return rows.map(_draftFromRow).toList();
  }

  RemoteMediaDraft? mediaDraft(String draftId) {
    final rows = _db.select('SELECT * FROM media_drafts WHERE draft_id = ?;', [
      draftId,
    ]);
    if (rows.isEmpty) return null;
    return _draftFromRow(rows.first);
  }

  void updateMediaDraftStatus({
    required String draftId,
    required String status,
    required int updatedAt,
  }) {
    final stmt = _db.prepare(
      'UPDATE media_drafts SET status = ?, updated_at = ? WHERE draft_id = ?;',
    );
    stmt.execute([status, updatedAt, draftId]);
    stmt.close();
  }

  void deleteMediaDraft(String draftId) {
    final stmt = _db.prepare('DELETE FROM media_drafts WHERE draft_id = ?;');
    stmt.execute([draftId]);
    stmt.close();
  }

  void savePlaybackState({
    required String messageId,
    required int positionMs,
    required double speed,
    required int updatedAt,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO media_playback_state (
        message_id,
        position_ms,
        speed,
        updated_at
      )
      VALUES (?, ?, ?, ?);
    ''');
    stmt.execute([messageId, positionMs, speed, updatedAt]);
    stmt.close();
  }

  RemoteMediaPlaybackState? playbackState(String messageId) {
    final rows = _db.select(
      'SELECT * FROM media_playback_state WHERE message_id = ?;',
      [messageId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return RemoteMediaPlaybackState(
      messageId: row['message_id'] as String,
      positionMs: row['position_ms'] as int,
      speed: (row['speed'] as num).toDouble(),
      updatedAt: row['updated_at'] as int,
    );
  }

  void saveMediaTransferPolicy({
    required String attachmentId,
    required bool backgroundAllowed,
    required int expiresAt,
    required int retryCount,
    required String status,
    required int updatedAt,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO media_transfer_policy (
        attachment_id,
        background_allowed,
        expires_at,
        retry_count,
        status,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      attachmentId,
      backgroundAllowed ? 1 : 0,
      expiresAt,
      retryCount,
      status,
      updatedAt,
    ]);
    stmt.close();
  }

  Map<String, dynamic>? mediaTransferPolicy(String attachmentId) {
    final rows = _db.select(
      'SELECT * FROM media_transfer_policy WHERE attachment_id = ?;',
      [attachmentId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return {
      'attachment_id': row['attachment_id'],
      'background_allowed': (row['background_allowed'] as int) != 0,
      'expires_at': row['expires_at'],
      'retry_count': row['retry_count'],
      'status': row['status'],
      'updated_at': row['updated_at'],
    };
  }

  RemoteMediaDraft _draftFromRow(Map<String, dynamic> row) {
    var waveform = const <int>[];
    try {
      final decoded = jsonDecode(row['waveform_json'] as String? ?? '[]');
      if (decoded is List) waveform = decoded.whereType<int>().toList();
    } catch (_) {}
    return RemoteMediaDraft(
      draftId: row['draft_id'] as String,
      conversationId: row['conversation_id'] as String,
      kind: row['kind'] as String,
      status: row['status'] as String,
      localPath: row['local_path'] as String,
      caption: row['caption'] as String? ?? '',
      durationMs: row['duration_ms'] as int? ?? 0,
      waveform: waveform,
      viewOnce: (row['view_once'] as int? ?? 0) != 0,
      createdAt: row['created_at'] as int? ?? 0,
      updatedAt: row['updated_at'] as int? ?? 0,
    );
  }
}
