part of '../remote_messaging_service.dart';

mixin RemotePersonalization
    on RemoteMessagingServiceBase, RemoteMessageSending {
  static const _emojiStickerMap = {
    '😀': 'smile',
    '😂': 'laugh',
    '❤️': 'heart',
    '👍': 'thumb',
    '🎉': 'party',
  };

  void saveThemePreference({
    required String scope,
    required String scopeId,
    required String mode,
    String colorSeed = '',
    String wallpaperAttachmentId = '',
    bool highContrast = false,
  }) {
    if (!{'system', 'light', 'dark'}.contains(mode)) {
      throw ArgumentError('Theme mode must be system, light, or dark');
    }
    db.saveThemePreference(
      RemoteThemePreference(
        scope: scope,
        scopeId: scopeId,
        mode: mode,
        colorSeed: colorSeed,
        wallpaperAttachmentId: wallpaperAttachmentId,
        highContrast: highContrast,
        updatedAt: _clock().millisecondsSinceEpoch,
      ),
    );
  }

  RemoteThemePreference? themePreference(String scope, String scopeId) =>
      db.themePreference(scope, scopeId);

  bool themeContrastAllowed({
    required int foreground,
    required int background,
  }) {
    int channel(int color, int shift) => (color >> shift) & 0xff;
    final fg =
        (channel(foreground, 16) * 299 +
            channel(foreground, 8) * 587 +
            channel(foreground, 0) * 114) /
        1000;
    final bg =
        (channel(background, 16) * 299 +
            channel(background, 8) * 587 +
            channel(background, 0) * 114) /
        1000;
    return (fg - bg).abs() >= 125;
  }

  Future<void> saveAboutNote({
    required String note,
    required String audience,
    Duration? ttl,
    String? noteId,
  }) async {
    final accountId = _requireAccountId();
    final now = _clock().millisecondsSinceEpoch;
    final encrypted = await protector.encryptText(
      conversationId: 'profile:$accountId',
      messageId: noteId ?? 'about_$now',
      plaintext: note,
      recipientDeviceId: 'local-profile',
    );
    db.saveAboutNote(
      RemoteAboutNote(
        noteId: noteId ?? 'about_$now',
        accountId: accountId,
        encryptedText: encrypted,
        audience: audience,
        expiresAt: ttl == null ? 0 : now + ttl.inMilliseconds,
        updatedAt: now,
      ),
    );
  }

  RemoteAboutNote? aboutNote(String accountId) =>
      db.aboutNote(accountId, _clock().millisecondsSinceEpoch);

  void saveProfileImage({
    required String attachmentId,
    required String thumbnailAttachmentId,
    required String audience,
    required int cacheVersion,
  }) {
    db.saveProfileImage(
      accountId: _requireAccountId(),
      attachmentId: attachmentId,
      thumbnailAttachmentId: thumbnailAttachmentId,
      audience: audience,
      cacheVersion: cacheVersion,
      updatedAt: _clock().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic>? profileImage(String accountId) =>
      db.profileImage(accountId);

  void upsertStickerPack({
    required String packId,
    required String title,
    Map<String, dynamic> manifest = const {},
  }) {
    db.upsertStickerPack(
      packId: packId,
      title: title,
      manifestJson: jsonEncode(manifest),
      createdAt: _clock().millisecondsSinceEpoch,
    );
  }

  void upsertSticker({
    required String stickerId,
    required String packId,
    required String kind,
    required String attachmentId,
    String emoji = '',
    String tags = '',
    required int sizeBytes,
    int durationMs = 0,
  }) {
    db.upsertSticker(
      RemoteStickerRecord(
        stickerId: stickerId,
        packId: packId,
        kind: kind,
        attachmentId: attachmentId,
        emoji: emoji,
        tags: tags,
        sizeBytes: sizeBytes,
        durationMs: durationMs,
        favorite: false,
        recentAt: 0,
        createdAt: _clock().millisecondsSinceEpoch,
      ),
    );
  }

  List<RemoteStickerRecord> searchStickers(String query) =>
      db.searchStickers(query);

  void favoriteSticker(String stickerId, {required bool favorite}) =>
      db.markStickerFavorite(stickerId, favorite);

  List<RemoteStickerRecord> recentStickers() => db.recentStickers();

  List<RemoteStickerRecord> stickerSuggestionsForEmoji(String emoji) {
    final term = _emojiStickerMap[emoji] ?? emoji;
    return db.searchStickers(term, limit: 6);
  }

  Future<String> sendSticker({
    required String conversationId,
    required String stickerId,
    required String keyDeliverySecret,
    required List<String> recipientDeviceIds,
    String? messageId,
  }) async {
    final sticker = db.sticker(stickerId);
    if (sticker == null) throw StateError('Unknown sticker');
    final attachment = db.getAttachment(sticker.attachmentId);
    if (attachment == null) throw StateError('Missing sticker attachment');
    final content = RemoteStickerContent(
      stickerId: sticker.stickerId,
      packId: sticker.packId,
      kind: sticker.kind,
      emoji: sticker.emoji,
      altText: sticker.tags,
      attachment: RemoteAttachmentContent(
        fileId: sticker.attachmentId,
        filename: attachment['filename'] as String,
        fileSize: attachment['size_bytes'] as int,
        fileHash: sticker.attachmentId,
        mimeType: sticker.kind == 'animated' ? 'image/gif' : 'image/webp',
        keyDeliverySecret: keyDeliverySecret,
      ),
    );
    final sent = await _sendContent(
      conversationId: conversationId,
      messagePlaintext: content.toPlaintext(),
      recipientDeviceIds: recipientDeviceIds,
      messageId: messageId,
      privacy: _privacyForOutgoingContent(conversationId),
    );
    db.markStickerRecent(stickerId, _clock().millisecondsSinceEpoch);
    return sent;
  }
}
