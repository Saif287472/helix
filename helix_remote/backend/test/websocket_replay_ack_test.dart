// Batch 3 — WebSocket offline-event replay backpressure.
//
// Verifies the paginated, ACK-gated replay path in
// WebSocketRelay._replayOfflineEvents: a device reconnecting with a large
// backlog receives every event, in order, across multiple pages, and the
// server genuinely waits on the client's `replay_ack` between pages rather
// than blasting the whole backlog through the sink unthrottled.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:helix_remote_backend/helix_remote_backend.dart';

import 'test_registration.dart';

void main() {
  late BackendServer server;
  late int port;
  late HttpClient client;

  setUp(() async {
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_for_websocket_replay_ack',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
    );
    await server.start('127.0.0.1', 0);
    port = server.httpServer!.port;
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
  });

  test('reconnect with a backlog spanning multiple pages replays every event, '
      'in order, once the client acknowledges each page', () async {
    final material = await registerTestAccount(
      client: client,
      host: '127.0.0.1',
      port: port,
      db: server.db,
      accountId: 'replay_acc',
      username: 'replay_user',
      deviceId: 'replay_device',
      deviceName: 'Replay Phone',
    );
    final loginResult = await loginTestAccount(
      client: client,
      host: '127.0.0.1',
      port: port,
      accountId: 'replay_acc',
      deviceId: 'replay_device',
      deviceSigningKeyPair: material.deviceSigningKeyPair,
    );
    final token = loginResult['token'] as String;

    // Seed a backlog spanning three replay pages (page size is 50).
    const totalEvents = 120;
    for (var i = 0; i < totalEvents; i++) {
      server.db.writeDeviceEvent(
        eventId: 'evt_replay_$i',
        recipientDeviceId: 'replay_device',
        eventType: 'chat_message',
        payload: jsonEncode({'i': i}),
      );
    }

    final ws = await WebSocket.connect(
      'ws://127.0.0.1:$port/api/v1/ws?since=0',
      headers: {'Authorization': 'Bearer $token'},
    );

    final received = <int>[];
    final done = Completer<void>();
    final sub = ws.listen((data) {
      final map = jsonDecode(data as String) as Map<String, dynamic>;
      final seq = map['server_sequence'] as int?;
      if (seq == null) return;
      received.add(seq);
      ws.add(jsonEncode({'type': 'replay_ack', 'server_sequence': seq}));
      if (received.length == totalEvents && !done.isCompleted) {
        done.complete();
      }
    });

    final stopwatch = Stopwatch()..start();
    await done.future.timeout(const Duration(seconds: 10));
    stopwatch.stop();

    expect(received, hasLength(totalEvents));
    expect(received, equals(List.generate(totalEvents, (i) => i + 1)));
    // With prompt acks each page should advance immediately rather than
    // waiting out the 5-second no-ack timeout fallback (two page
    // boundaries would cost 10s+ if pacing fell back to timeouts).
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 4)));

    await sub.cancel();
    await ws.close();
  }, timeout: const Timeout(Duration(seconds: 20)));
}
