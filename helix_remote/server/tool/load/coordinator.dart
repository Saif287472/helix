import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/helix_remote_server.dart';
import 'package:helix_remote_server/src/modules/identity/sms.dart';
import 'package:helix_remote_server/src/platform/db/postgres_db.dart';

import 'options.dart';
import 'stats.dart';

/// The database the load run uses. Only a database whose name contains
/// `test` is accepted, so a run can never touch the production `helix`
/// database. The URL holds a password and is never printed.
const loadDatabaseUrlVariable = 'HELIX_TEST_DATABASE_URL';

/// Runs one load test (see `LoadOptions.usage`) and returns its report.
///
/// The server node runs in this isolate, exactly as `bin/server.dart` builds
/// it (all modules, Postgres platform, default rate limits), on 127.0.0.1
/// with an OS-assigned port and a fresh schema prefix. The simulated
/// devices run in [LoadOptions.workerCount] worker isolates with their own
/// heaps (`worker.dart`). Everything is torn down and the schemas are
/// dropped, even when the run fails.
Future<LoadReport> runLoad(
  LoadOptions options, {
  void Function(String line) progress = _quiet,
}) async {
  options.validate();
  final url = Platform.environment[loadDatabaseUrlVariable]?.trim() ?? '';
  if (url.isEmpty) {
    throw StateError('$loadDatabaseUrlVariable is not set (server/README.md)');
  }
  final dbName = Uri.tryParse(url)?.pathSegments.lastOrNull ?? '';
  if (!dbName.contains('test')) {
    throw StateError(
      'refusing to load-test a database whose name does not contain "test"',
    );
  }

  final random = math.Random.secure();
  final prefix = 'ld${_token(random, 8)}_';
  final tag = random.nextInt(1 << 32);
  final blobDir = Directory.systemTemp.createTempSync('helix_load_blobs_');
  final logs = _CountingSink();
  final workers = <_WorkerHandle>[];
  HelixPlatform? platform;
  HelixServer? server;
  final wall = Stopwatch()..start();
  try {
    platform = await HelixPlatform.open(
      ServerConfig.fromEnv({
        'HELIX_DATABASE_URL': url,
        'HELIX_HOST': '127.0.0.1',
        'HELIX_PORT': '0',
        'HELIX_JWT_KEYS': '{"load":"${encodeBytes(_randomBytes(random))}"}',
        'HELIX_SCHEMA_PREFIX': prefix,
        'HELIX_BLOB_DIR': blobDir.path,
        // Only for the recording SMS provider (the codes stay in memory);
        // dev mode changes nothing on the measured paths.
        'HELIX_DEV_MODE': 'true',
        'HELIX_GLOBAL_MODE': 'true',
        'HELIX_PHONE_PEPPER': encodeBytes(_randomBytes(random)),
      }),
      log: Log(sink: logs),
    );
    final sms = RecordingSmsProvider();
    server = await HelixServer.start(platform, allModules(sms: sms));
    final db = platform.db;
    final postgres = (await db.queryOne(
      'SHOW server_version',
    ))!.string('server_version');
    progress(
      'server on ${server.baseUri} (schema prefix $prefix), '
      'PostgreSQL $postgres',
    );

    // ------------------------------------------------------------ workers
    final count = math.min(options.workerCount, options.devices);
    final workerUri = (await Isolate.resolvePackageUri(
      Uri.parse('package:helix_remote_server/'),
    ))!.resolve('../tool/load/worker.dart');
    final spawn = Stopwatch()..start();
    for (var w = 0; w < count; w++) {
      workers.add(
        await _WorkerHandle.spawn(
          workerUri,
          id: w,
          base: server.baseUri,
          tag: tag,
          options: options,
          codes: sms,
        ),
      );
    }
    await Future.wait([for (final w in workers) w.ready]);
    progress('$count worker isolates ready in ${_s(spawn)}');

    // ------------------------------------------------------- provisioning
    final provision = Stopwatch()..start();
    final accounts = List<String?>.filled(options.devices, null);
    final devices = List<String?>.filled(options.devices, null);
    final provisioned = await Future.wait([
      for (final w in workers)
        w.request({
          't': 'provision',
          'devices': [for (var i = w.id; i < options.devices; i += count) i],
        }, 'provisioned'),
    ]);
    final setup = <String, Samples>{};
    for (final r in provisioned) {
      for (final d in r['devices']! as List) {
        final row = d as List;
        accounts[row[0]! as int] = row[1]! as String;
        devices[row[0]! as int] = row[2]! as String;
      }
      _merge(setup, r['samples']);
    }
    final live = [
      for (var i = 0; i < options.devices; i++)
        if (accounts[i] != null) i,
    ];
    progress(
      'registered ${live.length}/${options.devices} devices in '
      '${_s(provision)}',
    );
    if (live.length < 2) {
      throw StateError('provisioning failed: ${_errorsOf(provisioned)}');
    }

    // ------------------------------------------------- directory + groups
    final groups = <List<int>>[];
    if (options.groupsEnabled) {
      for (
        var i = 0;
        i + options.groupSize <= live.length;
        i += options.groupSize
      ) {
        groups.add(live.sublist(i, i + options.groupSize));
      }
    }
    final groupIds = [for (final _ in groups) Uuid.v7()];
    await Future.wait([
      for (final w in workers)
        w.request({
          't': 'directory',
          'accounts': accounts,
          'devices': devices,
          'groups': groups,
          'group_ids': groupIds,
        }, 'directory_ok'),
    ]);
    if (groups.isNotEmpty) {
      final created = Stopwatch()..start();
      final done = await Future.wait([
        for (final w in workers) w.request({'t': 'groups'}, 'groups_done'),
      ]);
      for (final r in done) {
        _merge(setup, r['samples']);
      }
      progress('created ${groups.length} groups in ${_s(created)}');
    }

    // ------------------------------------------------------------ sockets
    final connecting = Stopwatch()..start();
    final connected = await Future.wait([
      for (final w in workers) w.request({'t': 'connect'}, 'connected'),
    ]);
    var open = 0;
    for (final r in connected) {
      open += r['open']! as int;
      _merge(setup, r['samples']);
    }
    progress('opened $open sockets in ${_s(connecting)}');

    // ---------------------------------------------------------------- run
    final now = DateTime.now().microsecondsSinceEpoch;
    final start = now + 500000;
    final from = start + options.warmupSeconds * 1000000;
    final to = from + options.durationSeconds * 1000000;
    for (final w in workers) {
      w.send({
        't': 'run',
        'start_us': start,
        'measure_from_us': from,
        'measure_to_us': to,
      });
    }
    progress(
      'sending: ${options.rate}/s per device, warm-up '
      '${options.warmupSeconds}s, measuring ${options.durationSeconds}s',
    );
    await _sleepUntil(from);
    final metricsBefore = _routeTotals(platform.metrics.render());
    final cpuBefore = await _cpuSnapshot();
    final serverLag = Samples();
    final lagWatch = _watchLoopLag(serverLag);
    await _sleepUntil(to);
    lagWatch.cancel();
    final cpuAfter = await _cpuSnapshot();
    final metricsAfter = _routeTotals(platform.metrics.render());

    final sent = await Future.wait([for (final w in workers) w.expect('sent')]);
    final expected = sent.fold<int>(0, (a, r) => a + (r['expected']! as int));

    // -------------------------------------------------------------- drain
    final drain = Stopwatch()..start();
    var received = 0;
    while (true) {
      final p = await Future.wait([
        for (final w in workers) w.request({'t': 'progress'}, 'progress'),
      ]);
      received = p.fold<int>(0, (a, r) => a + (r['received']! as int));
      if (received >= expected ||
          drain.elapsed.inSeconds >= options.drainSeconds) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    progress('delivered $received/$expected (drain ${_s(drain)})');

    final reports = await Future.wait([
      for (final w in workers) w.request({'t': 'finish'}, 'report'),
    ]);
    final run = <String, Samples>{};
    final errors = Counts();
    final counts = Counts();
    for (final r in reports) {
      _merge(run, r['samples']);
      errors.addAll(r['errors']! as Map);
      counts.addAll(r['counts']! as Map);
    }

    return LoadReport(
      options: options,
      environment: {
        'date': DateTime.now().toUtc().toIso8601String(),
        'os': Platform.operatingSystemVersion,
        'dart': Platform.version.split(' ').first,
        'cpu_cores': Platform.numberOfProcessors,
        'postgres': postgres,
        'server': 'in-process, 1 node, 127.0.0.1, default limits',
      },
      setup: setup,
      run: run,
      errors: errors,
      counts: counts,
      expected: expected,
      received: received,
      measuredSeconds: (to - from) / 1e6,
      serverLag: serverLag,
      serverRoutes: _routeDiff(metricsBefore, metricsAfter),
      cpu: _cpuUse(cpuBefore, cpuAfter),
      serverLogs: logs.counts,
      wall: wall.elapsed,
    );
  } finally {
    for (final w in workers) {
      w.kill();
    }
    try {
      try {
        await server?.stop();
      } on Object catch (e) {
        progress('server stop failed: ${e.runtimeType}: $e');
      }
      // Idempotent; closes the pools even when stop() threw.
      await platform?.close();
    } finally {
      await _dropSchemas(url, prefix);
      if (blobDir.existsSync()) blobDir.deleteSync(recursive: true);
    }
  }
}

void _quiet(String _) {}

// ---------------------------------------------------------------- workers

/// The coordinator's side of one worker isolate. Answers the worker's
/// SMS-code lookups directly; other messages are awaited by type.
final class _WorkerHandle {
  _WorkerHandle._(this.id, this._isolate, this._inbox, this._errors);

  final int id;
  final Isolate _isolate;
  final ReceivePort _inbox;
  final ReceivePort _errors;
  final Completer<void> _ready = Completer();
  final Map<String, Completer<Map<String, Object?>>> _waiting = {};
  final Map<String, List<Map<String, Object?>>> _early = {};
  late final SendPort _port;
  Object? _failure;

  Future<void> get ready => _ready.future;

  static Future<_WorkerHandle> spawn(
    Uri uri, {
    required int id,
    required Uri base,
    required int tag,
    required LoadOptions options,
    required RecordingSmsProvider codes,
  }) async {
    final inbox = ReceivePort();
    final errors = ReceivePort();
    final isolate = await Isolate.spawnUri(
      uri,
      const [],
      {
        'port': inbox.sendPort,
        'worker': id,
        'base': '$base',
        'tag': tag,
        'options': options.toJson(),
      },
      onError: errors.sendPort,
      packageConfig: await Isolate.packageConfig,
      debugName: 'load-worker-$id',
    );
    final handle = _WorkerHandle._(id, isolate, inbox, errors);
    errors.listen((e) => handle._fail('worker $id crashed: $e'));
    inbox.listen((raw) {
      final m = (raw as Map<Object?, Object?>).cast<String, Object?>();
      switch (m['t']) {
        case 'ready':
          handle._port = m['port']! as SendPort;
          handle._ready.complete();
        case 'code?':
          handle._port.send({
            't': 'code',
            'id': m['id'],
            'code': codes.lastCodeFor(m['phone']! as String),
          });
        case 'fatal':
          handle._fail('worker $id failed: ${m['error']}\n${m['stack']}');
        default:
          final type = m['t']! as String;
          final waiter = handle._waiting.remove(type);
          if (waiter != null) {
            waiter.complete(m);
          } else {
            handle._early.putIfAbsent(type, () => []).add(m);
          }
      }
    });
    return handle;
  }

  void _fail(String message) {
    _failure ??= StateError(message);
    if (!_ready.isCompleted) _ready.completeError(_failure!);
    for (final w in _waiting.values) {
      w.completeError(_failure!);
    }
    _waiting.clear();
  }

  void send(Map<String, Object?> message) => _port.send(message);

  Future<Map<String, Object?>> expect(String type) {
    if (_failure != null) return Future.error(_failure!);
    final early = _early[type];
    if (early != null && early.isNotEmpty) {
      return Future.value(early.removeAt(0));
    }
    return (_waiting[type] = Completer()).future;
  }

  Future<Map<String, Object?>> request(
    Map<String, Object?> message,
    String reply,
  ) {
    final answer = expect(reply);
    send(message);
    return answer;
  }

  void kill() {
    _isolate.kill(priority: Isolate.immediate);
    _inbox.close();
    _errors.close();
  }
}

// ------------------------------------------------------------- helpers

String _token(math.Random random, int length) => List.generate(
  length,
  (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[random.nextInt(36)],
).join();

List<int> _randomBytes(math.Random random) =>
    List.generate(32, (_) => random.nextInt(256));

String _s(Stopwatch w) =>
    '${(w.elapsedMilliseconds / 1000).toStringAsFixed(1)}s';

Future<void> _sleepUntil(int epochMicros) => Future<void>.delayed(
  Duration(
    microseconds: math.max(
      0,
      epochMicros - DateTime.now().microsecondsSinceEpoch,
    ),
  ),
);

void _merge(Map<String, Samples> into, Object? wire) {
  for (final e in (wire! as Map).entries) {
    into
        .putIfAbsent(e.key! as String, Samples.new)
        .addAll(Samples.fromWire(e.value));
  }
}

String _errorsOf(List<Map<String, Object?>> replies) {
  final c = Counts();
  for (final r in replies) {
    c.addAll(r['errors']! as Map);
  }
  return '${c.sorted()}';
}

/// Event-loop lag of this (the server's) isolate: how late a 50 ms timer
/// fires. High values mean the node itself is CPU-bound.
Timer _watchLoopLag(Samples into) {
  var expected = DateTime.now().microsecondsSinceEpoch + 50000;
  return Timer.periodic(const Duration(milliseconds: 50), (_) {
    final now = DateTime.now().microsecondsSinceEpoch;
    into.add(math.max(0, now - expected));
    expected = now + 50000;
  });
}

/// Drops every schema of this run.
Future<void> _dropSchemas(String url, String prefix) async {
  final db = await PostgresDb.open(url, maxConnections: 1);
  try {
    final rows = await db.query(
      r"SELECT schema_name FROM information_schema.schemata WHERE schema_name LIKE @p:text ESCAPE '\'",
      {'p': '${prefix.replaceAll('_', r'\_')}%'},
    );
    for (final row in rows) {
      await db.execute(
        'DROP SCHEMA IF EXISTS "${row.string('schema_name')}" CASCADE',
      );
    }
  } finally {
    await db.close();
  }
}

/// Server-side request time per route (sum, count) from `/metrics` text.
Map<String, (double, int)> _routeTotals(String metrics) {
  final out = <String, (double, int)>{};
  final pattern = RegExp(
    r'^helix_http_request_seconds_(sum|count)\{route="([^"]*)",status="([^"]*)"\} (\S+)$',
    multiLine: true,
  );
  for (final m in pattern.allMatches(metrics)) {
    final key = '${m.group(2)} ${m.group(3)}';
    final (sum, count) = out[key] ?? (0.0, 0);
    final value = double.parse(m.group(4)!);
    out[key] = m.group(1) == 'sum' ? (value, count) : (sum, value.round());
  }
  return out;
}

Map<String, Object?> _routeDiff(
  Map<String, (double, int)> before,
  Map<String, (double, int)> after,
) {
  final out = <String, Object?>{};
  for (final e in after.entries) {
    final (sum0, count0) = before[e.key] ?? (0.0, 0);
    final count = e.value.$2 - count0;
    if (count <= 0) continue;
    out[e.key] = {
      'count': count,
      'mean_ms': ((e.value.$1 - sum0) / count * 1e5).round() / 100,
    };
  }
  return out;
}

/// CPU seconds used so far by this process and by all `postgres`
/// processes (shared with anything else using the same Postgres), plus
/// the wall time of the reading. Null fields where unavailable.
Future<(DateTime, double?, double?)> _cpuSnapshot() async {
  try {
    if (Platform.isWindows) {
      final r = await Process.run('powershell.exe', [
        '-NoProfile',
        '-Command',
        r'$a=(Get-Process -Id '
            '$pid'
            r').TotalProcessorTime.TotalSeconds; '
            r'$b=(Get-Process postgres -ErrorAction SilentlyContinue | '
            r'Measure-Object -Property CPU -Sum).Sum; "$a $b"',
      ]);
      final parts = '${r.stdout}'.trim().split(RegExp(r'\s+'));
      return (
        DateTime.now(),
        double.tryParse(parts.first),
        parts.length > 1 ? double.tryParse(parts[1]) : null,
      );
    }
    if (Platform.isLinux) {
      final stat = File('/proc/self/stat').readAsStringSync();
      final fields = stat.substring(stat.lastIndexOf(')') + 2).split(' ');
      // utime and stime, in clock ticks (100 per second on Linux).
      final ticks = int.parse(fields[11]) + int.parse(fields[12]);
      return (DateTime.now(), ticks / 100, null);
    }
  } on Object {
    // Best effort only.
  }
  return (DateTime.now(), null, null);
}

Map<String, Object?> _cpuUse(
  (DateTime, double?, double?) before,
  (DateTime, double?, double?) after,
) {
  final seconds = after.$1.difference(before.$1).inMilliseconds / 1000;
  double? cores(double? a, double? b) => a == null || b == null || seconds <= 0
      ? null
      : ((b - a) / seconds * 100).roundToDouble() / 100;
  return {
    'window_s': seconds,
    'load_process_cores': cores(before.$2, after.$2),
    'all_postgres_cores': cores(before.$3, after.$3),
  };
}

/// Counts the server's log lines by level and, for warnings and errors, by
/// event. Lines are formatted and redacted as in production, then dropped,
/// so stdout I/O does not limit the run.
final class _CountingSink implements LogSink {
  final Counts counts = Counts();

  static final _level = RegExp(r'"level":"(\w+)","event":"([^"]+)"');

  @override
  void write(String line) {
    final m = _level.firstMatch(line);
    if (m == null) return;
    final level = m.group(1)!;
    if (level == 'info' || level == 'debug') {
      counts.add(level);
      return;
    }
    // Warnings and errors: the event plus the (already redacted) error
    // type and code location, which is what a bug report needs.
    final fields = jsonDecode(line) as Map<String, Object?>;
    final error = fields['error'];
    final at = '${fields['at'] ?? ''}'.replaceFirst(RegExp(r'^#\d+\s+'), '');
    counts.add(
      [
        '$level:${m.group(2)}',
        if (error != null) '$error',
        if (at.isNotEmpty) at,
      ].join(' '),
    );
  }
}

// ----------------------------------------------------------------- report

final class LoadReport {
  LoadReport({
    required this.options,
    required this.environment,
    required this.setup,
    required this.run,
    required this.errors,
    required this.counts,
    required this.expected,
    required this.received,
    required this.measuredSeconds,
    required this.serverLag,
    required this.serverRoutes,
    required this.cpu,
    required this.serverLogs,
    required this.wall,
  });

  final LoadOptions options;
  final Map<String, Object?> environment;
  final Map<String, Samples> setup;
  final Map<String, Samples> run;
  final Counts errors;
  final Counts counts;

  /// Deliveries owed for sends accepted in the measured window, and how
  /// many of those arrived (unique) before the drain ended.
  final int expected;
  final int received;
  final double measuredSeconds;
  final Samples serverLag;
  final Map<String, Object?> serverRoutes;
  final Map<String, Object?> cpu;
  final Counts serverLogs;
  final Duration wall;

  Summary _of(Map<String, Samples> m, String key) =>
      (m[key] ?? Samples()).summarize();

  int get accepted =>
      _of(run, 'send_direct').count + _of(run, 'send_group').count;

  /// Deliveries owed but not seen. Sends the client timed out on may
  /// still commit and arrive, so [received] can exceed [expected].
  int get lost => math.max(0, expected - received);

  List<(String, Summary)> get rows => [
    ('REST send 1:1', _of(run, 'send_direct')),
    ('REST send group', _of(run, 'send_group')),
    ('Delivery 1:1 (send -> socket)', _of(run, 'e2e_direct')),
    ('Delivery group (send -> socket)', _of(run, 'e2e_group')),
    ('REST ack (sampled)', _of(run, 'ack_rest')),
    ('WS connect (to hello)', _of(setup, 'connect')),
    ('Registration (3 calls)', _of(setup, 'registration')),
    ('  phone challenge', _of(setup, 'challenge')),
    ('  phone verify', _of(setup, 'verify')),
    ('  register', _of(setup, 'register')),
    ('Group create', _of(setup, 'group_create')),
    ('Client key generation', _of(setup, 'keygen')),
    ('Server loop lag', serverLag.summarize()),
    ('Worker loop lag', _of(run, 'loop_lag')),
  ];

  String render() {
    final out = StringBuffer()
      ..writeln()
      ..writeln(latencyTable(rows))
      ..writeln(
        'Throughput: ${(accepted / measuredSeconds).toStringAsFixed(1)} sends/s '
        'accepted, ${(received / measuredSeconds).toStringAsFixed(1)} '
        'deliveries/s; attempted ${counts.values['attempted'] ?? 0}',
      )
      ..writeln(
        'Delivered $received of $expected (lost or late: $lost, duplicates: '
        '${counts.values['duplicates'] ?? 0}, reconnects: '
        '${counts.values['reconnects'] ?? 0})',
      )
      ..writeln('Errors: ${errors.values.isEmpty ? 'none' : errors.sorted()}')
      ..writeln('CPU: $cpu')
      ..writeln('Server log: ${serverLogs.sorted()}')
      ..writeln('Environment: $environment')
      ..writeln('Wall time: ${wall.inSeconds}s');
    return out.toString();
  }

  Map<String, Object?> toJson() => {
    'environment': environment,
    'options': options.toJson(),
    'latency': {
      for (final k in run.keys) k: _of(run, k).toJson(),
      for (final k in setup.keys) k: _of(setup, k).toJson(),
      'server_loop_lag': serverLag.summarize().toJson(),
    },
    'throughput': {
      'measured_s': measuredSeconds,
      'attempted': counts.values['attempted'] ?? 0,
      'accepted': accepted,
      'accepted_per_s': accepted / measuredSeconds,
      'deliveries_expected': expected,
      'deliveries_received': received,
      'deliveries_per_s': received / measuredSeconds,
      'lost_or_late': lost,
      'duplicates': counts.values['duplicates'] ?? 0,
      'reconnects': counts.values['reconnects'] ?? 0,
    },
    'errors': errors.sorted(),
    'server_routes': serverRoutes,
    'cpu': cpu,
    'server_log': serverLogs.sorted(),
    'wall_s': wall.inSeconds,
  };
}
