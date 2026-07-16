part of '../database.dart';

class RemoteAppLockSettings {
  const RemoteAppLockSettings({
    required this.enabled,
    required this.relockAfterSeconds,
    required this.useBiometric,
    this.pinVerifier,
    this.recoveryBehavior = 'require_recovery_secret',
  });

  final bool enabled;
  final int relockAfterSeconds;
  final bool useBiometric;
  final String? pinVerifier;
  final String recoveryBehavior;

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'relock_after_seconds': relockAfterSeconds,
    'use_biometric': useBiometric,
    if (pinVerifier != null) 'pin_verifier': pinVerifier,
    'recovery_behavior': recoveryBehavior,
  };

  factory RemoteAppLockSettings.fromJson(Map<String, dynamic> json) {
    return RemoteAppLockSettings(
      enabled: json['enabled'] as bool? ?? false,
      relockAfterSeconds: json['relock_after_seconds'] as int? ?? 60,
      useBiometric: json['use_biometric'] as bool? ?? false,
      pinVerifier: json['pin_verifier'] as String?,
      recoveryBehavior:
          json['recovery_behavior'] as String? ?? 'require_recovery_secret',
    );
  }
}

class RemoteConversationPrivacy {
  const RemoteConversationPrivacy({
    this.isLocked = false,
    this.hiddenFromList = false,
    this.secretCodeHint = '',
    this.disappearingSeconds = 0,
    this.exportAllowed = true,
    this.externalSaveAllowed = true,
    this.forwardingAllowed = true,
    this.automaticMediaSaveAllowed = true,
    this.aiProcessingAllowed = false,
  });

  final bool isLocked;
  final bool hiddenFromList;
  final String secretCodeHint;
  final int disappearingSeconds;
  final bool exportAllowed;
  final bool externalSaveAllowed;
  final bool forwardingAllowed;
  final bool automaticMediaSaveAllowed;
  final bool aiProcessingAllowed;

  RemoteConversationPrivacy copyWith({
    bool? isLocked,
    bool? hiddenFromList,
    String? secretCodeHint,
    int? disappearingSeconds,
    bool? exportAllowed,
    bool? externalSaveAllowed,
    bool? forwardingAllowed,
    bool? automaticMediaSaveAllowed,
    bool? aiProcessingAllowed,
  }) {
    return RemoteConversationPrivacy(
      isLocked: isLocked ?? this.isLocked,
      hiddenFromList: hiddenFromList ?? this.hiddenFromList,
      secretCodeHint: secretCodeHint ?? this.secretCodeHint,
      disappearingSeconds: disappearingSeconds ?? this.disappearingSeconds,
      exportAllowed: exportAllowed ?? this.exportAllowed,
      externalSaveAllowed: externalSaveAllowed ?? this.externalSaveAllowed,
      forwardingAllowed: forwardingAllowed ?? this.forwardingAllowed,
      automaticMediaSaveAllowed:
          automaticMediaSaveAllowed ?? this.automaticMediaSaveAllowed,
      aiProcessingAllowed: aiProcessingAllowed ?? this.aiProcessingAllowed,
    );
  }

  Map<String, dynamic> toAdvancedJson() => {
    'export_allowed': exportAllowed,
    'external_save_allowed': externalSaveAllowed,
    'forwarding_allowed': forwardingAllowed,
    'automatic_media_save_allowed': automaticMediaSaveAllowed,
    'ai_processing_allowed': aiProcessingAllowed,
  };

  static RemoteConversationPrivacy fromRow(Row row) {
    final advanced = _advancedFromJson(row['advanced_privacy_json'] as String?);
    return RemoteConversationPrivacy(
      isLocked: (row['is_locked'] as int? ?? 0) != 0,
      hiddenFromList: (row['hidden_from_list'] as int? ?? 0) != 0,
      secretCodeHint: row['secret_code_hint'] as String? ?? '',
      disappearingSeconds: row['disappearing_seconds'] as int? ?? 0,
      exportAllowed: advanced['export_allowed'] as bool? ?? true,
      externalSaveAllowed: advanced['external_save_allowed'] as bool? ?? true,
      forwardingAllowed: advanced['forwarding_allowed'] as bool? ?? true,
      automaticMediaSaveAllowed:
          advanced['automatic_media_save_allowed'] as bool? ?? true,
      aiProcessingAllowed: advanced['ai_processing_allowed'] as bool? ?? false,
    );
  }

