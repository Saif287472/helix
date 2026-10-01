import 'package:helix_remote_server/src/platform/blobs/object_storage.dart';
import 'package:helix_remote_server/src/platform/bus/event_bus.dart';
import 'package:helix_remote_server/src/platform/clock.dart';
import 'package:helix_remote_server/src/platform/config/server_config.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/db/schema_names.dart';
import 'package:helix_remote_server/src/platform/ephemeral/ephemeral_store.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/jobs/jobs.dart';
import 'package:helix_remote_server/src/platform/observability/log.dart';
import 'package:helix_remote_server/src/platform/observability/metrics.dart';
import 'package:helix_remote_server/src/platform/push/push.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';

/// Readiness checks by name (`GET /v1/health/ready`).
final class HealthRegistry {
  final Map<String, Future<bool> Function()> _checks = {};

  void add(String name, Future<bool> Function() check) {
    if (_checks.containsKey(name)) throw StateError('health check $name twice');
    _checks[name] = check;
  }

  Future<Map<String, bool>> run() async {
    final results = <String, bool>{};
    for (final e in _checks.entries) {
      try {
        results[e.key] = await e.value().timeout(const Duration(seconds: 3));
      } on Object {
        results[e.key] = false;
      }
    }
    return results;
  }
}

/// Everything a module may use. Modules get infrastructure only from here
/// and other modules only through their `api.dart` facades (ADR-026).
final class ModuleContext {
  ModuleContext({
    required this.config,
    required this.db,
    required this.schemas,
    required this.bus,
    required this.ephemeral,
    required this.rateLimiter,
    required this.outbox,
    required this.blobs,
    required this.clock,
    required this.log,
    required this.metrics,
    required this.health,
    required this.push,
  });

  final ServerConfig config;
  final Db db;
  final SchemaNames schemas;
  final EventBus bus;
  final EphemeralStore ephemeral;
  final RateLimiter rateLimiter;
  final Outbox outbox;
  final ObjectStorage blobs;
  final Clock clock;
  final Log log;
  final Metrics metrics;
  final HealthRegistry health;

  /// Data-only device wake-ups (FCM).
  final PushProvider push;

  /// The schema of [module] (its own name for a module's own tables).
  String schema(String module) => schemas.of(module);
}

/// One area of the server (ADR-026). The server is a list of these.
abstract interface class HelixModule {
  /// Module name, which is also its Postgres schema name.
  String get name;

  List<Migration> get migrations;

  /// Registers this module's catalog routes.
  void routes(RouteRegistry routes);

  /// Outbox job handlers by job kind (kinds are `<module>.<name>`).
  Map<String, JobHandler> get jobs;

  List<PeriodicJob> get periodic;

  /// Called after migrations, before the server accepts requests.
  Future<void> start();

  Future<void> stop();
}

/// Defaults for modules that do not need every hook.
abstract base class ModuleBase implements HelixModule {
  ModuleBase(this.context);

  final ModuleContext context;

  late final Log log = context.log.child({'module': name});

  /// This module's schema.
  String get schema => context.schema(name);

  @override
  List<Migration> get migrations => const [];

  @override
  Map<String, JobHandler> get jobs => const {};

  @override
  List<PeriodicJob> get periodic => const [];

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

/// Implemented by the module that verifies device and admin tokens
/// (identity), and by the one that verifies S2S signatures (federation).
abstract interface class ProvidesAuthentication {
  Authenticator get authenticator;
}
