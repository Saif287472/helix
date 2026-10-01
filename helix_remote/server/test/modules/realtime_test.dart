import 'dart:io';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/helix_remote_server.dart';
import 'package:helix_remote_server/src/kernel/presence.dart';
import 'package:helix_remote_server/src/modules/identity/api.dart';
import 'package:helix_remote_server/src/modules/identity/sms.dart';
import 'package:helix_remote_server/src/modules/messaging/api.dart';
import 'package:helix_remote_server/src/platform/clock.dart';
import 'package:test/test.dart';

import '../support/flows.dart';
import '../support/harness.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';
import '../support/test_platform.dart';
import '../support/test_socket.dart';

void main() {
  group('realtime', skip: databaseTestSkipReason, () {
    late Harness h;
    late TestDevice a1;
    late TestDevice b1;

    setUp(() async {
      h = await Harness.start();
      a1 = await h.registerGlobal(aliceNumber);
      b1 = await h.registerGlobal(bobNumber);
    });

    tearDown(() async => h.stop());

    test(
      'hello, replay of stored envelopes, ack over the socket deletes them',
      () async {
        await send(h, a1, {
          b1.accountId: [b1.id],
        });
        await send(h, a1, {
          b1.accountId: [b1.id],
        });
        final socket = await TestSocket.connect(h.server.baseUri, b1.bearer);
        final hello = await socket.hello();
        expect(hello.lastSeq, 2);
        expect(hello.window, 100);
        final first = await socket.envelope();
        final second = await socket.envelope();
        expect([first.seq, second.seq], [1, 2]);
        socket.ack(2);
        await eventually(
          () async => expect((await mailbox(h, b1)).envelopes, isEmpty),
        );
        socket.ping('n1');
        expect(
          (await socket.next()) as PongFrame,
          isA<PongFrame>().having((p) => p.nonce, 'nonce', 'n1'),
        );
        await socket.close();
      },
    );

    test('live delivery as sends commit', () async {
      final socket = await TestSocket.connect(h.server.baseUri, b1.bearer);
      await socket.hello();
      final id = Uuid.v7();
      await send(h, a1, {
        b1.accountId: [b1.id],
      }, id: id);
      final envelope = await socket.envelope();
      expect(envelope.id, id);
      expect(envelope.from!.device, a1.id);
      await socket.close();
    });

    test('the window caps un-acked envelopes; acks release the rest', () async {
      for (var i = 0; i < 105; i++) {
        await send(h, a1, {
          b1.accountId: [b1.id],
        }, urgent: false);
      }
      final socket = await TestSocket.connect(h.server.baseUri, b1.bearer);
      await socket.hello();
      var last = 0;
      for (var i = 0; i < 100; i++) {
        last = (await socket.envelope()).seq!;
      }
      expect(last, 100);
      expect(await socket.next(), isA<WakeFrame>(), reason: 'window full');
      socket.ack(100);
      final rest = [for (var i = 0; i < 5; i++) (await socket.envelope()).seq];
      expect(rest, [101, 102, 103, 104, 105]);
      await socket.close();
    });

    test(
      'ephemeral sends reach online devices only and are never stored',
      () async {
        final b2 = await secondDevice(h, b1, bobNumber);
        final socket = await TestSocket.connect(h.server.baseUri, b1.bearer);
        await socket.hello();
        // Drain account signals from the second device.
        while (!await socket.silent(const Duration(milliseconds: 300))) {}
        final response = await send(h, a1, {
          b1.accountId: [b1.id, b2.id],
        }, ephemeral: true);
        expect(response.status, 200);
        final envelope = await socket.envelope();
        expect(envelope.isEphemeral, isTrue);
        expect(
          (await mailbox(
            h,
            b2,
          )).envelopes.where((e) => e.kind == EnvelopeKind.message),
          isEmpty,
        );
        await socket.close();
      },
    );

    test('a newer connection supersedes the older one', () async {
      final old = await TestSocket.connect(h.server.baseUri, b1.bearer);
      await old.hello();
      final fresh = await TestSocket.connect(h.server.baseUri, b1.bearer);
      await fresh.hello();
      expect(await old.closed, RealtimeCloseCode.superseded);
      await fresh.close();
    });

    test('revoking a device closes its socket', () async {
      final b2 = await secondDevice(h, b1, bobNumber);
      final socket = await TestSocket.connect(h.server.baseUri, b2.bearer);
      await socket.hello();
      await h.api.call(
        Routes.revokeDevice,
        params: {'device_id': b2.id},
        bearer: b1.bearer,
      );
      expect(await socket.closed, RealtimeCloseCode.deviceRevoked);
    });

    test('upgrades need a valid token and the helix subprotocol', () async {
      await expectLater(
        TestSocket.connect(h.server.baseUri, 'not-a-token'),
        throwsA(isA<WebSocketException>()),
      );
      final wrong = await TestSocket.connect(
        h.server.baseUri,
        b1.bearer,
        protocols: ['chat'],
      );
      expect(await wrong.closed, isNot(1000));
    });

    test('malformed frames close the socket with a protocol error', () async {
      final socket = await TestSocket.connect(h.server.baseUri, b1.bearer);
      await socket.hello();
      socket.sendRaw('{not json');
      expect(await socket.closed, RealtimeCloseCode.protocolError);
    });

    test(
      'a socket on another node receives sends made through this node',
      () async {
        final second = await HelixServer.start(
          await HelixPlatform.open(
            testConfig(
              prefix: h.env.prefix,
              extra: {
                'HELIX_PHONE_PEPPER': testPepper,
                'HELIX_GLOBAL_MODE': 'true',
              },
            ),
            log: Log(sink: MemorySink()),
          ),
          allModules(sms: RecordingSmsProvider()),
        );
        try {
          final socket = await TestSocket.connect(second.baseUri, b1.bearer);
          await socket.hello();
          final id = Uuid.v7();
          await send(h, a1, {
            b1.accountId: [b1.id],
          }, id: id);
          expect(
            (await socket.envelope()).id,
            id,
            reason: 'woken across nodes by the bus',
          );
          final eph = await send(h, a1, {
            b1.accountId: [b1.id],
          }, ephemeral: true);
          expect(eph.status, 200);
          expect((await socket.envelope()).isEphemeral, isTrue);
          await socket.close();
        } finally {
          final dir = second.platform.config.blobs.directory!;
          await second.stop();
          Directory(dir).deleteSync(recursive: true);
        }
      },
    );

    test(
      'sign-out closes the socket on every node; a fresh session stays',
      () async {
        final second = await secondNode(h);
        try {
          final socket = await TestSocket.connect(second.baseUri, b1.bearer);
          await socket.hello();
          final ended = h.env.platform.bus
              .subscribe(IdentityTopics.sessionsEnded)
              .first;
          expect(
            (await h.api.call(Routes.signOut, bearer: b1.bearer)).status,
            204,
          );
          expect(await socket.closed, RealtimeCloseCode.unauthorized);
          final cutOff = await ended;
          expect(cutOff['device'], b1.id);
          expect(cutOff['before'], isA<int>());

          b1.session = await deviceSignIn(h, b1);
          final fresh = await TestSocket.connect(second.baseUri, b1.bearer);
          await fresh.hello();
          // The same cut-off arriving late must not end the new session.
          await h.env.platform.bus.publish(
            IdentityTopics.sessionsEnded,
            cutOff,
          );
          expect(await fresh.silent(), isTrue);
          await fresh.close();
        } finally {
          await stopNode(second);
        }
      },
    );

    test('refresh-token reuse closes the socket (theft response)', () async {
      final first = b1.session!;
      final rotated = Session.fromJson(
        (await h.api.call(
          Routes.refreshSession,
          body: RefreshRequest(refreshToken: first.refreshToken).toJson(),
        )).json,
      );
      final socket = await TestSocket.connect(
        h.server.baseUri,
        rotated.accessToken,
      );
      await socket.hello();
      final reuse = await h.api.call(
        Routes.refreshSession,
        body: RefreshRequest(refreshToken: first.refreshToken).toJson(),
      );
      expect(reuse.status, 401);
      expect(await socket.closed, RealtimeCloseCode.unauthorized);
    });

    test('the route refresh closes sockets of ended sessions', () async {
      final socket = await TestSocket.connect(h.server.baseUri, b1.bearer);
      await socket.hello();
      await h.realtime.refreshConnections();
      expect(await socket.silent(), isTrue, reason: 'still a valid session');
      // A cut-off written without a bus event (another path, a lost event).
      await h.env.platform.db.execute(
        "UPDATE ${h.env.platform.schemas.of('identity')}.devices "
        "SET tokens_valid_after = now() + interval '1 second' WHERE id = @d:uuid",
        {'d': b1.id},
      );
      await h.realtime.refreshConnections();
      expect(await socket.closed, RealtimeCloseCode.unauthorized);
    });

    test(
      'suspension closes live sockets with 4004; reconnecting works',
      () async {
        final socket = await TestSocket.connect(h.server.baseUri, b1.bearer);
        await socket.hello();
        await h.env.platform.db.tx(
          (tx) => h.identity.api.admin.setSuspended(
            tx,
            b1.accountId,
            suspended: true,
          ),
        );
        expect(await socket.closed, RealtimeCloseCode.suspended);
        final again = await TestSocket.connect(h.server.baseUri, b1.bearer);
        await again.hello();
        await h.realtime.refreshConnections();
        again.ping('still-open');
        // Stored envelopes (the suspension signal) come first; a closed
        // socket would make next() throw.
        while (await again.next() is! PongFrame) {}
        await again.close();
      },
    );

    test('a late route refresh never overwrites a newer connection', () async {
      final socket = await TestSocket.connect(h.server.baseUri, b1.bearer);
      await socket.hello();
      final store = h.env.platform.ephemeral;
      final key = Presence.routeKey(b1.id);
      // A newer connection on another node, before its bus event arrives.
      await store.put(key, 'other-node|newer', Presence.routeTtl);
      await h.realtime.refreshConnections();
      expect(await socket.closed, RealtimeCloseCode.superseded);
      expect(
        await store.get(key),
        'other-node|newer',
        reason: 'neither the refresh nor the close touched the newer route',
      );
    });

    test("REST acks return the socket's window credit", () async {
      for (var i = 0; i < 105; i++) {
        await send(h, a1, {
          b1.accountId: [b1.id],
        }, urgent: false);
      }
      final socket = await TestSocket.connect(h.server.baseUri, b1.bearer);
      await socket.hello();
      for (var i = 0; i < 100; i++) {
        await socket.envelope();
      }
      expect(await socket.next(), isA<WakeFrame>());
      final acked = await h.api.call(
        Routes.ackMailbox,
        bearer: b1.bearer,
        body: const AckRequest(seq: 100).toJson(),
      );
      expect(acked.status, 200);
      await h.realtime.refreshConnections();
      final rest = [for (var i = 0; i < 5; i++) (await socket.envelope()).seq];
      expect(rest, [101, 102, 103, 104, 105]);
      await socket.close();
    });

    test('too many upgrades or frames close with 4029', () async {
      for (var i = 0; i < 20; i++) {
        final s = await TestSocket.connect(h.server.baseUri, a1.bearer);
        await s.hello();
        await s.close();
      }
      final limited = await TestSocket.connect(h.server.baseUri, a1.bearer);
      expect(await limited.closed, RealtimeCloseCode.rateLimited);

      final flood = await TestSocket.connect(h.server.baseUri, b1.bearer);
      await flood.hello();
      for (var i = 0; i < 400; i++) {
        flood.ping();
      }
      expect(await flood.closed, RealtimeCloseCode.rateLimited);
    });

    test('a failed delivery closes the socket and drops its route', () async {
      final socket = await TestSocket.connect(h.server.baseUri, b1.bearer);
      await socket.hello();
      final key = Presence.routeKey(b1.id);
      expect(await h.env.platform.ephemeral.get(key), isNotNull);
      final mailbox = '${h.env.platform.schemas.of('messaging')}.mailbox';
      await h.env.platform.db.execute(
        'ALTER TABLE $mailbox RENAME TO mailbox_away',
      );
      try {
        await h.env.platform.bus.publish(MailboxTopics.wake, {
          'd': [b1.id],
        });
        expect(await socket.closed, RealtimeCloseCode.goingAway);
        await eventually(
          () async => expect(await h.env.platform.ephemeral.get(key), isNull),
        );
      } finally {
        await h.env.platform.db.execute(
          'ALTER TABLE ${h.env.platform.schemas.of('messaging')}.mailbox_away RENAME TO mailbox',
        );
      }
    });

    test('shutdown closes open sockets cleanly', () async {
      final setup = await h.api.call(
        Routes.adminSetup,
        body: const AdminPasswordRequest(
          password: 'operator password 1',
        ).toJson(),
      );
      final adminToken = AdminSession.fromJson(setup.json).token;
      final second = await secondNode(h);
      final dir = second.platform.config.blobs.directory!;
      final socket = await TestSocket.connect(second.baseUri, b1.bearer);
      await socket.hello();
      final logs = await WebSocket.connect(
        second.baseUri
            .replace(scheme: 'ws', path: Routes.adminLogStream.path)
            .toString(),
        headers: {'authorization': 'Bearer $adminToken'},
      );
      final logsClosed = logs.drain<void>().then((_) => logs.closeCode);
      await second.stop();
      Directory(dir).deleteSync(recursive: true);
      expect(await socket.closed, RealtimeCloseCode.goingAway);
      expect(
        await logsClosed.timeout(const Duration(seconds: 5)),
        RealtimeCloseCode.goingAway,
      );
    });
  });

  group('realtime token expiry', skip: databaseTestSkipReason, () {
    test('the route refresh closes sockets whose token expired', () async {
      final clock = _OffsetClock();
      final h = await Harness.start(clock: clock);
      try {
        final b1 = await h.registerGlobal(bobNumber);
        final socket = await TestSocket.connect(h.server.baseUri, b1.bearer);
        await socket.hello();
        clock.offset = const Duration(minutes: 16);
        await h.realtime.refreshConnections();
        expect(await socket.closed, RealtimeCloseCode.unauthorized);
      } finally {
        await h.stop();
      }
    });
  });
}

