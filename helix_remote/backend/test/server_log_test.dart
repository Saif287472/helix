import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_backend/src/server_identity.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// Swallows the console copy so a test run isn't flooded with the lines
/// each case records.
IOSink _nullSink() => File(
  '${Directory.systemTemp.createTempSync('helix_log_console').path}'
  '/console.txt',
).openWrite();

void main() {
  group('ServerLogSink', () {
    late Directory tempDir;

    setUp(() => tempDir = Directory.systemTemp.createTempSync('helix_log'));
    tearDown(() {
      resetServerLogForTesting();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test(
      'buffers recorded lines and returns the most recent first-in order',
      () {
        final sink = ServerLogSink(
          stdoutSink: _nullSink(),
          stderrSink: _nullSink(),
        );

        sink.info('one');
        sink.warn('two');
        sink.error('three');

        final lines = sink.tail(10);
        expect(lines, hasLength(3));
        expect(lines[0], contains('[INFO] one'));
        expect(lines[1], contains('[WARN] two'));
        expect(lines[2], contains('[ERROR] three'));
      },
    );

    test('drops the oldest lines once capacity is reached', () {
      final sink = ServerLogSink(
        capacity: 3,
        stdoutSink: _nullSink(),
        stderrSink: _nullSink(),
      );

      for (var i = 1; i <= 6; i++) {
        sink.info('line $i');
      }

      final lines = sink.tail(10);
      expect(lines, hasLength(3));
      expect(lines.first, contains('line 4'));
      expect(lines.last, contains('line 6'));
    });

    test('tail returns only the requested number of lines', () {
      final sink = ServerLogSink(
        stdoutSink: _nullSink(),
        stderrSink: _nullSink(),
      );
      for (var i = 1; i <= 10; i++) {
        sink.info('line $i');
      }

      final lines = sink.tail(2);
      expect(lines, hasLength(2));
      expect(lines.first, contains('line 9'));
      expect(lines.last, contains('line 10'));
    });

    test('splits multi-line messages so each row stays one line', () {
      final sink = ServerLogSink(
        stdoutSink: _nullSink(),
        stderrSink: _nullSink(),
      );

      sink.error('boom\n  at frame one\n  at frame two');

      final lines = sink.tail(10);
      expect(lines, hasLength(3));
      expect(lines.every((line) => !line.contains('\n')), isTrue);
      expect(lines[1], contains('at frame one'));
    });

    test('redacts bearer tokens before they reach the buffer', () {
      final sink = ServerLogSink(
        stdoutSink: _nullSink(),
        stderrSink: _nullSink(),
      );

      sink.error('request failed with Authorization: Bearer sk_live_abc123def');

      final line = sink.tail(1).single;
      expect(line, contains('[redacted]'));
      expect(line, isNot(contains('sk_live_abc123def')));
    });

    test('appends to the configured file and reports it as active', () async {
      final path = '${tempDir.path}/server.log';
      final sink = ServerLogSink(
        filePath: path,
        stdoutSink: _nullSink(),
        stderrSink: _nullSink(),
      );

      sink.info('persisted line');
      await sink.dispose();

      expect(sink.fileError, isNull);
      expect(File(path).readAsStringSync(), contains('persisted line'));
    });

    test('creates the parent directory when it does not exist yet', () async {
      final path = '${tempDir.path}/nested/dir/server.log';
      final sink = ServerLogSink(
        filePath: path,
        stdoutSink: _nullSink(),
        stderrSink: _nullSink(),
      );

      sink.info('nested line');
      await sink.dispose();

      expect(File(path).existsSync(), isTrue);
    });

    test('rotates the file once it passes the size cap', () async {
      final path = '${tempDir.path}/rotating.log';
      final sink = ServerLogSink(
        filePath: path,
        maxFileBytes: 200,
        stdoutSink: _nullSink(),
        stderrSink: _nullSink(),
      );

      for (var i = 0; i < 40; i++) {
        sink.info('a reasonably long log line number $i');
      }
      await sink.dispose();

      expect(File('$path.1').existsSync(), isTrue);
      // The live file must stay well under the cap after rotation rather
      // than growing forever.
      expect(File(path).lengthSync(), lessThan(400));
    });

    test(
      'records a file error instead of throwing when the path is unusable',
      () {
        // A path whose "directory" is actually an existing file can never be
        // created, which is the shape of a misconfigured HELIX_REMOTE_LOG_FILE.
        final blocker = File('${tempDir.path}/not-a-dir')
          ..writeAsStringSync('x');
        final sink = ServerLogSink(
          filePath: '${blocker.path}/server.log',
          stdoutSink: _nullSink(),
          stderrSink: _nullSink(),
        );

        expect(() => sink.info('still fine'), returnsNormally);
        expect(sink.fileError, isNotNull);
        expect(sink.fileActive, isFalse);
        // The line is still buffered - a broken file must not cost the
        // operator their in-memory logs too.
        expect(sink.tail(1).single, contains('still fine'));
      },
    );

    test('logServerError falls back to stderr when no sink is installed', () {
      resetServerLogForTesting();
      expect(() => logServerError('no sink installed'), returnsNormally);
    });

    test('logServerError routes through the installed sink', () {
      final sink = ServerLogSink(
        stdoutSink: _nullSink(),
        stderrSink: _nullSink(),
      );
      installServerLog(sink);

      logServerError('routed to sink');

      expect(sink.tail(1).single, contains('routed to sink'));
    });
  });

  group('/api/v1/ops/logs', () {
    late BackendServer server;
    late HttpClient httpClient;
    late int port;
    late ServerIdentity identity;
    late Directory tempDir;

    Future<Map<String, dynamic>> getLogs({String query = ''}) async {
      final request = await httpClient.getUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/ops/logs$query'),
      );
      request.headers.set('Authorization', 'Bearer ${identity.adminToken}');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    }

    Future<void> startServer({String? logFilePath}) async {
      server = BackendServer.create(
        sqliteDb: sqlite3.openInMemory(),
        jwtSecret: 'test_jwt_secret_min_32_bytes_server_log',
        rateLimitMaxTokens: 1000,
        rateLimitRefillRate: 1000,
        logFilePath: logFilePath,
      );
      identity = await ServerIdentity.loadOrCreate(server.db);
      await server.start('127.0.0.1', 0);
      port = server.httpServer!.port;
      httpClient = HttpClient();
    }

    setUp(() => tempDir = Directory.systemTemp.createTempSync('helix_ops_log'));

    tearDown(() async {
      httpClient.close(force: true);
      await server.stop();
      resetServerLogForTesting();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    // The regression this whole file exists for: with no log file
    // configured, /ops/logs used to answer "Log file not configured" and an
    // empty array, so the admin console's Logs screen was blank on every
    // deployment no matter how much the server had logged.
    test('serves in-memory output when no log file is configured', () async {
      final sink = ServerLogSink(
        stdoutSink: _nullSink(),
        stderrSink: _nullSink(),
      );
      installServerLog(sink);
      await startServer();
      // A real server has its startup banner buffered by the time anyone
      // can reach this endpoint; the request-logging middleware only
      // records a request once its handler has already returned.
      sink.info('Helix Remote backend monolith is online.');

      final body = await getLogs();

      expect(body['source'], 'memory');
      final logs = (body['logs'] as List).cast<String>();
      expect(logs, isNotEmpty);
      expect(logs.any((line) => line.contains('monolith is online')), isTrue);
    });

    test('logs each request with method, path and status', () async {
      installServerLog(
        ServerLogSink(stdoutSink: _nullSink(), stderrSink: _nullSink()),
      );
      await startServer();

      await getLogs();
      final logs = ((await getLogs())['logs'] as List).cast<String>();

      expect(
        logs.any((line) => line.contains('GET /api/v1/ops/logs 200')),
        isTrue,
      );
    });

    test('never writes query strings into log lines', () async {
      installServerLog(
        ServerLogSink(stdoutSink: _nullSink(), stderrSink: _nullSink()),
      );
      await startServer();

      // Invite and pairing codes ride in query strings; they must not be
      // persisted to a file the admin API hands back.
      await getLogs(query: '?limit=5&invite=super_secret_code');
      final logs = ((await getLogs())['logs'] as List).cast<String>();

      expect(logs.any((line) => line.contains('super_secret_code')), isFalse);
    });

    test('prefers the file once the sink is writing one', () async {
      final path = '${tempDir.path}/server.log';
      installServerLog(
        ServerLogSink(
          filePath: path,
          stdoutSink: _nullSink(),
          stderrSink: _nullSink(),
        ),
      );
      await startServer(logFilePath: path);

      // Prime the file with history from a "previous run".
      activeServerLog!.info('line from an earlier boot');
      await getLogs();

      final body = await getLogs();
      expect(body['source'], 'file');
      final logs = (body['logs'] as List).cast<String>();
      expect(logs.any((l) => l.contains('line from an earlier boot')), isTrue);
    });

    test('honours limit and clamps it to the maximum', () async {
      final sink = ServerLogSink(
        capacity: 5000,
        stdoutSink: _nullSink(),
        stderrSink: _nullSink(),
      );
      installServerLog(sink);
      await startServer();
      for (var i = 0; i < 1500; i++) {
        sink.info('filler line $i');
      }

      expect(
        ((await getLogs(query: '?limit=5'))['logs'] as List),
        hasLength(5),
      );
      expect(
        ((await getLogs(query: '?limit=99999'))['logs'] as List),
        hasLength(1000),
      );
    });

    test('rejects a non-positive limit', () async {
      installServerLog(
        ServerLogSink(stdoutSink: _nullSink(), stderrSink: _nullSink()),
      );
      await startServer();

      final request = await httpClient.getUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/ops/logs?limit=0'),
      );
      request.headers.set('Authorization', 'Bearer ${identity.adminToken}');
      final response = await request.close();
      await response.drain<void>();

      expect(response.statusCode, 400);
    });

    test('explains itself rather than returning a bare empty list', () async {
      // No sink installed at all - the shape a CLI-launched server has.
      await startServer();

      final body = await getLogs();

      expect(body['source'], 'none');
      expect((body['logs'] as List), isEmpty);
      expect(body['message'], isNotNull);
      expect(body['message'], contains('log sink'));
    });

    test('requires admin privileges', () async {
      installServerLog(
        ServerLogSink(stdoutSink: _nullSink(), stderrSink: _nullSink()),
      );
      await startServer();

      final request = await httpClient.getUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/ops/logs'),
      );
      final response = await request.close();
      await response.drain<void>();

      expect(response.statusCode, anyOf(401, 403));
    });
  });
}
