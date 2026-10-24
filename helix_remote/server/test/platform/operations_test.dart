import 'dart:async';
import 'dart:io';

import 'package:helix_remote_server/src/platform/config/server_config.dart';
import 'package:helix_remote_server/src/platform/observability/log.dart';
import 'package:helix_remote_server/src/platform/startup.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The operations code of the 2026-10-09 review, batch 9 (H-03, H-05): the
/// start-up retry, the stop file the scheduled task uses, daily log rotation.
void main() {
  group('retryStartup', () {
    test('retries until the database answers', () async {
      final memory = MemorySink();
      var calls = 0;
      final value = await retryStartup(
        () async {
          if (++calls < 3) throw const SocketException('refused');
          return 'open';
        },
        log: Log(sink: memory),
        every: const Duration(milliseconds: 10),
      );
      expect(value, 'open');
      expect(calls, 3);
      expect(
        memory.lines.where((l) => l.contains('startup_retry')),
        hasLength(2),
      );
    });

    test(
      'gives up after the wait, and never retries a configuration error',
      () async {
        await expectLater(
          retryStartup<void>(
            () async => throw const SocketException('refused'),
            log: Log(sink: MemorySink()),
            wait: const Duration(milliseconds: 60),
            every: const Duration(milliseconds: 20),
          ),
          throwsA(isA<SocketException>()),
        );
        var calls = 0;
        await expectLater(
          retryStartup<void>(
            () async {
              calls++;
              throw ConfigError(['HELIX_X is wrong']);
            },
            log: Log(sink: MemorySink()),
            every: const Duration(milliseconds: 10),
          ),
          throwsA(isA<ConfigError>()),
        );
        expect(calls, 1);
      },
    );
  });

  test('watchStopFile completes once the file appears', () async {
    final dir = Directory.systemTemp.createTempSync('helix_stop_');
    try {
      final path = p.join(dir.path, 'stop');
      var stopped = false;
      unawaited(
        watchStopFile(
          path,
          every: const Duration(milliseconds: 10),
        ).then((_) => stopped = true),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(stopped, isFalse);
      File(path).writeAsStringSync('');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(stopped, isTrue);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  group('FileSink rotation', () {
    late Directory dir;
    late String path;
    var now = DateTime.utc(2026, 10, 14, 23, 59);

    setUp(() {
      dir = Directory.systemTemp.createTempSync('helix_log_');
      path = p.join(dir.path, 'helix.log');
      now = DateTime.utc(2026, 10, 14, 23, 59);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    List<String> files() =>
        [for (final f in dir.listSync()) p.basename(f.path)]..sort();

    test('the first line of a new UTC day starts a new file', () async {
      final sink = FileSink.open(path, now: () => now)..write('one');
      now = DateTime.utc(2026, 10, 15, 0, 1);
      sink.write('two');
      await sink.close();
      expect(files(), ['helix-2026-10-14.log', 'helix.log']);
      expect(
        File(p.join(dir.path, 'helix-2026-10-14.log')).readAsStringSync(),
        'one\n',
      );
      expect(File(path).readAsStringSync(), 'two\n');
    });

    test('a line is buffered, not written on the request thread', () async {
      final sink = FileSink.open(path, now: () => now)..write('one');
      expect(
        File(path).readAsStringSync(),
        isEmpty,
        reason: 'the write returns before the disk sees it (AUD-1a-5)',
      );
      await sink.close();
      expect(File(path).readAsStringSync(), 'one\n');
    });

    test('a day past its byte bound rotates early and stays bounded', () async {
      // Above the sink's flush bound, so the rotation is the day's own limit
      // rather than one oversized write hitting a cap a batch cannot fit in.
      const cap = 256 * 1024;
      final sink = FileSink.open(path, maxBytesPerDay: cap, now: () => now);
      final padding = 'x' * 200;
      const lines = 4000; // ~800 KiB: three times the cap
      for (var i = 0; i < lines; i++) {
        sink.write('n$i-$padding');
      }
      await sink.close();

      final files1 = dir.listSync().whereType<File>().toList();
      final bytes = files1.fold<int>(0, (total, f) => total + f.lengthSync());
      final text = files1.map((f) => f.readAsStringSync()).join();
      expect(
        bytes,
        lessThanOrEqualTo(2 * cap + FileSink.flushBeforeBytes),
        reason: 'one day of logs costs the cap, not whatever the flood wrote',
      );
      expect(
        bytes,
        greaterThan(cap),
        reason: 'the flood is really bigger than the cap',
      );
      expect(text, contains('n${lines - 1}-'), reason: 'the tail is kept');
      expect(text, isNot(contains('n0-')), reason: 'the oldest went first');
      expect(
        files1.map((f) => p.basename(f.path)),
        contains(matches(r'^helix-2026-10-14\.\d+\.log$')),
        reason: 'the day rotated more than once instead of growing forever',
      );
    });

    test('rotated files older than keepDays are deleted', () async {
      for (final day in ['2026-09-01', '2026-10-10', '2026-10-13']) {
        File(p.join(dir.path, 'helix-$day.log')).writeAsStringSync('x');
      }
      File(p.join(dir.path, 'other-2026-09-01.log')).writeAsStringSync('x');
      final sink = FileSink.open(path, keepDays: 3, now: () => now);
      await sink.close();
      expect(files(), [
        'helix-2026-10-13.log',
        'helix.log',
        'other-2026-09-01.log',
      ], reason: 'only this log, and only older than three days');
    });

    test('a file left from an earlier day is rotated at open', () async {
      File(path)
        ..writeAsStringSync('yesterday\n')
        ..setLastModifiedSync(DateTime.utc(2026, 10, 13, 12));
      // The same day rotated already (a restart): the next one is numbered.
      File(p.join(dir.path, 'helix-2026-10-13.log')).writeAsStringSync('x');
      final sink = FileSink.open(path, now: () => now)..write('today');
      await sink.close();
      expect(files(), [
        'helix-2026-10-13.1.log',
        'helix-2026-10-13.log',
        'helix.log',
      ]);
      expect(File(path).readAsStringSync(), 'today\n');
    });
  });

  test('HELIX_LOG_KEEP_DAYS: 14 unless set, 1 to 3650', () {
    ServerConfig config(String? days) => ServerConfig.fromEnv({
      'HELIX_DATABASE_URL': 'postgresql://u:p@localhost/db',
      'HELIX_JWT_KEYS':
          '{"k1":"dGVzdC1vbmx5LWp3dC1rZXktdGhhdC1pcy0zMi1ieXRlcw"}',
      'HELIX_LOG_KEEP_DAYS': ?days,
    });
    expect(config(null).logKeepDays, 14);
    expect(config('30').logKeepDays, 30);
    for (final bad in ['0', '4000', 'week']) {
      expect(() => config(bad), throwsA(isA<ConfigError>()), reason: bad);
    }
  });

  test('HELIX_LOG_MAX_BYTES_PER_DAY: 256 MiB unless set, 0 turns it off', () {
    ServerConfig config(String? bytes) => ServerConfig.fromEnv({
      'HELIX_DATABASE_URL': 'postgresql://u:p@localhost/db',
      'HELIX_JWT_KEYS':
          '{"k1":"dGVzdC1vbmx5LWp3dC1rZXktdGhhdC1pcy0zMi1ieXRlcw"}',
      'HELIX_LOG_MAX_BYTES_PER_DAY': ?bytes,
    });
    expect(config(null).logMaxBytesPerDay, FileSink.defaultMaxBytesPerDay);
    expect(config('1024').logMaxBytesPerDay, 1024);
    expect(
      config('0').logMaxBytesPerDay,
      0,
      reason: 'the daily rotation alone, as before this bound existed',
    );
    for (final bad in ['-1', 'week']) {
      expect(() => config(bad), throwsA(isA<ConfigError>()), reason: bad);
    }
  });
}
