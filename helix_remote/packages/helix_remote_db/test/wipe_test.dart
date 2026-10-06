import 'dart:io';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Deleted data does not linger in the file (CRYPTO_V2.md §14: sign-out must
/// not leave key material recoverable). The tests read the bytes of an
/// *unencrypted* file database: an encrypted file never shows plaintext, so
/// it could not show a leak.
void main() {
  const marker = 'wipe_marker_ratchet_chain_key_0123456789';
  const setting = Setting<String?>('wipe.secret', null);

  Future<HelixDb> plainDb(File file) async {
    final db = await HelixDb.openPlainFileForTesting(file);
    addTearDown(db.close);
    return db;
  }

  Future<int> pragma(HelixDb db, String name) async {
    final rows = await db.customSelect('PRAGMA $name').get();
    return rows.first.data.values.first! as int;
  }

  test(
    'every connection overwrites deleted content and bounds the WAL',
    () async {
      final file = dbFile(tempDir());
      final key = DatabaseKey.generate();
      final db = await HelixDb.open(file, key: key);
      addTearDown(db.close);
      expect(await pragma(db, 'secure_delete'), 1);
      expect(await pragma(db, 'journal_size_limit'), walSizeLimitBytes);
      final memory = memoryDb();
      expect(await pragma(memory, 'secure_delete'), 1);
    },
  );

  test('a deleted value is gone from the file after a checkpoint, and would '
      'not be without secure_delete', () async {
    final file = dbFile(tempDir());
    final db = await plainDb(file);
    final chat = await directChat(db, 'bob');
    final row = await db.messagesDao.insertMessage(
      textMessage(chat.id, 'm1', sentAt: t0, body: marker),
    );
    await db.settingsDao.set(setting, marker);
    await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    expect(
      databaseFilesContain(file, marker),
      isTrue,
      reason: 'positive control: the file is plaintext, the marker is in it',
    );

    await db.messagesDao.removeMessages([row.localRowid]);
    await db.settingsDao.reset(setting);
    await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    expect(databaseFilesContain(file, marker), isFalse);

    // Negative control: the same steps without secure_delete leave it in a
    // free page, so the assertion above really detects a leak.
    final other = dbFile(tempDir());
    final leaky = await plainDb(other);
    await leaky.customStatement('PRAGMA secure_delete = OFF');
    await leaky.settingsDao.set(setting, marker);
    await leaky.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    await leaky.settingsDao.reset(setting);
    await leaky.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    expect(databaseFilesContain(other, marker), isTrue);
  });

  test('wipeAll leaves no trace of the data in the file or the log', () async {
    final file = dbFile(tempDir());
    final db = await plainDb(file);
    final chat = await directChat(db, 'bob');
    for (var i = 0; i < 40; i++) {
      await db.messagesDao.insertMessage(
        textMessage(chat.id, 'm$i', sentAt: at(i), body: '$marker $i'),
      );
    }
    await db.settingsDao.set(setting, marker);
    expect(
      databaseFilesContain(file, marker),
      isTrue,
      reason: 'positive control: it is in the file or the log',
    );

    await db.wipeAll();

    expect(databaseFilesContain(file, marker), isFalse);
    expect(await db.settingsDao.get(setting), isNull);
    expect(
      File('${file.path}-wal').existsSync()
          ? File('${file.path}-wal').lengthSync()
          : 0,
      0,
      reason: 'the log is truncated',
    );
    expect(
      await pragma(db, 'freelist_count'),
      0,
      reason: 'the file was vacuumed, no free pages are left',
    );
    // The database is usable again afterwards.
    await db.settingsDao.set(setting, 'again');
    expect(await db.settingsDao.get(setting), 'again');
  });

  test('wipeAll works on the encrypted file the app uses', () async {
    final file = dbFile(tempDir());
    final key = DatabaseKey.generate();
    final db = await HelixDb.open(file, key: key);
    addTearDown(db.close);
    await db.settingsDao.set(setting, marker);
    await db.wipeAll();
    expect(await db.settingsDao.get(setting), isNull);
    expect(hasPlaintextSqliteHeader(file), isFalse);
  });

  test('destroyDatabaseFiles removes the database and its companions, '
      'and a missing file is fine', () async {
    final dir = tempDir();
    final file = dbFile(dir);
    final db = await HelixDb.open(file, key: DatabaseKey.generate());
    await db.settingsDao.set(setting, marker);
    await db.close();
    File('${file.path}-wal').writeAsBytesSync(List.filled(100000, 7));
    File('${file.path}-shm').writeAsBytesSync([1, 2, 3]);
    expect(file.existsSync(), isTrue);

    await destroyDatabaseFiles(file);
    expect(file.existsSync(), isFalse);
    expect(File('${file.path}-wal').existsSync(), isFalse);
    expect(File('${file.path}-shm').existsSync(), isFalse);
    await destroyDatabaseFiles(file);
  });
}
