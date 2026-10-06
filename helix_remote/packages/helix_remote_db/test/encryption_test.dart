import 'dart:io';
import 'dart:isolate';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

import 'support.dart';

/// SQLCipher at rest (carried over from v1 P2-01) and background opening.
void main() {
  const marker = 'p2_plaintext_marker_alice_secret';

  Future<void> writeMarker(HelixDb db) async {
    final chat = await directChat(db, 'bob');
    await db.messagesDao.insertMessage(
      textMessage(chat.id, 'm1', sentAt: t0, body: marker),
    );
  }

  test(
    'P2-01 encrypted database rejects a wrong key and hides content',
    () async {
      final file = dbFile(tempDir());
      final key = DatabaseKey.generate();

      final db = await HelixDb.open(file, key: key);
      await writeMarker(db);
      // Content is on disk in the WAL before a checkpoint; check both states.
      expect(databaseFilesContain(file, marker), isFalse);
      await db.close();
      expect(databaseFilesContain(file, marker), isFalse);
      expect(hasPlaintextSqliteHeader(file), isFalse);

      await expectLater(
        HelixDb.open(file, key: DatabaseKey.generate()),
        throwsA(isA<DbEncryptionException>()),
      );
      expect(_opensWithoutKey(file), isFalse);

      final reopened = await HelixDb.open(file, key: key);
      addTearDown(reopened.close);
      final rows = await reopened.messagesDao.search('p2_plaintext_marker');
      expect(rows.single.body, marker);
    },
  );

  test('refuses a plaintext database file instead of opening it', () async {
    final file = dbFile(tempDir());
    sqlite.sqlite3.open(file.path)
      ..execute('CREATE TABLE t (x TEXT)')
      ..execute("INSERT INTO t VALUES ('$marker')")
      ..close();
    expect(hasPlaintextSqliteHeader(file), isTrue);

    await expectLater(
      HelixDb.open(file, key: DatabaseKey.generate()),
      throwsA(isA<DbEncryptionException>()),
    );
    expect(hasPlaintextSqliteHeader(file), isTrue, reason: 'left untouched');
  });

  test('the SQLCipher library is loaded and keys take effect', () {
    final raw = sqlite.sqlite3.openInMemory();
    addTearDown(raw.close);
    final version = raw.select('PRAGMA cipher_version').first.values.first;
    expect('$version', isNotEmpty);

    // The in-memory test opener can be encrypted too.
    final db = HelixDb.inMemory(key: DatabaseKey.generate());
    addTearDown(db.close);
    expect(
      db
          .customSelect('PRAGMA cipher_status')
          .getSingle()
          .then((r) => '${r.data.values.first}'),
      completion('1'),
    );
  });

  test('opens on a background isolate with WAL and foreign keys', () async {
    final file = dbFile(tempDir());
    final key = DatabaseKey.generate();
    final db = await HelixDb.open(file, key: key);

    Future<Object?> pragma(String name) async =>
        (await db.customSelect('PRAGMA $name').getSingle()).data.values.first;

    expect(await pragma('journal_mode'), 'wal');
    expect(await pragma('foreign_keys'), 1);

    // Statements run on another isolate: while a long query runs, this
    // isolate's event loop keeps going (a timer fires before it finishes).
    var slowDone = false;
    final slow = db
        .customSelect(
          'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n '
          'WHERE i < 3000000) SELECT count(*) AS c FROM n',
        )
        .getSingle()
        .whenComplete(() => slowDone = true);
    final doneWhenTimerFired = await Future<bool>.delayed(
      const Duration(milliseconds: 20),
      () => slowDone,
    );
    expect(doneWhenTimerFired, isFalse);
    expect((await slow).read<int>('c'), 3000000);

    await writeMarker(db);
    await db.close();

    // A second open (as the FCM background isolate does) sees the data.
    final count = await Isolate.run(_counter(file.path, key.bytes));
    expect(count, 1);
  });

  test('a database key is 32 bytes and never printed', () {
    final key = DatabaseKey.generate();
    expect(key.bytes, hasLength(32));
    expect(key.toString(), 'DatabaseKey(<redacted>)');
    expect(DatabaseKey(key.bytes), key);
    expect(() => DatabaseKey(const [1, 2, 3]), throwsArgumentError);
  });
}

/// A closure that captures only sendable values (a path and key bytes).
Future<int> Function() _counter(String path, List<int> keyBytes) =>
    () => _countInOtherIsolate(path, keyBytes);

Future<int> _countInOtherIsolate(String path, List<int> keyBytes) async {
  final other = await HelixDb.open(File(path), key: DatabaseKey(keyBytes));
  try {
    return (await other.messagesDao.pageOlder('direct:bob')).messages.length;
  } finally {
    await other.close();
  }
}

bool _opensWithoutKey(File file) {
  sqlite.Database? raw;
  try {
    raw = sqlite.sqlite3.open(file.path);
    raw.select('SELECT count(*) FROM sqlite_master;');
    return true;
  } on Object {
    return false;
  } finally {
    raw?.close();
  }
}
