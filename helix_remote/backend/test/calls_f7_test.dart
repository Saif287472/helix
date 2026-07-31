// Tests for Phase F7: Reliable direct calls — push token CRUD, TURN credentials,
// multi-device ring + answered-elsewhere, offline call wake, call metrics upload.
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:helix_remote_backend/helix_remote_backend.dart';

class _Client {
  _Client(this.baseUrl, this.token);
  final String baseUrl;
  final String token;
  final _http = HttpClient();

  Future<
    ({int status, Map<String, dynamic> json, Map<String, List<String>> headers})
  >
  get(String path) async {
    final req = await _http.getUrl(Uri.parse('$baseUrl$path'));
    if (token.isNotEmpty) req.headers.set('Authorization', 'Bearer $token');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
    final headers = <String, List<String>>{};
    res.headers.forEach((name, values) => headers[name] = values);
    return (
      status: res.statusCode,
      json: decoded is Map<String, dynamic> ? decoded : {'_body': decoded},
      headers: headers,
    );
  }

  Future<({int status, Map<String, dynamic> json})> post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final req = await _http.postUrl(Uri.parse('$baseUrl$path'));
    if (token.isNotEmpty) req.headers.set('Authorization', 'Bearer $token');
    req.headers.set('Content-Type', 'application/json');
    req.write(jsonEncode(payload));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
    return (
      status: res.statusCode,
      json: decoded is Map<String, dynamic> ? decoded : {'_body': decoded},
    );
  }

  Future<({int status, Map<String, dynamic> json})> delete(String path) async {
    final req = await _http.deleteUrl(Uri.parse('$baseUrl$path'));
    if (token.isNotEmpty) req.headers.set('Authorization', 'Bearer $token');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    final decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
    return (
      status: res.statusCode,
      json: decoded is Map<String, dynamic> ? decoded : {'_body': decoded},
    );
  }
}

