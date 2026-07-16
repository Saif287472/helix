part of '../database.dart';

class RemoteThemePreference {
  const RemoteThemePreference({
    required this.scope,
    required this.scopeId,
    required this.mode,
    this.colorSeed = '',
    this.wallpaperAttachmentId = '',
    this.highContrast = false,
    required this.updatedAt,
  });

  final String scope;
  final String scopeId;
  final String mode;
  final String colorSeed;
  final String wallpaperAttachmentId;
  final bool highContrast;
  final int updatedAt;
}

class RemoteAboutNote {
  const RemoteAboutNote({
    required this.noteId,
    required this.accountId,
    required this.encryptedText,
    required this.audience,
    required this.expiresAt,
    required this.updatedAt,
  });

  final String noteId;
  final String accountId;
  final String encryptedText;
  final String audience;
  final int expiresAt;
  final int updatedAt;
}

class RemoteStickerRecord {
  const RemoteStickerRecord({
    required this.stickerId,
    required this.packId,
    required this.kind,
    required this.attachmentId,
    required this.emoji,
    required this.tags,
    required this.sizeBytes,
    required this.durationMs,
    required this.favorite,
    required this.recentAt,
    required this.createdAt,
  });

  final String stickerId;
  final String packId;
  final String kind;
  final String attachmentId;
  final String emoji;
  final String tags;
  final int sizeBytes;
  final int durationMs;
  final bool favorite;
  final int recentAt;
  final int createdAt;
}

