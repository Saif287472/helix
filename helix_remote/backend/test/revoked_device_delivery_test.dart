// A revoked device keeps its row in `devices` (the admin console shows what
// was removed) but loses its prekeys, so no sender can ever encrypt to it.
// Sending must therefore not demand an envelope for it - otherwise every
// account that ever signed in on a new phone becomes unreachable.

import 'dart:convert';
import 'dart:io';

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
      jwtSecret: 'test_jwt_secret_for_revoked_device_delivery',
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

  test('a message needs no envelope for a revoked recipient device', () async {
    final alice = await registerTestAccount(
      client: client,
      host: '127.0.0.1',
      port: port,
      db: server.db,
      accountId: 'rev_alice',
      username: 'rev_alice_user',
      deviceId: 'rev_alice_device',
      deviceName: 'Alice Phone',
    );
    await registerTestAccount(
      client: client,
      host: '127.0.0.1',
      port: port,
      db: server.db,
      accountId: 'rev_bob',
      username: 'rev_bob_user',
      deviceId: 'rev_bob_old',
      deviceName: 'Bob Old Phone',
    );
    // Bob moves to a new phone; the old one is revoked.
    server.db.registerDevice(
      'rev_bob_new',
      'rev_bob',
      'new_signing_key',
      'new_agreement_key',
      'Bob New Phone',
    );
    server.db.revokeDevice('rev_bob', 'rev_bob_old');

    final aliceToken =
        (await loginTestAccount(
              client: client,
              host: '127.0.0.1',
              port: port,
              accountId: 'rev_alice',
              deviceId: 'rev_alice_device',
              deviceSigningKeyPair: alice.deviceSigningKeyPair,
            ))['token']
            as String;

    final create = await postJson('/api/v1/messages/conversations/create', {
      'conversation_id': 'conv_revoked',
      'type': 'DIRECT',
      'members': ['rev_alice', 'rev_bob'],
    }, token: aliceToken);
    expect(create.statusCode, 200);
    await create.drain<void>();

    final send = await postJson('/api/v1/messages/send', {
      'message_id': 'msg_to_new_phone',
      'conversation_id': 'conv_revoked',
      'envelopes': [
        {'recipient_device_id': 'rev_bob_new', 'ciphertext': 'ct'},
      ],
    }, token: aliceToken);
    final body = await send.transform(utf8.decoder).join();
    expect(send.statusCode, 200, reason: body);

    // A stale sender that still encrypts to the signed-out phone is not
    // failed for it: that envelope is dropped.
    final toRevoked = await postJson('/api/v1/messages/send', {
      'message_id': 'msg_to_old_phone',
      'conversation_id': 'conv_revoked',
      'envelopes': [
        {'recipient_device_id': 'rev_bob_new', 'ciphertext': 'ct'},
        {'recipient_device_id': 'rev_bob_old', 'ciphertext': 'ct'},
      ],
    }, token: aliceToken);
    await toRevoked.drain<void>();
    expect(toRevoked.statusCode, 200);
    expect(
      server.db.getMessageCountForDevice('rev_bob_old'),
      0,
      reason: 'nothing is stored for a signed-out device',
    );
  });
}
