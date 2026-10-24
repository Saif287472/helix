import 'dart:async';

import 'package:helix_remote_server/src/platform/bus/event_bus.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/db/postgres_db.dart';
import 'package:helix_remote_server/src/platform/db/schema_names.dart';
import 'package:helix_remote_server/src/platform/jobs/jobs.dart';
import 'package:helix_remote_server/src/platform/observability/log.dart';
import 'package:helix_remote_server/src/platform/observability/metrics.dart';
import 'package:helix_remote_server/src/platform/platform_migrations.dart';
import 'package:test/test.dart';

import '../support/query_plans.dart';
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
      Duration jobTimeout = const Duration(seconds: 60),
      int batchSize = 5,
    }) => JobRunner(
      db: on,
      platformSchema: schemas.platform,
      bus: bus,
      nodeId: node,
      log: Log(sink: MemorySink()),
      metrics: Metrics(),
      settings: JobRunnerSettings(
        baseBackoff: backoff,
        batchSize: batchSize,
        jobTimeout: jobTimeout,
      ),
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
        // One batch: what a thousand-device fan-out enqueues as.
        await outbox().enqueueMany(tx, [
          for (var i = 0; i < 30; i++) QueuedJob('demo.ok', {'n': i}),
        ]);
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

    test('a dead job does not spend its dedupe key', () async {
      var calls = 0;
      final r = runner(db, 'n1')
        ..register('demo.flap', (p) async {
          calls++;
          if (calls == 1) throw StateError('the first attempt dies');
        });
      await db.tx(
        (tx) => outbox().enqueue(
          tx,
          'demo.flap',
          const {},
          dedupeKey: 'x',
          maxAttempts: 1,
        ),
      );
      await r.tick();
      expect(calls, 1);
      final dead = await db.queryOne(
        "SELECT dedupe_key FROM ${schemas.platform}.jobs WHERE status = 'dead'",
      );
      expect(dead!.string('dedupe_key'), 'x');

      // The same wake-up is asked for again - the next message for that
      // device, the next relay for that group. It must run: the dead row is
      // the operator's record, not a tombstone that silences the key for
      // ever (AUD-1b-1).
      await db.tx(
        (tx) => outbox().enqueue(tx, 'demo.flap', const {}, dedupeKey: 'x'),
      );
      await r.tick();
      expect(calls, 2);
      expect(
        await db.query(
          "SELECT id FROM ${schemas.platform}.jobs WHERE status = 'dead'",
        ),
        hasLength(1),
        reason: 'the dead row is still there for the operator',
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

    test('a fan-out enqueues with one statement and keeps each field', () async {
      // AUD-3-1: a push per recipient device used to be one insert and one
      // wake per device.
      final devices = List.generate(200, (i) => 'dev-$i');
      final log = <Statement>[];
      final wakes = <Map<String, Object?>>[];
      final sub = bus.subscribe(Outbox.wakeTopic).listen(wakes.add);
      await db.tx(
        (tx) => outbox().enqueueMany(Recording(tx, log), [
          for (final d in devices)
            QueuedJob(
              'demo.fan',
              {'device': d},
              maxAttempts: 3,
              dedupeKey: 'fan:$d',
            ),
          const QueuedJob('demo.later', {}, delay: Duration(hours: 1)),
          const QueuedJob('demo.free', {}),
          const QueuedJob('demo.free', {}),
        ]),
      );
      expect(log, hasLength(1), reason: '203 jobs through one insert');
      await Future<void>.delayed(Duration.zero);
      expect(wakes, hasLength(1), reason: 'and one wake for the whole batch');

      final rows = await db.query(
        'SELECT kind, payload, max_attempts, dedupe_key, run_at > now() AS later '
        'FROM ${schemas.platform}.jobs',
      );
      final fan = rows.where((r) => r.string('kind') == 'demo.fan').toList();
      expect(fan, hasLength(200));
      expect(
        fan.map((r) => r.json('payload')['device']).toSet(),
        devices.toSet(),
        reason: 'each row kept its own payload: the lists did not shift',
      );
      expect(fan.every((r) => r.integer('max_attempts') == 3), isTrue);
      expect(
        fan.map((r) => r.optString('dedupe_key')).toSet(),
        devices.map((d) => 'fan:$d').toSet(),
      );
      final free = rows.where((r) => r.string('kind') == 'demo.free');
      expect(free, hasLength(2), reason: 'a null dedupe key never conflicts');
      expect(
        rows
            .singleWhere((r) => r.string('kind') == 'demo.later')
            .boolean('later'),
        isTrue,
        reason: 'its own delay travelled with it',
      );

      // The same batch again: deduped rows are ignored, the rest are new.
      await db.tx(
        (tx) => outbox().enqueueMany(tx, [
          for (final d in devices)
            QueuedJob('demo.fan', {'device': d}, dedupeKey: 'fan:$d'),
          const QueuedJob('demo.free', {}),
        ]),
      );
      expect(await _pending(db, schemas.platform, 'demo.fan'), 200);
      expect(await _pending(db, schemas.platform, 'demo.free'), 3);
      await sub.cancel();
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

    test('a handler that never finishes does not stop the next job', () async {
      // The failure A-04: a job handler that hangs (a push provider whose
      // token endpoint stalled) holds the drain, later ticks join the pass in
      // flight, and nothing else runs on the node until it restarts.
      var quick = 0;
      final r =
          runner(
              db,
              'n1',
              jobTimeout: const Duration(milliseconds: 100),
              batchSize: 2,
            )
            ..register('demo.hang', (p) => Completer<void>().future)
            ..register('demo.quick', (p) async => quick++);
      await db.tx((tx) async {
        await outbox().enqueue(tx, 'demo.hang', const {}, maxAttempts: 1);
        await outbox().enqueue(tx, 'demo.quick', const {});
      });

      final started = DateTime.now();
      await r.tick();
      expect(
        DateTime.now().difference(started),
        lessThan(const Duration(seconds: 10)),
        reason: 'the pass ends at the timeout instead of never',
      );
      expect(quick, 1, reason: 'the other job in the batch still ran');

      // The hung job went back for a retry rather than being lost.
      final hung = await db.queryOne(
        "SELECT status, last_error FROM ${schemas.platform}.jobs WHERE kind = 'demo.hang'",
      );
      expect(hung!.string('status'), 'dead');
      expect(
        hung.string('last_error'),
        contains('TimeoutException'),
        reason: 'a timeout is recorded as the failure it was',
      );
    });

    test('a periodic job that never finishes releases the loop', () async {
      // Same shape one layer up: the periodic loop runs its jobs one after
      // another, so one that hangs stops every later job on the node.
      final ran = <String>[];
      final scheduler =
          PeriodicScheduler(
              db: db,
              platformSchema: schemas.platform,
              nodeId: 'n1',
              log: Log(sink: MemorySink()),
              jobTimeout: const Duration(milliseconds: 100),
            )
            ..register(
              PeriodicJob(
                'demo.hang',
                const Duration(minutes: 5),
                () => Completer<void>().future,
              ),
            )
            ..register(
              PeriodicJob('demo.after', const Duration(minutes: 5), () async {
                ran.add('after');
              }),
            );
      await scheduler.start();
      await scheduler.tick();

      expect(ran, ['after']);
      // Its lease is released, so it runs again next interval instead of
      // staying claimed.
      final locked = await db.queryOne(
        "SELECT locked_until FROM ${schemas.platform}.periodic_jobs "
        "WHERE name = 'demo.hang'",
      );
      expect(locked!.isNull('locked_until'), isTrue);
      await scheduler.stop();
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

/// Jobs of [kind] still waiting to run.
Future<int> _pending(PostgresDb db, String platform, String kind) async =>
    (await db.queryOne(
      "SELECT count(*)::int8 AS n FROM $platform.jobs "
      "WHERE kind = @k:text AND status = 'pending'",
      {'k': kind},
    ))!.integer('n');
