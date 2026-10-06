import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../support/harness.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';
import '../support/flows.dart';
import '../support/test_socket.dart';

void main() {
  group('messaging', skip: databaseTestSkipReason, () {
    late Harness h;
    late TestDevice a1;
    late TestDevice a2;
    late TestDevice b1;

    setUp(() async {
      h = await Harness.start();
      a1 = await h.registerGlobal(aliceNumber);
      a2 = await secondDevice(h, a1, aliceNumber);
      b1 = await h.registerGlobal(bobNumber);
      // Drain the account signals the second device produced.
      for (final d in [a1, a2]) {
        final page = await mailbox(h, d);
        if (page.lastSeq > 0) {
          await h.api.call(
            Routes.ackMailbox,
            bearer: d.bearer,
            body: AckRequest(seq: page.lastSeq).toJson(),
          );
        }
      }
    });

    tearDown(() async => h.stop());

    test(
      'a send reaches the peer and the sender\'s other devices, once',
      () async {
        final id = Uuid.v7();
        final response = await send(h, a1, {
          b1.accountId: [b1.id],
          a1.accountId: [a2.id],
        }, id: id);
        expect(response.status, 200);

        final bobBox = await mailbox(h, b1);
        final envelope = bobBox.envelopes.single;
        expect(envelope.id, id);
        expect(envelope.kind, EnvelopeKind.message);
        expect(
          envelope.from,
          EnvelopeSender(account: a1.accountId, device: a1.id),
        );
        expect(envelope.payload, bytes(64, b1.id.hashCode));
        expect(envelope.seq, 1);
        expect((await mailbox(h, a2)).envelopes.single.id, id);

        final replay = await send(h, a1, {
          b1.accountId: [b1.id],
          a1.accountId: [a2.id],
        }, id: id);
        expect(SendMessageResponse.fromJson(replay.json).replayed, isTrue);
        expect(
          (await mailbox(h, b1)).envelopes,
          hasLength(1),
          reason: 'retries never duplicate',
        );
      },
    );

    test('seq increases per device; acks delete', () async {
      for (var i = 0; i < 3; i++) {
        await send(h, a1, {
          b1.accountId: [b1.id],
          a1.accountId: [a2.id],
        });
      }
      final box = await mailbox(h, b1);
      expect(box.envelopes.map((e) => e.seq), [1, 2, 3]);
      final acked = await h.api.call(
        Routes.ackMailbox,
        bearer: b1.bearer,
        body: const AckRequest(seq: 2).toJson(),
      );
      expect(AckResponse.fromJson(acked.json).deleted, 2);
      expect((await mailbox(h, b1)).envelopes.map((e) => e.seq), [3]);
      await send(h, a1, {
        b1.accountId: [b1.id],
        a1.accountId: [a2.id],
      });
      expect((await mailbox(h, b1)).envelopes.map((e) => e.seq), [
        3,
        4,
      ], reason: 'never reused');
    });

    test(
      'a stale device list is refused with the missing and extra devices',
      () async {
        final b2 = await secondDevice(h, b1, bobNumber);
        final stale = await send(h, a1, {
          b1.accountId: [b1.id],
          a1.accountId: [a2.id],
        });
        expect(stale.status, 409);
        final details = StaleDevices.fromJson(
          stale.json.object('error').object('details'),
        );
        expect(details.accounts.single.account, b1.accountId);
        expect(details.accounts.single.missing, [b2.id]);
        expect(
          (await mailbox(
            h,
            b1,
          )).envelopes.where((e) => e.kind == EnvelopeKind.message),
          isEmpty,
          reason: 'nothing is sent',
        );

        final extra = await send(h, a1, {
          b1.accountId: [b1.id, b2.id, Uuid.v7()],
          a1.accountId: [a2.id],
        });
        expect(
          StaleDevices.fromJson(
            extra.json.object('error').object('details'),
          ).accounts.single.extra,
          hasLength(1),
        );

        final missingOwn = await send(h, a1, {
          b1.accountId: [b1.id, b2.id],
          a1.accountId: [],
        });
        expect(
          missingOwn.status,
          409,
          reason: 'own other devices must be complete when listed',
        );
      },
    );

    test(
      'bad requests: unknown account, oversized payload, own sending device',
      () async {
        expect(
          (await send(h, a1, {
            Uuid.v7(): [Uuid.v7()],
          })).status,
          404,
        );
        expect(
          (await send(h, a1, {
            b1.accountId: [b1.id],
          }, size: 300 * 1024)).status,
          413,
        );
        expect(
          (await send(h, a1, {
            a1.accountId: [a1.id],
          })).errorCode,
          'invalid_field',
        );
      },
    );

    test('offline urgent sends push the device; online ones do not', () async {
      await h.api.call(
        Routes.setPushToken,
        bearer: b1.bearer,
        body: const PushTokenRequest(token: 'bob-token').toJson(),
      );
      await send(h, a1, {
        b1.accountId: [b1.id],
        a1.accountId: [a2.id],
      });
      await send(h, a1, {
        b1.accountId: [b1.id],
        a1.accountId: [a2.id],
      });
      await h.env.platform.jobs.tick();
      // One push per pending batch: the live runner may already have sent
      // the first before the second send, so 1 or 2 (dedupe itself is
      // covered in jobs_test).
      expect(
        h.push.sent.where((p) => p.token == 'bob-token').length,
        inInclusiveRange(1, 2),
      );
      expect(
        h.push.sent.every(
          (p) => p.reason.wire == 'message' && p.callId == null,
        ),
        isTrue,
        reason: 'wake-ups only, no content',
      );

      final socket = await TestSocket.connect(h.server.baseUri, b1.bearer);
      await socket.hello();
      h.push.sent.clear();
      await send(h, a1, {
        b1.accountId: [b1.id],
        a1.accountId: [a2.id],
      });
      await h.env.platform.jobs.tick();
      expect(h.push.sent, isEmpty);
      await socket.close();

      await send(h, a1, {
        b1.accountId: [b1.id],
        a1.accountId: [a2.id],
      }, urgent: false);
      await h.env.platform.jobs.tick();
      expect(h.push.sent, isEmpty, reason: 'non-urgent sends never push');
    });

    test('blocked senders are dropped silently', () async {
      h.messaging.api.setBlockPolicy(
        (db, sender, recipients) async =>
            sender == a1.accountId ? recipients.toSet() : <String>{},
      );
      final response = await send(h, a1, {
        b1.accountId: [b1.id],
        a1.accountId: [a2.id],
      });
      expect(response.status, 200);
      expect((await mailbox(h, b1)).envelopes, isEmpty);
      expect(
        (await mailbox(h, a2)).envelopes,
        hasLength(1),
        reason: 'own devices still get the copy',
      );
    });

    test(
      'a new sign-in is announced to the other devices; the list change too',
      () async {
        final a3 = await secondDevice(h, a1, aliceNumber);
        final kinds = (await mailbox(
          h,
          a1,
        )).envelopes.map((e) => e.kind).toList();
        expect(
          kinds,
          containsAll([
            EnvelopeKind.accountSignal,
            EnvelopeKind.deviceListChange,
          ]),
        );
        final signal = (await mailbox(
          h,
          a1,
        )).envelopes.firstWhere((e) => e.kind == EnvelopeKind.accountSignal);
        final event = AccountSignalEvent.fromJson(JsonReader(signal.data!));
        expect(event.signal, AccountSignalKind.newSignIn);
        expect(event.device, a3.id);
        expect(
          (await mailbox(
            h,
            a3,
          )).envelopes.where((e) => e.kind == EnvelopeKind.accountSignal),
          isEmpty,
          reason: 'not told about itself',
        );
      },
    );

    test('revoking a device deletes its mailbox', () async {
      await send(h, a1, {
        b1.accountId: [b1.id],
        a1.accountId: [a2.id],
      });
      await h.api.call(
        Routes.revokeDevice,
        params: {'device_id': a2.id},
        bearer: a1.bearer,
      );
      final rows = await h.env.platform.db.query(
        'SELECT count(*) AS n FROM ${h.env.platform.schemas.of('messaging')}.mailbox WHERE device_id = @d:uuid',
        {'d': a2.id},
      );
      expect(rows.single.integer('n'), 0);
    });

    test(
      'low prekeys produce a prekeys_low envelope for that device',
      () async {
        final c = await h.registerGlobal('+8801711000003', oneTime: 20);
        await h.api.call(
          Routes.accountKeys,
          params: {'account': c.accountId},
          bearer: b1.bearer,
        );
        final box = await mailbox(h, c);
        final low = box.envelopes.singleWhere(
          (e) => e.kind == EnvelopeKind.prekeysLow,
        );
        expect(PrekeysLowEvent.fromJson(JsonReader(low.data!)).remaining, 19);
      },
    );
  });
}
