import 'package:helix_remote_server/src/platform/blobs/object_storage.dart';
import 'package:helix_remote_server/src/platform/bus/event_bus.dart';
import 'package:helix_remote_server/src/platform/clock.dart';
import 'package:helix_remote_server/src/platform/config/server_config.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/postgres_db.dart';
import 'package:helix_remote_server/src/platform/db/schema_names.dart';
import 'package:helix_remote_server/src/platform/ephemeral/ephemeral_store.dart';
import 'package:helix_remote_server/src/platform/http/idempotency.dart';
import 'package:helix_remote_server/src/platform/jobs/jobs.dart';
import 'package:helix_remote_server/src/platform/module.dart';
import 'package:helix_remote_server/src/platform/observability/log.dart';
import 'package:helix_remote_server/src/platform/observability/metrics.dart';
import 'package:helix_remote_server/src/platform/push/push.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';

/// The shared infrastructure of one server process, built from config.
/// Everything here is safe to run on several nodes against one database.
final class HelixPlatform {
  HelixPlatform._({
    required this.config,
    required this.db,
    required this.schemas,
    required this.bus,
    required this.ephemeral,
    required this.rateLimiter,
    required this.idempotency,
    required this.outbox,
    required this.jobs,
    required this.periodic,
    required this.blobs,
    required this.clock,
    required this.log,
    required this.metrics,
    required this.health,
    required this.push,
  });

  static Future<HelixPlatform> open(
    ServerConfig config, {
    Log? log,
    Clock clock = const SystemClock(),
    ObjectStorage? blobs,
    PushProvider? push,
  }) async {
    final logger = log ?? Log();
    final schemas = SchemaNames(prefix: config.schemaPrefix);
    final db = await PostgresDb.open(config.databaseUrl);
    final metrics = Metrics();
    final bus = PostgresEventBus(db, prefix: config.schemaPrefix);
    final storage =
        blobs ??
        switch (config.blobs.backend) {
          BlobBackend.local => LocalObjectStorage(config.blobs.directory!),
          BlobBackend.s3 => S3ObjectStorage(config.blobs.s3!),
        };
    final health = HealthRegistry()
      ..add('database', db.ping)
      ..add('storage', storage.ping);
    return HelixPlatform._(
      config: config,
      db: db,
      schemas: schemas,
      bus: bus,
      ephemeral: PostgresEphemeralStore(db, schemas.platform),
      rateLimiter: PostgresRateLimiter(db, schemas.platform),
      idempotency: PostgresIdempotencyStore(db, schemas.platform),
      outbox: Outbox(schemas.platform, bus),
      jobs: JobRunner(
        db: db,
        platformSchema: schemas.platform,
        bus: bus,
        nodeId: config.nodeId,
        log: logger,
        metrics: metrics,
      ),
      periodic: PeriodicScheduler(
        db: db,
        platformSchema: schemas.platform,
        nodeId: config.nodeId,
        log: logger,
      ),
      blobs: storage,
      clock: clock,
      log: logger,
      metrics: metrics,
      health: health,
      push: push ?? pushProviderFrom(config),
    );
  }

  final ServerConfig config;
  final Db db;
  final SchemaNames schemas;
  final EventBus bus;
  final EphemeralStore ephemeral;
  final RateLimiter rateLimiter;
  final IdempotencyStore idempotency;
  final Outbox outbox;
  final JobRunner jobs;
  final PeriodicScheduler periodic;
  final ObjectStorage blobs;
  final Clock clock;
  final Log log;
  final Metrics metrics;
  final HealthRegistry health;
  final PushProvider push;

  ModuleContext moduleContext() => ModuleContext(
    config: config,
    db: db,
    schemas: schemas,
    bus: bus,
    ephemeral: ephemeral,
    rateLimiter: rateLimiter,
    outbox: outbox,
    blobs: blobs,
    clock: clock,
    log: log,
    metrics: metrics,
    health: health,
    push: push,
  );

  /// Platform housekeeping, run once per interval cluster-wide.
  List<PeriodicJob> get housekeeping => [
    PeriodicJob(
      'platform.sweep_ephemeral',
      const Duration(minutes: 1),
      () async {
        await ephemeral.sweep();
      },
    ),
    PeriodicJob(
      'platform.sweep_rate_buckets',
      const Duration(minutes: 10),
      () async {
        await rateLimiter.sweep();
      },
    ),
    PeriodicJob(
      'platform.sweep_idempotency',
      const Duration(hours: 1),
      () async {
        await idempotency.sweep();
      },
    ),
  ];

  bool _closed = false;

  /// Closes the bus and database. Safe to call more than once.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await bus.close();
    await db.close();
  }
}
