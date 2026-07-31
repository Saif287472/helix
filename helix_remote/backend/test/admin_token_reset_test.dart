// Admin token recovery flow (bin/reset_admin_token.dart's DB-level logic):
// clearing 'admin_token_hash' and calling ServerIdentity.loadOrCreate again
// must mint a fresh token WITHOUT regenerating the server's identity/keypair
// (which would break federation trust with any peer that already has this
// server's public key), and the old token must stop authenticating while
// the new one starts working.

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

void main() {
  test('clearing admin_token_hash and reloading identity mints a new token, '
      'preserves the server id/keypair, and immediately supersedes the old '
      'token for admin auth', () async {
    final sqliteDb = sqlite3.openInMemory();
    final server = BackendServer.create(
      sqliteDb: sqliteDb,
      jwtSecret: 'test_jwt_secret_for_admin_token_reset_flow',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
    );

    // First boot: identity + admin token both freshly generated.
    final before = await ServerIdentity.loadOrCreate(server.db);
    expect(before.adminToken, isNotNull);
    final oldToken = before.adminToken!;

    // Simulate bin/reset_admin_token.dart: clear just the token hash.
    server.db.deleteServerConfig('admin_token_hash');
    final after = await ServerIdentity.loadOrCreate(server.db);

    expect(after.adminToken, isNotNull);
    final newToken = after.adminToken!;
    expect(newToken, isNot(equals(oldToken)));

    // Server identity (id + federation keypair) must be untouched.
    expect(after.serverId, equals(before.serverId));
    final beforePub = await before.serverKeyPair.extractPublicKey();
    final afterPub = await after.serverKeyPair.extractPublicKey();
    expect(afterPub.bytes, equals(beforePub.bytes));

    server.serverIdentity = after;
    await server.start('127.0.0.1', 0);
    final port = server.httpServer!.port;
    final client = HttpClient();
    try {
      final withOld = await _getJson(
        client,
        port,
        '/api/v1/ops/config',
        token: oldToken,
      );
      expect(withOld.statusCode, equals(403));

      final withNew = await _getJson(
        client,
        port,
        '/api/v1/ops/config',
        token: newToken,
      );
      expect(withNew.statusCode, equals(200));
      final body = jsonDecode(withNew.body) as Map<String, dynamic>;
      expect(body['server_id'], equals(after.serverId));
    } finally {
      client.close(force: true);
      await server.stop();
    }
  });
}
