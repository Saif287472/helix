import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:helix_remote_backend/helix_remote_backend.dart';

/// End-to-end enforcement of a call's IP-privacy policy on the signaling
/// path.
///
/// `call_media_policy_test.dart` covers the primitive in isolation - what
/// counts as a relay candidate, what `fromWire` does with rubbish. These
/// tests cover the part that was missing until the primitive was wired in:
/// that a real signal, arriving over the real endpoint, actually gets
/// filtered before it reaches the far side.
class TestHttpClient {
  TestHttpClient(this.baseUrl, this.token);
  final String baseUrl;
  final String token;
  final _inner = HttpClient();

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

Future<Map<String, dynamic>> nextWsJson(
  StreamIterator<dynamic> iterator,
) async {
  final hasNext = await iterator.moveNext();
  if (!hasNext) throw StateError('WebSocket closed before next message');
  return jsonDecode(iterator.current as String) as Map<String, dynamic>;
}

/// A private host candidate and a relayed one in the same blob, which is
/// what an honest client under `direct_and_relay` sends and what a client
/// ignoring `relay_only` would send anyway.
const String hostCandidate =
    'candidate:1 1 udp 2130706431 192.168.1.10 54321 typ host';
const String relayCandidate =
    'candidate:2 1 udp 16777215 203.0.113.9 3478 typ relay';

const String mixedSdp =
    'v=0\r\n'
    'o=- 0 0 IN IP4 127.0.0.1\r\n'
    's=-\r\n'
    'a=$hostCandidate\r\n'
    'a=$relayCandidate\r\n'
    'a=end-of-candidates\r\n';

void main() {
  late BackendServer server;
  late int port;
  late String tokenA;
  late String tokenB;
  WebSocket? calleeSocket;
  StreamIterator<dynamic>? calleeQueue;

  setUp(() async {
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_media_policy',
      rateLimitMaxTokens: 400.0,
      rateLimitRefillRate: 100.0,
      turnSecret: 'test_turn_secret',
      turnUrl: 'turn:turn.test.example:3478',
    );

    server.db.createAccount('user1', 'alice', 'alice_key');
    server.db.registerDevice('device1', 'user1', 'device1_key', 'Alice Phone');
    server.db.createAccount('user2', 'bob', 'bob_key');
    server.db.registerDevice('device2', 'user2', 'device2_key', 'Bob Phone');
    server.db.addContact('user1', 'user2', null);
    server.db.addContact('user2', 'user1', null);

    tokenA = server.jwt.generateToken({
      'account_id': 'user1',
      'device_id': 'device1',
    }, const Duration(hours: 1));
    tokenB = server.jwt.generateToken({
      'account_id': 'user2',
      'device_id': 'device2',
    }, const Duration(hours: 1));

    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;
  });

  tearDown(() async {
    await calleeQueue?.cancel();
    await calleeSocket?.close();
    calleeQueue = null;
    calleeSocket = null;
    await server.stop();
  });

  /// Connects the callee so offers have somewhere to be delivered.
  Future<StreamIterator<dynamic>> connectCallee() async {
    final ws = await WebSocket.connect(
      'ws://127.0.0.1:$port/api/v1/ws',
      headers: {'Authorization': 'Bearer $tokenB'},
    );
    calleeSocket = ws;
    final queue = StreamIterator<dynamic>(ws);
    calleeQueue = queue;
    await Future<void>.delayed(const Duration(milliseconds: 60));
    return queue;
  }

