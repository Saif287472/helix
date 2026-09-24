import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_backend/src/server_identity.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

class _Response {
  const _Response(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

Future<_Response> _getJson(
  HttpClient client,
  int port,
  String path, {
  String? token,
}) async {
  final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port$path'));
  if (token != null) {
    request.headers.set('Authorization', 'Bearer $token');
  }
  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();
  return _Response(response.statusCode, body);
}

Future<_Response> _postJson(
  HttpClient client,
  int port,
  String path, {
  Map<String, dynamic>? body,
  String? token,
}) async {
  final request = await client.postUrl(Uri.parse('http://127.0.0.1:$port$path'));
  request.headers.set('Content-Type', 'application/json');
  if (token != null) {
    request.headers.set('Authorization', 'Bearer $token');
  }
  if (body != null) {
    request.write(jsonEncode(body));
  }
  final response = await request.close();
  final resBody = await response.transform(utf8.decoder).join();
  return _Response(response.statusCode, resBody);
}

void main() {
  test('Admin password 3-step check: setup-status, in-app setup, and .env priority', () async {
    final sqliteDb = sqlite3.openInMemory();
    final server = BackendServer.create(
      sqliteDb: sqliteDb,
      jwtSecret: 'test_jwt_secret_for_admin_password_setup',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
    );

    await ServerIdentity.loadOrCreate(server.db);
    await server.start('127.0.0.1', 0);
    final port = server.httpServer!.port;
    final httpClient = HttpClient();

    try {
      // 1. Initial state: No .env password, no DB password -> needs_setup: true
      final initialStatus = await _getJson(httpClient, port, '/api/v1/ops/setup-status');
      expect(initialStatus.statusCode, 200);
      final initialJson = jsonDecode(initialStatus.body) as Map<String, dynamic>;
      expect(initialJson['needs_setup'], isTrue);

      // Attempting to access protected ops endpoint with random password fails
      final unauthorizedRes = await _getJson(
        httpClient,
        port,
        '/api/v1/ops/config',
        token: 'random_attempt',
      );
      expect(unauthorizedRes.statusCode, 401);

      // 2. In-App Setup: Submit new admin password via POST /api/v1/ops/setup-admin-password
      final setupTooShort = await _postJson(
        httpClient,
        port,
        '/api/v1/ops/setup-admin-password',
        body: {'password': '123'},
      );
      expect(setupTooShort.statusCode, 400);

      const chosenPassword = 'my_super_secure_admin_password_123';
      final setupSuccess = await _postJson(
        httpClient,
        port,
        '/api/v1/ops/setup-admin-password',
        body: {'password': chosenPassword},
      );
      expect(setupSuccess.statusCode, 200);

      // 3. Server is now initialized: setup-status reports needs_setup: false
      final postSetupStatus = await _getJson(httpClient, port, '/api/v1/ops/setup-status');
      expect(postSetupStatus.statusCode, 200);
      final postJson = jsonDecode(postSetupStatus.body) as Map<String, dynamic>;
      expect(postJson['needs_setup'], isFalse);

      // Subsequent setup attempts are rejected with 409 Conflict
      final repeatSetup = await _postJson(
        httpClient,
        port,
        '/api/v1/ops/setup-admin-password',
        body: {'password': 'another_password'},
      );
      expect(repeatSetup.statusCode, 409);

      // 4. Authenticating with chosenPassword works and grants ops:* access
      final authorizedRes = await _getJson(
        httpClient,
        port,
        '/api/v1/ops/config',
        token: chosenPassword,
      );
      expect(authorizedRes.statusCode, 200);

      // 5. Database reset: clearing password hash returns server to setup mode
      server.db.deleteServerConfig('admin_password_hash');
      server.db.deleteServerConfig('admin_password_salt');
      expect(server.needsAdminSetup, isTrue);

      final resetStatus = await _getJson(httpClient, port, '/api/v1/ops/setup-status');
      expect((jsonDecode(resetStatus.body) as Map<String, dynamic>)['needs_setup'], isTrue);
    } finally {
      httpClient.close(force: true);
      await server.stop();
    }
  });

  test('.env password override takes precedence over database password and skips setup', () async {
    final sqliteDb = sqlite3.openInMemory();
    const envPassword = 'env_master_password_override';
    final server = BackendServer.create(
      sqliteDb: sqliteDb,
      jwtSecret: 'test_jwt_secret_for_admin_env_priority',
      adminPasswordOverride: envPassword,
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
    );

    await ServerIdentity.loadOrCreate(server.db);
    await server.start('127.0.0.1', 0);
    final port = server.httpServer!.port;
    final httpClient = HttpClient();

    try {
      // With envPassword, needs_setup is false immediately
      final status = await _getJson(httpClient, port, '/api/v1/ops/setup-status');
      expect(status.statusCode, 200);
      expect((jsonDecode(status.body) as Map<String, dynamic>)['needs_setup'], isFalse);

      // Authenticates with envPassword
      final authorizedRes = await _getJson(
        httpClient,
        port,
        '/api/v1/ops/config',
        token: envPassword,
      );
      expect(authorizedRes.statusCode, 200);
    } finally {
      httpClient.close(force: true);
      await server.stop();
    }
  });
}
