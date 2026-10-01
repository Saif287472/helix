import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../support/flows.dart';
import '../support/harness.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';
import '../support/test_socket.dart';

void main() {
  group('calls', skip: databaseTestSkipReason, () {
    late Harness h;
    late TestDevice alice;
    late TestDevice bob1;
    late TestDevice bob2;

    setUp(() async {
      h = await Harness.start(
        extra: {
          'HELIX_TURN_URLS': 'turn:turn.example:3478,turns:turn.example:5349',
          'HELIX_TURN_SECRET': 'turn-secret-for-tests',
        },
      );
      alice = await h.registerGlobal(aliceNumber);
      bob1 = await h.registerGlobal(bobNumber);
      bob2 = await secondDevice(h, bob1, bobNumber);
      await h.api.call(
        Routes.setPushToken,
        bearer: bob2.bearer,
        body: const PushTokenRequest(token: 'bob2-push').toJson(),
      );
    });

    tearDown(() async => h.stop());

    Future<TestResponse> signal(
      String callId,
      CallSignalKind kind,
      Map<String, List<String>> to,
    ) => h.api.call(
      Routes.sendCallSignal,
      params: {'call_id': callId},
      bearer: alice.bearer,
      body: CallSignalRequest(
        kind: kind,
        recipients: [
          for (final e in to.entries)
            Recipient(
              account: e.key,
              devices: [
                for (final d in e.value)
                  DevicePayload(device: d, payload: bytes(120, d.hashCode)),
              ],
            ),
        ],
      ).toJson(),
    );

    test('TURN credentials follow the coturn REST scheme', () async {
      final creds = TurnCredentials.fromJson(
        (await h.api.call(Routes.turnCredentials, bearer: alice.bearer)).json,
      );
      expect(creds.urls, hasLength(2));
      expect(creds.username, endsWith(':${alice.accountId}'));
      final expected = base64.encode(
        crypto.Hmac(
          crypto.sha1,
          utf8.encode('turn-secret-for-tests'),
        ).convert(utf8.encode(creds.username)).bytes,
      );
      expect(creds.credential, expected);
    });

    test(
      'an offer rings online devices live and pends with a push for offline ones',
      () async {
        final socket = await TestSocket.connect(h.server.baseUri, bob1.bearer);
        await socket.hello();
        while (!await socket.silent(const Duration(milliseconds: 300))) {}
        final callId = 'call-${Uuid.v7()}';
        final r = CallSignalResponse.fromJson(
          (await signal(callId, CallSignalKind.offer, {
            bob1.accountId: [bob1.id, bob2.id],
          })).json,
        );
        expect(r.delivered, [bob1.id]);
        expect(r.pending, [bob2.id]);

        final live = await socket.envelope();
        expect(live.kind, EnvelopeKind.callSignal);
        expect(live.callId, callId);
        expect(live.payload, bytes(120, bob1.id.hashCode));
        expect(live.data, {
          'kind': 'offer',
        }, reason: 'the server knows only the kind');

        await h.env.platform.jobs.tick();
        expect(h.push.sent.single.reason.wire, 'call');
        expect(h.push.sent.single.callId, callId);

        final pending = PendingCallList.fromJson(
          (await h.api.call(Routes.pendingCalls, bearer: bob2.bearer)).json,
        );
        expect(pending.calls.single.callId, callId);
        expect(pending.calls.single.from.device, alice.id);
        expect(pending.calls.single.payload, bytes(120, bob2.id.hashCode));
        await socket.close();
      },
    );

    test('answering on one device stops the others ringing', () async {
      final callId = 'call-${Uuid.v7()}';
      await signal(callId, CallSignalKind.offer, {
        bob1.accountId: [bob1.id, bob2.id],
      });
      await h.env.platform.jobs.tick();
      h.push.sent.clear();
      final socket = await TestSocket.connect(h.server.baseUri, bob2.bearer);
      await socket.hello();
      while (!await socket.silent(const Duration(milliseconds: 300))) {}

      expect(
        (await h.api.call(
          Routes.setCallState,
          params: {'call_id': callId},
          bearer: bob1.bearer,
          body: const CallStateRequest(state: CallState.answered).toJson(),
        )).status,
        204,
      );
      final stop = await socket.envelope();
      expect(stop.callId, callId);
      expect(stop.data, {'kind': 'end', 'state': 'answered'});
      expect(
        (PendingCallList.fromJson(
          (await h.api.call(Routes.pendingCalls, bearer: bob2.bearer)).json,
        )).calls,
        isEmpty,
      );
      await h.env.platform.jobs.tick();
      expect(h.push.sent.map((p) => p.reason.wire), contains('call_ended'));
      await socket.close();
    });

    test(
      'offers must ring every device; blocked callers reach nobody',
      () async {
        final incomplete = await signal(
          'call-${Uuid.v7()}',
          CallSignalKind.offer,
          {
            bob1.accountId: [bob1.id],
          },
        );
        expect(incomplete.status, 409);

        await h.api.call(
          Routes.block,
          params: {'account': alice.accountId},
          bearer: bob1.bearer,
        );
        final blocked = CallSignalResponse.fromJson(
          (await signal('call-${Uuid.v7()}', CallSignalKind.offer, {
            bob1.accountId: [bob1.id, bob2.id],
          })).json,
        );
        expect(blocked.delivered, isEmpty);
        expect(blocked.pending, isEmpty);
      },
    );

    test('call ids are validated; metrics are accepted', () async {
      expect(
        (await signal('x', CallSignalKind.offer, {
          bob1.accountId: [bob1.id, bob2.id],
        })).errorCode,
        'invalid_field',
      );
      final m = await h.api.call(
        Routes.callMetrics,
        bearer: alice.bearer,
        body: const CallMetricsRequest(
          callId: 'call-metrics-1',
          setupMs: 800,
          relayed: true,
        ).toJson(),
      );
      expect(m.status, 204);
    });
  });
}