  test('an offer that declares no policy is enforced as relay-only', () async {
    final queue = await connectCallee();
    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);

    final res = await client.post('/api/v1/calls/signal', {
      'target_account_id': 'user2',
      'payload': {
        'signal_type': 'offer',
        'call_id': 'call_default',
        'sdp': mixedSdp,
      },
    });
    expect(res.status, equals(200));

    final payload =
        (await nextWsJson(queue))['payload'] as Map<String, dynamic>;
    final sdp = payload['sdp'] as String;
    expect(
      sdp,
      isNot(contains('typ host')),
      reason: 'a client that declares nothing must not leak a host candidate',
    );
    expect(sdp, contains('typ relay'));
    expect(payload['ip_privacy'], equals('relay_only'));

    expect(
      server.db.getPendingCall('call_default')!['ip_privacy'],
      equals('relay_only'),
    );
  });

  test('an offer declaring direct_and_relay keeps host candidates', () async {
    final queue = await connectCallee();
    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);

    final res = await client.post('/api/v1/calls/signal', {
      'target_account_id': 'user2',
      'payload': {
        'signal_type': 'offer',
        'call_id': 'call_direct',
        'sdp': mixedSdp,
        'ip_privacy': 'direct_and_relay',
      },
    });
    expect(res.status, equals(200));

    final payload =
        (await nextWsJson(queue))['payload'] as Map<String, dynamic>;
    final sdp = payload['sdp'] as String;
    expect(sdp, contains('typ host'));
    expect(sdp, contains('typ relay'));
    expect(payload['ip_privacy'], equals('direct_and_relay'));

    expect(
      server.db.getPendingCall('call_direct')!['ip_privacy'],
      equals('direct_and_relay'),
    );
  });

  test('an unrecognised policy value resolves to relay-only', () async {
    final queue = await connectCallee();
    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);

    final res = await client.post('/api/v1/calls/signal', {
      'target_account_id': 'user2',
      'payload': {
        'signal_type': 'offer',
        'call_id': 'call_unknown',
        'sdp': mixedSdp,
        'ip_privacy': 'wide_open_please',
      },
    });
    // Accepted, not rejected: an unknown policy is a newer client, not a
    // malformed frame. It just does not get the benefit of the doubt.
    expect(res.status, equals(200));

    final payload =
        (await nextWsJson(queue))['payload'] as Map<String, dynamic>;
    expect(payload['sdp'], isNot(contains('typ host')));
    expect(
      server.db.getPendingCall('call_unknown')!['ip_privacy'],
      equals('relay_only'),
    );
  });

  test('a non-relay trickle candidate is dropped, not relayed', () async {
    final queue = await connectCallee();
    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);

    await client.post('/api/v1/calls/signal', {
      'target_account_id': 'user2',
      'payload': {'signal_type': 'offer', 'call_id': 'call_ice', 'sdp': 'v=0'},
    });
    expect(
      (await nextWsJson(queue))['type'],
      equals('call_signal'),
      reason: 'the offer should arrive before anything else',
    );

    final dropped = await client.post('/api/v1/calls/signal', {
      'payload': {
        'signal_type': 'ice',
        'call_id': 'call_ice',
        'candidate': hostCandidate,
      },
    });
    expect(dropped.status, equals(200));
    expect(
      (jsonDecode(dropped.body) as Map<String, dynamic>)['status'],
      equals('dropped'),
    );

    // Prove the drop by sending a legitimate candidate straight after: if
    // the host one had been relayed it would arrive first, and this
    // assertion would see it instead.
    final allowed = await client.post('/api/v1/calls/signal', {
      'payload': {
        'signal_type': 'ice',
        'call_id': 'call_ice',
        'candidate': relayCandidate,
      },
    });
    expect(allowed.status, equals(200));

    final payload =
        (await nextWsJson(queue))['payload'] as Map<String, dynamic>;
    expect(payload['signal_type'], equals('ice'));
    expect(payload['candidate'], equals(relayCandidate));
  });

  test('the answer tightens the policy for the rest of the call', () async {
    final queue = await connectCallee();
    final callerClient = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final calleeClient = TestHttpClient('http://127.0.0.1:$port', tokenB);

    await callerClient.post('/api/v1/calls/signal', {
      'target_account_id': 'user2',
      'payload': {
        'signal_type': 'offer',
        'call_id': 'call_tighten',
        'sdp': 'v=0',
        'ip_privacy': 'direct_and_relay',
      },
    });
    expect(
      (await nextWsJson(queue))['type'],
      equals('call_signal'),
      reason: 'the offer should arrive before anything else',
    );

    final answer = await calleeClient.post('/api/v1/calls/signal', {
      'payload': {
        'signal_type': 'answer',
        'call_id': 'call_tighten',
        'sdp': mixedSdp,
        'ip_privacy': 'relay_only',
      },
    });
    expect(answer.status, equals(200));

    expect(
      server.db.getPendingCall('call_tighten')!['ip_privacy'],
      equals('relay_only'),
      reason: 'the stricter of the two sides wins',
    );

    // And it binds the caller too, on frames sent after the negotiation:
    // the caller asked for direct_and_relay and no longer gets it.
    final dropped = await callerClient.post('/api/v1/calls/signal', {
      'payload': {
        'signal_type': 'ice',
        'call_id': 'call_tighten',
        'candidate': hostCandidate,
      },
    });
    expect(
      (jsonDecode(dropped.body) as Map<String, dynamic>)['status'],
      equals('dropped'),
      reason: 'the caller asked for direct but the callee did not agree',
    );
  });

  test('the answer cannot loosen a relay-only call', () async {
    final queue = await connectCallee();
    final callerClient = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final calleeClient = TestHttpClient('http://127.0.0.1:$port', tokenB);

    await callerClient.post('/api/v1/calls/signal', {
      'target_account_id': 'user2',
      'payload': {
        'signal_type': 'offer',
        'call_id': 'call_loosen',
        'sdp': 'v=0',
        'ip_privacy': 'relay_only',
      },
    });
    expect(
      (await nextWsJson(queue))['type'],
      equals('call_signal'),
      reason: 'the offer should arrive before anything else',
    );

    await calleeClient.post('/api/v1/calls/signal', {
      'payload': {
        'signal_type': 'answer',
        'call_id': 'call_loosen',
        'sdp': 'v=0',
        'ip_privacy': 'direct_and_relay',
      },
    });

    expect(
      server.db.getPendingCall('call_loosen')!['ip_privacy'],
      equals('relay_only'),
      reason: 'a callee must not be able to talk a caller out of relay-only',
    );
  });
}
