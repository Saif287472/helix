// Locks the wire contract between the backend's TURN credential endpoint
// and the coturn relay deployed alongside it (deploy/coturn/).
//
// coturn runs in `use-auth-secret` mode, which means it holds no user
// accounts and instead recomputes the expected password from the shared
// secret on every allocation, per the TURN REST API draft:
//
//   username = <unix-expiry-seconds>:<arbitrary-identifier>
//   password = base64(HMAC-SHA1(shared-secret, username))
//
// The assertions below recompute that construction independently of the
// server's own code. If someone changes the hash, the encoding, or the
// username layout, every call on every deployment starts failing to
// connect with a 401 from the relay - a failure that shows up nowhere in
// the backend's own logs, because the backend is not involved once the
// credential is handed out. Verified against coturn 4.6.1 by allocating a
// real relay with a credential produced by this endpoint.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

const _turnSecret = 'test_shared_secret_for_turn_rest_api';
const _turnUrls = 'turn:hr.example.com:3478,turns:hr.example.com:5349';

void main() {
  late BackendServer server;
  late int port;
  late String token;

  setUp(() async {
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_min_32_bytes_turn_rest',
      rateLimitMaxTokens: 500,
      rateLimitRefillRate: 100,
      turnUrl: _turnUrls,
      turnSecret: _turnSecret,
    );
    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;

    server.db.createAccount('alice', 'alice_user', 'alice_identity_key');
    server.db.registerDevice(
      'alice_device1',
      'alice',
      'alice_device_key',
      'Alice Phone',
    );
    token = server.jwt.generateToken({
      'account_id': 'alice',
      'device_id': 'alice_device1',
    }, const Duration(hours: 1));
  });

  tearDown(() async => server.stop());

  Future<Map<String, dynamic>> fetchCredentials() async {
    final http = HttpClient();
    try {
      final request = await http.getUrl(
        Uri.parse('http://127.0.0.1:$port/api/v1/calls/turn-credentials'),
      );
      request.headers.set('Authorization', 'Bearer $token');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      expect(response.statusCode, 200);
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      http.close(force: true);
    }
  }

  /// The password coturn will independently compute for [username].
  String expectedCoturnPassword(String username) {
    final hmac = Hmac(sha1, utf8.encode(_turnSecret));
    return base64Encode(hmac.convert(utf8.encode(username)).bytes);
  }

  test('credential is the HMAC-SHA1 password coturn recomputes', () async {
    final body = await fetchCredentials();

    final username = body['username'] as String;
    final credential = body['credential'] as String;

    expect(credential, expectedCoturnPassword(username));
  });

  test('username starts with the expiry timestamp coturn parses', () async {
    final body = await fetchCredentials();

    final username = body['username'] as String;
    final parts = username.split(':');
    // coturn takes everything before the first colon as a unix timestamp
    // and rejects the credential outright once it is in the past.
    final expiry = int.tryParse(parts.first);
    expect(expiry, isNotNull, reason: 'username must start with <expiry>:');

    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    expect(expiry!, greaterThan(nowSeconds));
    expect(body['expires_at'], expiry);
  });

  test('username identifies the issuing account and device', () async {
    final body = await fetchCredentials();

    expect(body['username'], matches(RegExp(r'^\d+:alice:alice_device1$')));
  });

  test(
    'serves every configured URL so clients can fall back to turns:',
    () async {
      final body = await fetchCredentials();

      final urls = (body['urls'] as List).cast<String>();
      expect(urls, ['turn:hr.example.com:3478', 'turns:hr.example.com:5349']);
      // Older clients read the singular field.
      expect(body['url'], 'turn:hr.example.com:3478');
    },
  );

  test(
    'reports 503 rather than issuing unusable credentials when TURN is off',
    () async {
      final unconfigured = BackendServer.create(
        sqliteDb: sqlite3.openInMemory(),
        jwtSecret: 'test_jwt_secret_min_32_bytes_turn_off',
        rateLimitMaxTokens: 500,
        rateLimitRefillRate: 100,
      );
      await unconfigured.start('127.0.0.1', 0);
      unconfigured.db.createAccount('bob', 'bob_user', 'bob_identity_key');
      unconfigured.db.registerDevice(
        'bob_device1',
        'bob',
        'bob_device_key',
        'Bob Phone',
      );
      final bobToken = unconfigured.jwt.generateToken({
        'account_id': 'bob',
        'device_id': 'bob_device1',
      }, const Duration(hours: 1));

      final http = HttpClient();
      try {
        final request = await http.getUrl(
          Uri.parse(
            'http://127.0.0.1:${unconfigured.httpServer!.port}'
            '/api/v1/calls/turn-credentials',
          ),
        );
        request.headers.set('Authorization', 'Bearer $bobToken');
        final response = await request.close();
        final body =
            jsonDecode(await response.transform(utf8.decoder).join())
                as Map<String, dynamic>;

        expect(response.statusCode, 503);
        expect(body['turn_configured'], isFalse);
      } finally {
        http.close(force: true);
        await unconfigured.stop();
      }
    },
  );

  test(
    'a malformed TURN URL is dropped rather than served to clients',
    () async {
      // resolveTurnUrls only accepts turn:/turns: schemes - a typo'd entry
      // in .env must not reach clients as an ICE server they will fail on.
      expect(
        CallsModule.resolveTurnUrls('https://hr.example.com:3478'),
        isEmpty,
      );
      expect(CallsModule.resolveTurnUrls('turn:a:3478, ,turns:b:5349'), [
        'turn:a:3478',
        'turns:b:5349',
      ]);
    },
  );
}
