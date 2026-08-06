import 'dart:io';

import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_backend/src/server_identity.dart';
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test('P9 JWT key ring accepts overlap key and signs with active kid', () {
    final retiring = JwtHelper.keyRing({
      'old-2026-07': 'old_secret_that_is_long_enough_for_a_test',
      'new-2026-08': 'new_secret_that_is_long_enough_for_a_test',
    }, keyId: 'old-2026-07');
    final oldToken = retiring.generateToken({
      'account_id': 'alice',
      'refresh': false,
    }, const Duration(hours: 1));
    final rotated = JwtHelper.keyRing({
      'old-2026-07': 'old_secret_that_is_long_enough_for_a_test',
      'new-2026-08': 'new_secret_that_is_long_enough_for_a_test',
    }, keyId: 'new-2026-08');
    final newToken = rotated.generateToken({
      'account_id': 'alice',
      'refresh': false,
    }, const Duration(hours: 1));

    expect(
      rotated.verifyToken(oldToken, expect: ExpectedTokenType.access),
      isNotNull,
    );
    expect(
      rotated.verifyToken(newToken, expect: ExpectedTokenType.access),
      isNotNull,
    );
    final retired = JwtHelper.keyRing({
      'new-2026-08': 'new_secret_that_is_long_enough_for_a_test',
    }, keyId: 'new-2026-08');
    expect(
      retired.verifyToken(oldToken, expect: ExpectedTokenType.access),
      isNull,
    );
  });

  test('P9 SQLite rate limit state survives a process restart', () async {
    final dir = await Directory.systemTemp.createTemp('helix_phase9_rate_');
    final path = '${dir.path}${Platform.pathSeparator}rate.db';
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final firstDb = sqlite3.open(path);
    final first = RateLimiter(
      maxTokens: 1,
      refillRatePerSecond: 0,
      store: SqliteRateLimitStore(firstDb),
    );
    expect(first.isAllowed('ip:198.51.100.10'), isTrue);
    first.dispose();
    firstDb.close();

    final secondDb = sqlite3.open(path);
    final second = RateLimiter(
      maxTokens: 1,
      refillRatePerSecond: 0,
      store: SqliteRateLimitStore(secondDb),
    );
    addTearDown(secondDb.close);
    expect(second.isAllowed('ip:198.51.100.10'), isFalse);
  });

  test('P9 paired admin credentials are scoped and expire', () async {
    var now = DateTime.utc(2026, 8, 7);
    final sqliteDb = sqlite3.openInMemory();
    final server = BackendServer.create(
      sqliteDb: sqliteDb,
      jwtSecret: 'test_jwt_secret_that_is_long_enough_for_phase_nine',
      now: () => now,
    );
    addTearDown(server.stop);
    final identity = await ServerIdentity.loadOrCreate(
      server.db,
      now: () => now,
    );
    server.serverIdentity = identity;
    final token = identity.adminToken!;
    expect(server.getHandler(), isNotNull);
    final expiry = int.parse(
      server.db.getServerConfig('admin_token_expires_at')!,
    );
    expect(server.db.getServerConfig('admin_token_scopes'), equals('ops:*'));

    now = DateTime.fromMillisecondsSinceEpoch(expiry + 1, isUtc: true);
    // The auth middleware must no longer turn the expired raw token into an
    // administrator; a normal protected request gets the standard 401.
    final response = await server.getHandler().call(
      _requestWithBearer('/api/v1/ops/metrics', token),
    );
    expect(response.statusCode, equals(401));
  });

  test('P9 feature flags are allow-listed and default closed', () {
    final db = BackendDatabase(sqlite3.openInMemory());
    addTearDown(db.close);
    final flags = FeatureFlagService(db);

    expect(flags.isEnabled('crash_reporting_upload'), isFalse);
    flags.set('crash_reporting_upload', true);
    expect(flags.snapshot()['crash_reporting_upload'], isTrue);
    expect(() => flags.set('typo_is_not_a_feature', true), throwsArgumentError);
  });

  test('P9 request correlation ids are echoed or safely generated', () async {
    final server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_that_is_long_enough_for_phase_nine',
    );
    addTearDown(server.stop);
    final handler = server.getHandler();
    final supplied = await handler.call(
      Request(
        'GET',
        Uri.parse('http://localhost/api/v1/health/live'),
        headers: {'x-correlation-id': 'client_trace_0001'},
      ),
    );
    expect(supplied.headers['x-correlation-id'], equals('client_trace_0001'));

    final generated = await handler.call(
      Request(
        'GET',
        Uri.parse('http://localhost/api/v1/health/live'),
        headers: {'x-correlation-id': 'bad value'},
      ),
    );
    expect(
      generated.headers['x-correlation-id'],
      matches(r'^[A-Za-z0-9_-]{16}$'),
    );
  });
}

Request _requestWithBearer(String path, String token) => Request(
  'GET',
  Uri.parse('http://localhost$path'),
  headers: {'Authorization': 'Bearer $token'},
);
