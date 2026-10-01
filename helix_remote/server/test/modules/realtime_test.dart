import 'dart:io';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/helix_remote_server.dart';
import 'package:helix_remote_server/src/modules/identity/sms.dart';
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
  });
}
