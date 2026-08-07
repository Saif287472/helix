// P1-1 / H2 — "permessage-deflate negotiation mismatch" as a cause of the
// recurring WebSocket close with code 1002.
//
// HELIX_REMEDIATION_PLAN.md ranks this second behind the flood hypothesis and
// calls it "cheap to test": the client uses WebSocket.connect, which offers
// compression by default, while the server uses shelf_web_socket, and an
// RSV-bit or window-bits disagreement produces exactly 1002.
//
// The hypothesis does not survive contact with the code, and this suite is
// what pins that conclusion so nobody re-runs the experiment:
//
//   1. shelf_web_socket writes the 101 response by hand and emits only
//      Upgrade, Connection, Sec-WebSocket-Accept and (optionally)
//      Sec-WebSocket-Protocol. It never emits Sec-WebSocket-Extensions, which
//      per RFC 7692 declines every extension the client offered.
//   2. It then calls WebSocket.fromUpgradedSocket without a `compression:`
//      argument. That factory forwards to _WebSocketImpl._fromSocket, whose
//      optional `deflate` positional it does not pass — so the server's
//      deflate helper is null no matter what CompressionOptions says, and
//      outgoing frames never set RSV1.
//   3. dart:io's negotiateClientCompression returns null unless the response
//      carries Sec-WebSocket-Extensions: permessage-deflate, so the client's
//      deflate helper is null too.
//
// Both ends therefore agree on "no compression" — the one state that cannot
// produce an RSV mismatch. Disabling compression on the client, which the
// plan lists as diagnostic step 2, would be a no-op.
//
// What these tests protect is the *agreement*, not the absence of
// compression. A shelf_web_socket upgrade that starts echoing
// Sec-WebSocket-Extensions, or a switch to serving the upgrade through
// HttpServer (whose _negotiateCompression path does honour CompressionOptions),
// would reopen H2. That is the regression this catches.

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
      jwtSecret: 'test_jwt_secret_for_websocket_compression',
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

  Future<String> authenticate(String suffix) async {
    final material = await registerTestAccount(
      client: client,
      host: '127.0.0.1',
      port: port,
      db: server.db,
      accountId: 'deflate_acc_$suffix',
      username: 'deflate_user_$suffix',
      deviceId: 'deflate_device_$suffix',
      deviceName: 'Deflate Phone',
    );
    final login = await loginTestAccount(
      client: client,
      host: '127.0.0.1',
      port: port,
      accountId: 'deflate_acc_$suffix',
      deviceId: 'deflate_device_$suffix',
      deviceSigningKeyPair: material.deviceSigningKeyPair,
    );
    return login['token'] as String;
  }

  test('the server declines permessage-deflate, so no RSV mismatch is '
      'possible (P1-1 H2)', () async {
    final token = await authenticate('default');

    // WebSocket.connect offers permessage-deflate by default — the exact
    // client behaviour the hypothesis is about.
    final ws = await WebSocket.connect(
      'ws://127.0.0.1:$port/api/v1/ws?since=0',
      headers: {'Authorization': 'Bearer $token'},
    );
    addTearDown(() => ws.close());

    expect(
      ws.extensions,
      isEmpty,
      reason:
          'a negotiated extension here would mean the two ends can '
          'disagree about RSV1, which is what H2 proposes',
    );

    await ws.close();
    expect(
      ws.closeCode,
      isNot(equals(1002)),
      reason: '1002 is the protocol error the field logs show',
    );
  });

  test('an explicit compression request is still declined', () async {
    final token = await authenticate('explicit');

    // Belt and braces: even a client that asks loudly, with non-default
    // window bits, must not come away believing deflate was agreed.
    final ws = await WebSocket.connect(
      'ws://127.0.0.1:$port/api/v1/ws?since=0',
      headers: {'Authorization': 'Bearer $token'},
      compression: const CompressionOptions(
        clientMaxWindowBits: 12,
        serverMaxWindowBits: 12,
      ),
    );
    addTearDown(() => ws.close());

    expect(ws.extensions, isEmpty);
  });

  test('frames survive a round trip uncompressed', () async {
    final token = await authenticate('roundtrip');
    final ws = await WebSocket.connect(
      'ws://127.0.0.1:$port/api/v1/ws?since=0',
      headers: {'Authorization': 'Bearer $token'},
    );
    addTearDown(() => ws.close());

    // A ping/pong exercises the full encode-write-read-decode path in both
    // directions. If either side were framing with RSV1 set while the other
    // was not expecting it, the transformer would raise and close with 1002
    // rather than answering.
    final pong = Completer<Map<String, dynamic>>();
    final subscription = ws.listen((data) {
      final decoded = jsonDecode(data as String) as Map<String, dynamic>;
      if (decoded['type'] == 'pong' && !pong.isCompleted) {
        pong.complete(decoded);
      }
    });
    addTearDown(subscription.cancel);

    ws.add(jsonEncode({'type': 'ping'}));

    await expectLater(
      pong.future.timeout(const Duration(seconds: 5)),
      completes,
    );
    expect(ws.closeCode, isNull, reason: 'the socket must still be open');
  });
}
