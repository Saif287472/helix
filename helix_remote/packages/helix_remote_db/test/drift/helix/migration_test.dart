import 'dart:io';

import 'package:drift_dev/api/migrations_native.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;

/// Migration tests against the checked-in schema dumps (plan §6.2: every
/// migration has a drift_dev test from the first release onward).
///
/// When the schema changes: bump `HelixDb.schemaVersion`, add the step to
/// `HelixDb.migration`, run `dart run tool/codegen.dart`, and add a
/// data-integrity test below for the new step (see MODULE.md).
void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('the current schema version has a dump', () {
    final db = HelixDb.inMemory();
    addTearDown(db.close);
    expect(GeneratedHelper.versions.last, db.schemaVersion);
    expect(
      File(
        'drift_schemas/helix/drift_schema_v${db.schemaVersion}.json',
      ).existsSync(),
      isTrue,
    );
  });

  test('a fresh database matches the latest dump', () async {
    final latest = GeneratedHelper.versions.last;
    final schema = await verifier.schemaAt(latest);
    final db = HelixDb.withExecutor(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, latest);
  });

  // Every upgrade path between dumped versions, oldest to newest.
  final versions = GeneratedHelper.versions;
  for (final (i, from) in versions.indexed) {
    for (final to in versions.skip(i + 1)) {
      test('migrates from $from to $to', () async {
        final schema = await verifier.schemaAt(from);
        final db = HelixDb.withExecutor(schema.newConnection());
        addTearDown(db.close);
        await verifier.migrateAndValidate(db, to);
      });
    }
  }

  test(
    '1 to 2 keeps every schema-1 row and adds empty, working C4 tables',
    () async {
      final schema = await verifier.schemaAt(1);
      final old = v1.DatabaseAtV1(schema.newConnection());
      await old.customStatement(
        "INSERT INTO people (account_id, helix_name, updated_at) "
        "VALUES ('bob', 'Bob', 1000)",
      );
      await old.customStatement(
        "INSERT INTO conversations (id, kind, created_at) "
        "VALUES ('direct:bob', 'direct', 1000)",
      );
      await old.customStatement(
        "INSERT INTO settings (key, value, updated_at) VALUES ('k', '5', 1000)",
      );
      await old.close();

      final db = HelixDb.withExecutor(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 2);

      // Nothing from schema 1 moved or was lost.
      expect((await db.peopleDao.byAccount('bob'))?.helixName, 'Bob');
      expect(await db.conversationsDao.byId('direct:bob'), isNotNull);
      expect(await db.settingsDao.get(const Setting<int>('k', 0)), 5);

      // The C4 tables exist, are empty and accept writes (foreign keys and
      // indexes included).
      expect(await db.groupsDao.all(), isEmpty);
      expect(await db.callsDao.recent(), isEmpty);
      expect(await db.transfersDao.pending(), isEmpty);
      await db.groupsDao.upsert(
        GroupsCompanion.insert(
          id: 'g1',
          title: 'Team',
          role: 'owner',
          createdAt: DateTime.utc(2026, 10, 2),
        ),
      );
      expect((await db.groupsDao.byId('g1'))?.title, 'Team');
    },
  );
}
