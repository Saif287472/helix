/// Persistent SQLite database for Helix chat data.
///
/// Uses `package:sqlite3` directly (backed by `sqlite3_flutter_libs` for the
/// native binary) instead of Drift code-generation, keeping the data layer
/// dependency-light and fully synchronous at the SQL level.
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'package:helix_domain/domain/models.dart';

/// Low-level SQLite wrapper that owns the database connection and provides
/// typed CRUD helpers for every table.
class HelixDatabase {
  /// Opens (or creates) the database at [file].
  ///
  /// Call [initialize] before any other method.
  HelixDatabase(this._file);

  final File _file;
  late final Database _db;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Opens the database, creates tables if they don't exist, and applies any
  /// pending forward-only migrations.
  ///
  /// Throws [SqliteException] on a corrupt or unreadable file, guaranteeing
  /// that no file handle is leaked even when initialization fails partway.
  void initialize() {
    _db = sqlite3.open(_file.path);
    try {
      _db.execute('PRAGMA journal_mode = WAL;');
      _db.execute('PRAGMA foreign_keys = ON;');
      _onCreate();
      _applyMigrations();
    } catch (_) {
      _db.close();
      rethrow;
    }
  }

  /// The current schema version stored in the database.
  int get schemaVersion =>
      _db.select('PRAGMA user_version').first['user_version'] as int;

  // ---------------------------------------------------------------------------
  // Migrations
  // ---------------------------------------------------------------------------

  void _applyMigrations() {
    final version = schemaVersion;
    if (version < 3) _runMigration(3, _migration3);
  }

  void _runMigration(int targetVersion, void Function() steps) {
    _db.execute('BEGIN;');
    try {
      steps();
      _db.execute('PRAGMA user_version = $targetVersion;');
      _db.execute('COMMIT;');
    } catch (e) {
      try {
        _db.execute('ROLLBACK;');
      } catch (_) {}
      rethrow;
    }
  }

  bool _columnExists(String table, String column) {
    final info = _db.select('PRAGMA table_info($table)');
    return info.any((row) => row['name'] == column);
  }

