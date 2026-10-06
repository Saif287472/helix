import 'package:test/test.dart';

import 'support/test_database.dart';

/// Phase 0 proof that the test database is reachable, is the PostgreSQL major
/// version the server targets (ADR-025), and that the per-test schema
/// harness isolates and cleans up.
void main() {
  group('test database', skip: databaseTestSkipReason, () {
    test('is PostgreSQL 17 or newer', () async {
      final connection = await openTestConnection();
      try {
        final result = await connection.execute('SHOW server_version_num');
        final version = int.parse(result.single.single! as String);
        expect(version, greaterThanOrEqualTo(170000));
      } finally {
        await connection.close();
      }
    });

    test('withTestSchema isolates tables and drops the schema', () async {
      final schema = await withTestSchema((connection, schema) async {
        await connection.execute(
          'CREATE TABLE probe (id uuid PRIMARY KEY, body bytea NOT NULL)',
        );
        await connection.execute(
          "INSERT INTO probe VALUES (gen_random_uuid(), '\\x00ff'::bytea)",
        );
        final rows = await connection.execute(
          'SELECT count(*) FROM $schema.probe',
        );
        expect(rows.single.single, 1);
        return schema;
      });

      final connection = await openTestConnection();
      try {
        final left = await connection.execute(
          'SELECT count(*) FROM information_schema.schemata '
          "WHERE schema_name = '$schema'",
        );
        expect(left.single.single, 0);
      } finally {
        await connection.close();
      }
    });
  });
}
