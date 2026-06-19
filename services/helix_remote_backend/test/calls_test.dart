import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:helix_remote_backend/helix_remote_backend.dart';

// Minimal HTTP test client
class TestHttpClient {
  TestHttpClient(this.baseUrl, this.token);
  final String baseUrl;
  final String token;
  final _inner = HttpClient();

  Future<({int status, String body})> get(String path) async {
    final req = await _inner.getUrl(Uri.parse('$baseUrl$path'));
    if (token.isNotEmpty) req.headers.set('Authorization', 'Bearer $token');
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return (status: res.statusCode, body: body);
  }

  Future<({int status, String body})> post(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final req = await _inner.postUrl(Uri.parse('$baseUrl$path'));
    if (token.isNotEmpty) req.headers.set('Authorization', 'Bearer $token');
    req.headers.set('Content-Type', 'application/json');
    req.write(jsonEncode(payload));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return (status: res.statusCode, body: body);
  }
}

void main() {
  late BackendServer server;
  late int port;
  late String tokenA;

  setUp(() async {
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_calls_phase15',
      rateLimitMaxTokens: 200.0,
      rateLimitRefillRate: 50.0,
      turnSecret: 'test_turn_secret',
      turnUrl: 'turn:turn.test.example:3478',
    );

    server.db.createAccount('user1', 'alice', 'alice_key');
    server.db.registerDevice('device1', 'user1', 'device1_key', 'Alice Phone');
    server.db.createAccount('user2', 'bob', 'bob_key');
    server.db.registerDevice('device2', 'user2', 'device2_key', 'Bob Phone');

    tokenA = server.jwt.generateToken(
      {'account_id': 'user1', 'device_id': 'device1'},
      const Duration(hours: 1),
    );

    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;
  });

  tearDown(() async {
    await server.stop();
  });

  // P15-003 / P15-004: TURN credential issuance
  test('TURN credentials are issued with HMAC-SHA1 and expire in 1 hour',
      () async {
    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final res = await client.get('/api/v1/calls/turn-credentials');
    expect(res.status, equals(200));

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    expect(body['url'], equals('turn:turn.test.example:3478'));
    expect(body['username'], isA<String>());
    expect(body['credential'], isA<String>());
    expect(body['expires_at'], isA<int>());

    // Verify HMAC-SHA1 credential matches expected value.
    final username = body['username'] as String;
    final credential = body['credential'] as String;
    final hmac = Hmac(sha1, utf8.encode('test_turn_secret'));
    final expected = base64Encode(hmac.convert(utf8.encode(username)).bytes);
    expect(credential, equals(expected));

    // expires_at should be approximately now + 3600 seconds.
    final expiresAt = body['expires_at'] as int;
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    expect(expiresAt, greaterThanOrEqualTo(nowSeconds + 3590));
    expect(expiresAt, lessThanOrEqualTo(nowSeconds + 3610));
  });

  test('TURN credential issuance is logged for quota tracking', () async {
    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    await client.get('/api/v1/calls/turn-credentials');
    expect(server.db.getTurnCredentialCountLastHour('user1'), equals(1));

    await client.get('/api/v1/calls/turn-credentials');
    expect(server.db.getTurnCredentialCountLastHour('user1'), equals(2));
  });

  // P15-005: TURN abuse and bandwidth controls
  test('TURN credential quota is enforced at 10 per hour', () async {
    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    for (var i = 0; i < 10; i++) {
      final r = await client.get('/api/v1/calls/turn-credentials');
      expect(r.status, equals(200), reason: 'Request $i should succeed');
    }
    final rejected = await client.get('/api/v1/calls/turn-credentials');
    expect(rejected.status, equals(429));
    expect(
      (jsonDecode(rejected.body) as Map<String, dynamic>)['error'],
      contains('quota'),
    );
  });

  test('TURN quota applies per-account, not globally', () async {
    final tokenB = server.jwt.generateToken(
      {'account_id': 'user2', 'device_id': 'device2'},
      const Duration(hours: 1),
    );
    final clientA = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final clientB = TestHttpClient('http://127.0.0.1:$port', tokenB);

    for (var i = 0; i < 10; i++) {
      await clientA.get('/api/v1/calls/turn-credentials');
    }
    expect(
      (await clientA.get('/api/v1/calls/turn-credentials')).status,
      equals(429),
    );

    // user2 has its own quota — must still succeed.
    expect(
      (await clientB.get('/api/v1/calls/turn-credentials')).status,
      equals(200),
    );
  });

  // P15-002: Call signal relay
  test('signal to online device is relayed via WebSocket', () async {
    final tokenB = server.jwt.generateToken(
      {'account_id': 'user2', 'device_id': 'device2'},
      const Duration(hours: 1),
    );
    final wsUri = Uri.parse(
      'ws://127.0.0.1:$port/api/v1/ws?token=$tokenB',
    );
    final ws = WebSocketChannel.connect(wsUri);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final res = await client.post('/api/v1/calls/signal', {
      'target_device_id': 'device2',
      'payload': {'signal_type': 'offer', 'call_id': 'call_abc', 'sdp': 'stub'},
    });

    expect(res.status, equals(200));
    expect(
      (jsonDecode(res.body) as Map<String, dynamic>)['delivered'],
      isTrue,
    );

    await ws.sink.close();
  });

  // P15-007: No call content in push notification for offline devices
  test('signal to offline device enqueues push notification with no call content',
      () async {
    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final res = await client.post('/api/v1/calls/signal', {
      'target_device_id': 'device2',
      'payload': {
        'signal_type': 'offer',
        'call_id': 'call_xyz',
        'sdp': 'secret_sdp',
      },
    });

    expect(res.status, equals(200));
    expect(
      (jsonDecode(res.body) as Map<String, dynamic>)['delivered'],
      isFalse,
    );

    final pending = server.db.getPendingOutbox();
    final notifs =
        pending.where((e) => e['type'] == 'PUSH_NOTIFICATION').toList();
    expect(notifs, isNotEmpty);

    final payload =
        jsonDecode(notifs.first['payload'] as String) as Map<String, dynamic>;
    // No call content must appear in the push notification.
    expect(payload.containsKey('sdp'), isFalse);
    expect(payload.containsKey('call_id'), isFalse);
    expect(payload['notification_type'], equals('incoming_call'));
  });

  test('signal endpoint rejects missing target_device_id', () async {
    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final res = await client.post('/api/v1/calls/signal', {
      'payload': {'signal_type': 'offer'},
    });
    expect(res.status, equals(400));
  });

  test('unauthenticated TURN credential request is rejected with 401', () async {
    final client = TestHttpClient('http://127.0.0.1:$port', '');
    final res = await client.get('/api/v1/calls/turn-credentials');
    expect(res.status, equals(401));
  });
}
