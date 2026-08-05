// Batch 3 — WebSocket offline-event replay backpressure.
//
// Verifies the ack-paced replay path in
// WebSocketRelay._replayOfflineEvents: a device reconnecting with a large
// backlog receives every event, in order, and the server genuinely waits on
// the client's `replay_ack` rather than blasting the whole backlog through
// the sink unthrottled — including *within* a page, which is where the
// pacing used to be missing entirely.

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

  /// Registers a device, seeds it [events] queued device events and opens a
  /// WebSocket that replays from scratch.
  Future<WebSocket> connectWithBacklog({
    required String suffix,
    required int events,
  }) async {
    final material = await registerTestAccount(
      client: client,
      host: '127.0.0.1',
      port: port,
      db: server.db,
      accountId: 'replay_acc_$suffix',
      username: 'replay_user_$suffix',
      deviceId: 'replay_device_$suffix',
      deviceName: 'Replay Phone',
    );
    final loginResult = await loginTestAccount(
      client: client,
      host: '127.0.0.1',
      port: port,
      accountId: 'replay_acc_$suffix',
      deviceId: 'replay_device_$suffix',
      deviceSigningKeyPair: material.deviceSigningKeyPair,
    );
    final token = loginResult['token'] as String;

    for (var i = 0; i < events; i++) {
      server.db.writeDeviceEvent(
        eventId: 'evt_${suffix}_$i',
        recipientDeviceId: 'replay_device_$suffix',
        eventType: 'chat_message',
        payload: jsonEncode({'i': i}),
      );
    }

    return WebSocket.connect(
      'ws://127.0.0.1:$port/api/v1/ws?since=0',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  test('reconnect with a large backlog replays every event, in order, once '
      'the client acknowledges what it has received', () async {
    const totalEvents = 120;
    final ws = await connectWithBacklog(suffix: 'ordered', events: totalEvents);

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
    // With prompt acks the window reopens immediately rather than waiting
    // out the 5-second no-ack timeout fallback.
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 4)));

    await sub.cancel();
    await ws.close();
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('a client that stops acking stops receiving: no more than one window '
      'of events is ever outstanding', () async {
    // The regression this pins down: pacing used to apply only *between*
    // 50-event pages, so a client that acked nothing still had all 50 events
    // of the first page pushed at it back-to-back. The window is applied per
    // event now, so a silent client sees exactly `replayWindow` and no more
    // until it acks.
    const totalEvents = 120;
    final ws = await connectWithBacklog(suffix: 'window', events: totalEvents);

    final received = <int>[];
    var acking = false;
    final all = Completer<void>();
    final sub = ws.listen((data) {
      final map = jsonDecode(data as String) as Map<String, dynamic>;
      final seq = map['server_sequence'] as int?;
      if (seq == null) return;
      received.add(seq);
      if (acking) {
        ws.add(jsonEncode({'type': 'replay_ack', 'server_sequence': seq}));
      }
      if (received.length == totalEvents && !all.isCompleted) all.complete();
    });

    // Well inside the 5-second no-ack timeout, so this measures the window
    // rather than the fallback.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(
      received,
      hasLength(WebSocketRelay.replayWindow),
      reason:
          'a silent client should be held at the window, not fed a whole page',
    );

    // Draining the window releases the rest.
    acking = true;
    for (final seq in List<int>.of(received)) {
      ws.add(jsonEncode({'type': 'replay_ack', 'server_sequence': seq}));
    }
    await all.future.timeout(const Duration(seconds: 10));
    expect(received, equals(List.generate(totalEvents, (i) => i + 1)));

    await sub.cancel();
    await ws.close();
  }, timeout: const Timeout(Duration(seconds: 30)));

  test(
    'a client that never acks still receives the whole backlog',
    () async {
      // Older app builds do not send `replay_ack` at all. They must not be
      // held at the window forever, and must not pay the ack timeout once per
      // window either — the first timeout latches the fallback for the rest of
      // the replay.
      const totalEvents = 120;
      final ws = await connectWithBacklog(
        suffix: 'silent',
        events: totalEvents,
      );

      final received = <int>[];
      final done = Completer<void>();
      final sub = ws.listen((data) {
        final map = jsonDecode(data as String) as Map<String, dynamic>;
        final seq = map['server_sequence'] as int?;
        if (seq == null) return;
        received.add(seq);
        if (received.length == totalEvents && !done.isCompleted) {
          done.complete();
        }
      });

      final stopwatch = Stopwatch()..start();
      await done.future.timeout(const Duration(seconds: 20));
      stopwatch.stop();

      expect(received, equals(List.generate(totalEvents, (i) => i + 1)));
      // One timeout, not one per window: five windows at 5 s each would be 25 s.
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 12)));

      await sub.cancel();
      await ws.close();
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
