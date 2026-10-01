/// Several servers per test: allow for parallel runs on a busy machine.
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/federation/peers.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/federated.dart';
import '../support/flows.dart';
import '../support/harness.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';

void main() {
  group('federation', skip: databaseTestSkipReason, () {
    late Harness a;
    late Harness b;
    late TestDevice alice;
    late TestDevice bob;

    setUp(() async {
      a = await federated();
      b = await federated();
      alice = await a.registerGlobal(aliceNumber);
      bob = await b.registerGlobal(bobNumber);
    });
    tearDown(() async {
      await a.stop();
      await b.stop();
    });

    String bobAt() => '${bob.accountId}@${b.domain}';
    String aliceAt() => '${alice.accountId}@${a.domain}';

    test('each server publishes its identity document', () async {
      final doc = ServerIdentityDocument.fromJson(
        (await b.api.call(Routes.serverIdentity)).json,
      );
      expect(doc.serverId, b.domain);
      expect(decodeBytes(doc.publicKey), hasLength(32));
      expect(doc.apiBase, 'http://${b.domain}');
    });

    test('key bundles come from the home server', () async {
      final before = KeyStatus.fromJson(
        (await b.api.call(Routes.keyStatus, bearer: bob.bearer)).json,
      ).oneTimeRemaining;
      final response = await a.api.call(
        Routes.accountKeys,
        params: {'account': bobAt()},
        bearer: alice.bearer,
      );
      expect(response.status, 200, reason: '$response');
      final keys = AccountKeys.fromJson(response.json);
      expect(keys.account, bobAt());
      expect(keys.devices.single.deviceId, bob.id);
      final after = KeyStatus.fromJson(
        (await b.api.call(Routes.keyStatus, bearer: bob.bearer)).json,
      ).oneTimeRemaining;
      expect(after, before - 1);

      final unknown = await a.api.call(
        Routes.accountKeys,
        params: {'account': '${Uuid.v7()}@${b.domain}'},
        bearer: alice.bearer,
      );
      expect(unknown.errorCode, 'not_found');
    });

    test('messages cross servers both ways with qualified senders', () async {
      final sent = await send(a, alice, {
        bobAt(): [bob.id],
      });
      expect(sent.status, 200, reason: '$sent');
      final inbox = await mailbox(b, bob);
      final envelope = inbox.envelopes.single;
      expect(envelope.kind, EnvelopeKind.message);
      expect(envelope.from!.account, aliceAt());
      expect(envelope.from!.device, alice.id);

      final reply = await send(b, bob, {
        envelope.from!.account: [alice.id],
      });
      expect(reply.status, 200, reason: '$reply');
      expect((await mailbox(a, alice)).envelopes.single.from!.account, bobAt());

      // A retried send is not delivered twice.
      final id = Uuid.v7();
      await send(a, alice, {
        bobAt(): [bob.id],
      }, id: id);
      await send(a, alice, {
        bobAt(): [bob.id],
      }, id: id);
      expect((await mailbox(b, bob)).envelopes, hasLength(2));
    });

    test('a stale remote device list comes back qualified', () async {
      final bob2 = await secondDevice(b, bob, bobNumber);
      final response = await send(a, alice, {
        bobAt(): [bob.id],
      });
      expect(response.errorCode, 'device_list_stale');
      final stale = StaleDevices.fromJson(
        response.json.object('error').object('details'),
      );
      expect(stale.accounts.single.account, bobAt());
      expect(stale.accounts.single.missing, [bob2.id]);
      expect(
        (await mailbox(
          b,
          bob,
        )).envelopes.where((e) => e.kind == EnvelopeKind.message),
        isEmpty,
      );

      final unknown = await send(a, alice, {
        '${Uuid.v7()}@${b.domain}': [Uuid.v7()],
      });
      expect(unknown.errorCode, 'not_found');
    });

    test('blocking a remote account drops its messages silently', () async {
      expect(
        (await b.api.call(
          Routes.block,
          params: {'account': aliceAt()},
          bearer: bob.bearer,
        )).status,
        204,
      );
      final blocks = BlockList.fromJson(
        (await b.api.call(Routes.blocks, bearer: bob.bearer)).json,
      );
      expect(blocks.accounts, [aliceAt()]);
      final sent = await send(a, alice, {
        bobAt(): [bob.id],
      });
      expect(sent.status, 200);
      expect((await mailbox(b, bob)).envelopes, isEmpty);
    });

    test('call offers ring the remote callee', () async {
      final callId = 'call-${Uuid.v7()}';
      final response = await a.api.call(
        Routes.sendCallSignal,
        params: {'call_id': callId},
        bearer: alice.bearer,
        body: CallSignalRequest(
          kind: CallSignalKind.offer,
          recipients: [
            Recipient(
              account: bobAt(),
              devices: [DevicePayload(device: bob.id, payload: bytes(40))],
            ),
          ],
        ).toJson(),
      );
      expect(response.status, 200, reason: '$response');
      expect(CallSignalResponse.fromJson(response.json).pending, [bob.id]);
      final pending = PendingCallList.fromJson(
        (await b.api.call(Routes.pendingCalls, bearer: bob.bearer)).json,
      );
      expect(pending.calls.single.callId, callId);
      expect(pending.calls.single.from.account, aliceAt());
    });

    group('S2S authentication', () {
      Future<http.Response> post(
        Harness to,
        Map<String, String> headers,
        List<int> body,
      ) => http.post(
        to.server.baseUri.resolve(Routes.s2sMessages.path),
        headers: {'content-type': 'application/json', ...headers},
        body: body,
      );

      List<int> batchFor({required String sender}) => utf8.encode(
        jsonEncode(
          S2SMessageBatch(
            id: Uuid.v7(),
            sender: sender,
            senderDevice: alice.id,
            recipients: [
              Recipient(
                account: bob.accountId,
                devices: [DevicePayload(device: bob.id, payload: bytes(32))],
              ),
            ],
          ).toJson(),
        ),
      );

      test('unsigned, re-used and tampered requests are refused', () async {
        final body = batchFor(sender: aliceAt());
        expect((await post(b, const {}, body)).statusCode, 401);

        final headers = await a.federation.client.sign(
          'POST',
          Routes.s2sMessages.path,
          body,
        );
        expect((await post(b, headers, body)).statusCode, 200);
        expect(
          (await post(b, headers, body)).statusCode,
          401,
          reason: 'a signature is accepted once',
        );

        final other = batchFor(sender: aliceAt());
        final signed = await a.federation.client.sign(
          'POST',
          Routes.s2sMessages.path,
          other,
        );
        final tampered = [...other]..[other.length - 3] ^= 1;
        expect((await post(b, signed, tampered)).statusCode, 401);

        final old = await a.federation.client.sign(
          'POST',
          Routes.s2sMessages.path,
          other,
        );
        final stale = {
          ...old,
          HelixHeaders.s2sTimestamp:
              '${DateTime.now().subtract(const Duration(minutes: 6)).millisecondsSinceEpoch}',
        };
        expect((await post(b, stale, other)).statusCode, 401);
        expect((await mailbox(b, bob)).envelopes, hasLength(1));
      });

      test('a server may only send for its own accounts', () async {
        final body = batchFor(sender: '${alice.accountId}@example.org');
        final headers = await a.federation.client.sign(
          'POST',
          Routes.s2sMessages.path,
          body,
        );
        final response = await post(b, headers, body);
        expect(response.statusCode, 403);
      });
    });

    test('a reused message id cannot suppress another sender', () async {
      final carol = await b.registerGlobal('+8801711000003');
      final id = Uuid.v7();
      // Server A (or any co-recipient's server) sends id first...
      expect(
        (await send(a, alice, {
          bobAt(): [bob.id],
        }, id: id)).status,
        200,
      );
      // ...and Carol's own message with that id still arrives.
      final mine = await send(b, carol, {
        bob.accountId: [bob.id],
      }, id: id);
      expect(mine.status, 200, reason: '$mine');
      expect(SendMessageResponse.fromJson(mine.json).replayed, isFalse);
      expect((await mailbox(b, bob)).envelopes.map((e) => e.from!.account), [
        aliceAt(),
        carol.accountId,
      ]);
      // Carol's retry is still a replay.
      final again = await send(b, carol, {
        bob.accountId: [bob.id],
      }, id: id);
      expect(SendMessageResponse.fromJson(again.json).replayed, isTrue);
      expect((await mailbox(b, bob)).envelopes, hasLength(2));
    });

    test('remote key fetches count against the account\'s limit', () async {
      // Drain Bob's per-account bundle bucket on B (local fetches share it).
      final target = RateLimitPolicy.per(
        'keys.bundle_target',
        600,
        const Duration(hours: 1),
      );
      for (var i = 0; i < 600; i += 50) {
        await Future.wait([
          for (var j = 0; j < 50; j++)
            b.env.platform.rateLimiter.hit(target, bob.accountId),
        ]);
      }
      final response = await a.api.call(
        Routes.accountKeys,
        params: {'account': bobAt()},
        bearer: alice.bearer,
      );
      expect(response.errorCode, 'rate_limited');
    });

    group('outbound requests', () {
      late HttpServer evil;
      late HttpServer internal;
      var internalHits = 0;
      var redirectIdentity = false;

      setUp(() async {
        internalHits = 0;
        redirectIdentity = false;
        internal = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        internal.listen((r) {
          internalHits++;
          r.response
            ..statusCode = 200
            ..close();
        });
        evil = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final domain = '127.0.0.1:${evil.port}';
        evil.listen((r) {
          final wellKnown = r.uri.path == '/.well-known/helix-server';
          if (wellKnown && !redirectIdentity) {
            r.response
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode(
                  ServerIdentityDocument(
                    serverId: domain,
                    publicKey: encodeBytes(bytes(32)),
                    apiBase: 'http://$domain',
                  ).toJson(),
                ),
              )
              ..close();
            return;
          }
          r.response
            ..statusCode = 307
            ..headers.set('location', 'http://127.0.0.1:${internal.port}/x')
            ..close();
        });
      });
      tearDown(() async {
        await evil.close(force: true);
        await internal.close(force: true);
      });

      test('never follow redirects', () async {
        final domain = '127.0.0.1:${evil.port}';
        redirectIdentity = true;
        await expectLater(
          a.federation.peers.resolve(domain),
          throwsA(isA<PeerUnavailable>()),
        );
        expect(internalHits, 0);

        redirectIdentity = false;
        await expectLater(
          a.federation.client.call(
            domain,
            'POST',
            Routes.s2sMessages.path,
            body: const {},
          ),
          throwsA(isA<PeerUnavailable>()),
        );
        expect(internalHits, 0);
      });
    });

    test('federation switched off refuses both directions', () async {
      await b.setFederation(false);
      final toB = await send(a, alice, {
        bobAt(): [bob.id],
      });
      expect(toB.errorCode, 'federation_unavailable');
      final fromB = await send(b, bob, {
        aliceAt(): [alice.id],
      });
      expect(fromB.errorCode, 'federation_unavailable');
      expect(
        (await b.api.call(
          Routes.s2sGroup,
          params: {'group_id': Uuid.v7()},
        )).status,
        401,
      );
    });

    test('unreachable servers get the message later', () async {
      final port = await freePort();
      final response = await send(a, alice, {
        '${Uuid.v7()}@127.0.0.1:$port': [Uuid.v7()],
      });
      expect(response.status, 200, reason: '$response');
      final platform = a.env.platform.schemas.of('platform');
      final jobs = await a.env.platform.db.query(
        "SELECT payload FROM $platform.jobs WHERE kind = 'federation.relay'",
      );
      expect(jobs, hasLength(1));
      expect(jobs.single.json('payload')['domain'], '127.0.0.1:$port');
    });
  });

  group('federation addresses', () {
    bool refused(String ip, {bool allowPrivate = false}) =>
        PeerDirectory.refuses(InternetAddress(ip), allowPrivate: allowPrivate);

    test('IPv6 forms of IPv4 addresses are judged as IPv4', () {
      // Metadata services are refused in every form, even on private LANs.
      for (final ip in [
        '169.254.169.254',
        '::ffff:169.254.169.254',
        '::169.254.169.254',
        '64:ff9b::a9fe:a9fe',
        '2002:a9fe:a9fe::1',
        '0.0.0.0',
        '::',
        'fe80::1',
      ]) {
        expect(refused(ip, allowPrivate: true), isTrue, reason: ip);
      }
      for (final ip in [
        '127.0.0.1',
        '::ffff:127.0.0.1',
        '::1',
        '::ffff:10.0.0.1',
        '64:ff9b::a00:1',
        '64:ff9b:1::1',
        '2002:c0a8:101::1',
        'fd00::1',
      ]) {
        expect(refused(ip), isTrue, reason: ip);
        expect(refused(ip, allowPrivate: true), isFalse, reason: ip);
      }
      for (final ip in ['8.8.8.8', '::ffff:8.8.8.8', '2606:4700::1111']) {
        expect(refused(ip), isFalse, reason: ip);
      }
    });
  });

  group('federation policy', skip: databaseTestSkipReason, () {
    test('allow lists and private addresses limit peers', () async {
      final b = await federated();
      final strict = await federated(
        extra: {'HELIX_FEDERATION_ALLOW_PRIVATE': 'false'},
      );
      final listed = await federated(
        extra: {'HELIX_FEDERATION_ALLOW': 'helix.example.org'},
      );
      try {
        final bob = await b.registerGlobal(bobNumber);
        final target = '${bob.accountId}@${b.domain}';
        for (final h in [strict, listed]) {
          final alice = await h.registerGlobal(aliceNumber);
          final response = await send(h, alice, {
            target: [bob.id],
          });
          expect(response.errorCode, 'federation_unavailable');
        }
        expect((await mailbox(b, bob)).envelopes, isEmpty);
      } finally {
        await b.stop();
        await strict.stop();
        await listed.stop();
      }
    });

    test('a server without federation refuses remote recipients', () async {
      final h = await Harness.start();
      try {
        final alice = await h.registerGlobal(aliceNumber);
        final response = await send(h, alice, {
          '${Uuid.v7()}@helix.example.org': [Uuid.v7()],
        });
        expect(response.errorCode, 'federation_unavailable');
      } finally {
        await h.stop();
      }
    });
  });
}
