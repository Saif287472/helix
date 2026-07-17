// Batch 4 — SQLite concurrent transaction safety.
//
// The audit roadmap worried that `BackendOperationalRepository.runInTransaction`
// could let concurrent REST calls interleave SQL into the same SAVEPOINT,
// since Dart's single-threaded event loop can preempt a suspended `async`
// function at any `await`. Auditing the actual database layer shows this
// class of bug cannot occur here: every transaction block across
// backend/lib/src/database/ (including runInTransaction itself) is fully
// synchronous — zero `await` between BEGIN/SAVEPOINT and COMMIT/RELEASE —
// so the synchronous, FFI-based sqlite3 driver never yields control back to
// the event loop mid-transaction. This test locks that invariant in: firing
// many concurrent `POST /messages/send` requests must never corrupt or
// interleave the per-device event sequence.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'test_registration.dart';

void main() {
  late BackendServer server;
  late int port;
  late HttpClient client;

  setUp(() async {
    server = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_for_message_send_concurrency',
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

  Future<String> login(
    String accountId,
    String deviceId,
    crypto.SimpleKeyPair deviceSigningKeyPair,
  ) async {
    final result = await loginTestAccount(
      client: client,
      host: '127.0.0.1',
      port: port,
      accountId: accountId,
      deviceId: deviceId,
      deviceSigningKeyPair: deviceSigningKeyPair,
    );
    return result['token'] as String;
  }

  Future<HttpClientResponse> postJson(
    String path,
    Map<String, dynamic> body, {
    required String token,
  }) async {
    final request = await client.post('127.0.0.1', port, path);
    request.headers.contentType = ContentType.json;
    request.headers.set('Authorization', 'Bearer $token');
    request.write(jsonEncode(body));
    return request.close();
  }

  test(
    '50 concurrent message sends produce a gap-free, duplicate-free '
    "recipient device_sequence and don't corrupt the messages table",
    () async {
      final aliceMaterial = await registerTestAccount(
        client: client,
        host: '127.0.0.1',
        port: port,
        accountId: 'conc_alice',
        username: 'conc_alice_user',
        deviceId: 'conc_alice_device',
        deviceName: 'Alice Phone',
      );
      await registerTestAccount(
        client: client,
        host: '127.0.0.1',
        port: port,
        accountId: 'conc_bob',
        username: 'conc_bob_user',
        deviceId: 'conc_bob_device',
        deviceName: 'Bob Phone',
      );
      final aliceToken = await login(
        'conc_alice',
        'conc_alice_device',
        aliceMaterial.deviceSigningKeyPair,
      );

      final createConv = await postJson(
        '/api/v1/messages/conversations/create',
        {
          'conversation_id': 'conv_concurrency',
          'type': 'DIRECT',
          'members': ['conc_alice', 'conc_bob'],
        },
        token: aliceToken,
      );
      expect(createConv.statusCode, equals(200));
      await createConv.drain<void>();

      const messageCount = 50;
      final responses = await Future.wait([
        for (var i = 0; i < messageCount; i++)
          postJson('/api/v1/messages/send', {
            'message_id': 'conc_msg_$i',
            'conversation_id': 'conv_concurrency',
            'envelopes': [
              {
                'recipient_device_id': 'conc_bob_device',
                'ciphertext': 'ciphertext_$i',
              },
            ],
          }, token: aliceToken),
      ]);

      for (final resp in responses) {
        expect(resp.statusCode, equals(200));
        await resp.drain<void>();
      }

      // No transaction corruption: every message_id was persisted exactly
      // once, and the sender never observed its own idempotency guard firing
      // (which would indicate a torn/interleaved write).
      for (var i = 0; i < messageCount; i++) {
        expect(server.db.getMessage('conc_msg_$i'), isNotNull);
      }

      final bobEvents = server.db.getDeviceEvents('conc_bob_device', 0);
      expect(bobEvents, hasLength(messageCount));
      final sequences =
          bobEvents.map((row) => row['device_sequence'] as int).toList()
            ..sort();
      // Strictly sequential 1..50 — any gap or duplicate would mean two
      // concurrent transactions interleaved their sequence allocation.
      expect(sequences, equals(List.generate(messageCount, (i) => i + 1)));

      expect(server.db.quickCheckOk(), isTrue);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
