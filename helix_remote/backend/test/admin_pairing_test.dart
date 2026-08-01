// Live admin-token pairing flow (lib/src/modules/admin_pairing.dart): an
// operator with terminal access mints a short-lived, single-use code via a
// loopback-only call while the server keeps running, and the admin app
// redeems that code over the network for a freshly-rotated admin token.
// /generate must reject anything that isn't the real loopback socket peer
// (not just a spoofable header), and /redeem must be single-use, expire,
// and be rate-limited.

import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_backend/src/modules/admin_pairing.dart';
import 'package:helix_remote_backend/src/server_identity.dart';
import 'package:shelf/shelf.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

class _FakeConnectionInfo implements HttpConnectionInfo {
  _FakeConnectionInfo(this.remoteAddress);
  @override
  final InternetAddress remoteAddress;
  @override
  int get remotePort => 54321;
  @override
  int get localPort => 8080;
}

Request _request(
  String method,
  String path, {
  InternetAddress? peer,
  String? body,
  String? clientIp,
}) {
  final connInfo = peer == null ? null : _FakeConnectionInfo(peer);
  return Request(
    method,
    Uri.parse('http://localhost$path'),
    body: body,
    context: {
      'shelf.io.connection_info': ?connInfo,
      'client_ip': ?clientIp,
    },
  );
}

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
  String path,
  Map<String, dynamic> body,
) async {
  final request = await client.postUrl(Uri.parse('http://127.0.0.1:$port$path'));
  request.headers.set('Content-Type', 'application/json');
  request.write(jsonEncode(body));
  final response = await request.close();
  final responseBody = await response.transform(utf8.decoder).join();
  return _Response(response.statusCode, responseBody);
}

void main() {
  group('AdminPairingModule (direct router, no real sockets)', () {
    late BackendDatabase db;

    setUp(() {
      db = BackendDatabase(sqlite3.openInMemory());
    });

    tearDown(() => db.close());

    test('generate rejects a non-loopback caller', () async {
      final module = AdminPairingModule(db: db);
      final response = await module.router.call(
        _request(
          'POST',
          '/generate',
          peer: InternetAddress('203.0.113.5'),
        ),
      );
      expect(response.statusCode, equals(403));
    });

    test('generate accepts a loopback caller and returns a 16-digit code', () async {
      final module = AdminPairingModule(db: db);
      final response = await module.router.call(
        _request('POST', '/generate', peer: InternetAddress.loopbackIPv4),
      );
      expect(response.statusCode, equals(200));
      final code = (await response.readAsString()).trim();
      expect(RegExp(r'^[0-9]{16}$').hasMatch(code), isTrue);
    });

    test('redeem is single-use: a second redemption of the same code fails', () async {
      final module = AdminPairingModule(db: db);
      final genResponse = await module.router.call(
        _request('POST', '/generate', peer: InternetAddress.loopbackIPv4),
      );
      final code = (await genResponse.readAsString()).trim();

      final first = await module.router.call(
        _request(
          'POST',
          '/redeem',
          body: jsonEncode({'code': code}),
          clientIp: '198.51.100.1',
        ),
      );
      expect(first.statusCode, equals(200));
      final firstBody =
          jsonDecode(await first.readAsString()) as Map<String, dynamic>;
      expect(firstBody['admin_token'], isA<String>());
      expect((firstBody['admin_token'] as String).isNotEmpty, isTrue);

      final second = await module.router.call(
        _request(
          'POST',
          '/redeem',
          body: jsonEncode({'code': code}),
          clientIp: '198.51.100.2',
        ),
      );
      expect(second.statusCode, equals(401));
    });

    test('redeem rejects an expired code', () async {
      var now = DateTime.utc(2026, 1, 1);
      final module = AdminPairingModule(
        db: db,
        now: () => now,
        codeValidity: const Duration(minutes: 10),
      );
      final genResponse = await module.router.call(
        _request('POST', '/generate', peer: InternetAddress.loopbackIPv4),
      );
      final code = (await genResponse.readAsString()).trim();

      now = now.add(const Duration(minutes: 11));
      final response = await module.router.call(
        _request(
          'POST',
          '/redeem',
          body: jsonEncode({'code': code}),
          clientIp: '198.51.100.1',
        ),
      );
      expect(response.statusCode, equals(401));
    });

    test('redeem rejects a malformed body and a well-formed but wrong code', () async {
      final module = AdminPairingModule(db: db);

      final malformed = await module.router.call(
        _request(
          'POST',
          '/redeem',
          body: 'not json',
          clientIp: '198.51.100.1',
        ),
      );
      expect(malformed.statusCode, equals(400));

      final wrong = await module.router.call(
        _request(
          'POST',
          '/redeem',
          body: jsonEncode({'code': '0000000000000000'}),
          clientIp: '198.51.100.1',
        ),
      );
      expect(wrong.statusCode, equals(401));
    });

    test('redeem is rate-limited per caller', () async {
      final module = AdminPairingModule(
        db: db,
        redeemRateLimiter: RateLimiter(
          maxTokens: 1,
          refillRatePerSecond: 0,
          store: InMemoryRateLimitStore(),
        ),
      );

      final first = await module.router.call(
        _request(
          'POST',
          '/redeem',
          body: jsonEncode({'code': '0000000000000000'}),
          clientIp: '198.51.100.1',
        ),
      );
      // Wrong code, but the rate limiter's single token is now spent.
      expect(first.statusCode, equals(401));

      final second = await module.router.call(
        _request(
          'POST',
          '/redeem',
          body: jsonEncode({'code': '0000000000000000'}),
          clientIp: '198.51.100.1',
        ),
      );
      expect(second.statusCode, equals(429));
    });
  });

  test(
    'end-to-end over real HTTP: generate + redeem yields a working admin '
    'token and invalidates the previous one',
    () async {
      final sqliteDb = sqlite3.openInMemory();
      final server = BackendServer.create(
        sqliteDb: sqliteDb,
        jwtSecret: 'test_jwt_secret_for_admin_pairing_flow',
        rateLimitMaxTokens: 1000,
        rateLimitRefillRate: 1000,
      );
      final firstBoot = await ServerIdentity.loadOrCreate(server.db);
      final oldToken = firstBoot.adminToken!;
      server.serverIdentity = firstBoot;

      await server.start('127.0.0.1', 0);
      final port = server.httpServer!.port;
      final client = HttpClient();
      try {
        final genResponse = await client.postUrl(
          Uri.parse('http://127.0.0.1:$port/api/v1/admin-pairing/generate'),
        );
        final gen = await genResponse.close();
        final code = (await gen.transform(utf8.decoder).join()).trim();
        expect(gen.statusCode, equals(200));
        expect(RegExp(r'^[0-9]{16}$').hasMatch(code), isTrue);

        final redeem = await _postJson(
          client,
          port,
          '/api/v1/admin-pairing/redeem',
          {'code': code},
        );
        expect(redeem.statusCode, equals(200));
        final newToken =
            (jsonDecode(redeem.body) as Map<String, dynamic>)['admin_token']
                as String;
        expect(newToken, isNot(equals(oldToken)));

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
      } finally {
        client.close(force: true);
        await server.stop();
      }
    },
  );
}
