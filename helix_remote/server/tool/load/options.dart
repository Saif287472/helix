import 'dart:io';
import 'dart:math' as math;

/// Parameters of one load run (`dart run tool/load.dart --help`).
final class LoadOptions {
  const LoadOptions({
    this.devices = 1000,
    int? workers,
    this.warmupSeconds = 5,
    this.durationSeconds = 60,
    this.drainSeconds = 15,
    this.rate = 0.2,
    this.groupShare = 0.1,
    this.groupSize = 8,
    this.payloadBytes = 0,
    this.ackSample = 0.05,
    this.oneTimePrekeys = 20,
    this.provisionConcurrency = 8,
    this.connectConcurrency = 32,
    this.jsonPath,
  }) : workers = workers ?? 0;

  /// Simulated devices, one account each.
  final int devices;

  /// Client isolates (0: chosen from the core count, see [workerCount]).
  final int workers;

  /// Sending before measurement starts (JIT warm-up, connection pools).
  final int warmupSeconds;

  /// Measured sending time.
  final int durationSeconds;

  /// After sending stops: how long to wait for outstanding deliveries.
  final int drainSeconds;

  /// Messages per second per device (Poisson arrivals, open loop).
  final double rate;

  /// Share of sends that go to the device's group instead of one peer.
  final double groupShare;

  /// Members per group (consecutive device indices); below 2: no groups.
  final int groupSize;

  /// Fixed sealed payload size; 0 picks from a realistic mix (see
  /// `payloadSize` in worker.dart).
  final int payloadBytes;

  /// Share of received envelopes also acked over REST, to time acks
  /// (socket acks have no response).
  final double ackSample;

  /// One-time prekeys uploaded with each registration.
  final int oneTimePrekeys;

  /// Registrations in flight per worker.
  final int provisionConcurrency;

  /// Socket connects in flight per worker.
  final int connectConcurrency;

  /// Where to write the JSON report (null: none).
  final String? jsonPath;

  bool get groupsEnabled => groupShare > 0 && groupSize >= 2;

  /// Default: half the cores (the server isolate and Postgres need the
  /// rest), between 1 and 8.
  int get workerCount => workers > 0
      ? workers
      : math.max(1, math.min(8, Platform.numberOfProcessors ~/ 2));

  /// Access tokens last 15 minutes and the tool does not refresh them.
  static const maxRunSeconds = 13 * 60;

  void validate() {
    final problems = <String>[
      if (devices < 2) '--devices must be at least 2',
      if (workers < 0) '--workers must be positive',
      if (durationSeconds < 1) '--duration must be at least 1',
      if (warmupSeconds < 0 || drainSeconds < 0)
        '--warmup and --drain must not be negative',
      if (warmupSeconds + durationSeconds + drainSeconds > maxRunSeconds)
        'warmup + duration + drain must stay under $maxRunSeconds s '
            '(access tokens expire after 15 minutes)',
      if (rate <= 0) '--rate must be positive',
      if (groupShare < 0 || groupShare > 1) '--group-share must be 0..1',
      if (groupsEnabled && groupSize > devices)
        '--group-size must not exceed --devices',
      if (payloadBytes < 0 || payloadBytes > 256 * 1024)
        '--payload-bytes must be 0..262144',
      if (ackSample < 0 || ackSample > 1) '--ack-sample must be 0..1',
      if (oneTimePrekeys < 0 || oneTimePrekeys > 200)
        '--one-time-prekeys must be 0..200',
      if (provisionConcurrency < 1 || connectConcurrency < 1)
        'concurrency must be at least 1',
    ];
    if (problems.isNotEmpty) throw ArgumentError(problems.join('\n'));
  }

  Map<String, Object?> toJson() => {
    'devices': devices,
    'workers': workerCount,
    'warmup_s': warmupSeconds,
    'duration_s': durationSeconds,
    'drain_s': drainSeconds,
    'rate_per_device': rate,
    'group_share': groupsEnabled ? groupShare : 0,
    'group_size': groupsEnabled ? groupSize : 0,
    'payload_bytes': payloadBytes == 0 ? 'mix' : payloadBytes,
    'ack_sample': ackSample,
    'one_time_prekeys': oneTimePrekeys,
    'provision_concurrency': provisionConcurrency,
    'connect_concurrency': connectConcurrency,
  };