mixin RemotePersonalizationRepository on HelixRemoteDatabaseBase {
  void saveThemePreference(RemoteThemePreference pref) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO theme_preferences (
        scope,
        scope_id,
        mode,
        color_seed,
        wallpaper_attachment_id,
        high_contrast,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      pref.scope,
      pref.scopeId,
      pref.mode,
      pref.colorSeed,
      pref.wallpaperAttachmentId,
      pref.highContrast ? 1 : 0,
      pref.updatedAt,
    ]);
    stmt.close();
  }

  RemoteThemePreference? themePreference(String scope, String scopeId) {
    final rows = _db.select(
      'SELECT * FROM theme_preferences WHERE scope = ? AND scope_id = ?;',
      [scope, scopeId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return RemoteThemePreference(
      scope: row['scope'] as String,
      scopeId: row['scope_id'] as String,
      mode: row['mode'] as String,
      colorSeed: row['color_seed'] as String? ?? '',
      wallpaperAttachmentId: row['wallpaper_attachment_id'] as String? ?? '',
      highContrast: (row['high_contrast'] as int? ?? 0) != 0,
      updatedAt: row['updated_at'] as int,
    );
  }

  void saveAboutNote(RemoteAboutNote note) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO profile_about_notes (
        note_id,
        account_id,
        encrypted_text,
        audience,
        expires_at,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      note.noteId,
      note.accountId,
      note.encryptedText,
      note.audience,
      note.expiresAt,
      note.updatedAt,
    ]);
    stmt.close();
  }

  RemoteAboutNote? aboutNote(String accountId, int nowMs) {
    final rows = _db.select(
      '''
      SELECT * FROM profile_about_notes
      WHERE account_id = ? AND (expires_at = 0 OR expires_at > ?)
      ORDER BY updated_at DESC
      LIMIT 1;
      ''',
      [accountId, nowMs],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return RemoteAboutNote(
      noteId: row['note_id'] as String,
      accountId: row['account_id'] as String,
      encryptedText: row['encrypted_text'] as String,
      audience: row['audience'] as String,
      expiresAt: row['expires_at'] as int,
      updatedAt: row['updated_at'] as int,
    );
  }

  void saveProfileImage({
    required String accountId,
    required String attachmentId,
    required String thumbnailAttachmentId,
    required String audience,
    required int cacheVersion,
    required int updatedAt,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO profile_images (
        account_id,
        attachment_id,
        thumbnail_attachment_id,
        audience,
        cache_version,
        updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      accountId,
      attachmentId,
      thumbnailAttachmentId,
      audience,
      cacheVersion,
      updatedAt,
    ]);
    stmt.close();
  }

  Map<String, dynamic>? profileImage(String accountId) {
    final rows = _db.select(
      'SELECT * FROM profile_images WHERE account_id = ?;',
      [accountId],
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  void upsertStickerPack({
    required String packId,
    required String title,
    required String manifestJson,
    required int createdAt,
  }) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO sticker_packs (
        pack_id,
        title,
        manifest_json,
        created_at
      )
      VALUES (?, ?, ?, ?);
    ''');
    stmt.execute([packId, title, manifestJson, createdAt]);
    stmt.close();
  }

  void upsertSticker(RemoteStickerRecord sticker) {
    if (sticker.sizeBytes > 512 * 1024) {
      throw ArgumentError('Sticker exceeds the 512KB safety limit');
    }
    if (sticker.kind == 'animated' && sticker.durationMs > 3000) {
      throw ArgumentError('Animated stickers must be 3 seconds or shorter');
    }
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO stickers (
        sticker_id,
        pack_id,
        kind,
        attachment_id,
        emoji,
        tags,
        size_bytes,
        duration_ms,
        favorite,
        recent_at,
        created_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    ''');
    stmt.execute([
      sticker.stickerId,
      sticker.packId,
      sticker.kind,
      sticker.attachmentId,
      sticker.emoji,
      sticker.tags,
      sticker.sizeBytes,
      sticker.durationMs,
      sticker.favorite ? 1 : 0,
      sticker.recentAt,
      sticker.createdAt,
    ]);
    stmt.close();
  }

  RemoteStickerRecord? sticker(String stickerId) {
    final rows = _db.select('SELECT * FROM stickers WHERE sticker_id = ?;', [
      stickerId,
    ]);
    if (rows.isEmpty) return null;
    return _stickerFromRow(rows.first);
  }

  List<RemoteStickerRecord> searchStickers(String query, {int limit = 30}) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];
    final rows = _db.select(
      '''
      SELECT * FROM stickers
      WHERE lower(tags || ' ' || emoji) LIKE ?
      ORDER BY favorite DESC, recent_at DESC, created_at DESC
      LIMIT ?;
      ''',
      ['%$normalized%', limit],
    );
    return rows.map(_stickerFromRow).toList();
  }

  void markStickerFavorite(String stickerId, bool favorite) {
    final stmt = _db.prepare(
      'UPDATE stickers SET favorite = ? WHERE sticker_id = ?;',
    );
    stmt.execute([favorite ? 1 : 0, stickerId]);
    stmt.close();
  }

  void markStickerRecent(String stickerId, int recentAt) {
    final stmt = _db.prepare(
      'UPDATE stickers SET recent_at = ? WHERE sticker_id = ?;',
    );
    stmt.execute([recentAt, stickerId]);
    stmt.close();
  }

  List<RemoteStickerRecord> recentStickers({int limit = 12}) {
    final rows = _db.select(
      'SELECT * FROM stickers WHERE recent_at > 0 ORDER BY recent_at DESC LIMIT ?;',
      [limit],
    );
    return rows.map(_stickerFromRow).toList();
  }

  RemoteStickerRecord _stickerFromRow(Map<String, dynamic> row) {
    return RemoteStickerRecord(
      stickerId: row['sticker_id'] as String,
      packId: row['pack_id'] as String,
      kind: row['kind'] as String,
      attachmentId: row['attachment_id'] as String,
      emoji: row['emoji'] as String? ?? '',
      tags: row['tags'] as String? ?? '',
      sizeBytes: row['size_bytes'] as int,
      durationMs: row['duration_ms'] as int,
      favorite: (row['favorite'] as int? ?? 0) != 0,
      recentAt: row['recent_at'] as int,
      createdAt: row['created_at'] as int,
    );
  }
}