  static Map<String, dynamic> _advancedFromJson(String? encoded) {
    if (encoded == null || encoded.isEmpty) return const {};
    try {
      final decoded = jsonDecode(encoded);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }
}

class RemotePrivacyCheckupItem {
  const RemotePrivacyCheckupItem({
    required this.id,
    required this.label,
    required this.state,
    required this.enforcementSource,
  });

  final String id;
  final String label;
  final String state;
  final String enforcementSource;
}

mixin RemotePrivacyRepository on HelixRemoteDatabaseBase {
  static const String _appLockKey = 'app_lock';
  static const String _accountDefaultDisappearingKey =
      'account_default_disappearing_seconds';
  static const String _strictPresetKey = 'strict_account_settings_applied';
  static const String _unknownCallPolicyKey = 'silence_unknown_callers';
  static const String _notificationPreviewKey = 'notification_previews';
  static const String _lockedChatSecretVerifierKey =
      'locked_chat_secret_verifier';

  RemoteAppLockSettings getAppLockSettings() {
    final raw = _getPrivacySetting(_appLockKey);
    if (raw == null) {
      return const RemoteAppLockSettings(
        enabled: false,
        relockAfterSeconds: 60,
        useBiometric: false,
      );
    }
    return RemoteAppLockSettings.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
  }

  void setAppLockSettings(RemoteAppLockSettings settings) {
    const allowed = {0, 60, 300, 900};
    if (!allowed.contains(settings.relockAfterSeconds) &&
        settings.relockAfterSeconds < 1) {
      throw ArgumentError('Invalid app lock relock policy');
    }
    _setPrivacySetting(_appLockKey, jsonEncode(settings.toJson()));
  }

  int getAccountDefaultDisappearingSeconds() {
    return int.tryParse(
          _getPrivacySetting(_accountDefaultDisappearingKey) ?? '',
        ) ??
        0;
  }

  void setAccountDefaultDisappearingSeconds(int seconds) {
    if (seconds < 0) throw ArgumentError('Disappearing seconds must be >= 0');
    _setPrivacySetting(_accountDefaultDisappearingKey, '$seconds');
  }

  bool getStrictAccountSettingsApplied() =>
      _getPrivacySetting(_strictPresetKey) == 'true';

  Map<String, dynamic> strictAccountSettingsPreview() => {
    'search_discoverable': false,
    'presence_visibility': 'NOBODY',
    'last_seen_visibility': 'NOBODY',
    'read_receipts': false,
    'notification_previews': false,
    'silence_unknown_callers': true,
    'app_lock': 'enabled, immediate relock',
    'backup_recovery': 'recovery secret required',
  };

  void applyStrictAccountSettingsPreset() {
    setAppLockSettings(
      const RemoteAppLockSettings(
        enabled: true,
        relockAfterSeconds: 0,
        useBiometric: true,
      ),
    );
    setSilenceUnknownCallers(enabled: true);
    setNotificationPreviews(enabled: false);
    _setPrivacySetting(_strictPresetKey, 'true');
  }

  bool getSilenceUnknownCallers() =>
      _getPrivacySetting(_unknownCallPolicyKey) == 'true';

  void setSilenceUnknownCallers({required bool enabled}) {
    _setPrivacySetting(_unknownCallPolicyKey, enabled ? 'true' : 'false');
  }

  bool getNotificationPreviewsEnabled() =>
      _getPrivacySetting(_notificationPreviewKey) != 'false';

  void setNotificationPreviews({required bool enabled}) {
    _setPrivacySetting(_notificationPreviewKey, enabled ? 'true' : 'false');
  }

  RemoteConversationPrivacy getConversationPrivacy(String conversationId) {
    final stmt = _db.prepare(
      'SELECT * FROM conversations WHERE conversation_id = ?;',
    );
    final res = stmt.select([conversationId]);
    stmt.close();
    if (res.isEmpty) return const RemoteConversationPrivacy();
    return RemoteConversationPrivacy.fromRow(res.first);
  }

  void setConversationPrivacy(
    String conversationId,
    RemoteConversationPrivacy privacy,
  ) {
    final stmt = _db.prepare('''
      UPDATE conversations
      SET is_locked = ?,
          hidden_from_list = ?,
          secret_code_hint = ?,
          disappearing_seconds = ?,
          advanced_privacy_json = ?
      WHERE conversation_id = ?;
    ''');
    stmt.execute([
      privacy.isLocked ? 1 : 0,
      privacy.hiddenFromList ? 1 : 0,
      privacy.secretCodeHint,
      privacy.disappearingSeconds,
      jsonEncode(privacy.toAdvancedJson()),
      conversationId,
    ]);
    stmt.close();
  }

  void setConversationLocked(
    String conversationId, {
    required bool locked,
    bool hidden = true,
    String secretCodeHint = '',
  }) {
    final current = getConversationPrivacy(conversationId);
    setConversationPrivacy(
      conversationId,
      current.copyWith(
        isLocked: locked,
        hiddenFromList: locked && hidden,
        secretCodeHint: locked ? secretCodeHint : '',
      ),
    );
  }

  void setConversationDisappearingPolicy(String conversationId, int seconds) {
    if (seconds < 0) throw ArgumentError('Disappearing seconds must be >= 0');
    final current = getConversationPrivacy(conversationId);
    setConversationPrivacy(
      conversationId,
      current.copyWith(disappearingSeconds: seconds),
    );
  }

  void setConversationAdvancedPrivacy(
    String conversationId, {
    required bool exportAllowed,
    required bool externalSaveAllowed,
    required bool forwardingAllowed,
    required bool automaticMediaSaveAllowed,
    required bool aiProcessingAllowed,
  }) {
    final current = getConversationPrivacy(conversationId);
    setConversationPrivacy(
      conversationId,
      current.copyWith(
        exportAllowed: exportAllowed,
        externalSaveAllowed: externalSaveAllowed,
        forwardingAllowed: forwardingAllowed,
        automaticMediaSaveAllowed: automaticMediaSaveAllowed,
        aiProcessingAllowed: aiProcessingAllowed,
      ),
    );
  }

  void setMessagePrivacyMetadata({
    required String messageId,
    int? expiresAt,
    int? retentionDeadline,
    bool viewOnce = false,
    bool keepInChat = false,
  }) {
    final stmt = _db.prepare('''
      UPDATE messages
      SET expires_at = ?,
          retention_deadline = ?,
          view_once = ?,
          keep_in_chat = ?
      WHERE message_id = ?;
    ''');
    stmt.execute([
      expiresAt ?? 0,
      retentionDeadline ?? 0,
      viewOnce ? 1 : 0,
      keepInChat ? 1 : 0,
      messageId,
    ]);
    stmt.close();
  }

  void markViewOnceOpened(String messageId, int openedAt) {
    final stmt = _db.prepare('''
      UPDATE messages
      SET view_once_opened_at = ?, expires_at = ?
      WHERE message_id = ? AND view_once = 1 AND view_once_opened_at = 0;
    ''');
    stmt.execute([openedAt, openedAt, messageId]);
    stmt.close();
  }

  void keepMessageInChat(String messageId, {required bool keep}) {
    final stmt = _db.prepare(
      'UPDATE messages SET keep_in_chat = ? WHERE message_id = ?;',
    );
    stmt.execute([keep ? 1 : 0, messageId]);
    stmt.close();
  }

  @override
  List<String> cleanupExpiredMessages(int nowMs) {
    final rows = _db.select(
      '''
      SELECT message_id FROM messages
      WHERE keep_in_chat = 0
        AND (
          (expires_at > 0 AND expires_at <= ?)
          OR (view_once = 1 AND view_once_opened_at > 0)
        );
      ''',
      [nowMs],
    );
    final ids = rows.map((row) => row['message_id'] as String).toList();
    for (final id in ids) {
      saveTombstone(id, 'MESSAGE');
      deleteMessage(id);
    }
    return ids;
  }

  void setLockedChatSecretVerifier(String verifier) {
    _setPrivacySetting(_lockedChatSecretVerifierKey, verifier);
  }

  bool verifyLockedChatSecret(String secret, int nowMs) {
    final verifier = _getPrivacySetting(_lockedChatSecretVerifierKey);
    if (verifier == null || verifier.isEmpty) return false;
    final attempts = _recentSecretAttempts(nowMs);
    if (attempts >= 5) return false;
    final valid = _constantTimeEquals(_simpleSecretVerifier(secret), verifier);
    if (!valid) _recordSecretAttempt(nowMs);
    return valid;
  }

  String createLockedChatSecretVerifier(String secret) =>
      _simpleSecretVerifier(secret);

  List<RemotePrivacyCheckupItem> privacyCheckupItems() {
    final appLock = getAppLockSettings();
    return [
      RemotePrivacyCheckupItem(
        id: 'search_discoverability',
        label: 'Search discoverability',
        state: getStrictAccountSettingsApplied() ? 'strict' : 'default',
        enforcementSource: 'backend account_privacy.search_discoverable',
      ),
      RemotePrivacyCheckupItem(
        id: 'presence_last_seen',
        label: 'Presence and last seen',
        state: getStrictAccountSettingsApplied() ? 'nobody' : 'contacts',
        enforcementSource: 'backend ContactsModule.getPresenceForViewer',
      ),
      RemotePrivacyCheckupItem(
        id: 'read_receipts',
        label: 'Read receipts',
        state: getStrictAccountSettingsApplied() ? 'off' : 'on',
        enforcementSource: 'RemoteMessagingService.markRead',
      ),
      RemotePrivacyCheckupItem(
        id: 'unknown_callers',
        label: 'Unknown callers',
        state: getSilenceUnknownCallers() ? 'silenced' : 'ring',
        enforcementSource: 'RemoteCallService.processInboundSignal',
      ),
      RemotePrivacyCheckupItem(
        id: 'app_lock',
        label: 'App lock',
        state: appLock.enabled
            ? 'enabled:${appLock.relockAfterSeconds}s'
            : 'disabled',
        enforcementSource: 'RemoteAppLockSettings',
      ),
      RemotePrivacyCheckupItem(
        id: 'locked_chats',
        label: 'Locked chats',
        state: '${getLockedConversations().length} locked',
        enforcementSource: 'conversations.is_locked',
      ),
      RemotePrivacyCheckupItem(
        id: 'backup',
        label: 'Backups',
        state: 'locked/view-once excluded',
        enforcementSource: 'RemoteBackupsRepository.exportBackupSnapshot',
      ),
      RemotePrivacyCheckupItem(
        id: 'blocked_contacts',
        label: 'Blocked contacts',
        state: '${getContacts().where((c) => c.status == 'Blocked').length}',
        enforcementSource: 'contacts.status',
      ),
    ];
  }

  List<RemoteConversation> getLockedConversations() {
    final rows = _db.select('''
      SELECT * FROM conversations
      WHERE is_locked = 1
      ORDER BY last_sequence DESC;
      ''');
    return rows.map(_conversationFromRow).toList();
  }

  String? _getPrivacySetting(String key) {
    final stmt = _db.prepare(
      'SELECT value FROM local_privacy_settings WHERE key = ?;',
    );
    final res = stmt.select([key]);
    stmt.close();
    if (res.isEmpty) return null;
    return res.first['value'] as String?;
  }

  void _setPrivacySetting(String key, String value) {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO local_privacy_settings (key, value, updated_at)
      VALUES (?, ?, ?);
    ''');
    stmt.execute([key, value, DateTime.now().millisecondsSinceEpoch]);
    stmt.close();
  }

  int _recentSecretAttempts(int nowMs) {
    final cutoff = nowMs - const Duration(minutes: 15).inMilliseconds;
    final stmt = _db.prepare(
      'SELECT COUNT(*) AS count FROM secret_attempts WHERE attempted_at >= ?;',
    );
    final res = stmt.select([cutoff]);
    stmt.close();
    return res.first['count'] as int;
  }

  void _recordSecretAttempt(int nowMs) {
    final stmt = _db.prepare(
      'INSERT INTO secret_attempts (attempted_at) VALUES (?);',
    );
    stmt.execute([nowMs]);
    stmt.close();
    final cutoff = nowMs - const Duration(hours: 1).inMilliseconds;
    _db.execute('DELETE FROM secret_attempts WHERE attempted_at < $cutoff;');
  }

  String _simpleSecretVerifier(String secret) {
    final normalized = secret.trim();
    var hash = 0x811c9dc5;
    for (final unit in normalized.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  RemoteConversation _conversationFromRow(Row row) {
    return RemoteConversation(
      conversationId: row['conversation_id'] as String,
      title: row['title'] as String? ?? '',
      type: row['type'] as String,
      lastActivitySequence: row['last_sequence'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      isPinned: (row['is_pinned'] as int? ?? 0) != 0,
      isMuted: (row['is_muted'] as int? ?? 0) != 0,
      isFavorite: (row['is_favorite'] as int? ?? 0) != 0,
    );
  }
}
