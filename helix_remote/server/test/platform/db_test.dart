import 'dart:async';
import 'dart:typed_data';

import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/db/postgres_db.dart';
import 'package:helix_remote_server/src/platform/db/schema_names.dart';
import 'package:postgres/postgres.dart' as pg;
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

    test(
      'a read-only snapshot is chosen when the transaction begins, and keeps '
      'its timeouts',
      () async {
        // The compliance export used `SET TRANSACTION` inside the body, which
        // Postgres refuses once the timeouts have been set (a 500).
        final settings = await db.tx(
          (tx) async => (await tx.queryOne(
            "SELECT current_setting('transaction_isolation') AS iso, "
            "current_setting('transaction_read_only') AS ro, "
            "current_setting('statement_timeout') AS st",
          ))!,
          readOnlySnapshot: true,
        );
        expect(settings.string('iso'), 'repeatable read');
        expect(settings.string('ro'), 'on');
        expect(settings.string('st'), '15s');
        await expectLater(
          db.tx(
            (tx) => tx.execute(
              "INSERT INTO $table (id, name) VALUES (gen_random_uuid(), 'x')",
            ),
            readOnlySnapshot: true,
          ),
          throwsA(anything),
          reason: 'read only',
        );
      },
    );

    test('a transaction gives up on a lock wait instead of hanging', () async {
      // A-07: a long lock (a row held FOR UPDATE by a fan-out) used to make
      // requests queue for minutes on a pool connection, and every other
      // request then waited for a connection that never came back.
      await db.execute(
        "INSERT INTO $table (id, name) VALUES (gen_random_uuid(), 'locked')",
      );
      final holder = await openTestDb();
      addTearDown(holder.close);
      // Another connection holds the row, then lets go (so the test ends).
      final blocker = holder.tx((tx) async {
        await tx.execute(
          "SELECT * FROM $table WHERE name = 'locked' FOR UPDATE",
        );
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      // The row is locked by another connection now.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      await expectLater(
        db.tx(
          (tx) => tx.execute(
            "UPDATE $table SET name = 'taken' WHERE name = 'locked'",
          ),
          lockTimeout: const Duration(milliseconds: 300),
        ),
        throwsA(
          isA<pg.ServerException>().having(
            (e) => e.code,
            'code',
            '55P03', // lock_not_available
          ),
        ),
      );
      // The pool connection came back: the next transaction runs.
      expect(await db.tx((tx) => tx.queryOne('SELECT 1 AS x')), isNotNull);
      await blocker;
    });

    test(
      'a migration-style transaction runs without a statement timeout',
      () async {
        // The zero that `MigrationRunner` passes means "no limit" (Postgres's
        // own meaning), which is what index builds and purges need.
        await expectLater(
          db.tx(
            (tx) => tx.execute('SELECT pg_sleep(0.3)'),
            statementTimeout: Duration.zero,
            lockTimeout: Duration.zero,
          ),
          completes,
        );
        // The connection default is still in force for the next transaction.
        await expectLater(
          db.tx(
            (tx) => tx.execute('SELECT pg_sleep(0.3)'),
            statementTimeout: const Duration(milliseconds: 100),
          ),
          throwsA(
            isA<pg.ServerException>().having((e) => e.code, 'code', '57014'),
          ),
        );
      },
    );

    test('a failing after-commit action neither fails the request nor skips '
        'the rest', () async {
      // A-08: after-commit actions are best effort. The first one throwing
      // used to answer 500 for a change that had been committed and to
      // skip every publish after it.
      final fired = <String>[];
      await db.tx((tx) async {
        await tx.execute(
          "INSERT INTO $table (id, name) VALUES (gen_random_uuid(), 'kept')",
        );
        tx.afterCommit(() async {
          fired.add('first');
          throw StateError('the bus is down');
        });
        tx.afterCommit(() async => fired.add('second'));
      });
      expect(fired, [
        'first',
        'second',
      ], reason: 'the failure is contained and the rest still ran');
      expect(
        (await db.query(
          'SELECT name FROM $table',
        )).map((r) => r.string('name')),
        ['kept'],
      );
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
