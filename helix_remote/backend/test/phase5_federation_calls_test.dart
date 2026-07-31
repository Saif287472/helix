import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:helix_remote_backend/src/server_identity.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'test_registration.dart';

/// Milestone 5.1 — Federation: Calls.
///
/// Two servers: A (alice) and B (bob). Unlike Milestone 4's groups, a call
/// has no home-server-authority concept -- each server just relays signals
/// to whichever domain the *other* party lives on (the bilateral
/// message-proxy pattern from Milestone 3), so a two-server harness is
/// sufficient (mirrors phase3_federation_test.dart's shape, not phase4's
/// three-server one).
void main() {
  late FederationDirectoryServer directory;
  late BackendServer serverA;
  late BackendServer serverB;
  late ServerIdentity identityA;
  late ServerIdentity identityB;
  late int directoryPort;
  late int portA;
  late int portB;

  setUp(() async {
    directory = FederationDirectoryServer();
    await directory.start('127.0.0.1', 0);
    directoryPort = directory.httpServer!.port;
    final directoryUrl = 'http://127.0.0.1:$directoryPort';

    serverA = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_for_phase5_server_a',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
      federationDomain: 'a.test',
      federationDirectoryUrl: directoryUrl,
      turnSecret: 'turn_secret_a',
      turnUrl: 'turn:turn.a.test:3478',
    );
    identityA = await ServerIdentity.loadOrCreate(serverA.db);
    serverA.serverIdentity = identityA;
    await serverA.start('127.0.0.1', 0);
    portA = serverA.httpServer!.port;

    serverB = BackendServer.create(
      sqliteDb: sqlite3.openInMemory(),
      jwtSecret: 'test_jwt_secret_for_phase5_server_b',
      rateLimitMaxTokens: 1000,
      rateLimitRefillRate: 1000,
      federationDomain: 'b.test',
      federationDirectoryUrl: directoryUrl,
      turnSecret: 'turn_secret_b',
      turnUrl: 'turn:turn.b.test:3478',
    );
    identityB = await ServerIdentity.loadOrCreate(serverB.db);
    serverB.serverIdentity = identityB;
    await serverB.start('127.0.0.1', 0);
    portB = serverB.httpServer!.port;

    await _registerServer(
      identity: identityA,
      domain: 'a.test',
      address: 'http://127.0.0.1:$portA',
      directoryUrl: 'http://127.0.0.1:$directoryPort',
      users: const ['alice@a.test'],
      db: serverA.db,
    );
    await _registerServer(
      identity: identityB,
      domain: 'b.test',
      address: 'http://127.0.0.1:$portB',
      directoryUrl: 'http://127.0.0.1:$directoryPort',
      users: const ['bob@b.test'],
      db: serverB.db,
    );
  });

  tearDown(() async {
    await serverA.stop();
    await serverB.stop();
    await directory.stop();
  });

  test(
    'federated offer/answer/ice/end round-trips across two servers',
    () async {
      final client = HttpClient();
      try {
        final alice = await _register(client, portA, serverA.db, 'alice');
        final bob = await _register(client, portB, serverB.db, 'bob');

        // Establish a federated DIRECT conversation -- this is the trust
        // gate a federated call reuses instead of local `contacts`.
        final create = await _postJson(
          client,
          portA,
          '/api/v1/messages/conversations/create',
          {
            'conversation_id': 'conv_call_1',
            'type': 'DIRECT',
            'members': ['alice', 'bob@b.test'],
          },
          token: alice.token,
        );
        expect(create.statusCode, equals(200), reason: create.body);

        final aliceWs = await WebSocket.connect(
          'ws://127.0.0.1:$portA/api/v1/ws',
          headers: {'Authorization': 'Bearer ${alice.token}'},
        );
        final aliceEvents = StreamIterator<dynamic>(aliceWs);
        final bobWs = await WebSocket.connect(
          'ws://127.0.0.1:$portB/api/v1/ws',
          headers: {'Authorization': 'Bearer ${bob.token}'},
        );
        final bobEvents = StreamIterator<dynamic>(bobWs);
        await Future<void>.delayed(const Duration(milliseconds: 80));

        // Alice offers a call to bob@b.test.
        final offerRes = await _postJson(
          client,
          portA,
          '/api/v1/calls/signal',
          {
            'target_account_id': 'bob@b.test',
            'payload': {
              'signal_type': 'offer',
              'call_id': 'call_fed_1',
              'sdp': 'offer_sdp_stub',
            },
          },
          token: alice.token,
        );
        expect(offerRes.statusCode, equals(200), reason: offerRes.body);

        final offerEvent = await _nextWsJson(bobEvents);
        expect(offerEvent['type'], equals('call_signal'));
        final offerPayload = offerEvent['payload'] as Map<String, dynamic>;
        expect(offerPayload['signal_type'], equals('offer'));
        expect(offerPayload['call_id'], equals('call_fed_1'));
        expect(offerPayload['caller_account_id'], equals('alice@a.test'));
        expect(offerPayload['callee_account_id'], equals('bob'));
        expect(offerPayload['target_device_id'], equals('bob_device'));

        // Bob answers -- must reach alice's original device on server A.
        final answerRes = await _postJson(
          client,
          portB,
          '/api/v1/calls/signal',
          {
            'payload': {
              'signal_type': 'answer',
              'call_id': 'call_fed_1',
              'sdp': 'answer_sdp_stub',
            },
          },
          token: bob.token,
        );
        expect(answerRes.statusCode, equals(200), reason: answerRes.body);

        final answerEvent = await _nextWsJson(aliceEvents);
        expect(answerEvent['type'], equals('call_signal'));
        final answerPayload = answerEvent['payload'] as Map<String, dynamic>;
        expect(answerPayload['signal_type'], equals('answer'));
        expect(answerPayload['call_id'], equals('call_fed_1'));
        expect(answerPayload['target_device_id'], equals('alice_device'));

        // ICE candidate from alice, now routed to bob's specific device.
        final iceRes = await _postJson(client, portA, '/api/v1/calls/signal', {
          'payload': {
            'signal_type': 'ice',
            'call_id': 'call_fed_1',
            'candidate': 'candidate:1 1 UDP 1 1.1.1.1 1 typ host',
          },
        }, token: alice.token);
        expect(iceRes.statusCode, equals(200), reason: iceRes.body);
        final iceEvent = await _nextWsJson(bobEvents);
        expect(
          (iceEvent['payload'] as Map<String, dynamic>)['signal_type'],
          equals('ice'),
        );

        // Bob ends the call; alice's session must be marked terminal too.
        final endRes = await _postJson(client, portB, '/api/v1/calls/signal', {
          'payload': {'signal_type': 'end', 'call_id': 'call_fed_1'},
        }, token: bob.token);
        expect(endRes.statusCode, equals(200), reason: endRes.body);
        final endEvent = await _nextWsJson(aliceEvents);
        expect(
          (endEvent['payload'] as Map<String, dynamic>)['signal_type'],
          equals('end'),
        );
        final sessionOnA = serverA.db.getPendingCall('call_fed_1');
        expect(sessionOnA!['status'], equals('END'));
        final sessionOnB = serverB.db.getPendingCall('call_fed_1');
        expect(sessionOnB!['status'], equals('END'));

        await aliceEvents.cancel();
        await bobEvents.cancel();
        await aliceWs.close();
        await bobWs.close();
      } finally {
        client.close(force: true);
      }
    },
  );

  test(
    'a call to an account with no shared federated conversation is rejected',
    () async {
      final client = HttpClient();
      try {
        final alice = await _register(client, portA, serverA.db, 'alice');
        await _register(client, portB, serverB.db, 'bob');

        final offerRes = await _postJson(
          client,
          portA,
          '/api/v1/calls/signal',
          {
            'target_account_id': 'bob@b.test',
            'payload': {'signal_type': 'offer', 'call_id': 'call_fed_reject'},
          },
          token: alice.token,
        );
        final body = jsonDecode(offerRes.body) as Map<String, dynamic>;
        expect(body['status'], equals('rejected'));
      } finally {
        client.close(force: true);
      }
    },
  );

  test(
    'a federated callee can decline, and the caller session is marked declined',
    () async {
      final client = HttpClient();
      try {
        final alice = await _register(client, portA, serverA.db, 'alice');
        final bob = await _register(client, portB, serverB.db, 'bob');
        await _postJson(
          client,
          portA,
          '/api/v1/messages/conversations/create',
          {
            'conversation_id': 'conv_call_2',
            'type': 'DIRECT',
            'members': ['alice', 'bob@b.test'],
          },
          token: alice.token,
        );

        final aliceWs = await WebSocket.connect(
          'ws://127.0.0.1:$portA/api/v1/ws',
          headers: {'Authorization': 'Bearer ${alice.token}'},
        );
        final aliceEvents = StreamIterator<dynamic>(aliceWs);
        await Future<void>.delayed(const Duration(milliseconds: 80));

        final offerRes = await _postJson(
          client,
          portA,
          '/api/v1/calls/signal',
          {
            'target_account_id': 'bob@b.test',
            'payload': {'signal_type': 'offer', 'call_id': 'call_fed_decline'},
          },
          token: alice.token,
        );
        expect(offerRes.statusCode, equals(200), reason: offerRes.body);

        final declineRes = await _postJson(
          client,
          portB,
          '/api/v1/calls/pending/call_fed_decline/decline',
          {},
          token: bob.token,
        );
        expect(declineRes.statusCode, equals(200), reason: declineRes.body);

        final declineEvent = await _nextWsJson(aliceEvents);
        expect(
          (declineEvent['payload'] as Map<String, dynamic>)['signal_type'],
          equals('decline'),
        );
        // The caller-side session status is derived from the relayed
        // signal_type ('decline'.toUpperCase()); this differs from
        // _handleDeclinePending's hardcoded 'DECLINED' on the callee side
        // -- a pre-existing inconsistency in the local-only code, not
        // something Milestone 5 introduces.
        final sessionOnA = serverA.db.getPendingCall('call_fed_decline');
        expect(sessionOnA!['status'], equals('DECLINE'));

        await aliceEvents.cancel();
        await aliceWs.close();
      } finally {
        client.close(force: true);
      }
    },
  );

  test(
    'each party fetches TURN credentials independently from its own home server',
    () async {
      final client = HttpClient();
      try {
        final alice = await _register(client, portA, serverA.db, 'alice');
        final bob = await _register(client, portB, serverB.db, 'bob');

        final aliceTurn = await _getJson(
          client,
          portA,
          '/api/v1/calls/turn-credentials',
          token: alice.token,
        );
        final bobTurn = await _getJson(
          client,
          portB,
          '/api/v1/calls/turn-credentials',
          token: bob.token,
        );
        expect(aliceTurn.statusCode, equals(200));
        expect(bobTurn.statusCode, equals(200));
        final aliceBody = jsonDecode(aliceTurn.body) as Map<String, dynamic>;
        final bobBody = jsonDecode(bobTurn.body) as Map<String, dynamic>;
        expect(aliceBody['url'], equals('turn:turn.a.test:3478'));
        expect(bobBody['url'], equals('turn:turn.b.test:3478'));
        expect(aliceBody['credential'], isNot(equals(bobBody['credential'])));
      } finally {
        client.close(force: true);
      }
    },
  );
}

