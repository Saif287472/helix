import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:helix_remote_protocol/helix_remote_protocol.dart' show Uuid;
import 'package:helix_remote_server/src/platform/bus/event_bus.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/observability/log.dart';
import 'package:helix_remote_server/src/platform/observability/metrics.dart';

/// Work that must happen after a transaction commits and must not be lost
/// (push notifications, federation relays, purges). Enqueued *inside* the
/// caller's transaction (the transactional outbox), executed by any node.
final class Outbox {
  Outbox(this._platformSchema, this._bus);

  final String _platformSchema;
  final EventBus _bus;

  static const wakeTopic = 'jobs.wake';

  /// Enqueues a job in [tx]. With [dedupeKey], a second enqueue of the same
  /// key while the first is still pending is ignored.
  Future<void> enqueue(
    Tx tx,
    String kind,
    Map<String, Object?> payload, {
    Duration delay = Duration.zero,
    int maxAttempts = 8,
    String? dedupeKey,
  }) async {
    await tx.execute(
      '''INSERT INTO $_platformSchema.jobs
           (id, kind, payload, run_at, max_attempts, dedupe_key)
         VALUES (@id:uuid, @kind:text, @payload:jsonb,
                 now() + make_interval(secs => @delay:int8 / 1000.0),
                 @max:int4, @dedupe:text)
         ON CONFLICT (dedupe_key) DO NOTHING''',
      {
        'id': Uuid.v7(),
        'kind': kind,
        'payload': jsonEncode(payload),
        'delay': delay.inMilliseconds,
        'max': maxAttempts,
        'dedupe': dedupeKey,
      },
    );
    if (delay == Duration.zero) {
      tx.afterCommit(() => _bus.publish(wakeTopic, const {}));
    }
  }

  /// Jobs that ran out of attempts, for operators.
  Future<int> deadCount(SqlSession s) async => (await s.queryOne(
    "SELECT count(*)::int8 AS n FROM $_platformSchema.jobs WHERE status = 'dead'",
  ))!.integer('n');

  /// Deletes dead jobs (admin purge); returns how many.
  Future<int> purgeDead(SqlSession s) =>
      s.execute("DELETE FROM $_platformSchema.jobs WHERE status = 'dead'");
}

/// A job handler. Throwing schedules a retry with exponential backoff;
/// after `max_attempts` the job is kept as `dead` for operators.
typedef JobHandler = Future<void> Function(Map<String, Object?> payload);

final class JobRunnerSettings {
  const JobRunnerSettings({
    this.pollInterval = const Duration(seconds: 2),
    this.lease = const Duration(minutes: 2),
    this.batchSize = 20,
    this.baseBackoff = const Duration(seconds: 5),
    this.maxBackoff = const Duration(hours: 1),
  });

  final Duration pollInterval;
  final Duration lease;
  final int batchSize;
  final Duration baseBackoff;
  final Duration maxBackoff;
}

/// Claims and runs outbox jobs. Any number of nodes may run one: claims use
/// `FOR UPDATE SKIP LOCKED` and a lease, so a job runs on one node at a time
/// and a crashed node's jobs are picked up when the lease expires.
final class JobRunner {
  JobRunner({
    required this._db,
    required String platformSchema,
    required this._bus,
    required this.nodeId,
    required Log log,
    required Metrics metrics,
    this.settings = const JobRunnerSettings(),
  }) : _table = '$platformSchema.jobs',
       _log = log.child({'component': 'jobs'}),
       _completed = metrics.counter(
         'helix_jobs_total',
         'Jobs finished, by kind and result',
       );

  final Db _db;
  final String _table;
  final EventBus _bus;
  final String nodeId;
  final Log _log;
  final Counter _completed;
  final JobRunnerSettings settings;
  final Map<String, JobHandler> _handlers = {};

  Timer? _timer;
  StreamSubscription<void>? _wakeSub;
  bool _stopped = false;
  bool _again = false;
  Future<int>? _inFlight;

  void register(String kind, JobHandler handler) {
    if (_handlers.containsKey(kind)) {
      throw StateError('job kind $kind registered twice');
    }
    _handlers[kind] = handler;
  }

  void start() {
    _timer = Timer.periodic(settings.pollInterval, (_) => unawaited(tick()));
    _wakeSub = _bus
        .subscribe(Outbox.wakeTopic)
        .listen((_) => unawaited(tick()));
  }

  Future<void> stop() async {
    _stopped = true;
    _timer?.cancel();
    await _wakeSub?.cancel();
    await _inFlight;
  }

  /// Runs every ready job once (tests call this directly). Overlapping calls
  /// join the running pass, which loops again to pick up new work.
  Future<int> tick() {
    if (_stopped) return Future.value(0);
    final running = _inFlight;
    if (running != null) {
      _again = true;
      return running;
    }
    final pass = _inFlight = _drain().whenComplete(() => _inFlight = null);
    return pass;
  }

  Future<int> _drain() async {
    var processed = 0;
    do {
      _again = false;
      if (_stopped) break;
      final batch = await _claim();
      processed += batch.length;
      await Future.wait(batch.map(_run));
      if (batch.length == settings.batchSize) _again = true;
    } while (_again);
    return processed;
  }

