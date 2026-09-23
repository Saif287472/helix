part of '../database.dart';

mixin RemoteBackupsRepository on HelixRemoteDatabaseBase {
  static const int currentBackupSnapshotVersion = 2;
  static const int currentTransferArchiveVersion = 1;
  static const int currentAttachmentManifestVersion = 1;
  static const List<String> _restorableTables = [
    'accounts',
    'devices',
    'contacts',
    'contact_requests',
    'conversations',
    'members',
    'messages',
    'message_receipts',
    'revisions',
    'attachments',
    'groups',
    'group_epoch_keys',
    'group_invites',
    'crypto_sessions',
    'call_history',
    'tombstones',
  ];
  static const List<String> _excludedTables = [
    'local_prekeys',
    'trusted_devices',
    'sync_cursors',
    'processed_event_ids',
    'pending_operations',
    'quarantine_events',
    'active_call',
    'local_privacy_settings',
    'secret_attempts',
    'account_runtime_profiles',
    'proxy_profiles',
    'platform_capability_profiles',
  ];

  // ---------------------------------------------------------------------------
  // Backup / restore snapshots (P17-005, P17-008, P17-012, P17-014)
  // ---------------------------------------------------------------------------

  String exportBackupSnapshot({int version = currentBackupSnapshotVersion}) {
    cleanupExpiredMessages(DateTime.now().millisecondsSinceEpoch);
    final conversationIds = _backupConversationIds();
    return jsonEncode({
      'version': version,
      'snapshot_version': version,
      'exported_at': DateTime.now().millisecondsSinceEpoch,
      'restore_semantics': 'replace_local_state',
      'manifest': _backupManifest(version),
      'accounts': _selectAll('accounts'),
      'devices': _selectAll('devices'),
      'contacts': _selectAll('contacts'),
      'contact_requests': _selectAll('contact_requests'),
      'conversations': _selectRowsForBackup('conversations', conversationIds),
      'members': _selectRowsForBackup('members', conversationIds),
      'messages': _selectRowsForBackup('messages', conversationIds),
      'message_receipts': _selectRowsForBackup(
        'message_receipts',
        conversationIds,
      ),
      'revisions': _selectBackupRevisions(conversationIds),
      'attachments': _selectBackupAttachments(conversationIds),
      'groups': _selectAll('groups'),
      'group_epoch_keys': _selectAll('group_epoch_keys'),
      'group_invites': _selectAll('group_invites'),
      'crypto_sessions': _selectAll('crypto_sessions'),
      'call_history': _selectAll('call_history'),
      'tombstones': _selectAll('tombstones'),
      'attachment_manifest': _attachmentManifest(),
    });
  }

  Map<String, dynamic> validateBackupSnapshot(String snapshotJson) {
    final decoded = jsonDecode(snapshotJson) as Map<String, dynamic>;
    final version = _snapshotVersion(decoded);
    if (version < 1 || version > currentBackupSnapshotVersion) {
      throw UnsupportedError('Unsupported backup snapshot version: $version');
    }
    for (final table in _restorableTables) {
      final value = decoded[table == 'members' ? 'members' : table];
      if (value != null && value is! List) {
        throw FormatException('Backup snapshot table $table must be a list');
      }
    }
    return {
      'version': version,
      'restore_semantics':
          decoded['restore_semantics'] as String? ?? 'replace_local_state',
      'tables': _restorableTables,
      'messages': (decoded['messages'] as List? ?? const []).length,
      'attachments': (decoded['attachments'] as List? ?? const []).length,
      'tombstones': (decoded['tombstones'] as List? ?? const []).length,
    };
  }

  void restoreBackupSnapshot(String snapshotJson) {
    final decoded = jsonDecode(snapshotJson) as Map<String, dynamic>;
    validateBackupSnapshot(snapshotJson);

    _db.execute('SAVEPOINT restore_backup_snapshot;');
    try {
      _clearRestorableTables();
      _restoreRows('accounts', decoded['accounts'] as List? ?? const []);
      _restoreRows('devices', decoded['devices'] as List? ?? const []);
      _restoreRows('contacts', decoded['contacts'] as List? ?? const []);
      _restoreRows(
        'contact_requests',
        decoded['contact_requests'] as List? ?? const [],
      );
      _restoreRows(
        'conversations',
        decoded['conversations'] as List? ?? const [],
      );
      _restoreRows('members', decoded['members'] as List? ?? const []);
      _restoreRows('messages', decoded['messages'] as List? ?? const []);
      _restoreRows(
        'message_receipts',
        decoded['message_receipts'] as List? ?? const [],
      );
      _restoreRows('revisions', decoded['revisions'] as List? ?? const []);
      _restoreRows('attachments', decoded['attachments'] as List? ?? const []);
      _restoreRows('groups', decoded['groups'] as List? ?? const []);
      _restoreRows(
        'group_epoch_keys',
        decoded['group_epoch_keys'] as List? ?? const [],
      );
      _restoreRows(
        'group_invites',
        decoded['group_invites'] as List? ?? const [],
      );
      _restoreRows(
        'crypto_sessions',
        decoded['crypto_sessions'] as List? ?? const [],
      );
      _restoreRows(
        'call_history',
        decoded['call_history'] as List? ?? const [],
      );
      _restoreRows('tombstones', decoded['tombstones'] as List? ?? const []);
      _applyRestoredTombstones();
      _db.execute('RELEASE SAVEPOINT restore_backup_snapshot;');
    } catch (_) {
      _db.execute('ROLLBACK TO SAVEPOINT restore_backup_snapshot;');
      _db.execute('RELEASE SAVEPOINT restore_backup_snapshot;');
      rethrow;
    }
  }

  String exportTransferArchive({
    String sourcePlatform = 'unknown',
    int version = currentTransferArchiveVersion,
  }) {
    final snapshot = jsonDecode(exportBackupSnapshot()) as Map<String, dynamic>;
    return jsonEncode({
      'archive_version': version,
      'type': 'helix.remote.transfer-archive',
      'source_platform': sourcePlatform,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'snapshot_version': snapshot['snapshot_version'],
      'restore_semantics': 'replace_local_state',
      'snapshot': snapshot,
      'chunks': [
        {
          'index': 0,
          'kind': 'snapshot',
          'encoding': 'json',
          'byte_length': utf8.encode(jsonEncode(snapshot)).length,
        },
      ],
    });
  }

  void restoreTransferArchive(String archiveJson) {
    final decoded = jsonDecode(archiveJson) as Map<String, dynamic>;
    final archiveVersion = decoded['archive_version'] as int? ?? 0;
    if (archiveVersion != currentTransferArchiveVersion ||
        decoded['type'] != 'helix.remote.transfer-archive') {
      throw UnsupportedError(
        'Unsupported transfer archive version: $archiveVersion',
      );
    }
    final snapshot = decoded['snapshot'];
    if (snapshot is! Map<String, dynamic>) {
      throw const FormatException('Transfer archive missing snapshot');
    }
    restoreBackupSnapshot(jsonEncode(snapshot));
  }

  @override
  List<Map<String, dynamic>> getTombstones() => _selectAll('tombstones');

  List<Map<String, dynamic>> _selectAll(String table) {
    final res = _db.select('SELECT * FROM $table;');
    return res.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  int _snapshotVersion(Map<String, dynamic> decoded) {
    return decoded['snapshot_version'] as int? ??
        decoded['version'] as int? ??
        0;
  }

  Map<String, dynamic> _backupManifest(int version) {
    return {
      'manifest_version': 1,
      'snapshot_version': version,
      'included_tables': _restorableTables,
      'excluded_tables': _excludedTables,
      'non_restorable_secrets': [
        'access_tokens',
        'refresh_tokens',
        'push_tokens',
        'runtime_locks',
        'crypto_session_chain_state',
        'local_prekey_private_material',
        'processed_event_cache',
        'outbox_retry_state',
        'quarantined_events',
        'expired_view_once_content',
        'locked_chat_secret_codes',
        'locked_chat_messages_by_default',
        'opened_view_once_media',
      ],
      'privacy_exclusions': {
        'locked_chats':
            'excluded unless a future explicit vault-backup mode is implemented',
        'view_once': 'excluded after opening and never exported as media blobs',
        'app_lock': 'local credential state is not restorable',
      },
    };
  }

  Map<String, dynamic> _attachmentManifest() {
    final attachments = _selectBackupAttachments(_backupConversationIds());
    return {
      'manifest_version': currentAttachmentManifestVersion,
      'objects': [
        for (final attachment in attachments)
          {
            'attachment_id': attachment['attachment_id'],
            'size_bytes': attachment['size_bytes'],
            'status': attachment['status'],
            'has_downloaded_ciphertext':
                (attachment['downloaded_ciphertext_path'] as String?)
                    ?.isNotEmpty ==
                true,
            'has_encrypted_cache':
                (attachment['encrypted_cache_path'] as String?)?.isNotEmpty ==
                true,
          },
      ],
    };
  }

  List<String> _backupConversationIds() {
    cleanupExpiredMessages(DateTime.now().millisecondsSinceEpoch);
    final rows = _db.select('''
      SELECT conversation_id FROM conversations
      WHERE is_locked = 0 AND hidden_from_list = 0;
    ''');
    return rows.map((row) => row['conversation_id'] as String).toList();
  }

  List<Map<String, dynamic>> _selectRowsForBackup(
    String table,
    List<String> conversationIds,
  ) {
    if (conversationIds.isEmpty) return const [];
    final placeholders = List.filled(conversationIds.length, '?').join(', ');
    final whereColumn = table == 'conversations'
        ? 'conversation_id'
        : 'conversation_id';
    final extra = table == 'messages'
        ? ' AND view_once = 0 AND (expires_at = 0 OR keep_in_chat = 1 OR expires_at > ?)'
        : '';
    final args = <Object?>[
      ...conversationIds,
      if (table == 'messages') DateTime.now().millisecondsSinceEpoch,
    ];
    final rows = _db.select(
      'SELECT * FROM $table WHERE $whereColumn IN ($placeholders)$extra;',
      args,
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  List<Map<String, dynamic>> _selectBackupRevisions(
    List<String> conversationIds,
  ) {
    if (conversationIds.isEmpty) return const [];
    final placeholders = List.filled(conversationIds.length, '?').join(', ');
    final rows = _db.select(
      '''
      SELECT r.* FROM revisions r
      JOIN messages m ON m.message_id = r.message_id
      WHERE m.conversation_id IN ($placeholders)
        AND m.view_once = 0
        AND (m.expires_at = 0 OR m.keep_in_chat = 1 OR m.expires_at > ?);
      ''',
      [...conversationIds, DateTime.now().millisecondsSinceEpoch],
    );
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  List<Map<String, dynamic>> _selectBackupAttachments(
    List<String> conversationIds,
  ) {
    return _selectAll('attachments');
  }

  void _clearRestorableTables() {
    for (final table in [
      'message_receipts',
      'revisions',
      'messages',
      'members',
      'group_epoch_keys',
      'group_invites',
      'groups',
      'crypto_sessions',
      'call_history',
      'attachments',
      'contact_requests',
      'contacts',
      'devices',
      'conversations',
      'accounts',
      'tombstones',
    ]) {
      _db.execute('DELETE FROM $table;');
    }
  }

  void _restoreRows(String table, List<dynamic> rows) {
    for (final row in rows.cast<Map<String, dynamic>>()) {
      if (row.isEmpty) continue;
      final columns = row.keys.toList();
      final placeholders = List.filled(columns.length, '?').join(', ');
      final columnList = columns.join(', ');
      final stmt = _db.prepare(
        'INSERT OR REPLACE INTO $table ($columnList) VALUES ($placeholders);',
      );
      stmt.execute(columns.map((column) => row[column]).toList());
      stmt.close();
    }
  }

  void _applyRestoredTombstones() {
    final tombstones = getTombstones();
    for (final tombstone in tombstones) {
      final itemId = tombstone['item_id'] as String;
      final type = tombstone['type'] as String;
      if (type == 'MESSAGE') {
        deleteMessage(itemId);
      } else if (type == 'GROUP') {
        final stmt = _db.prepare(
          "UPDATE groups SET status = 'DELETED' WHERE group_id = ?;",
        );
        stmt.execute([itemId]);
        stmt.close();
      }
    }
  }
}