class _RegisteredUser {
  const _RegisteredUser(this.token);
  final String token;
}

Future<_RegisteredUser> _register(
  HttpClient client,
  int port,
  BackendDatabase db,
  String accountId,
) async {
  final material = await registerTestAccount(
    client: client,
    host: '127.0.0.1',
    port: port,
    db: db,
    accountId: accountId,
    username: '${accountId}_user',
    deviceId: '${accountId}_device',
    deviceName: '$accountId Phone',
  );
  final login = await loginTestAccount(
    client: client,
    host: '127.0.0.1',
    port: port,
    accountId: accountId,
    deviceId: '${accountId}_device',
    deviceSigningKeyPair: material.deviceSigningKeyPair,
  );
  return _RegisteredUser(login['token'] as String);
}

Future<void> _registerServer({
  required ServerIdentity identity,
  required String domain,
  required String address,
  required String directoryUrl,
  required List<String> users,
  required BackendDatabase db,
}) async {
  final client = FederationClient(
    db: db,
    identity: identity,
    directoryUrl: directoryUrl,
  );
  await client.registerDirectory(
    domain: domain,
    address: address,
    users: users,
  );
}

Future<Map<String, dynamic>> _nextWsJson(
  StreamIterator<dynamic> iterator,
) async {
  final hasNext = await iterator.moveNext();
  if (!hasNext) throw StateError('WebSocket closed before next message');
  return jsonDecode(iterator.current as String) as Map<String, dynamic>;
}

Future<_Response> _getJson(
  HttpClient client,
  int port,
  String path, {
  String? token,
}) async {
  final request = await client.get('127.0.0.1', port, path);
  if (token != null) {
    request.headers.set('Authorization', 'Bearer $token');
  }
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  return _Response(response.statusCode, body);
}

Future<_Response> _postJson(
  HttpClient client,
  int port,
  String path,
  Map<String, dynamic> data, {
  String? token,
}) async {
  final request = await client.post('127.0.0.1', port, path);
  request.headers.contentType = ContentType.json;
  if (token != null) {
    request.headers.set('Authorization', 'Bearer $token');
  }
  request.write(jsonEncode(data));
  final response = await request.close();
  final body = await utf8.decoder.bind(response).join();
  return _Response(response.statusCode, body);
}

class _Response {
  const _Response(this.statusCode, this.body);

  final int statusCode;
  final String body;
}