/// The system clock, moved forward by [offset].
final class _OffsetClock implements Clock {
  Duration offset = Duration.zero;

  @override
  DateTime now() => DateTime.now().toUtc().add(offset);
}

/// Another node on the same database and schema prefix as [h].
Future<HelixServer> secondNode(Harness h) async => HelixServer.start(
  await HelixPlatform.open(
    testConfig(
      prefix: h.env.prefix,
      extra: {
        'HELIX_PHONE_PEPPER': testPepper,
        'HELIX_GLOBAL_MODE': 'true',
        'HELIX_ADMIN_KDF_MEMORY_KIB': '256',
      },
    ),
    log: Log(sink: MemorySink()),
  ),
  allModules(sms: RecordingSmsProvider()),
);

Future<void> stopNode(HelixServer node) async {
  final dir = node.platform.config.blobs.directory!;
  await node.stop();
  Directory(dir).deleteSync(recursive: true);
}

/// Device-key sign-in (after a sign-out); returns the new session.
Future<Session> deviceSignIn(Harness h, TestDevice d) async {
  final challenge = DeviceChallengeResponse.fromJson(
    (await h.api.call(
      Routes.deviceChallenge,
      body: DeviceChallengeRequest(
        accountId: d.accountId,
        deviceId: d.id,
      ).toJson(),
    )).json,
  );
  final response = await h.api.call(
    Routes.deviceSignIn,
    body: DeviceSignInRequest(
      accountId: d.accountId,
      deviceId: d.id,
      challengeId: challenge.challengeId,
      challenge: challenge.challenge,
      signature: await sign(d.dsk, signInSignatureBody(challenge.challenge)),
    ).toJson(),
  );
  return Session.fromJson(response.json);
}