  Future<List<Row>> _claim() async {
    if (_handlers.isEmpty) return const [];
    return _db.query(
      '''UPDATE $_table SET
           locked_until = now() + make_interval(secs => @lease:int8),
           locked_by = @node:text,
           attempts = attempts + 1
         WHERE id IN (
           SELECT id FROM $_table
           WHERE status = 'pending' AND run_at <= now()
             AND (locked_until IS NULL OR locked_until < now())
             AND kind = ANY(string_to_array(@kinds:text, ','))
           ORDER BY run_at
           LIMIT @n:int4
           FOR UPDATE SKIP LOCKED)
         RETURNING id, kind, payload, attempts, max_attempts''',
      {
        'lease': settings.lease.inSeconds,
        'node': nodeId,
        'kinds': _handlers.keys.join(','),
        'n': settings.batchSize,
      },
    );
  }

  Future<void> _run(Row job) async {
    final id = job.string('id');
    final kind = job.string('kind');
    try {
      await _handlers[kind]!(job.json('payload'));
      await _db.execute('DELETE FROM $_table WHERE id = @id:uuid', {'id': id});
      _completed.inc({'kind': kind, 'result': 'ok'});
    } on Object catch (e) {
      final attempts = job.integer('attempts');
      final dead = attempts >= job.integer('max_attempts');
      final backoff = _backoff(attempts);
      await _db.execute(
        '''UPDATE $_table SET
             status = @status:text,
             run_at = now() + make_interval(secs => @backoff:int8),
             locked_until = NULL, locked_by = NULL,
             last_error = @error:text
           WHERE id = @id:uuid''',
        {
          'id': id,
          'status': dead ? 'dead' : 'pending',
          'backoff': backoff.inSeconds,
          'error': e.runtimeType.toString(),
        },
      );
      _completed.inc({'kind': kind, 'result': dead ? 'dead' : 'retry'});
      _log.warn(dead ? 'job_dead' : 'job_retry', {
        'kind': kind,
        'job_id': id,
        'attempts': attempts,
        'error': e.runtimeType.toString(),
      });
    }
  }

  Duration _backoff(int attempts) {
    final seconds = settings.baseBackoff.inSeconds * math.pow(2, attempts - 1);
    return Duration(
      seconds: math.min(seconds, settings.maxBackoff.inSeconds).toInt(),
    );
  }
}

/// A task that runs every [interval] on exactly one node of the cluster.
final class PeriodicJob {
  const PeriodicJob(this.name, this.interval, this.run);

  final String name;
  final Duration interval;
  final Future<void> Function() run;
}

/// Schedules [PeriodicJob]s. Each node checks every [checkInterval]; a
/// conditional update on `platform.periodic_jobs` decides which node runs a
/// due job, so it runs once per interval cluster-wide.
final class PeriodicScheduler {
  PeriodicScheduler({
    required this._db,
    required String platformSchema,
    required this.nodeId,
    required Log log,
    this.checkInterval = const Duration(seconds: 15),
  }) : _table = '$platformSchema.periodic_jobs',
       _log = log.child({'component': 'periodic'});

  final Db _db;
  final String _table;
  final String nodeId;
  final Log _log;
  final Duration checkInterval;
  final Map<String, PeriodicJob> _jobs = {};
  Timer? _timer;
  bool _stopped = false;
  Future<List<String>>? _inFlight;

  void register(PeriodicJob job) {
    if (_jobs.containsKey(job.name)) {
      throw StateError('periodic job ${job.name} twice');
    }
    _jobs[job.name] = job;
  }

  Future<void> start() async {
    for (final name in _jobs.keys) {
      await _db.execute(
        'INSERT INTO $_table (name) VALUES (@n:text) ON CONFLICT (name) DO NOTHING',
        {'n': name},
      );
    }
    _timer = Timer.periodic(checkInterval, (_) => unawaited(tick()));
  }

  Future<void> stop() async {
    _stopped = true;
    _timer?.cancel();
    await _inFlight;
  }

  /// Runs every due job this node wins (tests call this directly).
  Future<List<String>> tick() {
    if (_stopped) return Future.value(const []);
    return _inFlight ??= _tick().whenComplete(() => _inFlight = null);
  }

  Future<List<String>> _tick() async {
    final ran = <String>[];
    for (final job in _jobs.values) {
      final claimed = await _db.query(
        '''UPDATE $_table SET last_run_at = now(), locked_by = @node:text,
             locked_until = now() + make_interval(secs => @lease:int8)
           WHERE name = @n:text
             AND (last_run_at IS NULL OR last_run_at <= now() - make_interval(secs => @every:int8))
             AND (locked_until IS NULL OR locked_until < now())
           RETURNING name''',
        {
          'n': job.name,
          'node': nodeId,
          'every': job.interval.inSeconds,
          'lease': math.max(60, job.interval.inSeconds),
        },
      );
      if (claimed.isEmpty) continue;
      try {
        await job.run();
        ran.add(job.name);
      } on Object catch (e) {
        _log.warn('periodic_failed', {
          'job': job.name,
          'error': e.runtimeType.toString(),
        });
      } finally {
        await _db.execute(
          'UPDATE $_table SET locked_until = NULL WHERE name = @n:text',
          {'n': job.name},
        );
      }
    }
    return ran;
  }
}