  bool _tableExists(String name) {
    final result = _db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [name],
    );
    return result.isNotEmpty;
  }

  /// Migration 3: draft_text + is_archived on threads; pinned_messages table.
  void _migration3() {
    if (!_columnExists('threads', 'draft_text')) {
      _db.execute(
        "ALTER TABLE threads ADD COLUMN draft_text TEXT NOT NULL DEFAULT '';",
      );
    }
    if (!_columnExists('threads', 'is_archived')) {
      _db.execute(
        'ALTER TABLE threads ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0;',
      );
    }
    if (!_tableExists('pinned_messages')) {
      _db.execute('''
        CREATE TABLE pinned_messages (
          thread_id  TEXT NOT NULL,
          message_id TEXT NOT NULL,
          pinned_at  INTEGER NOT NULL,
          PRIMARY KEY (thread_id, message_id),
          FOREIGN KEY (thread_id) REFERENCES threads(thread_id) ON DELETE CASCADE
        );
      ''');
    }
  }

  /// Closes the underlying database connection.
  void close() => _db.close();

  /// Returns the size of the database file in bytes.
  int getDatabaseSizeBytes() {
    try {
      _db.execute('PRAGMA wal_checkpoint(PASSIVE);');
    } catch (_) {}
    return [
      _file,
      File('${_file.path}-wal'),
      File('${_file.path}-shm'),
    ].where((f) => f.existsSync()).fold(0, (sum, f) => sum + f.lengthSync());
  }

  /// Deletes all rows from every table atomically.
  void clearAll() {
    _db.execute('BEGIN IMMEDIATE;');
    try {
      _db.execute('DELETE FROM pinned_messages;');
      _db.execute('DELETE FROM messages;');
      _db.execute('DELETE FROM one_way_messages;');
      _db.execute('DELETE FROM threads;');
      _db.execute('DELETE FROM peers_cache;');
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Schema
  // ---------------------------------------------------------------------------

  void _onCreate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS threads (
        thread_id                  TEXT PRIMARY KEY,
        peer_display_name          TEXT NOT NULL,
        peer_device_suffix         TEXT NOT NULL,
        peer_static_key_fingerprint TEXT NOT NULL,
        peer_session_id            TEXT NOT NULL DEFAULT '',
        peer_host                  TEXT NOT NULL DEFAULT '',
        peer_port                  INTEGER NOT NULL DEFAULT 0,
        status                     INTEGER NOT NULL DEFAULT 0,
        unread_count               INTEGER NOT NULL DEFAULT 0,
        has_new_session_separator   INTEGER NOT NULL DEFAULT 0,
        created_at                 INTEGER NOT NULL,
        updated_at                 INTEGER NOT NULL
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        message_id      TEXT PRIMARY KEY,
        thread_id       TEXT NOT NULL REFERENCES threads(thread_id) ON DELETE CASCADE,
        origin          INTEGER NOT NULL,
        text            TEXT NOT NULL,
        timestamp       INTEGER NOT NULL,
        delivery_status INTEGER NOT NULL
      );
    ''');

    _db.execute('''
      CREATE INDEX IF NOT EXISTS idx_messages_thread
        ON messages(thread_id, timestamp ASC);
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS one_way_messages (
        message_id                  TEXT PRIMARY KEY,
        peer_display_name           TEXT NOT NULL,
        peer_device_suffix          TEXT NOT NULL,
        peer_session_id             TEXT NOT NULL,
        peer_static_key_fingerprint TEXT NOT NULL,
        peer_host                   TEXT NOT NULL,
        peer_port                   INTEGER NOT NULL,
        text                        TEXT NOT NULL,
        timestamp                   INTEGER NOT NULL
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS peers_cache (
        session_id     TEXT PRIMARY KEY,
        display_name   TEXT NOT NULL,
        device_suffix  TEXT NOT NULL,
        host           TEXT NOT NULL,
        port           INTEGER NOT NULL,
        source         INTEGER NOT NULL,
        seen_at        INTEGER NOT NULL,
        protocol_major INTEGER NOT NULL,
        protocol_minor INTEGER NOT NULL,
        is_favorite    INTEGER NOT NULL DEFAULT 0
      );
    ''');
  }

  // ---------------------------------------------------------------------------
  // Threads
  // ---------------------------------------------------------------------------

  /// Inserts or updates a thread's metadata.
  ///
  /// Messages are **not** touched — only the thread header row is upserted.
  void upsertThread(ChatThread thread) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute(
      '''
      INSERT INTO threads (
        thread_id, peer_display_name, peer_device_suffix,
        peer_static_key_fingerprint, peer_session_id,
        peer_host, peer_port, status, unread_count,
        has_new_session_separator, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(thread_id) DO UPDATE SET
        peer_display_name          = excluded.peer_display_name,
        peer_device_suffix         = excluded.peer_device_suffix,
        peer_static_key_fingerprint = excluded.peer_static_key_fingerprint,
        peer_session_id            = excluded.peer_session_id,
        peer_host                  = excluded.peer_host,
        peer_port                  = excluded.peer_port,
        status                     = excluded.status,
        unread_count               = excluded.unread_count,
        has_new_session_separator  = excluded.has_new_session_separator,
        updated_at                 = excluded.updated_at
      ''',
      [
        thread.threadId,
        thread.peerDisplayName,
        thread.peerDeviceSuffix,
        thread.peerStaticKeyFingerprint,
        thread.peerSessionId,
        thread.peerHost,
        thread.peerPort,
        thread.status.index,
        thread.unreadCount,
        thread.hasNewSessionSeparator ? 1 : 0,
        now,
        now,
      ],
    );
  }

  /// Deletes a thread and all its messages (via `ON DELETE CASCADE`).
  void deleteThread(String threadId) {
    _db.execute('DELETE FROM threads WHERE thread_id = ?', [threadId]);
  }

  /// Returns a single thread (without messages) or `null`.
  ChatThread? getThread(String threadId) {
    final result = _db.select('SELECT * FROM threads WHERE thread_id = ?', [
      threadId,
    ]);
    if (result.isEmpty) return null;
    return _threadFromRow(result.first);
  }

  /// Returns a page of threads, each pre-loaded with its most recent
  /// [preloadCount] messages (default 50), ordered by most-recently-updated
  /// first. Use [limit] and [offset] for pagination.
  ///
  /// When [includeArchived] is false (default), archived threads are excluded.
  List<ChatThread> getAllThreads({
    int preloadCount = 50,
    bool includeArchived = false,
    int limit = 100,
    int offset = 0,
  }) {
    final sql = includeArchived
        ? 'SELECT * FROM threads ORDER BY updated_at DESC LIMIT ? OFFSET ?'
        : 'SELECT * FROM threads WHERE is_archived = 0 ORDER BY updated_at DESC LIMIT ? OFFSET ?';
    final rows = _db.select(sql, [limit, offset]);
    return rows.map((r) {
      final thread = _threadFromRow(r);
      thread.messages.addAll(getMessages(thread.threadId, limit: preloadCount));
      return thread;
    }).toList();
  }

  /// Saves the draft text for a thread. Pass an empty string to clear.
  void saveDraft(String threadId, String text) {
    _db.execute('UPDATE threads SET draft_text = ? WHERE thread_id = ?', [
      text,
      threadId,
    ]);
  }

  /// Returns the saved draft text for a thread, or an empty string.
  String getDraft(String threadId) {
    final result = _db.select(
      'SELECT draft_text FROM threads WHERE thread_id = ?',
      [threadId],
    );
    if (result.isEmpty) return '';
    return (result.first['draft_text'] as String?) ?? '';
  }

  /// Archives or unarchives a thread.
  void archiveThread(String threadId, {required bool archive}) {
    _db.execute('UPDATE threads SET is_archived = ? WHERE thread_id = ?', [
      archive ? 1 : 0,
      threadId,
    ]);
  }

  /// Returns all archived threads (no message preload).
  List<ChatThread> getArchivedThreads({int limit = 100, int offset = 0}) {
    final rows = _db.select(
      'SELECT * FROM threads WHERE is_archived = 1 ORDER BY updated_at DESC LIMIT ? OFFSET ?',
      [limit, offset],
    );
    return rows.map(_threadFromRow).toList();
  }

  /// Deletes all data associated with a single thread.
  void clearThread(String threadId) => deleteThread(threadId);

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  /// Inserts a new message row.
  void insertMessage(ChatMessage message) {
    _db.execute(
      '''
      INSERT OR REPLACE INTO messages
        (message_id, thread_id, origin, text, timestamp, delivery_status)
      VALUES (?, ?, ?, ?, ?, ?)
      ''',
      [
        message.messageId,
        message.threadId,
        message.origin.index,
        message.text,
        message.timestamp.millisecondsSinceEpoch,
        message.deliveryStatus.index,
      ],
    );
  }

  /// Updates the delivery status of an existing message.
  void updateMessageStatus(String messageId, MessageDeliveryStatus status) {
    _db.execute(
      'UPDATE messages SET delivery_status = ? WHERE message_id = ?',
      [status.index, messageId],
    );
  }

  /// Returns messages for [threadId] ordered by timestamp ascending.
  ///
  /// Supports cursor-based pagination via [limit] and [offset].
  List<ChatMessage> getMessages(
    String threadId, {
    int limit = 50,
    int offset = 0,
  }) {
    final rows = _db.select(
      '''
      SELECT * FROM messages
       WHERE thread_id = ?
       ORDER BY timestamp ASC
       LIMIT ? OFFSET ?
      ''',
      [threadId, limit, offset],
    );
    return rows.map(_messageFromRow).toList();
  }

  /// Returns the total number of messages in a thread.
  int getMessageCount(String threadId) {
    final result = _db.select(
      'SELECT COUNT(*) AS cnt FROM messages WHERE thread_id = ?',
      [threadId],
    );
    return result.first['cnt'] as int;
  }

  // ---------------------------------------------------------------------------
  // One-way messages
  // ---------------------------------------------------------------------------

  /// Inserts a one-way (unlinked) message.
  void insertOneWayMessage(OneWayMessage message) {
    _db.execute(
      '''
      INSERT OR REPLACE INTO one_way_messages
        (message_id, peer_display_name, peer_device_suffix, peer_session_id,
         peer_static_key_fingerprint, peer_host, peer_port, text, timestamp)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        message.messageId,
        message.peerDisplayName,
        message.peerDeviceSuffix,
        message.peerSessionId,
        message.peerStaticKeyFingerprint,
        message.peerHost,
        message.peerPort,
        message.text,
        message.timestamp.millisecondsSinceEpoch,
      ],
    );
  }

  /// Returns a page of one-way messages, newest first.
  /// Use [limit] and [offset] for pagination.
  List<OneWayMessage> getAllOneWayMessages({int limit = 200, int offset = 0}) {
    final rows = _db.select(
      'SELECT * FROM one_way_messages ORDER BY timestamp DESC LIMIT ? OFFSET ?',
      [limit, offset],
    );
    return rows.map(_oneWayMessageFromRow).toList();
  }

  /// Deletes a single one-way message.
  void deleteOneWayMessage(String messageId) {
    _db.execute('DELETE FROM one_way_messages WHERE message_id = ?', [
      messageId,
    ]);
  }

  // ---------------------------------------------------------------------------
  // Peers cache
  // ---------------------------------------------------------------------------

  /// Inserts or updates a cached peer entry.
  ///
  /// When [isFavorite] is provided it overrides the stored value; otherwise the
  /// existing `is_favorite` flag is preserved (defaulting to `false` on first
  /// insert).
  void upsertPeerCache(Peer peer, {bool? isFavorite}) {
    // Build the is_favorite column for the ON CONFLICT clause: either set it
    // to the caller-supplied value or keep the existing row's value.
    final favoriteClause = isFavorite != null
        ? 'is_favorite = ${isFavorite ? 1 : 0}'
        : 'is_favorite = peers_cache.is_favorite';

    _db.execute(
      '''
      INSERT INTO peers_cache
        (session_id, display_name, device_suffix, host, port,
         source, seen_at, protocol_major, protocol_minor, is_favorite)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(session_id) DO UPDATE SET
        display_name   = excluded.display_name,
        device_suffix  = excluded.device_suffix,
        host           = excluded.host,
        port           = excluded.port,
        source         = excluded.source,
        seen_at        = excluded.seen_at,
        protocol_major = excluded.protocol_major,
        protocol_minor = excluded.protocol_minor,
        $favoriteClause
      ''',
      [
        peer.sessionId,
        peer.displayName,
        peer.deviceSuffix,
        peer.host,
        peer.port,
        peer.source.index,
        peer.seenAt.millisecondsSinceEpoch,
        peer.protocolMajor,
        peer.protocolMinor,
        isFavorite == null ? 0 : (isFavorite ? 1 : 0),
      ],
    );
  }

  /// Returns all peers that have been marked as favourites.
  List<Peer> getFavoritePeers({int limit = 100, int offset = 0}) {
    final rows = _db.select(
      'SELECT * FROM peers_cache WHERE is_favorite = 1 ORDER BY display_name LIMIT ? OFFSET ?',
      [limit, offset],
    );
    return rows.map(_peerFromRow).toList();
  }

  // ---------------------------------------------------------------------------
  // Pinned messages
  // ---------------------------------------------------------------------------

  /// Pins a message in a thread. Throws [StateError] if the thread already
  /// has 5 pinned messages.
  void pinMessage(String threadId, String messageId) {
    final count =
        _db.select(
              'SELECT COUNT(*) AS cnt FROM pinned_messages WHERE thread_id = ?',
              [threadId],
            ).first['cnt']
            as int;
    if (count >= 5) {
      throw StateError('Cannot pin more than 5 messages per thread.');
    }
    _db.execute(
      '''
      INSERT OR IGNORE INTO pinned_messages (thread_id, message_id, pinned_at)
      VALUES (?, ?, ?)
      ''',
      [threadId, messageId, DateTime.now().millisecondsSinceEpoch],
    );
  }

  /// Unpins a message from a thread.
  void unpinMessage(String threadId, String messageId) {
    _db.execute(
      'DELETE FROM pinned_messages WHERE thread_id = ? AND message_id = ?',
      [threadId, messageId],
    );
  }

  /// Returns pinned message IDs for [threadId], ordered by pin time ascending.
  List<String> getPinnedMessageIds(String threadId) {
    final rows = _db.select(
      'SELECT message_id FROM pinned_messages WHERE thread_id = ? ORDER BY pinned_at ASC',
      [threadId],
    );
    return rows.map((r) => r['message_id'] as String).toList();
  }

  // ---------------------------------------------------------------------------
  // Maintenance
  // ---------------------------------------------------------------------------

  /// Deletes the oldest threads (by `updated_at`) until the database file size
  /// is at or below [maxSizeBytes].
  void pruneOldestThreads(int maxSizeBytes) {
    var previousSize = getDatabaseSizeBytes();

    while (previousSize > maxSizeBytes) {
      final oldest = _db.select(
        'SELECT thread_id FROM threads ORDER BY updated_at ASC LIMIT 1',
      );
      if (oldest.isEmpty) break;

      deleteThread(oldest.first['thread_id'] as String);
      _db.execute('PRAGMA wal_checkpoint(TRUNCATE);');

      final newSize = getDatabaseSizeBytes();
      if (newSize >= previousSize) break;
      previousSize = newSize;
    }
  }

  // ---------------------------------------------------------------------------
  // Row → model converters
  // ---------------------------------------------------------------------------

  static T _enumOr<T>(List<T> values, Object? index, T fallback) {
    if (index is! int || index < 0 || index >= values.length) return fallback;
    return values[index];
  }

  static DateTime _dateTimeOr(Object? value, DateTime fallback) {
    if (value is! int) return fallback;
    const min = -8640000000000000;
    const max = 8640000000000000;
    if (value < min || value > max) return fallback;
    try {
      return DateTime.fromMillisecondsSinceEpoch(value);
    } catch (_) {
      return fallback;
    }
  }

  ChatThread _threadFromRow(Row row) {
    return ChatThread(
      threadId: row['thread_id'] as String,
      peerDisplayName: row['peer_display_name'] as String,
      peerDeviceSuffix: row['peer_device_suffix'] as String,
      peerStaticKeyFingerprint: row['peer_static_key_fingerprint'] as String,
      peerSessionId: row['peer_session_id'] as String,
      peerHost: row['peer_host'] as String,
      peerPort: row['peer_port'] as int,
      status: _enumOr(ThreadStatus.values, row['status'], ThreadStatus.active),
      unreadCount: row['unread_count'] as int,
      hasNewSessionSeparator: (row['has_new_session_separator'] as int) != 0,
      isArchived: ((row['is_archived'] as int?) ?? 0) != 0,
      draftText: (row['draft_text'] as String?) ?? '',
    );
  }

  ChatMessage _messageFromRow(Row row) {
    return ChatMessage(
      messageId: row['message_id'] as String,
      threadId: row['thread_id'] as String,
      origin: _enumOr(MessageOrigin.values, row['origin'], MessageOrigin.local),
      text: row['text'] as String,
      timestamp: _dateTimeOr(row['timestamp'], DateTime.now()),
      deliveryStatus: _enumOr(
        MessageDeliveryStatus.values,
        row['delivery_status'],
        MessageDeliveryStatus.sending,
      ),
    );
  }

  OneWayMessage _oneWayMessageFromRow(Row row) {
    return OneWayMessage(
      messageId: row['message_id'] as String,
      peerDisplayName: row['peer_display_name'] as String,
      peerDeviceSuffix: row['peer_device_suffix'] as String,
      peerSessionId: row['peer_session_id'] as String,
      peerStaticKeyFingerprint: row['peer_static_key_fingerprint'] as String,
      peerHost: row['peer_host'] as String,
      peerPort: row['peer_port'] as int,
      text: row['text'] as String,
      timestamp: _dateTimeOr(row['timestamp'], DateTime.now()),
    );
  }

  Peer _peerFromRow(Row row) {
    return Peer(
      sessionId: row['session_id'] as String,
      displayName: row['display_name'] as String,
      deviceSuffix: row['device_suffix'] as String,
      host: row['host'] as String,
      port: row['port'] as int,
      source: _enumOr(PeerSource.values, row['source'], PeerSource.mdns),
      seenAt: _dateTimeOr(row['seen_at'], DateTime.now()),
      protocolMajor: row['protocol_major'] as int,
      protocolMinor: row['protocol_minor'] as int,
    );
  }
}
