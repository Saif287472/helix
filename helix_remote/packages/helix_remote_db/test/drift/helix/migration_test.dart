import 'dart:io';

import 'package:drift_dev/api/migrations_native.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'generated/schema.dart';

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

  // Every upgrade path between dumped versions, oldest to newest. Empty
  // while only schema 1 exists.
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
}
