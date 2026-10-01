import 'dart:typed_data';

import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/db/postgres_db.dart';
import 'package:helix_remote_server/src/platform/db/schema_names.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';
import '../support/test_platform.dart';

void main() {
  group('Db', skip: databaseTestSkipReason, () {
    late PostgresDb db;
    late String prefix;
    late String table;

    setUp(() async {
      db = await openTestDb();
      prefix = randomPrefix();
      final schema = '${prefix}db';
      table = '$schema.items';
      await db.execute('CREATE SCHEMA $schema');
      await db.execute(
        'CREATE TABLE $table (id uuid PRIMARY KEY, name text NOT NULL UNIQUE, '
        'body bytea, at timestamptz, meta jsonb, n int8)',
      );
    });

    tearDown(() async {
      await db.close();
      await dropSchemas(prefix);
    });

    test('typed parameters and row getters round-trip', () async {
      final at = DateTime.utc(2026, 10, 1, 9, 30, 1, 5);
      await db.execute(
        'INSERT INTO $table VALUES (@id:uuid, @name:text, @body:bytea, '
        '@at:timestamptz, @meta:jsonb, @n:int8)',
        {
          'id': '0192a4f0-0000-7000-8000-000000000001',
          'name': 'one',
          'body': Uint8List.fromList([0, 255, 7]),
          'at': at,
          'meta': '{"k":[1,2]}',
          'n': 1 << 40,
        },
      );
      final row = (await db.queryOne('SELECT * FROM $table'))!;
      expect(row.string('id'), '0192a4f0-0000-7000-8000-000000000001');
      expect(row.bytes('body'), [0, 255, 7]);
      expect(row.time('at'), at);
      expect(row.json('meta'), {
        'k': [1, 2],
      });
      expect(row.integer('n'), 1 << 40);
      expect(() => row.integer('name'), throwsStateError);
    });

    test(
      'tx commits, rolls back on error, and runs afterCommit only on commit',
      () async {
        final fired = <String>[];
        await db.tx((tx) async {
          await tx.execute(
            "INSERT INTO $table (id, name) VALUES (gen_random_uuid(), 'kept')",
          );
          tx.afterCommit(() async => fired.add('committed'));
        });
        await expectLater(
          db.tx((tx) async {
            await tx.execute(
              "INSERT INTO $table (id, name) VALUES (gen_random_uuid(), 'lost')",
            );
            tx.afterCommit(() async => fired.add('should not run'));
            throw StateError('boom');
          }),
          throwsStateError,
        );
        final names = (await db.query(
          'SELECT name FROM $table',
        )).map((r) => r.string('name'));
        expect(names, ['kept']);
        expect(fired, ['committed']);
      },
    );

    test('unique violations become DbConstraintViolation', () async {
      await db.execute(
        "INSERT INTO $table (id, name) VALUES (gen_random_uuid(), 'dup')",
      );
      await expectLater(
        db.execute(
          "INSERT INTO $table (id, name) VALUES (gen_random_uuid(), 'dup')",
        ),
        throwsA(
          isA<DbConstraintViolation>().having(
            (e) => e.kind,
            'kind',
            DbConstraintKind.unique,
          ),
        ),
      );
    });

    test('serialization failures are retried', () async {
      await db.execute(
        "INSERT INTO $table (id, name, n) VALUES (gen_random_uuid(), 'c', 0)",
      );
      var attempts = 0;
      final result = await db.tx((tx) async {
        attempts++;
        if (attempts == 1) {
          await tx.execute(
            "DO \$\$ BEGIN RAISE EXCEPTION 'retry me' USING ERRCODE = '40001'; END \$\$",
          );
        }
        return tx.execute("UPDATE $table SET n = n + 1 WHERE name = 'c'");
      });
      expect(result, 1);
      expect(attempts, 2);
    });

    test('LISTEN/NOTIFY delivers to listeners', () async {
      final channel = '${prefix}chan';
      final received = (await db.listen(channel)).first;
      await db.notify(channel, 'hello');
      expect(await received.timeout(const Duration(seconds: 5)), 'hello');
    });
  });

  group('MigrationRunner', skip: databaseTestSkipReason, () {
    late PostgresDb db;
    late SchemaNames schemas;

    setUp(() async {
      db = await openTestDb();
      schemas = SchemaNames(prefix: randomPrefix());
    });

    tearDown(() async {
      await db.close();
      await dropSchemas(schemas.prefix);
    });

    MigrationSet set(List<Migration> migrations) =>
        MigrationSet(module: 'demo', migrations: migrations);

    final first = Migration(
      1,
      'create',
      (s) => 'CREATE TABLE $s.t (id int PRIMARY KEY)',
    );
    final second = Migration(
      2,
      'add column',
      (s) => 'ALTER TABLE $s.t ADD COLUMN note text',
    );

    test('applies once, in order, into the module schema', () async {
      final runner = MigrationRunner(db, schemas);
      expect(
        (await runner.run([
          set([first]),
        ])).applied,
        ['demo:1'],
      );
      expect(
        (await runner.run([
          set([first, second]),
        ])).applied,
        ['demo:2'],
      );
      expect(
        (await runner.run([
          set([first, second]),
        ])).applied,
        isEmpty,
      );
      await db.execute("INSERT INTO ${schemas.of('demo')}.t VALUES (1, 'x')");
    });

    test('refuses an edited migration', () async {
      final runner = MigrationRunner(db, schemas);
      await runner.run([
        set([first]),
      ]);
      final edited = Migration(
        1,
        'create',
        (s) => 'CREATE TABLE $s.t (id bigint PRIMARY KEY)',
      );
      await expectLater(
        runner.run([
          set([edited]),
        ]),
        throwsA(isA<MigrationIntegrityError>()),
      );
    });

    test('a failing migration applies nothing', () async {
      final runner = MigrationRunner(db, schemas);
      final broken = Migration(
        2,
        'broken',
        (s) => 'ALTER TABLE $s.nope ADD COLUMN x int',
      );
      await expectLater(
        runner.run([
          set([first, broken]),
        ]),
        throwsA(anything),
      );
      expect(
        (await runner.run([
          set([first]),
        ])).applied,
        ['demo:1'],
      );
    });

    test('checksums do not depend on the schema prefix', () {
      expect(
        first.checksum,
        Migration(
          1,
          'create',
          (s) => 'CREATE TABLE $s.t (id int PRIMARY KEY)',
        ).checksum,
      );
    });

    test('versions must increase', () async {
      await expectLater(
        MigrationRunner(db, schemas).run([
          set([second, first]),
        ]),
        throwsA(isA<MigrationIntegrityError>()),
      );
    });

    test('concurrent runners serialize on the advisory lock', () async {
      final other = await openTestDb();
      try {
        final results = await Future.wait([
          MigrationRunner(db, schemas).run([
            set([first, second]),
          ]),
          MigrationRunner(other, schemas).run([
            set([first, second]),
          ]),
        ]);
        final applied = [...results[0].applied, ...results[1].applied]..sort();
        expect(applied, ['demo:1', 'demo:2']);
      } finally {
        await other.close();
      }
    });
  });
}
