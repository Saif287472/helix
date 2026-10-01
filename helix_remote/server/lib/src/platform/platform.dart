import 'package:helix_remote_server/src/platform/blobs/object_storage.dart';
import 'package:helix_remote_server/src/platform/bus/event_bus.dart';
import 'package:helix_remote_server/src/platform/clock.dart';
import 'package:helix_remote_server/src/platform/config/server_config.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/postgres_db.dart';
import 'package:helix_remote_server/src/platform/db/schema_names.dart';
import 'package:helix_remote_server/src/platform/ephemeral/ephemeral_store.dart';
import 'package:helix_remote_server/src/platform/http/idempotency.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
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
    required this._ephemeralDb,
    required this.bodyBudget,
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
    // Config errors in the push section surface before any connection opens.
    final pushProvider = push ?? pushProviderFrom(config);
    final db = await PostgresDb.open(
      config.databaseUrl,
      maxConnections: config.dbPoolSize,
    );
    // The ephemeral store has its own small pool. Presence is read inside
    // send transactions (messaging `deliver`); on the shared pool each
    // in-flight send held one connection while waiting for a second, so
    // ten concurrent sends deadlocked the node until the acquire timeout
    // (S7 load harness). This pool never waits on the main one, which is
    // also the scale-out shape (ephemeral store -> Redis).
    final ephemeralDb = await PostgresDb.open(
      config.databaseUrl,
      maxConnections: 4,
    );
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
    final outbox = Outbox(schemas.platform, bus);
    final bodyBudget = BodyBudget(config.maxInFlightBodyBytes);
    metrics
      ..collectedGauge(
        'helix_jobs_dead',
        'Outbox jobs that ran out of attempts (cluster-wide)',
        () async => (await outbox.deadCount(db)).toDouble(),
      )
      ..gauge(
        'helix_http_body_bytes_in_flight',
        'Request body bytes buffered on this node',
        () => bodyBudget.inFlight.toDouble(),
      );
    return HelixPlatform._(
      config: config,
      db: db,
      schemas: schemas,
      bus: bus,
      ephemeral: PostgresEphemeralStore(ephemeralDb, schemas.platform),
      rateLimiter: PostgresRateLimiter(db, schemas.platform),
      idempotency: PostgresIdempotencyStore(
        db,
        schemas.platform,
        IdempotencySealer(config.jwtKeys, config.activeJwtKid),
      ),
      outbox: outbox,
      bodyBudget: bodyBudget,
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
      push: pushProvider,
      ephemeralDb: ephemeralDb,
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

  /// Request body bytes this node buffers at once (`HELIX_MAX_INFLIGHT_BODY_BYTES`).
  final BodyBudget bodyBudget;
  final Db _ephemeralDb;

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
    await _ephemeralDb.close();
  }
}
