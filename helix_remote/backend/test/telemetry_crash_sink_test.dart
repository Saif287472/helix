// MED-4 — the self-hosted crash sink.
//
// The audit's recommendation was specific: a self-hosted, opt-in, redacted
// crash sink satisfies both the observability goal and the privacy posture of
// a product that ships no vendor SDK. This covers the server half — that the
// route is authenticated, bounded, and observable.

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:helix_remote_backend/helix_remote_backend.dart';

import 'test_registration.dart';

void main() {
  late BackendServer server;
  late int port;
  late HttpClient client;

  setUp(() async {
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_for_telemetry_crash_sink',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
    );
    await server.start('127.0.0.1', 0);
    // The sink is opt-in: `crash_reporting_upload` gates `_reportCrash`, so a
    // deployment that has not turned it on must refuse reports.
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
  });

  Future<String> authenticate(String suffix) async {
    final material = await registerTestAccount(
      client: client,
      host: '127.0.0.1',
      port: port,
      db: server.db,
      accountId: 'crash_acc_$suffix',
      username: 'crash_user_$suffix',
      deviceId: 'crash_device_$suffix',
      deviceName: 'Crash Phone',
    );
    final login = await loginTestAccount(
      client: client,
      host: '127.0.0.1',
      port: port,
      accountId: 'crash_acc_$suffix',
      deviceId: 'crash_device_$suffix',
      deviceSigningKeyPair: material.deviceSigningKeyPair,
    );
    return login['token'] as String;
  }

  Future<HttpClientResponse> postCrash(
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:$port/api/v1/telemetry/crash'),
    );
    request.headers.contentType = ContentType.json;
    if (token != null) {
      request.headers.set('Authorization', 'Bearer $token');
    }
    request.write(jsonEncode(body));
    return request.close();
  }

  test('an unauthenticated report is refused', () async {
    // The route is not on the auth middleware's public skip list, and it must
    // stay off it: an open sink is an unauthenticated write into the
    // operator's log.
    final response = await postCrash({'name': 'app_crash', 'fields': {}});
    expect(response.statusCode, equals(401));
    await response.drain<void>();
  });

  test('the sink refuses reports while the operator flag is off', () async {
    // The flag defaults to off, so a deployment that never opted in must not
    // accept crash data - and the refusal has to be counted, otherwise
    // /ops/metrics cannot distinguish "no clients reporting" from "clients
    // reporting into a switched-off sink".
    server.db.setServerConfig(
      'feature_flag.crash_reporting_upload',
      'false',
    );
    final token = await authenticate('flag_off');

    final response = await postCrash(
      {'name': 'app_crash', 'fields': {'error': 'StateError: boom'}},
      token: token,
    );

    expect(response.statusCode, equals(403));
    final body =
        jsonDecode(await response.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    expect(
      body['error'],
      contains('disabled'),
      reason: 'the client is told why, rather than getting a bare 403',
    );

    server.db.createAccount('crash_flag_ops', 'crash_flag_ops_u', 'ops_key');
    server.db.setAccountAdmin('crash_flag_ops', isAdmin: true);
    server.db.registerDevice(
      'crash_flag_ops_device',
      'crash_flag_ops',
      'ops_device_key',
      'Ops',
    );
    final adminToken = server.jwt.generateToken({
      'account_id': 'crash_flag_ops',
      'device_id': 'crash_flag_ops_device',
    }, const Duration(hours: 1));

    final metricsRequest = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/api/v1/ops/metrics'),
    );
    metricsRequest.headers.set('Authorization', 'Bearer $adminToken');
    final metricsResponse = await metricsRequest.close();
    final metrics =
        jsonDecode(await metricsResponse.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    final telemetry = metrics['telemetry'] as Map<String, dynamic>;

    expect(telemetry['crash_reports_accepted'], equals(0));
    expect(
      telemetry['crash_reports_rejected'],
      equals(1),
      reason: 'a refused report is still observable',
    );
  });

  test('the feature flag snapshot reports the crash sink as on', () async {
    server.db.createAccount('crash_flag_read', 'crash_flag_read_u', 'ops_key');
    server.db.setAccountAdmin('crash_flag_read', isAdmin: true);
    server.db.registerDevice(
      'crash_flag_read_device',
      'crash_flag_read',
      'ops_device_key',
      'Ops',
    );
    final adminToken = server.jwt.generateToken({
      'account_id': 'crash_flag_read',
      'device_id': 'crash_flag_read_device',
    }, const Duration(hours: 1));

    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/api/v1/ops/feature-flags'),
    );
    request.headers.set('Authorization', 'Bearer $adminToken');
    final response = await request.close();
    final body =
        jsonDecode(await response.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    final flags = body['flags'] as Map<String, dynamic>;

    expect(flags['crash_reporting_upload'], isTrue);
  });

  test('an authenticated report is accepted and counted', () async {
    final token = await authenticate('ok');

    final response = await postCrash({
      'name': 'app_crash',
      'fields': {'error': 'StateError: boom', 'stack': 'main.dart:1'},
    }, token: token);

    expect(response.statusCode, equals(200));
    final body =
        jsonDecode(await response.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    expect(body['accepted'], isTrue);
  });

  test('a malformed report is rejected rather than logged', () async {
    final token = await authenticate('malformed');

    for (final body in <Map<String, dynamic>>[
      {'fields': <String, String>{}},
      {'name': '', 'fields': <String, String>{}},
      {'name': 'app_crash'},
      {'name': 'app_crash', 'fields': 'not-a-map'},
    ]) {
      final response = await postCrash(body, token: token);
      expect(
        response.statusCode,
        equals(400),
        reason: 'rejected shape: ${jsonEncode(body)}',
      );
      await response.drain<void>();
    }
  });

  test('the counters reach /ops/metrics so the rate is observable', () async {
    final token = await authenticate('metrics');
    (await postCrash({
      'name': 'app_crash',
      'fields': {'error': 'StateError: boom'},
    }, token: token)).drain<void>();

    // Admin is a stored capability, not a magic account id (CRIT-1), so the
    // grant is what makes this read allowed.
    server.db.createAccount('crash_ops', 'crash_ops_user', 'ops_key');
    server.db.setAccountAdmin('crash_ops', isAdmin: true);
    server.db.registerDevice(
      'crash_ops_device',
      'crash_ops',
      'ops_device_key',
      'Ops',
    );
    final adminToken = server.jwt.generateToken({
      'account_id': 'crash_ops',
      'device_id': 'crash_ops_device',
    }, const Duration(hours: 1));

    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port/api/v1/ops/metrics'),
    );
    request.headers.set('Authorization', 'Bearer $adminToken');
    final response = await request.close();
    expect(response.statusCode, equals(200));

    final metrics =
        jsonDecode(await response.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    final telemetry = metrics['telemetry'] as Map<String, dynamic>;

    expect(telemetry['crash_reports_accepted'], equals(1));
    expect(telemetry['last_crash_report_at'], isNotNull);
  });

  test('a device in a crash loop is rate limited', () async {
    // Budget sized so registration and login still succeed - they draw on
    // their own keys - while the per-device crash bucket is exhaustible
    // within a test. Zero refill keeps it deterministic.
    const budget = 20.0;
    final limited = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_for_telemetry_crash_rate',
      rateLimitMaxTokens: budget,
      rateLimitRefillRate: 0,
    );
    await limited.start('127.0.0.1', 0);
    limited.db.setServerConfig(
      'feature_flag.crash_reporting_upload',
      'true',
    );
    addTearDown(limited.stop);
    final limitedPort = limited.httpServer!.port;
    final limitedClient = HttpClient();
    addTearDown(() => limitedClient.close(force: true));

    final material = await registerTestAccount(
      client: limitedClient,
      host: '127.0.0.1',
      port: limitedPort,
      db: limited.db,
      accountId: 'crash_acc_loop',
      username: 'crash_user_loop',
      deviceId: 'crash_device_loop',
      deviceName: 'Looping Phone',
    );
    final login = await loginTestAccount(
      client: limitedClient,
      host: '127.0.0.1',
      port: limitedPort,
      accountId: 'crash_acc_loop',
      deviceId: 'crash_device_loop',
      deviceSigningKeyPair: material.deviceSigningKeyPair,
    );
    final token = login['token'] as String;

    final codes = <int>[];
    for (var i = 0; i < (budget * 2).toInt(); i++) {
      final request = await limitedClient.postUrl(
        Uri.parse('http://127.0.0.1:$limitedPort/api/v1/telemetry/crash'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set('Authorization', 'Bearer $token');
      request.write(
        jsonEncode({
          'name': 'app_crash',
          'fields': {'i': '$i'},
        }),
      );
      final response = await request.close();
      codes.add(response.statusCode);
      await response.drain<void>();
    }

    expect(
      codes,
      contains(429),
      reason: 'an unbounded sink lets one looping device fill the log',
    );
  });
}