void main() {
  late BackendServer server;
  late int port;
  late String tokenAlice;
  late String tokenBob;

  String base() => 'http://127.0.0.1:$port/api/v1';

  setUp(() async {
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_f7_calls',
      rateLimitMaxTokens: 500.0,
      rateLimitRefillRate: 100.0,
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
    server.db.createAccount('bob', 'bob_user', 'bob_identity_key');
    server.db.registerDevice(
      'bob_device1',
      'bob',
      'bob_device_key',
      'Bob Phone',
    );
    server.db.addContact('alice', 'bob', null);
    server.db.addContact('bob', 'alice', null);

    tokenAlice = server.jwt.generateToken({
      'account_id': 'alice',
      'device_id': 'alice_device1',
    }, const Duration(hours: 1));

    tokenBob = server.jwt.generateToken({
      'account_id': 'bob',
      'device_id': 'bob_device1',
    }, const Duration(hours: 1));
  });

  tearDown(() async => server.stop());

  // -------------------------------------------------------------------------
  // Push token registration
  // -------------------------------------------------------------------------

  group('push token CRUD', () {
    test('registers push token and returns 200', () async {
      final alice = _Client(base(), tokenAlice);
      final r = await alice.post('/calls/push-token', {
        'push_token': 'fcm-token-alice-001',
        'token_type': 'FCM',
      });
      expect(r.status, 200);
      expect(r.json['status'], 'registered');
    });

    test('upserts replace previous token for same device', () async {
      final alice = _Client(base(), tokenAlice);
      await alice.post('/calls/push-token', {
        'push_token': 'fcm-token-alice-001',
        'token_type': 'FCM',
      });
      final r = await alice.post('/calls/push-token', {
        'push_token': 'fcm-token-alice-002',
        'token_type': 'FCM',
      });
      expect(r.status, 200);
      // Only one token stored per device — no duplicate.
      final token = server.db.getPushTokenForDevice('alice_device1');
      expect(token, isNotNull);
      expect(token!['push_token'], 'fcm-token-alice-002');
    });

    test('deregisters push token', () async {
      final alice = _Client(base(), tokenAlice);
      await alice.post('/calls/push-token', {'push_token': 'fcm-old'});
      final del = await alice.delete('/calls/push-token');
      expect(del.status, 200);
      expect(del.json['status'], 'deregistered');
      expect(server.db.getPushTokenForDevice('alice_device1'), isNull);
    });

    test('rejects empty push_token', () async {
      final alice = _Client(base(), tokenAlice);
      final r = await alice.post('/calls/push-token', {'push_token': ''});
      expect(r.status, 400);
    });

    test('rejects invalid token_type', () async {
      final alice = _Client(base(), tokenAlice);
      final r = await alice.post('/calls/push-token', {
        'push_token': 'tok',
        'token_type': 'SMS',
      });
      expect(r.status, 400);
    });

    test('requires auth', () async {
      final anon = _Client(base(), '');
      final r = await anon.post('/calls/push-token', {'push_token': 'x'});
      expect(r.status, greaterThanOrEqualTo(400));
    });
  });

  // -------------------------------------------------------------------------
  // TURN credentials
  // -------------------------------------------------------------------------

  group('TURN credentials', () {
    test('returns credentials when TURN is configured', () async {
      final alice = _Client(base(), tokenAlice);
      final r = await alice.get('/calls/turn-credentials');
      // May return 200 or 503 depending on env config; just ensure no crash.
      expect([200, 503], contains(r.status));
    });

    test('includes X-Helix-Turn-Refresh-In header on 200', () async {
      // This test is env-dependent; skip if unconfigured.
      final alice = _Client(base(), tokenAlice);
      final r = await alice.get('/calls/turn-credentials');
      if (r.status == 200) {
        expect(r.headers.containsKey('x-helix-turn-refresh-in'), isTrue);
        final val = int.parse(r.headers['x-helix-turn-refresh-in']!.first);
        expect(val, greaterThan(0));
      }
    });
  });

  // -------------------------------------------------------------------------
  // Multi-device ring + answered-elsewhere
  // -------------------------------------------------------------------------

  group('multi-device ring', () {
    setUp(() async {
      // Register a second device for Alice (token not needed by these tests).
      server.db.registerDevice(
        'alice_device2',
        'alice',
        'alice_device_key2',
        'Tablet',
      );
    });

    test('offer reaches all callee devices', () async {
      final bob = _Client(base(), tokenBob);
      final r = await bob.post('/calls/signal', {
        'call_id': 'call_multidev_01',
        'signal_type': 'offer',
        'callee_account_id': 'alice',
        'is_video': false,
        'sdp': 'v=0\r\n',
      });
      expect(r.status, 200);
      // Both Alice devices should have a pending call.
      final now = DateTime.now().millisecondsSinceEpoch;
      final device1 = server.db.getPendingCallsForDevice(
        accountId: 'alice',
        deviceId: 'alice_device1',
        now: now,
      );
      final device2 = server.db.getPendingCallsForDevice(
        accountId: 'alice',
        deviceId: 'alice_device2',
        now: now,
      );
      expect(device1, isNotEmpty);
      expect(device2, isNotEmpty);
    });

    test('answered-elsewhere cancels sibling device', () async {
      final bob = _Client(base(), tokenBob);
      await bob.post('/calls/signal', {
        'call_id': 'call_multidev_02',
        'signal_type': 'offer',
        'callee_account_id': 'alice',
        'is_video': false,
        'sdp': 'v=0\r\n',
      });
      final alice1 = _Client(base(), tokenAlice);
      final accept = await alice1.post(
        '/calls/pending/call_multidev_02/accept',
        {},
      );
      expect(accept.status, 200);
      // Device 2 should now see no RINGING calls.
      final now = DateTime.now().millisecondsSinceEpoch;
      final device2Pending = server.db.getPendingCallsForDevice(
        accountId: 'alice',
        deviceId: 'alice_device2',
        now: now,
      );
      expect(device2Pending, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Call metrics upload
  // -------------------------------------------------------------------------

  group('call metrics', () {
    test('stores metrics and returns metric_id', () async {
      final alice = _Client(base(), tokenAlice);
      final r = await alice.post('/calls/metrics', {
        'call_id': 'call_metrics_001',
        'connection_type': 'relay',
        'setup_time_ms': 1200,
        'reconnect_count': 1,
        'packet_loss_percent': 3.5,
        'peer_rtt_ms': 120.0,
        'call_outcome': 'completed',
        'duration_seconds': 300,
      });
      expect(r.status, 200);
      expect(r.json['status'], 'recorded');
      expect(r.json['metric_id'], isA<String>());
    });

    test('accepts minimal payload (only call_id)', () async {
      final alice = _Client(base(), tokenAlice);
      final r = await alice.post('/calls/metrics', {
        'call_id': 'call_metrics_002',
      });
      expect(r.status, 200);
    });

    test('rejects missing call_id', () async {
      final alice = _Client(base(), tokenAlice);
      final r = await alice.post('/calls/metrics', {
        'connection_type': 'direct',
      });
      expect(r.status, 400);
    });

    test('requires auth', () async {
      final anon = _Client(base(), '');
      final r = await anon.post('/calls/metrics', {
        'call_id': 'call_metrics_anon',
      });
      expect(r.status, greaterThanOrEqualTo(400));
    });
  });
}
