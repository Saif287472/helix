import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_backend/src/server_identity.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  late BackendServer server;
  late HttpClient httpClient;
  late int port;
  late ServerIdentity identity;
  late File tempLogFile;

  setUp(() async {
    // Setup temporary log file
    tempLogFile = File('test_server_logs.log');
    if (tempLogFile.existsSync()) {
      tempLogFile.deleteSync();
    }
    tempLogFile.writeAsStringSync('line 1\nline 2\nline 3\n');

    final sqliteDb = sqlite3.openInMemory();
    server = BackendServer.create(
      sqliteDb: sqliteDb,
      jwtSecret: 'test_jwt_secret_min_32_bytes_ops_admin',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
      wsReconnectsPerMinute: 2,
      logFilePath: tempLogFile.path,
    );

    // Initialise identity
    identity = await ServerIdentity.loadOrCreate(server.db);

    // Since we're in in-memory DB, adminToken will be returned by loadOrCreate because it is first boot.
    // However, it is a base64 encoded token. If we generate a hash in the database, the raw token is returned by loadOrCreate.
    expect(identity.adminToken, isNotNull);

    // Register a dummy user to verify paginated list
    server.db.createAccount('user1', 'user_one', 'user_key');

    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;
    httpClient = HttpClient();
  });

  tearDown(() async {
    httpClient.close(force: true);
    await server.stop();
    if (tempLogFile.existsSync()) {
      tempLogFile.deleteSync();
    }
  });

  test('Admin Authentication & Config Endpoint', () async {
    // 1. Authorised Request
    final res = await _getJson(
      httpClient,
      port,
      '/api/v1/ops/config',
      token: identity.adminToken,
    );
    expect(res.statusCode, equals(200));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    expect(body['server_id'], equals(identity.serverId));
    expect(body['server_public_key'], isNotEmpty);
    expect(body['port'], isNotEmpty);

    // 2. Unauthorised Request (no token)
    final resNoToken = await _getJson(httpClient, port, '/api/v1/ops/config');
    expect(resNoToken.statusCode, equals(401));

    // 3. Unauthorised Request (bad token)
    final resBadToken = await _getJson(
      httpClient,
      port,
      '/api/v1/ops/config',
      token: 'invalid_token',
    );
    expect(resBadToken.statusCode, equals(403));
  });

  test('Admin Configured Token Override', () async {
    final overrideServer = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_min_32_bytes_ops_admin_override',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
      wsReconnectsPerMinute: 2,
      adminTokenOverride: 'custom_override_token_123',
    );

    // Initialise identity
    final overrideIdentity = await ServerIdentity.loadOrCreate(
      overrideServer.db,
    );

    await overrideServer.start('127.0.0.1', 0);
    final overridePort = overrideServer.httpServer!.port;

    try {
      // 1. Check override token works
      final resOverride = await _getJson(
        httpClient,
        overridePort,
        '/api/v1/ops/config',
        token: 'custom_override_token_123',
      );
      expect(resOverride.statusCode, equals(200));

      // 2. Check generated token is rejected
      final resOld = await _getJson(
        httpClient,
        overridePort,
        '/api/v1/ops/config',
        token: overrideIdentity.adminToken,
      );
      expect(resOld.statusCode, equals(403));
    } finally {
      await overrideServer.stop();
    }
  });

  test('Admin List Users Endpoint', () async {
    final res = await _getJson(
      httpClient,
      port,
      '/api/v1/ops/users?limit=10&offset=0',
      token: identity.adminToken,
    );
    expect(res.statusCode, equals(200));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final users = (body['users'] as List).cast<Map<String, dynamic>>();
    expect(users, isNotEmpty);
    expect(users[0]['account_id'], equals('user1'));
    expect(users[0].containsKey('username'), isFalse);
    expect(users[0].containsKey('phone_hash'), isFalse);
  });

  test('Admin Trigger Backup Endpoint', () async {
    final res = await _postJson(
      httpClient,
      port,
      '/api/v1/ops/backup',
      token: identity.adminToken,
    );
    expect(res.statusCode, equals(200));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    expect(body['status'], equals('success'));
    expect(body['backup_file'], contains('backups/backup_'));

    final backupFile = File(body['backup_file'] as String);
    expect(backupFile.existsSync(), isTrue);

    // Clean up backup file
    backupFile.deleteSync();
    if (Directory('backups').existsSync()) {
      Directory('backups').deleteSync(recursive: true);
    }
  });

  test('Admin Log Tailing Endpoint', () async {
    final res = await _getJson(
      httpClient,
      port,
      '/api/v1/ops/logs',
      token: identity.adminToken,
    );
    expect(res.statusCode, equals(200));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final logs = body['logs'] as List;
    expect(logs, equals(['line 1', 'line 2', 'line 3']));
  });
}

Future<_Response> _getJson(
  HttpClient client,
  int port,
  String path, {
  String? token,
  Map<String, String>? headers,
}) async {
  final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
  if (token != null) {
    request.headers.set('Authorization', 'Bearer $token');
  }
  headers?.forEach(request.headers.set);
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  return _Response(response.statusCode, body);
}

Future<_Response> _postJson(
  HttpClient client,
  int port,
  String path, {
  String? token,
  Map<String, String>? headers,
}) async {
  final request = await client.postUrl(
    Uri.parse('http://127.0.0.1:$port$path'),
  );
  if (token != null) {
    request.headers.set('Authorization', 'Bearer $token');
  }
  headers?.forEach(request.headers.set);
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  return _Response(response.statusCode, body);
}

class _Response {
  const _Response(this.statusCode, this.body);

  final int statusCode;
  final String body;
}
