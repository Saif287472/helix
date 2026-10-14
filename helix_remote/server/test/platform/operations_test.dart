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
}
