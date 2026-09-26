// Phase 1 — truthfulness, data integrity & quick backend fixes.
//
// Each test here pins a behaviour that was previously fabricated or broken:
// a read that wrote a row, a string-escape bug that dropped crash field
// values, a hardcoded `true` in a support bundle, and a count that was never
// sent to the admin console.

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_backend/src/sms_provider.dart';

import 'test_registration.dart';

void main() {
  group('getDevices no longer fabricates a device row', () {
    late Database raw;
    late BackendDatabase db;

    setUp(() {
      raw = sqlite3.openInMemory();
      db = BackendDatabase(raw);
    });
    tearDown(() => db.close());

    test('an account with no devices reads back empty', () {
      db.createAccount('acct_no_device', 'user_no_device', 'signing_key');

      expect(db.getDevices('acct_no_device'), isEmpty);
    });

    test('reading devices for a device-less account inserts nothing', () {
      db.createAccount('acct_no_device', 'user_no_device', 'signing_key');

      expect(_countDevices(raw, 'acct_no_device'), equals(0));
      // Read twice: the old implementation inserted its synthetic row on the
      // first read, so the second read returned that row instead of empty.
      db.getDevices('acct_no_device');
      db.getDevices('acct_no_device');

      expect(_countDevices(raw, 'acct_no_device'), equals(0),
          reason: 'a read must not write to the devices table');
    });

    test('a genuinely registered device is still returned', () {
      db.createAccount('acct_with_device', 'user_with_device', 'signing_key');
      db.registerDevice(
        'device_1',
        'acct_with_device',
        'device_signing_key',
        'device_agreement_key',
        'Pixel 9',
      );

      final devices = db.getDevices('acct_with_device');

      expect(devices, hasLength(1));
      expect(devices.single['device_id'], equals('device_1'));
      expect(devices.single['device_name'], equals('Pixel 9'));
    });

    test('a revoked device is still listed, with its revoked status', () {
      db.createAccount('acct_revoked', 'user_revoked', 'signing_key');
      db.registerDevice('device_1', 'acct_revoked', 'k1', 'k2', 'Old Phone');
      db.revokeDevice('acct_revoked', 'device_1');

      final devices = db.getDevices('acct_revoked');

      expect(devices, hasLength(1));
      expect(devices.single['status'], equals('REVOKED'));
    });
  });

  group('getAllUsersDetailedPaginated reports a real device_count', () {
    late BackendDatabase db;

    setUp(() => db = BackendDatabase(sqlite3.openInMemory()));
    tearDown(() => db.close());

    test('an account with no devices reports 0, not 1', () {
      db.createAccount('acct_empty', 'user_empty', 'signing_key');

      final users = db.getAllUsersDetailedPaginated(limit: 50, offset: 0);

      expect(users, hasLength(1));
      expect(users.single['account_id'], equals('acct_empty'));
      expect(users.single['device_count'], equals(0));
    });

    test('device_count reflects the number of ACTIVE devices', () {
      db.createAccount('acct_two', 'user_two', 'signing_key');
      db.registerDevice('device_1', 'acct_two', 'k1', 'k1', 'Phone A');
      db.registerDevice('device_2', 'acct_two', 'k2', 'k2', 'Phone B');
      db.registerDevice('device_3', 'acct_two', 'k3', 'k3', 'Phone C');
      db.revokeDevice('acct_two', 'device_3');

      final users = db.getAllUsersDetailedPaginated(limit: 50, offset: 0);

      expect(users.single['device_count'], equals(2),
          reason: 'a REVOKED device is not a connected device');
    });

    test('device_count is per-account, not a global total', () {
      db.createAccount('acct_a', 'user_a', 'signing_key');
      db.createAccount('acct_b', 'user_b', 'signing_key');
      db.registerDevice('device_a1', 'acct_a', 'k1', 'k1', 'Phone A');
      db.registerDevice('device_a2', 'acct_a', 'k2', 'k2', 'Phone B');
      db.registerDevice('device_b1', 'acct_b', 'k1', 'k1', 'Phone C');

      final users = db.getAllUsersDetailedPaginated(limit: 50, offset: 0);
      final byId = {for (final u in users) u['account_id'] as String: u};

      expect(byId['acct_a']!['device_count'], equals(2));
      expect(byId['acct_b']!['device_count'], equals(1));
    });
  });

  group('crash report truncation interpolates', () {
    late BackendServer server;
    late HttpClient client;
    late ServerLogSink sink;
    late int port;

    setUp(() async {
      // A sink is installed so the crash line lands in a buffer the test can
      // read back; the truncation bug was only visible in the emitted line.
      sink = ServerLogSink(capacity: 200);
      installServerLog(sink);
      server = BackendServer.create(
        sqliteDb: sqlite3.openInMemory(),
        jwtSecret: 'test_jwt_secret_for_phase1_truncation',
        rateLimitMaxTokens: 1000,
        rateLimitRefillRate: 1000,
      );
      await server.start('127.0.0.1', 0);
      // The crash sink is gated on the operator's `crash_reporting_upload`
      // flag, which defaults to off.
      server.db.setServerConfig(
        'feature_flag.crash_reporting_upload',
        'true',
      );
      port = server.httpServer!.port;
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.stop();
      await sink.dispose();
      resetServerLogForTesting();
    });

    Future<String> authenticate(String suffix) async {
      final material = await registerTestAccount(
        client: client,
        host: '127.0.0.1',
        port: port,
        db: server.db,
        accountId: 'phase1_acc_$suffix',
        username: 'phase1_user_$suffix',
        deviceId: 'phase1_device_$suffix',
        deviceName: 'Phase 1 Phone',
      );
      final login = await loginTestAccount(
        client: client,
        host: '127.0.0.1',
        port: port,
        accountId: 'phase1_acc_$suffix',
        deviceId: 'phase1_device_$suffix',
        deviceSigningKeyPair: material.deviceSigningKeyPair,
      );
      return login['token'] as String;
    }

    Future<int> postCrash(
      Map<String, dynamic> body, {
      required String token,
    }) async {
      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/telemetry/crash'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set('Authorization', 'Bearer $token');
      request.write(jsonEncode(body));
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    }

    test('an over-long field is truncated to 512 characters, not dropped', () async {
      final token = await authenticate('truncate');
      final longValue = List.filled(600, 'a').join();

      expect(
        await postCrash(
          {'name': 'app_crash', 'fields': {'error': longValue}},
          token: token,
        ),
        equals(200),
      );

      final lines = sink.tail(50).where((l) => l.contains('telemetry_crash'));
      expect(lines, isNotEmpty, reason: 'the crash must reach the server log');

      final line = lines.last;
      expect(
        line,
        isNot(contains(r'${flattened.substring')),
        reason: 'the truncation helper must interpolate, not emit its own '
            'source text as the log value',
      );
      expect(
        line,
        contains(List.filled(512, 'a').join()),
        reason: 'the first 512 characters of the field must be logged',
      );
      expect(
        line,
        isNot(contains(List.filled(513, 'a').join())),
        reason: 'nothing past the 512-character bound may be logged',
      );
    });

    test('a short field is logged verbatim', () async {
      final token = await authenticate('short');

      await postCrash(
        {'name': 'app_crash', 'fields': {'error': 'StateError: boom'}},
        token: token,
      );

      final lines = sink.tail(50).where((l) => l.contains('telemetry_crash'));
      expect(lines, isNotEmpty);
      expect(lines.last, contains('error=StateError: boom'));
    });

    test('whitespace is flattened before the bound is applied', () async {
      final token = await authenticate('whitespace');

      await postCrash(
        {
          'name': 'app_crash',
          'fields': {'error': 'line one\nline two   with   gaps'},
        },
        token: token,
      );

      final lines = sink.tail(50).where((l) => l.contains('telemetry_crash'));
      expect(lines.last, contains('error=line one line two with gaps'));
    });
  });

  group('support diagnostic reports the real websocket readiness', () {
    late BackendServer server;
    late HttpClient client;
    late int port;
    late String adminToken;

    setUp(() async {
      server = BackendServer.create(
        sqliteDb: sqlite3.openInMemory(),
        jwtSecret: 'test_jwt_secret_for_phase1_diagnostic',
        rateLimitMaxTokens: 1000,
        rateLimitRefillRate: 1000,
      );
      await server.start('127.0.0.1', 0);
      port = server.httpServer!.port;
      client = HttpClient();

      server.db.createAccount('phase1_ops', 'phase1_ops_user', 'ops_key');
      server.db.setAccountAdmin('phase1_ops', isAdmin: true);
      server.db.registerDevice(
        'phase1_ops_device',
        'phase1_ops',
        'ops_device_key',
        'Ops',
      );
      adminToken = server.jwt.generateToken({
        'account_id': 'phase1_ops',
        'device_id': 'phase1_ops_device',
      }, const Duration(hours: 1));
    });

    tearDown(() async {
      client.close(force: true);
      await server.stop();
    });

    Future<Map<String, dynamic>> getJson(String path) async {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port$path'),
      );
      request.headers.set('Authorization', 'Bearer $adminToken');
      final response = await request.close();
      final body =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      return body;
    }

    test('support-diagnostic websocket_ready agrees with /health/ready', () async {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/health/ready'),
      );
      final response = await request.close();
      final ready =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;

      final diagnostic = await getJson('/api/v1/ops/support-diagnostic');
      final diagnosticReadiness = diagnostic['readiness'] as Map<String, dynamic>;

      expect(
        diagnosticReadiness['websocket_ready'],
        equals(ready['websocket_ready']),
        reason: 'a support bundle must not over-report on the dependency the '
            'readiness probe already flagged',
      );
    });

    test('the diagnostic still reports the other readiness signals', () async {
      final diagnostic = await getJson('/api/v1/ops/support-diagnostic');
      final readiness = diagnostic['readiness'] as Map<String, dynamic>;

      expect(readiness.keys, containsAll(<String>[
        'api_ready',
        'websocket_ready',
        'push_ready',
        'turn_ready',
      ]));
    });
  });

  group('/ops/metrics exposes the SMS provider', () {
    late BackendServer server;
    late HttpClient client;
    late int port;
    late String adminToken;

    setUp(() async {
      server = BackendServer.create(
        sqliteDb: sqlite3.openInMemory(),
        jwtSecret: 'test_jwt_secret_for_phase1_sms_metric',
        rateLimitMaxTokens: 1000,
        rateLimitRefillRate: 1000,
      );
      await server.start('127.0.0.1', 0);
      port = server.httpServer!.port;
      client = HttpClient();

      server.db.createAccount('phase1_sms_ops', 'phase1_sms_ops_user', 'ops_key');
      server.db.setAccountAdmin('phase1_sms_ops', isAdmin: true);
      server.db.registerDevice(
        'phase1_sms_ops_device',
        'phase1_sms_ops',
        'ops_device_key',
        'Ops',
      );
      adminToken = server.jwt.generateToken({
        'account_id': 'phase1_sms_ops',
        'device_id': 'phase1_sms_ops_device',
      }, const Duration(hours: 1));
    });

    tearDown(() async {
      client.close(force: true);
      await server.stop();
    });

    Future<Map<String, dynamic>> getMetrics() async {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/ops/metrics'),
      );
      request.headers.set('Authorization', 'Bearer $adminToken');
      final response = await request.close();
      expect(response.statusCode, equals(200));
      return jsonDecode(await response.transform(utf8.decoder).join())
          as Map<String, dynamic>;
    }

    test('an unconfigured gateway is reported as unconfigured, by name', () async {
      final metrics = await getMetrics();
      final sms = metrics['sms_provider'] as Map<String, dynamic>;

      expect(sms['configured'], isFalse);
      expect(sms['name'], equals('None'));
    });

    test('a configured gateway is reported with its provider name', () async {
      await server.stop();
      server = BackendServer.create(
        sqliteDb: sqlite3.openInMemory(),
        jwtSecret: 'test_jwt_secret_for_phase1_sms_metric',
        rateLimitMaxTokens: 1000,
        rateLimitRefillRate: 1000,
        smsProvider: BulkSmsBdProvider(
          apiKey: 'test_api_key',
          senderId: 'TEST',
        ),
      );
      await server.start('127.0.0.1', 0);
      port = server.httpServer!.port;

      server.db.createAccount('phase1_sms_ops2', 'phase1_sms_ops2_user', 'ops_key');
      server.db.setAccountAdmin('phase1_sms_ops2', isAdmin: true);
      server.db.registerDevice(
        'phase1_sms_ops_device2',
        'phase1_sms_ops2',
        'ops_device_key',
        'Ops',
      );
      adminToken = server.jwt.generateToken({
        'account_id': 'phase1_sms_ops2',
        'device_id': 'phase1_sms_ops_device2',
      }, const Duration(hours: 1));

      final sms = (await getMetrics())['sms_provider'] as Map<String, dynamic>;

      expect(sms['configured'], isTrue);
      expect(sms['name'], equals('BulkSMSBD'));
    });
  });

  group('admin users endpoint sends a truthful device_count', () {
    late BackendServer server;
    late HttpClient client;
    late int port;
    late String adminToken;

    setUp(() async {
      server = BackendServer.create(
        sqliteDb: sqlite3.openInMemory(),
        jwtSecret: 'test_jwt_secret_for_phase1_users_devices',
        rateLimitMaxTokens: 1000,
        rateLimitRefillRate: 1000,
      );
      await server.start('127.0.0.1', 0);
      port = server.httpServer!.port;
      client = HttpClient();

      server.db.createAccount('phase1_users_ops', 'phase1_users_ops_u', 'ops_key');
      server.db.setAccountAdmin('phase1_users_ops', isAdmin: true);
      server.db.registerDevice(
        'phase1_users_ops_device',
        'phase1_users_ops',
        'ops_device_key',
        'Ops',
      );
      adminToken = server.jwt.generateToken({
        'account_id': 'phase1_users_ops',
        'device_id': 'phase1_users_ops_device',
      }, const Duration(hours: 1));
    });

    tearDown(() async {
      client.close(force: true);
      await server.stop();
    });

    Future<Map<String, dynamic>> getUsers() async {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/ops/users?limit=50&offset=0'),
      );
      request.headers.set('Authorization', 'Bearer $adminToken');
      final response = await request.close();
      expect(response.statusCode, equals(200));
      return jsonDecode(await response.transform(utf8.decoder).join())
          as Map<String, dynamic>;
    }

    test('a device-less account reports 0 and an empty device list', () async {
      server.db.createAccount('phase1_plain', 'phase1_plain_u', 'signing_key');

      final body = await getUsers();
      final users = (body['users'] as List).cast<Map<String, dynamic>>();
      final plain = users.firstWhere((u) => u['account_id'] == 'phase1_plain');

      expect(plain['device_count'], equals(0));
      expect(plain['devices'], isEmpty);
    });

    test('the device list matches device_count for an account with devices',
        () async {
      server.db.createAccount('phase1_with', 'phase1_with_u', 'signing_key');
      server.db.registerDevice(
        'phase1_with_d1',
        'phase1_with',
        'k1',
        'k1',
        'Phone A',
      );
      server.db.registerDevice(
        'phase1_with_d2',
        'phase1_with',
        'k2',
        'k2',
        'Phone B',
      );

      final body = await getUsers();
      final users = (body['users'] as List).cast<Map<String, dynamic>>();
      final withDevice = users.firstWhere(
        (u) => u['account_id'] == 'phase1_with',
      );

      expect(withDevice['device_count'], equals(2));
      expect(
        (withDevice['devices'] as List).length,
        equals(2),
        reason: 'the count and the list must not disagree',
      );
    });
  });

  group('admin reports endpoint is genuinely paged', () {
    late BackendServer server;
    late HttpClient client;
    late int port;
    late String adminToken;

    setUp(() async {
      server = BackendServer.create(
        sqliteDb: sqlite3.openInMemory(),
        jwtSecret: 'test_jwt_secret_for_phase1_reports_paging',
        rateLimitMaxTokens: 1000,
        rateLimitRefillRate: 1000,
      );
      await server.start('127.0.0.1', 0);
      port = server.httpServer!.port;
      client = HttpClient();

      server.db.createAccount('phase1_rep_ops', 'phase1_rep_ops_u', 'ops_key');
      server.db.setAccountAdmin('phase1_rep_ops', isAdmin: true);
      server.db.registerDevice(
        'phase1_rep_ops_device',
        'phase1_rep_ops',
        'ops_device_key',
        'Ops',
      );
      adminToken = server.jwt.generateToken({
        'account_id': 'phase1_rep_ops',
        'device_id': 'phase1_rep_ops_device',
      }, const Duration(hours: 1));

      server.db.createAccount('phase1_reporter', 'phase1_reporter_u', 'k');
      server.db.createAccount('phase1_subject', 'phase1_subject_u', 'k');
    });

    tearDown(() async {
      client.close(force: true);
      await server.stop();
    });

    Future<List<String>> getReportIds({int limit = 50, int offset = 0}) async {
      final request = await client.getUrl(
        Uri.parse(
          'http://127.0.0.1:$port/api/v1/admin/reports'
          '?limit=$limit&offset=$offset',
        ),
      );
      request.headers.set('Authorization', 'Bearer $adminToken');
      final response = await request.close();
      expect(response.statusCode, equals(200));
      final body =
          jsonDecode(await response.transform(utf8.decoder).join())
              as Map<String, dynamic>;
      final reports = (body['reports'] as List).cast<Map<String, dynamic>>();
      expect(body['limit'], equals(limit));
      expect(body['offset'], equals(offset));
      return reports.map((r) => r['report_id'] as String).toList();
    }

    test('limit and offset select different pages', () async {
      // 7 reports, 3 per page.
      for (var i = 0; i < 7; i++) {
        server.db.createReport(
          reportId: 'phase1_report_$i',
          reporterAccountId: 'phase1_reporter',
          subjectAccountId: 'phase1_subject',
          category: 'spam',
          reasonCode: 'reason_$i',
        );
      }

      final first = await getReportIds(limit: 3, offset: 0);
      final second = await getReportIds(limit: 3, offset: 3);
      final third = await getReportIds(limit: 3, offset: 6);

      expect(first, hasLength(3));
      expect(second, hasLength(3));
      expect(third, hasLength(1));

      final seen = {...first, ...second, ...third};
      expect(seen, hasLength(7), reason: 'every report appears exactly once');
      expect(
        first.toSet().intersection(second.toSet()),
        isEmpty,
        reason: 'page 2 must not repeat page 1',
      );
    });

    test('a negative offset is rejected rather than silently ignored', () async {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/admin/reports?offset=-1'),
      );
      request.headers.set('Authorization', 'Bearer $adminToken');
      final response = await request.close();
      await response.drain<void>();

      expect(response.statusCode, equals(400));
    });
  });
}

/// Reads the `devices` table directly, so a test can tell a genuine read from
/// one that quietly wrote a row on the way.
int _countDevices(Database raw, String accountId) {
  final result = raw.select(
    'SELECT COUNT(*) AS n FROM devices WHERE account_id = ?;',
    [accountId],
  );
  return result.first['n'] as int? ?? 0;
}
