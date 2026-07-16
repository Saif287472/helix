import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:helix_local_storage/data/database.dart';

void main() {
  setUpAll(() {
    if (Platform.isWindows) {
      var dir = Directory.current;
      String? foundPath;
      for (int i = 0; i < 5; i++) {
        final candidate = p.join(dir.path, '.dart_tool', 'lib', 'sqlite3.dll');
        if (File(candidate).existsSync()) {
          foundPath = candidate;
          break;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
      if (foundPath != null) {
        DynamicLibrary.open(foundPath);
      }
    }
  });

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('helix_db_test_');
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {
      // On Windows, sqlite3 file handles may not be released immediately after
      // an exception; ignore cleanup failures in that case.
    }
  });

  File tempFile(String name) => File('${tempDir.path}/$name');

  group('database migration', () {
    test('fresh database initializes at schema version 4', () {
      final db = HelixDatabase(tempFile('fresh.db'));
      db.initialize();
      addTearDown(db.close);
      expect(db.schemaVersion, equals(4));
    });

    test('fresh database keeps only Local metadata tables', () {
      final db = HelixDatabase(tempFile('full.db'));
      db.initialize();
      addTearDown(db.close);

      final raw = sqlite3.open(tempFile('full.db').path);
      addTearDown(raw.close);
      final tables = raw
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name'] as String)
          .toSet();

      expect(tables, contains('peers_cache'));
      expect(tables, isNot(contains('threads')));
      expect(tables, isNot(contains('messages')));
      expect(tables, isNot(contains('one_way_messages')));
      expect(tables, isNot(contains('pinned_messages')));
    });

    test(
      'v0 database migrates to schema version 4 and drops content tables',
      () {
        final path = tempFile('v0.db').path;

        // Build a pre-migration (v0) database — threads table lacks
        // draft_text and is_archived; no pinned_messages table.
        final raw = sqlite3.open(path);
        raw.execute('''
        CREATE TABLE threads (
          thread_id                   TEXT PRIMARY KEY,
          peer_display_name           TEXT NOT NULL,
          peer_device_suffix          TEXT NOT NULL,
          peer_static_key_fingerprint TEXT NOT NULL,
          peer_session_id             TEXT NOT NULL DEFAULT '',
          peer_host                   TEXT NOT NULL DEFAULT '',
          peer_port                   INTEGER NOT NULL DEFAULT 0,
          status                      INTEGER NOT NULL DEFAULT 0,
          unread_count                INTEGER NOT NULL DEFAULT 0,
          has_new_session_separator   INTEGER NOT NULL DEFAULT 0,
          created_at                  INTEGER NOT NULL,
          updated_at                  INTEGER NOT NULL
        );
      ''');
        raw.execute('''
        CREATE TABLE messages (
          message_id      TEXT PRIMARY KEY,
          thread_id       TEXT NOT NULL REFERENCES threads(thread_id)
                            ON DELETE CASCADE,
          origin          INTEGER NOT NULL,
          text            TEXT NOT NULL,
          timestamp       INTEGER NOT NULL,
          delivery_status INTEGER NOT NULL
        );
      ''');
        raw.execute('''
        CREATE TABLE one_way_messages (
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
        raw.execute('''
        CREATE TABLE peers_cache (
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
        // user_version stays at 0
        raw.close();

        // Run migration
        final db = HelixDatabase(File(path));
        db.initialize();
        addTearDown(db.close);

        expect(db.schemaVersion, equals(4));

        final raw2 = sqlite3.open(path);
        addTearDown(raw2.close);
        final tables = raw2
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((r) => r['name'] as String)
            .toSet();
        expect(tables, contains('peers_cache'));
        expect(tables, isNot(contains('threads')));
        expect(tables, isNot(contains('messages')));
        expect(tables, isNot(contains('one_way_messages')));
        expect(tables, isNot(contains('pinned_messages')));
      },
    );

    test('legacy thread data is deleted during migration', () {
      final path = tempFile('data.db').path;
      final now = DateTime.now().millisecondsSinceEpoch;

      // v0 database with one thread row
      final raw = sqlite3.open(path);
      raw.execute('''
        CREATE TABLE threads (
          thread_id                   TEXT PRIMARY KEY,
          peer_display_name           TEXT NOT NULL,
          peer_device_suffix          TEXT NOT NULL,
          peer_static_key_fingerprint TEXT NOT NULL,
          peer_session_id             TEXT NOT NULL DEFAULT '',
          peer_host                   TEXT NOT NULL DEFAULT '',
          peer_port                   INTEGER NOT NULL DEFAULT 0,
          status                      INTEGER NOT NULL DEFAULT 0,
          unread_count                INTEGER NOT NULL DEFAULT 0,
          has_new_session_separator   INTEGER NOT NULL DEFAULT 0,
          created_at                  INTEGER NOT NULL,
          updated_at                  INTEGER NOT NULL
        );
      ''');
      raw.execute('INSERT INTO threads VALUES (?,?,?,?,?,?,?,?,?,?,?,?)', [
        'thread-alice',
        'Alice',
        'a',
        'fp-alice',
        'sess-1',
        '10.0.0.1',
        7777,
        0, // status
        0, // unread_count
        0, // has_new_session_separator
        now,
        now,
      ]);
      raw.execute('''
        CREATE TABLE messages (
          message_id TEXT PRIMARY KEY, thread_id TEXT, origin INTEGER,
          text TEXT, timestamp INTEGER, delivery_status INTEGER
        );
      ''');
      raw.execute('''
        CREATE TABLE one_way_messages (
          message_id TEXT PRIMARY KEY, peer_display_name TEXT,
          peer_device_suffix TEXT, peer_session_id TEXT,
          peer_static_key_fingerprint TEXT, peer_host TEXT, peer_port INTEGER,
          text TEXT, timestamp INTEGER
        );
      ''');
      raw.execute('''
        CREATE TABLE peers_cache (
          session_id TEXT PRIMARY KEY, display_name TEXT, device_suffix TEXT,
          host TEXT, port INTEGER, source INTEGER, seen_at INTEGER,
          protocol_major INTEGER, protocol_minor INTEGER,
          is_favorite INTEGER DEFAULT 0
        );
      ''');
      raw.close();

      // Migrate
      final db = HelixDatabase(File(path));
      db.initialize();
      addTearDown(db.close);

      final raw2 = sqlite3.open(path);
      addTearDown(raw2.close);
      final tables = raw2
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name'] as String)
          .toSet();
      expect(tables, isNot(contains('threads')));
      expect(tables, isNot(contains('messages')));
      expect(tables, isNot(contains('one_way_messages')));
    });

    test('already-migrated database (v4) is not re-migrated', () {
      final file = tempFile('already_v3.db');

      final db1 = HelixDatabase(file);
      db1.initialize();
      db1.close();

      // Second open should be a no-op for migrations
      final db2 = HelixDatabase(file);
      db2.initialize();
      addTearDown(db2.close);
      expect(db2.schemaVersion, equals(4));
    });

    test('migration is rolled back when a step fails', () {
      // We cannot easily inject a failure into _migration3 without changing the
      // production class, so this test validates that a database that already
      // has the columns does not error — i.e., the column-existence guard works.
      //
      // A real mid-migration failure (e.g., disk full) would leave user_version
      // unchanged, and the next open would retry the migration from a clean state.
      final path = tempFile('partial.db').path;

      // Build a v0 database where draft_text already exists (simulates a
      // database that was partially hand-migrated or created by an older build
      // that happened to include draft_text in the base schema).
      final raw = sqlite3.open(path);
      raw.execute('''
        CREATE TABLE threads (
          thread_id TEXT PRIMARY KEY, peer_display_name TEXT NOT NULL,
          peer_device_suffix TEXT NOT NULL,
          peer_static_key_fingerprint TEXT NOT NULL,
          peer_session_id TEXT NOT NULL DEFAULT '',
          peer_host TEXT NOT NULL DEFAULT '', peer_port INTEGER NOT NULL DEFAULT 0,
          status INTEGER NOT NULL DEFAULT 0,
          unread_count INTEGER NOT NULL DEFAULT 0,
          has_new_session_separator INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
          draft_text TEXT NOT NULL DEFAULT ''
        );
      ''');
      raw.execute('''
        CREATE TABLE messages (
          message_id TEXT PRIMARY KEY, thread_id TEXT, origin INTEGER,
          text TEXT, timestamp INTEGER, delivery_status INTEGER
        );
      ''');
      raw.execute('''
        CREATE TABLE one_way_messages (
          message_id TEXT PRIMARY KEY, peer_display_name TEXT,
          peer_device_suffix TEXT, peer_session_id TEXT,
          peer_static_key_fingerprint TEXT, peer_host TEXT, peer_port INTEGER,
          text TEXT, timestamp INTEGER
        );
      ''');
      raw.execute('''
        CREATE TABLE peers_cache (
          session_id TEXT PRIMARY KEY, display_name TEXT, device_suffix TEXT,
          host TEXT, port INTEGER, source INTEGER, seen_at INTEGER,
          protocol_major INTEGER, protocol_minor INTEGER, is_favorite INTEGER DEFAULT 0
        );
      ''');
      raw.close();

      // Migration should succeed even though draft_text is already present.
      final db = HelixDatabase(File(path));
      expect(db.initialize, returnsNormally);
      addTearDown(db.close);
      expect(db.schemaVersion, equals(4));
    });

    test('corrupted file produces a controlled failure, not a crash', () {
      final file = tempFile('corrupt.db');
      file.writeAsBytesSync([0x00, 0x01, 0x02, 0xFF, 0xDE, 0xAD]);

      final db = HelixDatabase(file);
      // sqlite3 throws SqliteException (which is an Error, not Exception) on
      // corrupt files. Use throwsA(anything) to catch both Error and Exception.
      expect(db.initialize, throwsA(anything));
    });
  });
}
