/// Local-metadata SQLite database for Helix Local.
///
/// Stores only peer favorites (peers_cache). Message and thread content is
/// intentionally ephemeral and lives exclusively in RAM.
///
/// Migration 4 (2026-06-19): dropped legacy content tables (threads, messages,
/// one_way_messages, pinned_messages) — see P6-010/P6-011.
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'package:helix_local_domain/domain/models.dart';

/// Thrown by [HelixDatabase.deleteFiles] when one or more database files
/// cannot be deleted. The wipe orchestrator treats this as a partial failure
/// and records it in [WipeResult.errors].
class WipeDatabaseDeleteException implements Exception {
  WipeDatabaseDeleteException(this.failedPaths);
  final List<String> failedPaths;

  @override
  String toString() =>
      'WipeDatabaseDeleteException: failed to delete ${failedPaths.join(', ')}';
}

/// SQLite wrapper that owns the database connection and provides typed CRUD
/// helpers for the peers_cache table.
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
    if (version < 4) _runMigration(4, _migration4);
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

  /// Migration 3: draft_text + is_archived on threads; pinned_messages table.
  /// Retained for existing databases that have not yet applied this migration.
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
    final hasPinned = _db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='pinned_messages'",
    ).isNotEmpty;
    if (!hasPinned) {
      _db.execute('''
        CREATE TABLE IF NOT EXISTS pinned_messages (
          thread_id  TEXT NOT NULL,
          message_id TEXT NOT NULL,
          pinned_at  INTEGER NOT NULL,
          PRIMARY KEY (thread_id, message_id),
          FOREIGN KEY (thread_id) REFERENCES threads(thread_id) ON DELETE CASCADE
        );
      ''');
    }
  }

  /// Migration 4: drop legacy content tables.
  ///
  /// All message and thread content is ephemeral (RAM-only) per the Local
  /// product contract. Only peer favorites (peers_cache) persist on disk.
  void _migration4() {
    _db.execute('DROP TABLE IF EXISTS pinned_messages;');
    _db.execute('DROP TABLE IF EXISTS messages;');
    _db.execute('DROP TABLE IF EXISTS one_way_messages;');
    _db.execute('DROP TABLE IF EXISTS threads;');
  }

  /// Closes the underlying database connection.
  void close() => _db.close();

  /// Returns the size of the database file in bytes (including WAL and SHM).
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

  /// Deletes all rows from peers_cache atomically.
  ///
  /// Called by the panic wipe orchestrator before [deleteFiles].
  void clearAll() {
    _db.execute('BEGIN IMMEDIATE;');
    try {
      _db.execute('DELETE FROM peers_cache;');
      _db.execute('COMMIT;');
    } catch (_) {
      _db.execute('ROLLBACK;');
      rethrow;
    }
  }

  /// Checkpoints WAL, closes the database handle, then deletes the database
  /// file and its WAL and SHM companions.
  ///
  /// After this call the [HelixDatabase] instance must not be used again.
  ///
  /// Throws a [WipeDatabaseDeleteException] if any file cannot be deleted.
  /// The WAL checkpoint failure is non-fatal (the file is still deleted
  /// without a full checkpoint), but all three file deletions are attempted
  /// before an exception is thrown so the caller receives the full failure list.
  void deleteFiles() {
    try {
      _db.execute('PRAGMA wal_checkpoint(FULL);');
    } catch (_) {}
    _db.close();
    final failedPaths = <String>[];
    for (final suffix in ['', '-wal', '-shm']) {
      final f = File('${_file.path}$suffix');
      if (!f.existsSync()) continue;
      try {
        f.deleteSync();
      } catch (e) {
        failedPaths.add('${f.path}: $e');
      }
    }
    if (failedPaths.isNotEmpty) {
      throw WipeDatabaseDeleteException(failedPaths);
    }
  }

  // ---------------------------------------------------------------------------
  // Schema
  // ---------------------------------------------------------------------------

  void _onCreate() {
    // Legacy content tables — created here only so migration 3 can ALTER them
    // on existing databases. Migration 4 drops them immediately after.
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
  // Peers cache
  // ---------------------------------------------------------------------------

  /// Inserts or updates a cached peer entry.
  ///
  /// When [isFavorite] is provided it overrides the stored value; otherwise the
  /// existing `is_favorite` flag is preserved (defaulting to `false` on first
  /// insert).
  void upsertPeerCache(Peer peer, {bool? isFavorite}) {
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
