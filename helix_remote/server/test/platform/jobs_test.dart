import 'package:helix_remote_server/src/platform/bus/event_bus.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/db/postgres_db.dart';
import 'package:helix_remote_server/src/platform/db/schema_names.dart';
import 'package:helix_remote_server/src/platform/jobs/jobs.dart';
import 'package:helix_remote_server/src/platform/observability/log.dart';
import 'package:helix_remote_server/src/platform/observability/metrics.dart';
import 'package:helix_remote_server/src/platform/platform_migrations.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';
import '../support/test_platform.dart';

void main() {
  group('outbox and job runner', skip: databaseTestSkipReason, () {
    late PostgresDb db;
    late PostgresDb otherNode;
    late SchemaNames schemas;
    late InMemoryEventBus bus;

    setUp(() async {
      db = await openTestDb();
      otherNode = await openTestDb();
      schemas = SchemaNames(prefix: randomPrefix());
      bus = InMemoryEventBus();
      await MigrationRunner(db, schemas).run([platformMigrations]);
    });

    tearDown(() async {
      await db.close();
      await otherNode.close();
      await dropSchemas(schemas.prefix);
    });

    JobRunner runner(
      PostgresDb on,
      String node, {
      Duration backoff = Duration.zero,
    }) => JobRunner(
      db: on,
      platformSchema: schemas.platform,
      bus: bus,
      nodeId: node,
      log: Log(sink: MemorySink()),
      metrics: Metrics(),
      settings: JobRunnerSettings(baseBackoff: backoff, batchSize: 5),
    );

    Outbox outbox() => Outbox(schemas.platform, bus);

    test('jobs enqueued in a rolled-back transaction never run', () async {
      final ran = <Object?>[];
      final r = runner(db, 'n1')
        ..register('demo.ok', (p) async => ran.add(p['n']));
      await db.tx((tx) => outbox().enqueue(tx, 'demo.ok', {'n': 1}));
      await expectLater(
        db.tx((tx) async {
          await outbox().enqueue(tx, 'demo.ok', {'n': 2});
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(await r.tick(), 1);
      expect(ran, [1]);
      expect(await r.tick(), 0, reason: 'done jobs are deleted');
    });

    test('two nodes never run the same job', () async {
      final ranOn = <String, List<int>>{'n1': [], 'n2': []};
      final r1 = runner(db, 'n1')
        ..register('demo.ok', (p) async => ranOn['n1']!.add(p['n']! as int));
      final r2 = runner(otherNode, 'n2')
        ..register('demo.ok', (p) async => ranOn['n2']!.add(p['n']! as int));
      await db.tx((tx) async {
        for (var i = 0; i < 30; i++) {
          await outbox().enqueue(tx, 'demo.ok', {'n': i});
        }
      });
      await Future.wait([r1.tick(), r2.tick()]);
      final all = [...ranOn['n1']!, ...ranOn['n2']!]..sort();
      expect(all, List.generate(30, (i) => i));
    });

    test('failures retry with backoff, then go dead', () async {
      var calls = 0;
      final r = runner(db, 'n1')
        ..register('demo.fail', (p) async {
          calls++;
          throw StateError('nope');
        });
      await db.tx(
        (tx) => outbox().enqueue(tx, 'demo.fail', const {}, maxAttempts: 3),
      );
      for (var i = 0; i < 5; i++) {
        await r.tick();
      }
      expect(calls, 3);
      final row = await db.queryOne(
        'SELECT status, attempts, last_error FROM ${schemas.platform}.jobs',
      );
      expect(row!.string('status'), 'dead');
      expect(row.integer('attempts'), 3);
      expect(
        row.string('last_error'),
        'StateError',
        reason: 'type only, never the message',
      );
    });

    test('dedupe keys collapse pending duplicates', () async {
      var calls = 0;
      final r = runner(db, 'n1')..register('demo.once', (p) async => calls++);
      await db.tx((tx) async {
        await outbox().enqueue(tx, 'demo.once', const {}, dedupeKey: 'x');
        await outbox().enqueue(tx, 'demo.once', const {}, dedupeKey: 'x');
      });
      await r.tick();
      expect(calls, 1);
    });

    test('delayed jobs wait', () async {
      var calls = 0;
      final r = runner(db, 'n1')..register('demo.later', (p) async => calls++);
      await db.tx(
        (tx) => outbox().enqueue(
          tx,
          'demo.later',
          const {},
          delay: const Duration(hours: 1),
        ),
      );
      await r.tick();
      expect(calls, 0);
    });

    test('periodic jobs run once per interval across nodes', () async {
      final runs = <String>[];
      PeriodicScheduler scheduler(PostgresDb on, String node) =>
          PeriodicScheduler(
            db: on,
            platformSchema: schemas.platform,
            nodeId: node,
            log: Log(sink: MemorySink()),
          )..register(
            PeriodicJob(
              'demo.sweep',
              const Duration(hours: 1),
              () async => runs.add(node),
            ),
          );
      final s1 = scheduler(db, 'n1');
      final s2 = scheduler(otherNode, 'n2');
      await s1.start();
      await s2.start();
      await Future.wait([s1.tick(), s2.tick()]);
      await Future.wait([s1.tick(), s2.tick()]);
      await s1.stop();
      await s2.stop();
      expect(runs, hasLength(1));
    });
  });
}
