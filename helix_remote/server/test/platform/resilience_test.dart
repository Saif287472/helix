import 'package:helix_remote_server/src/platform/bus/event_bus.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/db/schema_names.dart';
import 'package:helix_remote_server/src/platform/jobs/jobs.dart';
import 'package:helix_remote_server/src/platform/observability/log.dart';
import 'package:helix_remote_server/src/platform/observability/metrics.dart';
import 'package:helix_remote_server/src/platform/platform_migrations.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';
import '../support/test_platform.dart';

/// Failures found by the S7 load harness (tool/load.dart).
void main() {
  group('under load', skip: databaseTestSkipReason, () {
    test(
      'background loops log a failed pass instead of ending the process',
      () async {
        final schemas = SchemaNames(prefix: randomPrefix());
        final db = await openTestDb();
        final sink = MemorySink();
        final log = Log(sink: sink);
        try {
          await MigrationRunner(db, schemas).run([platformMigrations]);
          final jobs = JobRunner(
            db: db,
            platformSchema: schemas.platform,
            bus: InMemoryEventBus(),
            nodeId: 'n1',
            log: log,
            metrics: Metrics(),
            settings: const JobRunnerSettings(
              pollInterval: Duration(milliseconds: 20),
            ),
          )..register('noop', (_) async {});
          final periodic = PeriodicScheduler(
            db: db,
            platformSchema: schemas.platform,
            nodeId: 'n1',
            log: log,
            checkInterval: const Duration(milliseconds: 20),
          )..register(PeriodicJob('noop', Duration.zero, () async {}));
          await periodic.start();
          jobs.start();
          // Every query now fails, as when the pool times out. Before the
          // fix the first failed tick was an unhandled error (test fails).
          await db.close();
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await jobs.stop();
          await periodic.stop();
          final events = sink.lines.join('\n');
          expect(events, contains('jobs_tick_failed'));
          expect(events, contains('periodic_tick_failed'));
        } finally {
          await dropSchemas(schemas.prefix);
        }
      },
    );

    test('more concurrent transactions than pool connections can read the '
        'ephemeral store inside the transaction', () async {
      final env = await TestPlatform.open();
      try {
        final p = env.platform;
        await MigrationRunner(p.db, p.schemas).run([platformMigrations]);
        await p.ephemeral.put('k', 'v', const Duration(minutes: 1));
        // messaging `deliver` reads presence inside the send transaction.
        // On one shared 10-connection pool this deadlocked until the
        // 15 s acquire timeout.
        final values = await Future.wait([
          for (var i = 0; i < 25; i++)
            p.db.tx((tx) async {
              await tx.execute('SELECT pg_sleep(0.05)');
              return p.ephemeral.get('k');
            }),
        ]).timeout(const Duration(seconds: 10));
        expect(values, everyElement('v'));
      } finally {
        await env.dispose();
      }
    });
  });
}