  static LoadOptions fromJson(Map<String, Object?> j) => LoadOptions(
    devices: j['devices']! as int,
    workers: j['workers']! as int,
    warmupSeconds: j['warmup_s']! as int,
    durationSeconds: j['duration_s']! as int,
    drainSeconds: j['drain_s']! as int,
    rate: (j['rate_per_device']! as num).toDouble(),
    groupShare: (j['group_share']! as num).toDouble(),
    groupSize: j['group_size']! as int,
    payloadBytes: j['payload_bytes'] is int ? j['payload_bytes']! as int : 0,
    ackSample: (j['ack_sample']! as num).toDouble(),
    oneTimePrekeys: j['one_time_prekeys']! as int,
    provisionConcurrency: j['provision_concurrency']! as int,
    connectConcurrency: j['connect_concurrency']! as int,
  );

  static const usage = '''
Helix Remote v2 load harness: boots a server node in-process on the test
database (HELIX_TEST_DATABASE_URL) under a fresh schema prefix, registers
N devices through the real phone flow, opens one WebSocket per device and
runs authenticated sends for a fixed time. The schema is dropped at the end.

  dart run tool/load.dart [options]

  --devices N              simulated devices, one account each (1000)
  --workers N              client isolates (half the cores, 1..8)
  --warmup S               unmeasured sending first (5)
  --duration S             measured sending (60)
  --drain S                wait for outstanding deliveries (15)
  --rate R                 messages/s per device, Poisson (0.2)
  --group-share F          share of sends to the device's group (0.1)
  --group-size N           members per group, < 2 disables groups (8)
  --payload-bytes N        fixed payload size; 0 = realistic mix (0)
  --ack-sample F           share of envelopes also acked over REST (0.05)
  --one-time-prekeys N     uploaded per registration (20)
  --provision-concurrency N  registrations in flight per worker (8)
  --connect-concurrency N  socket connects in flight per worker (32)
  --json PATH              also write the report as JSON
''';

  /// Parses `--name value` and `--name=value`.
  static LoadOptions parse(List<String> args) {
    final values = <String, String>{};
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (!arg.startsWith('--')) throw ArgumentError('unexpected "$arg"');
      final eq = arg.indexOf('=');
      if (eq > 0) {
        values[arg.substring(2, eq)] = arg.substring(eq + 1);
      } else {
        if (i + 1 >= args.length) throw ArgumentError('$arg needs a value');
        values[arg.substring(2)] = args[++i];
      }
    }
    int integer(String name, int orElse) {
      final v = values.remove(name);
      if (v == null) return orElse;
      return int.tryParse(v) ?? (throw ArgumentError('--$name: "$v"'));
    }

    double real(String name, double orElse) {
      final v = values.remove(name);
      if (v == null) return orElse;
      return double.tryParse(v) ?? (throw ArgumentError('--$name: "$v"'));
    }

    const d = LoadOptions();
    final options = LoadOptions(
      devices: integer('devices', d.devices),
      workers: integer('workers', 0),
      warmupSeconds: integer('warmup', d.warmupSeconds),
      durationSeconds: integer('duration', d.durationSeconds),
      drainSeconds: integer('drain', d.drainSeconds),
      rate: real('rate', d.rate),
      groupShare: real('group-share', d.groupShare),
      groupSize: integer('group-size', d.groupSize),
      payloadBytes: integer('payload-bytes', d.payloadBytes),
      ackSample: real('ack-sample', d.ackSample),
      oneTimePrekeys: integer('one-time-prekeys', d.oneTimePrekeys),
      provisionConcurrency: integer(
        'provision-concurrency',
        d.provisionConcurrency,
      ),
      connectConcurrency: integer('connect-concurrency', d.connectConcurrency),
      jsonPath: values.remove('json'),
    );
    if (values.isNotEmpty) {
      throw ArgumentError('unknown option(s): ${values.keys.join(', ')}');
    }
    options.validate();
    return options;
  }
}
