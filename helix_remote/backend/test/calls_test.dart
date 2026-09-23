import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
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

  Future<({int status, String body})> put(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final req = await _inner.putUrl(Uri.parse('$baseUrl$path'));
    if (token.isNotEmpty) req.headers.set('Authorization', 'Bearer $token');
    req.headers.set('Content-Type', 'application/json');
    req.write(jsonEncode(payload));
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    return (status: res.statusCode, body: body);
  }
}

class RecordingPushProvider implements PushProvider {
  final deliveries = <({String token, Map<String, dynamic> data})>[];

  @override
  bool get isConfigured => true;

  @override
  Future<void> deliver({
    required String token,
    required Map<String, dynamic> data,
    String? tokenType,
  }) async {
    deliveries.add((token: token, data: Map.of(data)));
  }
}

Future<Map<String, dynamic>> nextWsJson(
  StreamIterator<dynamic> iterator,
) async {
  final hasNext = await iterator.moveNext();
  if (!hasNext) throw StateError('WebSocket closed before next message');
  return jsonDecode(iterator.current as String) as Map<String, dynamic>;
}

void main() {
  late BackendServer server;
  late int port;
  late String tokenA;
  late RecordingPushProvider pushProvider;
  // Kept so a test can age a row directly. Reaching past the repository is
  // deliberate: simulating "this call has outlived its deadline" is a
  // storage fact, and inventing a production setter to express it would put
  // a method in the repository that only tests would ever call.
  late Database rawSqlite;

  setUp(() async {
    rawSqlite = sqlite3.openInMemory();
    pushProvider = RecordingPushProvider();
    server = BackendServer.create(
      sqliteDb: rawSqlite,
      jwtSecret: 'test_jwt_secret_calls_phase15',
      rateLimitMaxTokens: 200.0,
      rateLimitRefillRate: 50.0,
      turnSecret: 'test_turn_secret',
      turnUrl: 'turn:turn.test.example:3478',
      pushProvider: pushProvider,
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

    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;
  });

  tearDown(() async {
    await server.stop();
  });

  // P15-003 / P15-004: TURN credential issuance
  test(
    'TURN credentials are issued with HMAC-SHA1 and expire in 1 hour',
    () async {
      final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
      final res = await client.get('/api/v1/calls/turn-credentials');
      expect(res.status, equals(200));

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['url'], equals('turn:turn.test.example:3478'));
      expect(body['urls'], equals(['turn:turn.test.example:3478']));
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
    },
  );

  test('TURN credential issuance is logged for quota tracking', () async {
    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    await client.get('/api/v1/calls/turn-credentials');
    expect(server.db.getTurnCredentialCountLastHour('user1'), equals(1));

    await client.get('/api/v1/calls/turn-credentials');
    expect(server.db.getTurnCredentialCountLastHour('user1'), equals(2));
  });

  test('TURN credential request rejects missing TURN configuration', () async {
    final unconfigured = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_calls_no_turn',
      rateLimitMaxTokens: 200.0,
      rateLimitRefillRate: 50.0,
    );
    unconfigured.db.createAccount('user1', 'alice', 'alice_key');
    unconfigured.db.registerDevice(
      'device1',
      'user1',
      'device1_key',
      'Alice Phone',
    );
    final token = unconfigured.jwt.generateToken({
      'account_id': 'user1',
      'device_id': 'device1',
    }, const Duration(hours: 1));
    await unconfigured.start('127.0.0.1', 0);
    try {
      final client = TestHttpClient(
        'http://127.0.0.1:${unconfigured.httpServer!.port}',
        token,
      );
      final res = await client.get('/api/v1/calls/turn-credentials');
      expect(res.status, equals(503));
      expect(res.body, contains('TURN is not configured'));
    } finally {
      await unconfigured.stop();
    }
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
    final tokenB = server.jwt.generateToken({
      'account_id': 'user2',
      'device_id': 'device2',
    }, const Duration(hours: 1));
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
    final tokenB = server.jwt.generateToken({
      'account_id': 'user2',
      'device_id': 'device2',
    }, const Duration(hours: 1));
    final wsUri = Uri.parse('ws://127.0.0.1:$port/api/v1/ws');
    final ws = await WebSocket.connect(
      wsUri.toString(),
      headers: {'Authorization': 'Bearer $tokenB'},
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final res = await client.post('/api/v1/calls/signal', {
      'target_account_id': 'user2',
      'payload': {'signal_type': 'offer', 'call_id': 'call_abc', 'sdp': 'stub'},
    });

    expect(res.status, equals(200));
    expect((jsonDecode(res.body) as Map<String, dynamic>)['delivered'], isTrue);

    await ws.close();
  });

  test('offer routing injects authenticated caller identity', () async {
    final tokenB = server.jwt.generateToken({
      'account_id': 'user2',
      'device_id': 'device2',
    }, const Duration(hours: 1));
    final ws = await WebSocket.connect(
      'ws://127.0.0.1:$port/api/v1/ws',
      headers: {'Authorization': 'Bearer $tokenB'},
    );
    final queue = StreamIterator<dynamic>(ws);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final res = await client.post('/api/v1/calls/signal', {
      'target_account_id': 'user2',
      'payload': {
        'signal_type': 'offer',
        'call_id': 'call_identity',
        'caller_account_id': 'spoofed-account',
        'caller_device_id': 'spoofed-device',
        'sdp': 'stub',
      },
    });
    expect(res.status, equals(200));

    final event = await nextWsJson(queue);
    expect(event['type'], equals('call_signal'));
    final payload = event['payload'] as Map<String, dynamic>;
    expect(payload['caller_account_id'], equals('user1'));
    expect(payload['caller_device_id'], equals('device1'));
    expect(payload['callee_account_id'], equals('user2'));
    expect(payload['target_device_id'], equals('device2'));
    expect(payload['signal_type'], equals('offer'));

    await queue.cancel();
    await ws.close();
  });

  test('non-contact call is rejected', () async {
    server.db.createAccount('user3', 'charlie', 'charlie_key');
    server.db.registerDevice(
      'device4',
      'user3',
      'device4_key',
      'Charlie Phone',
    );

    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final res = await client.post('/api/v1/calls/signal', {
      'target_account_id': 'user3',
      'payload': {'signal_type': 'offer', 'call_id': 'call_blocked'},
    });
    expect(res.status, equals(400));
    expect(res.body, contains('accepted contact'));
  });

  test(
    'authenticated WebSocket call signal returns ack and routes offer',
    () async {
      final tokenB = server.jwt.generateToken({
        'account_id': 'user2',
        'device_id': 'device2',
      }, const Duration(hours: 1));
      final wsA = await WebSocket.connect(
        'ws://127.0.0.1:$port/api/v1/ws',
        headers: {'Authorization': 'Bearer $tokenA'},
      );
      final wsB = await WebSocket.connect(
        'ws://127.0.0.1:$port/api/v1/ws',
        headers: {'Authorization': 'Bearer $tokenB'},
      );
      final queueA = StreamIterator<dynamic>(wsA);
      final queueB = StreamIterator<dynamic>(wsB);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      wsA.add(
        jsonEncode({
          'type': 'call_signal',
          'request_id': 'req-ws-offer',
          'payload': {
            'signal_type': 'offer',
            'call_id': 'call_ws_offer',
            'callee_account_id': 'user2',
            'sdp': 'stub',
          },
        }),
      );

      final ack = await nextWsJson(queueA);
      expect(ack['type'], equals('call_signal_ack'));
      expect(ack['request_id'], equals('req-ws-offer'));
      expect(ack['status'], equals('delivered'));

      final offer = await nextWsJson(queueB);
      expect(offer['type'], equals('call_signal'));
      expect(
        (offer['payload'] as Map<String, dynamic>)['call_id'],
        'call_ws_offer',
      );

      await queueA.cancel();
      await queueB.cancel();
      await wsA.close();
      await wsB.close();
    },
  );

  test('multi-device ringing uses first-answer-wins', () async {
    server.db.registerDevice('device3', 'user2', 'device3_key', 'Bob Tablet');
    final tokenB1 = server.jwt.generateToken({
      'account_id': 'user2',
      'device_id': 'device2',
    }, const Duration(hours: 1));
    final tokenB2 = server.jwt.generateToken({
      'account_id': 'user2',
      'device_id': 'device3',
    }, const Duration(hours: 1));
    final wsB1 = await WebSocket.connect(
      'ws://127.0.0.1:$port/api/v1/ws',
      headers: {'Authorization': 'Bearer $tokenB1'},
    );
    final wsB2 = await WebSocket.connect(
      'ws://127.0.0.1:$port/api/v1/ws',
      headers: {'Authorization': 'Bearer $tokenB2'},
    );
    final queueB1 = StreamIterator<dynamic>(wsB1);
    final queueB2 = StreamIterator<dynamic>(wsB2);
    await Future<void>.delayed(const Duration(milliseconds: 60));

    final clientA = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final offerRes = await clientA.post('/api/v1/calls/signal', {
      'target_account_id': 'user2',
      'payload': {
        'signal_type': 'offer',
        'call_id': 'call_multi',
        'sdp': 'stub',
      },
    });
    expect(offerRes.status, equals(200));
    final offerBody = jsonDecode(offerRes.body) as Map<String, dynamic>;
    expect(offerBody['delivered_count'], equals(2));

    expect((await nextWsJson(queueB1))['type'], equals('call_signal'));
    expect((await nextWsJson(queueB2))['type'], equals('call_signal'));

    final clientB1 = TestHttpClient('http://127.0.0.1:$port', tokenB1);
    final answerRes = await clientB1.post('/api/v1/calls/signal', {
      'payload': {
        'signal_type': 'answer',
        'call_id': 'call_multi',
        'sdp': 'answer-sdp',
      },
    });
    expect(answerRes.status, equals(200));

    final sibling = await nextWsJson(queueB2);
    final siblingPayload = sibling['payload'] as Map<String, dynamic>;
    expect(siblingPayload['signal_type'], equals('answered_elsewhere'));

    final clientB2 = TestHttpClient('http://127.0.0.1:$port', tokenB2);
    final lateAnswer = await clientB2.post('/api/v1/calls/signal', {
      'payload': {
        'signal_type': 'answer',
        'call_id': 'call_multi',
        'sdp': 'late-answer-sdp',
      },
    });
    expect(lateAnswer.status, equals(409));

    await queueB1.cancel();
    await queueB2.cancel();
    await wsB1.close();
    await wsB2.close();
  });

  test('duplicate call signal request IDs are deduplicated', () async {
    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final body = {
      'request_id': 'req-duplicate-offer',
      'target_account_id': 'user2',
      'payload': {'signal_type': 'offer', 'call_id': 'call_duplicate'},
    };

    final first = await client.post('/api/v1/calls/signal', body);
    expect(first.status, equals(200));

    final second = await client.post('/api/v1/calls/signal', body);
    expect(second.status, equals(200));
    expect(
      (jsonDecode(second.body) as Map<String, dynamic>)['status'],
      equals('duplicate'),
    );
  });

  test('an answered call can still hang up past the ring timeout', () async {
    // From a device log, on a call that ran 77 seconds:
    //   [CALL_SIGNAL] send begin end cid=41717041
    //   [CALL_SIGNAL] end WS rejected status=expired reason=call expired
    //
    // The 45s deadline is a *ring* timeout. Applied to an answered call it
    // meant hanging up was refused, so the other end was never told and sat
    // there until its own ICE gave up.
    final tokenB = server.jwt.generateToken({
      'account_id': 'user2',
      'device_id': 'device2',
    }, const Duration(hours: 1));
    final clientA = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final clientB = TestHttpClient('http://127.0.0.1:$port', tokenB);

    await clientA.post('/api/v1/calls/signal', {
      'target_account_id': 'user2',
      'payload': {
        'signal_type': 'offer',
        'call_id': 'call_long',
        'sdp': 'offer-sdp',
      },
    });
    final answer = await clientB.post('/api/v1/calls/signal', {
      'payload': {
        'signal_type': 'answer',
        'call_id': 'call_long',
        'sdp': 'answer-sdp',
      },
    });
    expect(answer.status, equals(200));

    // Push the deadline into the past, as a call outlasting the ring
    // timeout does. The row stays ANSWERED — only ringing calls expire.
    rawSqlite.execute(
      'UPDATE pending_calls SET expires_at = 1 WHERE call_id = ?;',
      ['call_long'],
    );

    final end = await clientA.post('/api/v1/calls/signal', {
      'payload': {'signal_type': 'end', 'call_id': 'call_long'},
    });
    expect(end.status, equals(200));
    expect(
      (jsonDecode(end.body) as Map<String, dynamic>)['status'],
      isNot(equals('expired')),
      reason: 'a live call must be able to tell the other side it ended',
    );
    expect(server.db.getPendingCall('call_long')!['status'], equals('END'));
  });

  test('expired and out-of-order call signals do not revive a call', () async {
    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final earlyAnswer = await client.post('/api/v1/calls/signal', {
      'payload': {
        'signal_type': 'answer',
        'call_id': 'call_never_created',
        'sdp': 'answer-sdp',
      },
    });
    expect(earlyAnswer.status, equals(410));

    final offer = await client.post('/api/v1/calls/signal', {
      'target_account_id': 'user2',
      'payload': {'signal_type': 'offer', 'call_id': 'call_expire'},
    });
    expect(offer.status, equals(200));

    final expire = await client.post(
      '/api/v1/calls/pending/call_expire/expire',
      {},
    );
    expect(expire.status, equals(200));

    final tokenB = server.jwt.generateToken({
      'account_id': 'user2',
      'device_id': 'device2',
    }, const Duration(hours: 1));
    final clientB = TestHttpClient('http://127.0.0.1:$port', tokenB);
    final lateIce = await clientB.post('/api/v1/calls/signal', {
      'payload': {
        'signal_type': 'ice',
        'call_id': 'call_expire',
        'candidate': 'candidate:1 1 UDP 1 203.0.113.1 5000 typ relay',
      },
    });
    expect(lateIce.status, equals(410));
  });

  test('no active callee devices is reported explicitly', () async {
    server.db.revokeDevice('user2', 'device2');

    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final res = await client.post('/api/v1/calls/signal', {
      'target_account_id': 'user2',
      'payload': {'signal_type': 'offer', 'call_id': 'call_no_devices'},
    });

    expect(res.status, equals(409));
    expect(
      (jsonDecode(res.body) as Map<String, dynamic>)['status'],
      equals('no_active_devices'),
    );
  });

  // P15-007: No call content in push notification for offline devices
  test(
    'signal to offline device enqueues push notification with no call content',
    () async {
      final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
      final res = await client.post('/api/v1/calls/signal', {
        'target_account_id': 'user2',
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
      final notifs = pending
          .where((e) => e['type'] == 'PUSH_NOTIFICATION')
          .toList();
      expect(notifs, isNotEmpty);

      final payload =
          jsonDecode(notifs.first['payload'] as String) as Map<String, dynamic>;
      // No SDP or ICE content must appear in the push notification. The call id
      // is the minimal routing hint needed for killed-app pending-call recovery.
      expect(payload.containsKey('sdp'), isFalse);
      expect(payload['call_id'], equals('call_xyz'));
      expect(payload['notification_type'], equals('incoming_call'));
    },
  );

  test('offer sends push wake even when the WebSocket is connected', () async {
    server.db.upsertPushToken(
      tokenId: 'token_device2',
      accountId: 'user2',
      deviceId: 'device2',
      pushToken: 'fcm_device2',
      tokenType: 'FCM',
      now: DateTime.now().millisecondsSinceEpoch,
    );
    final tokenB = server.jwt.generateToken({
      'account_id': 'user2',
      'device_id': 'device2',
    }, const Duration(hours: 1));
    final socket = await WebSocket.connect(
      'ws://127.0.0.1:$port/api/v1/ws',
      headers: {'Authorization': 'Bearer $tokenB'},
    );
    try {
      final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
      final res = await client.post('/api/v1/calls/signal', {
        'target_account_id': 'user2',
        'payload': {'signal_type': 'offer', 'call_id': 'call_socket_wake'},
      });

      expect(res.status, equals(200));
      await Future<void>.delayed(Duration.zero);
      expect(pushProvider.deliveries, hasLength(1));
      expect(pushProvider.deliveries.single.token, equals('fcm_device2'));
      expect(
        pushProvider.deliveries.single.data['call_id'],
        equals('call_socket_wake'),
      );
      expect(server.db.getPendingOutbox(), isEmpty);
    } finally {
      await socket.close();
    }
  });

  test('signal endpoint rejects missing call target', () async {
    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final res = await client.post('/api/v1/calls/signal', {
      'payload': {'signal_type': 'offer'},
    });
    expect(res.status, equals(400));
  });

  test('P25 malformed ICE candidate is rejected before routing', () async {
    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final offer = await client.post('/api/v1/calls/signal', {
      'target_account_id': 'user2',
      'payload': {'signal_type': 'offer', 'call_id': 'call_bad_ice'},
    });
    expect(offer.status, equals(200));

    final tokenB = server.jwt.generateToken({
      'account_id': 'user2',
      'device_id': 'device2',
    }, const Duration(hours: 1));
    final clientB = TestHttpClient('http://127.0.0.1:$port', tokenB);
    final badIce = await clientB.post('/api/v1/calls/signal', {
      'payload': {
        'signal_type': 'ice',
        'call_id': 'call_bad_ice',
        'candidate': 'not-a-candidate',
      },
    });
    expect(badIce.status, equals(400));
    expect(badIce.body, contains('invalid candidate'));
  });

  test('P25 concurrent call limit rejects a second active call', () async {
    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final first = await client.post('/api/v1/calls/signal', {
      'target_account_id': 'user2',
      'payload': {'signal_type': 'offer', 'call_id': 'call_one'},
    });
    expect(first.status, equals(200));

    final second = await client.post('/api/v1/calls/signal', {
      'target_account_id': 'user2',
      'payload': {'signal_type': 'offer', 'call_id': 'call_two'},
    });
    expect(second.status, equals(400));
    expect(second.body, contains('concurrent call limit'));
  });

  test(
    'unauthenticated TURN credential request is rejected with 401',
    () async {
      final client = TestHttpClient('http://127.0.0.1:$port', '');
      final res = await client.get('/api/v1/calls/turn-credentials');
      expect(res.status, equals(401));
    },
  );

  // Push-token endpoint
  test('device can register and update push token', () async {
    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    final res = await client.put('/api/v1/accounts/devices/push-token', {
      'push_token': 'fcm_valid_token_abc123',
    });
    expect(res.status, equals(200));
    expect(
      (jsonDecode(res.body) as Map<String, dynamic>)['status'],
      equals('updated'),
    );
    expect(
      server.db.getDevicePushToken('device1'),
      equals('fcm_valid_token_abc123'),
    );
  });

  test(
    'call push-token registration also feeds message push delivery',
    () async {
      final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
      final res = await client.post('/api/v1/calls/push-token', {
        'push_token': 'fcm_call_registration_token',
      });
      expect(res.status, equals(200));
      expect(
        server.db.getDevicePushToken('device1'),
        equals('fcm_call_registration_token'),
      );
    },
  );

  test('push token endpoint rejects empty token', () async {
    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    expect(
      (await client.put('/api/v1/accounts/devices/push-token', {
        'push_token': '',
      })).status,
      equals(400),
    );
  });

  test('push token endpoint rejects token over 256 chars', () async {
    final client = TestHttpClient('http://127.0.0.1:$port', tokenA);
    expect(
      (await client.put('/api/v1/accounts/devices/push-token', {
        'push_token': 'x' * 257,
      })).status,
      equals(400),
    );
  });

  test('push token endpoint requires authentication', () async {
    final client = TestHttpClient('http://127.0.0.1:$port', '');
    expect(
      (await client.put('/api/v1/accounts/devices/push-token', {
        'push_token': 'tok',
      })).status,
      equals(401),
    );
  });

  // Pending call authorization
  test('wrong account cannot accept a pending call', () async {
    // user1 sends offer to user2
    final clientA = TestHttpClient('http://127.0.0.1:$port', tokenA);
    await clientA.post('/api/v1/calls/signal', {
      'target_account_id': 'user2',
      'payload': {'signal_type': 'offer', 'call_id': 'call_authz_accept'},
    });

    // user1 (caller) tries to accept their own call — not allowed
    final res = await clientA.post(
      '/api/v1/calls/pending/call_authz_accept/accept',
      {},
    );
    expect(res.status, anyOf(equals(403), equals(404)));
  });

  test('wrong account cannot decline a pending call', () async {
    final clientA = TestHttpClient('http://127.0.0.1:$port', tokenA);
    await clientA.post('/api/v1/calls/signal', {
      'target_account_id': 'user2',
      'payload': {'signal_type': 'offer', 'call_id': 'call_authz_decline'},
    });

    // A third account cannot decline the call
    server.db.createAccount('user3', 'carol', 'carol_key');
    server.db.registerDevice('device3', 'user3', 'device3_key', 'Carol Phone');
    final tokenC = server.jwt.generateToken({
      'account_id': 'user3',
      'device_id': 'device3',
    }, const Duration(hours: 1));
    final clientC = TestHttpClient('http://127.0.0.1:$port', tokenC);
    final res = await clientC.post(
      '/api/v1/calls/pending/call_authz_decline/decline',
      {},
    );
    expect(res.status, anyOf(equals(403), equals(404)));
  });

  test('offer_sdp is cleared after call is declined', () async {
    final clientA = TestHttpClient('http://127.0.0.1:$port', tokenA);
    await clientA.post('/api/v1/calls/signal', {
      'target_account_id': 'user2',
      'payload': {
        'signal_type': 'offer',
        'call_id': 'call_sdp_clear',
        'sdp': 'secret_offer_sdp',
      },
    });

    final before = server.db.getPendingCall('call_sdp_clear');
    expect(before, isNotNull);
    expect(before!['offer_sdp'], equals('secret_offer_sdp'));

    final tokenB = server.jwt.generateToken({
      'account_id': 'user2',
      'device_id': 'device2',
    }, const Duration(hours: 1));
    final clientB = TestHttpClient('http://127.0.0.1:$port', tokenB);
    await clientB.post('/api/v1/calls/pending/call_sdp_clear/decline', {});

    final after = server.db.getPendingCall('call_sdp_clear');
    expect(after, isNotNull);
    expect(after!['offer_sdp'], isNull);
  });

  test('pending calls endpoint returns sdp for callee device', () async {
    final clientA = TestHttpClient('http://127.0.0.1:$port', tokenA);
    await clientA.post('/api/v1/calls/signal', {
      'target_account_id': 'user2',
      'payload': {
        'signal_type': 'offer',
        'call_id': 'call_pending_sdp',
        'sdp': 'offer_sdp_value',
      },
    });

    final tokenB = server.jwt.generateToken({
      'account_id': 'user2',
      'device_id': 'device2',
    }, const Duration(hours: 1));
    final clientB = TestHttpClient('http://127.0.0.1:$port', tokenB);
    final res = await clientB.get('/api/v1/calls/pending');
    expect(res.status, equals(200));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final calls = body['calls'] as List<dynamic>;
    expect(calls, isNotEmpty);
    final call = calls.first as Map<String, dynamic>;
    expect(call['call_id'], equals('call_pending_sdp'));
    expect(call['sdp'], equals('offer_sdp_value'));
  });
}
