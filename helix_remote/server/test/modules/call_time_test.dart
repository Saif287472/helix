import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/billing/module.dart';
import 'package:helix_remote_server/src/modules/calls/module.dart';
import 'package:helix_remote_server/src/platform/config/server_config.dart';
import 'package:helix_remote_server/src/platform/clock.dart';
import 'package:test/test.dart';

import '../support/flows.dart';
import '../support/harness.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';
import '../support/test_platform.dart';

const adminPassword = 'correct horse battery staple';
const carolNumber = '+8801711000003';

String _hmac(String secret, String username) => base64.encode(
  crypto.Hmac(
    crypto.sha1,
    utf8.encode(secret),
  ).convert(utf8.encode(username)).bytes,
);

void main() {
  group('the relays\' settings', () {
    TurnConfig config(Map<String, String> turn) => TurnConfig.from(
      ServerConfig.fromEnv({
        'HELIX_DATABASE_URL': 'postgresql://u:p@localhost/db',
        'HELIX_JWT_KEYS': '{"test":"$testJwtKey"}',
        'HELIX_PHONE_PEPPER': testPepper,
        ...turn,
      }),
    );

    test('a voice relay needs its own secret', () {
      expect(
        () => config({
          'HELIX_TURN_URLS': 'turn:main.example:3478',
          'HELIX_TURN_SECRET': 'one',
          'HELIX_TURN_VOICE_URLS': 'turn:voice.example:3479',
          'HELIX_TURN_VOICE_SECRET': 'one',
        }),
        throwsA(isA<ConfigError>()),
      );
    });

    test('the voice URLs and secret come together or not at all', () {
      expect(
        () => config({
          'HELIX_TURN_URLS': 'turn:main.example:3478',
          'HELIX_TURN_SECRET': 'one',
          'HELIX_TURN_VOICE_URLS': 'turn:voice.example:3479',
        }),
        throwsA(isA<ConfigError>()),
      );
      final ok = config({
        'HELIX_TURN_URLS': 'turn:main.example:3478',
        'HELIX_TURN_SECRET': 'one',
        'HELIX_TURN_VOICE_URLS': 'turn:voice.example:3479',
        'HELIX_TURN_VOICE_SECRET': 'two',
      });
      expect(ok.hasVoiceRelay, isTrue);
      expect(config({}).hasVoiceRelay, isFalse);
    });
  });

  group('call time', skip: databaseTestSkipReason, () {
    late Harness h;
    late ManualClock clock;
    late String admin;

    // The accounts are registered before plans are on, so they are Free (an
    // account created afterwards starts with a trial week of Premium).
    late TestDevice alice;
    late TestDevice bob;
    late TestDevice carol;

    setUp(() async {
      clock = ManualClock(DateTime.utc(2026, 11, 1));
      h = await Harness.start(
        clock: clock,
        extra: {
          'HELIX_ADMIN_PASSWORD': adminPassword,
          'HELIX_TURN_URLS': 'turn:main.example:3478',
          'HELIX_TURN_SECRET': 'main-secret',
          'HELIX_TURN_VOICE_URLS': 'turn:voice.example:3479',
          'HELIX_TURN_VOICE_SECRET': 'voice-secret',
        },
      );
      alice = await h.registerGlobal(aliceNumber);
      bob = await h.registerGlobal(bobNumber);
      carol = await h.registerGlobal(carolNumber);
      admin = AdminSession.fromJson(
        (await h.api.call(
          Routes.adminSignIn,
          body: const AdminPasswordRequest(password: adminPassword).toJson(),
        )).json,
      ).token;
    });
    tearDown(() async => h.stop());

    BillingModule billing() =>
        h.server.modules.whereType<BillingModule>().single;

    Future<void> plansOn() async {
      final r = await h.api.call(
        Routes.adminSetFeatureFlag,
        params: {'name': 'billing_enabled'},
        bearer: admin,
        body: const SetFeatureFlagRequest(enabled: true).toJson(),
      );
      expect(r.status, 204, reason: r.body);
    }

    Future<CallTime> time(TestDevice d) async {
      final r = await h.api.call(Routes.callTime, bearer: d.bearer);
      expect(r.status, 200, reason: r.body);
      return CallTime.fromJson(r.json);
    }

    Future<TestResponse> claim(TestDevice d) =>
        h.api.call(Routes.claimCallTime, bearer: d.bearer);

    Future<TestResponse> turn(
      TestDevice d,
      String callId, {
      CallRole role = CallRole.caller,
      CallPool media = CallPool.voice,
      String? room,
    }) => h.api.call(
      Routes.turnCredentials,
      bearer: d.bearer,
      body: TurnRequest(
        callId: callId,
        role: role,
        media: media,
        roomId: room,
      ).toJson(),
    );

    TurnCredentials creds(TestResponse r) {
      expect(r.status, 200, reason: r.body);
      return TurnCredentials.fromJson(r.json);
    }

    Future<TestResponse> signal(
      String callId,
      CallSignalKind kind,
      TestDevice from,
      TestDevice to,
    ) => h.api.call(
      Routes.sendCallSignal,
      params: {'call_id': callId},
      bearer: from.bearer,
      body: CallSignalRequest(
        kind: kind,
        recipients: [
          Recipient(
            account: to.accountId,
            devices: [DevicePayload(device: to.id, payload: bytes(60))],
          ),
        ],
      ).toJson(),
    );

    String newCall() => 'call-${Uuid.v7()}';

    group('the balance', () {
      test('is unlimited while plans are off', () async {
        final t = await time(alice);
        expect(t.unlimited, isTrue);
        expect(t.pools, isEmpty);
        // Nothing to claim, nothing is kept.
        expect(
          (CallTime.fromJson((await claim(alice)).json)).unlimited,
          isTrue,
        );
      });

      test('starts empty on Free, with today\'s claim waiting', () async {
        await plansOn();
        final t = await time(alice);
        expect(t.unlimited, isFalse);
        expect(t.pool(CallPool.voice)!.minutes, 0);
        expect(t.pool(CallPool.video)!.minutes, 0);
        expect(t.pool(CallPool.voice)!.dailyMinutes, 100);
        expect(t.pool(CallPool.video)!.capMinutes, 90);
        expect(t.canClaim, isTrue);
      });

      test(
        'a claim gives 100 voice and 30 video minutes, once a day',
        () async {
          await plansOn();
          final r = await claim(alice);
          expect(r.status, 200, reason: r.body);
          final t = CallTime.fromJson(r.json);
          expect(t.pool(CallPool.voice)!.minutes, 100);
          expect(t.pool(CallPool.video)!.minutes, 30);
          expect(t.canClaim, isFalse);
          // The next claim opens at midnight in Dhaka (18:00 UTC).
          expect(t.nextClaimAt, DateTime.utc(2026, 11, 1, 18));

          final again = await claim(alice);
          expect(again.status, 409);
          expect(again.errorCode, 'conflict');
        },
      );

      test('holds three days at most and loses the oldest', () async {
        await plansOn();
        final id = alice.accountId;
        Future<CallTime> at(DateTime t) async {
          clock.set(t);
          return billing().callTime(id);
        }

        await billing().claimCallTime(id); // Dhaka Nov 1
        clock.set(DateTime.utc(2026, 11, 1, 18));
        await billing().claimCallTime(id); // Nov 2
        clock.set(DateTime.utc(2026, 11, 2, 18));
        await billing().claimCallTime(id); // Nov 3
        var t = await billing().callTime(id);
        expect(t.pool(CallPool.voice)!.minutes, 300);
        expect(t.pool(CallPool.video)!.minutes, 90);

        // A fourth day: the first claim ran out at the end of its third day.
        t = await at(DateTime.utc(2026, 11, 3, 18));
        expect(t.pool(CallPool.voice)!.minutes, 200);
        await billing().claimCallTime(id);
        t = await billing().callTime(id);
        expect(t.pool(CallPool.voice)!.minutes, 300);
        expect(t.pool(CallPool.video)!.minutes, 90);
      });
    });

    group('the relay credential', () {
      test('is refused without call time, and says which kind', () async {
        await plansOn();
        final r = await turn(alice, newCall());
        expect(r.status, 422);
        expect(r.errorCode, 'quota_exceeded');
        expect(
          r.json.object('error').object('details').string('reason'),
          'call_time',
        );
      });

      test('ends with the call time set aside, on the voice relay', () async {
        await plansOn();
        await claim(alice);
        final c = creds(await turn(alice, newCall()));
        expect(c.metered, isTrue);
        expect(c.expiresAt, DateTime.utc(2026, 11, 1, 1, 40));
        expect(c.urls, ['turn:voice.example:3479']);
        expect(c.credential, _hmac('voice-secret', c.username));
        expect(c.credential, isNot(_hmac('main-secret', c.username)));
        expect(
          int.parse(c.username.split(':').first),
          c.expiresAt.millisecondsSinceEpoch ~/ 1000,
        );
        // Everything held is set aside while the call runs.
        expect((await time(alice)).pool(CallPool.voice)!.minutes, 0);
        // The other pool is untouched.
        expect((await time(alice)).pool(CallPool.video)!.minutes, 30);
      });

      test('video spends video minutes and uses the main relay', () async {
        await plansOn();
        await claim(alice);
        final c = creds(await turn(alice, newCall(), media: CallPool.video));
        expect(c.expiresAt, DateTime.utc(2026, 11, 1, 0, 30));
        expect(c.urls, ['turn:main.example:3478']);
        expect(c.credential, _hmac('main-secret', c.username));
        final t = await time(alice);
        expect(t.pool(CallPool.voice)!.minutes, 100);
        expect(t.pool(CallPool.video)!.minutes, 0);
      });

      test('asking again for the same call gives the same end', () async {
        await plansOn();
        await claim(alice);
        final id = newCall();
        final a = creds(await turn(alice, id));
        clock.advance(const Duration(seconds: 20));
        final b = creds(await turn(alice, id));
        expect(b.expiresAt, a.expiresAt);
        expect(b.username, isNot(a.username));
        // Another account cannot take the call over.
        expect((await turn(bob, id)).status, 409);
      });

      test('Premium has no meter, and a long lifetime', () async {
        await plansOn();
        // Registered with plans on: a trial week of Premium.
        final dave = await h.registerGlobal('+8801711000004');
        final c = creds(await turn(dave, newCall()));
        expect(c.metered, isFalse);
        expect(c.expiresAt, DateTime.utc(2026, 11, 1, 8));
        expect((await time(dave)).unlimited, isTrue);
      });

      test(
        'has a long lifetime and no record on a server without plans',
        () async {
          final c = creds(await turn(alice, newCall()));
          expect(c.metered, isFalse);
          expect(c.expiresAt, DateTime.utc(2026, 11, 1, 8));
          final left = await h.env.platform.db.queryOne(
            'SELECT count(*) AS n FROM ${h.env.platform.schemas.of('billing')}.call_reservations',
          );
          expect(left!.integer('n'), 0);
        },
      );

      test('bad requests are refused', () async {
        await plansOn();
        final r = await h.api.call(
          Routes.turnCredentials,
          bearer: alice.bearer,
          body: {'call_id': 'x', 'role': 'caller', 'media': 'voice'},
        );
        expect(r.status, 400);
        expect(
          (await h.api.call(
            Routes.turnCredentials,
            bearer: alice.bearer,
            body: {'call_id': newCall(), 'role': 'caller', 'media': 'hologram'},
          )).status,
          400,
        );
        expect((await h.api.call(Routes.turnCredentials)).status, 401);
      });
    });

    group('the answering side', () {
      test(
        'runs under the caller\'s time, and only if it was offered',
        () async {
          await plansOn();
          await claim(alice);
          final id = newCall();
          final caller = creds(await turn(alice, id));

          // Nothing was offered yet: nobody may answer.
          expect((await turn(bob, id, role: CallRole.callee)).status, 404);

          expect(
            (await signal(id, CallSignalKind.offer, alice, bob)).status,
            200,
          );
          final answer = creds(await turn(bob, id, role: CallRole.callee));
          expect(answer.metered, isTrue);
          expect(answer.expiresAt, caller.expiresAt);
          expect(
            answer.urls,
            caller.urls,
            reason: 'both ends use the same relay',
          );
          // Bob has no call time and needs none to answer.
          expect((await time(bob)).pool(CallPool.voice)!.minutes, 0);
          // Someone the call was not offered to cannot use the relay for it.
          expect((await turn(carol, id, role: CallRole.callee)).status, 404);
        },
      );

      test(
        'cannot answer a call whose caller never asked for the relay',
        () async {
          await plansOn();
          final id = newCall();
          await signal(id, CallSignalKind.offer, alice, bob);
          final r = await turn(bob, id, role: CallRole.callee);
          expect(r.status, 409);
        },
      );

      test('a Premium caller\'s call is free for a Free callee', () async {
        await plansOn();
        final dave = await h.registerGlobal('+8801711000004'); // trial
        final id = newCall();
        await turn(dave, id);
        await signal(id, CallSignalKind.offer, dave, bob);
        final answer = creds(await turn(bob, id, role: CallRole.callee));
        expect(answer.metered, isFalse);
      });
    });

    group('settling', () {
      Future<int> voiceLeft(TestDevice d) async =>
          (await billing().callTime(d.accountId)).pool(CallPool.voice)!.minutes;

      test(
        'spends each started minute from the answer to the hang-up',
        () async {
          await plansOn();
          await claim(alice);
          final id = newCall();
          await turn(alice, id);
          await signal(id, CallSignalKind.offer, alice, bob);
          clock.advance(const Duration(seconds: 20)); // it rings
          await turn(bob, id, role: CallRole.callee);
          clock.advance(const Duration(minutes: 3, seconds: 10));
          expect(
            (await signal(id, CallSignalKind.end, bob, alice)).status,
            200,
          );

          expect(await voiceLeft(alice), 100 - 4);
        },
      );

      test('an unanswered call costs nothing', () async {
        await plansOn();
        await claim(alice);
        final id = newCall();
        await turn(alice, id);
        await signal(id, CallSignalKind.offer, alice, bob);
        expect(await voiceLeft(alice), 0, reason: 'held while it rings');
        clock.advance(const Duration(seconds: 25));
        await signal(id, CallSignalKind.end, alice, bob);
        expect(await voiceLeft(alice), 100);
      });

      test('a call that never ends is charged what was set aside', () async {
        await plansOn();
        await claim(alice);
        final id = newCall();
        await turn(alice, id);
        await signal(id, CallSignalKind.offer, alice, bob);
        await turn(bob, id, role: CallRole.callee);
        clock.advance(const Duration(minutes: 101));
        await billing().periodic
            .singleWhere((j) => j.name == 'billing.settle_calls')
            .run();
        expect(await voiceLeft(alice), 0);
        // Gone for good: nothing comes back once the claim is spent.
        final left = await h.env.platform.db.queryOne(
          'SELECT used FROM ${h.env.platform.schemas.of('billing')}.call_reservations',
        );
        expect(left!.integer('used'), 100);
      });

      test('minutes of a finished call can be spent again at once', () async {
        await plansOn();
        await claim(alice);
        final first = newCall();
        await turn(alice, first);
        await signal(first, CallSignalKind.offer, alice, bob);
        await turn(bob, first, role: CallRole.callee);
        clock.advance(const Duration(minutes: 2));
        await signal(first, CallSignalKind.end, alice, bob);

        final second = creds(await turn(alice, newCall()));
        expect(second.expiresAt, clock.now().add(const Duration(minutes: 98)));
      });

      test(
        'the refund goes to the claims it came from, not the expired',
        () async {
          await plansOn();
          final id = alice.accountId;
          await billing().claimCallTime(id); // Nov 1
          clock.set(DateTime.utc(2026, 11, 1, 18));
          await billing().claimCallTime(id); // Nov 2
          var t = await billing().callTime(id);
          expect(t.pool(CallPool.voice)!.minutes, 200);

          // The call takes both claims and ends after 5 minutes.
          final call = newCall();
          final g = await billing().grantCall(
            accountId: id,
            callId: call,
            role: CallRole.caller,
            pool: CallPool.voice,
          );
          expect(g.expiresAt, clock.now().add(const Duration(minutes: 200)));
          await billing().grantCall(
            accountId: bob.accountId,
            callId: call,
            role: CallRole.callee,
            pool: CallPool.voice,
          );
          clock.advance(const Duration(minutes: 5));
          await billing().callEnded(call);
          t = await billing().callTime(id);
          expect(t.pool(CallPool.voice)!.minutes, 195);
        },
      );
    });

    group('switching between voice and video', () {
      Future<(int, int)> left(TestDevice d) async {
        final t = await time(d);
        return (
          t.pool(CallPool.voice)!.minutes,
          t.pool(CallPool.video)!.minutes,
        );
      }

      Future<String> liveVoiceCall() async {
        final id = newCall();
        await turn(alice, id);
        await signal(id, CallSignalKind.offer, alice, bob);
        await turn(bob, id, role: CallRole.callee);
        return id;
      }

      test('settles the voice used and reserves video for the rest', () async {
        await plansOn();
        await claim(alice);
        final id = await liveVoiceCall();
        clock.advance(const Duration(minutes: 3, seconds: 10));

        final c = creds(await turn(alice, id, media: CallPool.video));
        expect(c.metered, isTrue);
        expect(c.urls, ['turn:main.example:3478']);
        expect(c.credential, _hmac('main-secret', c.username));
        expect(c.expiresAt, clock.now().add(const Duration(minutes: 30)));
        // Four started voice minutes are gone; the rest of voice is back.
        expect(await left(alice), (96, 0));

        // The other person asks for the same media and gets the new relay.
        final answer = creds(
          await turn(bob, id, role: CallRole.callee, media: CallPool.video),
        );
        expect(answer.urls, c.urls);
        expect(answer.expiresAt, c.expiresAt);

        // Ending the call settles the video part.
        clock.advance(const Duration(minutes: 2));
        await signal(id, CallSignalKind.end, bob, alice);
        expect(await left(alice), (96, 28));
      });

      test(
        'is refused when the other pool is empty, and nothing changes',
        () async {
          await plansOn();
          await claim(alice);
          // Spend all the video minutes on another call first.
          final other = newCall();
          await turn(alice, other, media: CallPool.video);
          final id = await liveVoiceCall();

          final r = await turn(alice, id, media: CallPool.video);
          expect(r.status, 422);
          expect(r.body, contains('video'));
          // The voice call is still on the voice relay and keeps its time.
          final again = creds(await turn(alice, id));
          expect(again.urls, ['turn:voice.example:3479']);
        },
      );

      test('can go back to voice, and the video used is only the started '
          'minutes', () async {
        await plansOn();
        await claim(alice);
        final id = newCall();
        await turn(alice, id, media: CallPool.video);
        await signal(id, CallSignalKind.offer, alice, bob);
        await turn(bob, id, role: CallRole.callee, media: CallPool.video);
        clock.advance(const Duration(minutes: 5));

        final c = creds(await turn(alice, id));
        expect(c.urls, ['turn:voice.example:3479']);
        expect(await left(alice), (0, 25));
        clock.advance(const Duration(minutes: 1));
        await signal(id, CallSignalKind.end, alice, bob);
        expect(await left(alice), (99, 25));
      });

      test('a Premium caller switches freely and nothing is recorded as '
          'spent', () async {
        await plansOn();
        await h.api.call(
          Routes.adminGrantPlan,
          params: {'account': alice.accountId},
          bearer: admin,
          body: const GrantPlanRequest(months: 1).toJson(),
        );
        final id = await liveVoiceCall();
        final c = creds(await turn(alice, id, media: CallPool.video));
        expect(c.metered, isFalse);
        expect(c.urls, ['turn:main.example:3478']);
      });
    });

    group('the operator', () {
      Future<TestResponse> grant(TestDevice d, Map<String, Object?> body) =>
          h.api.call(
            Routes.adminGrantCallTime,
            params: {'account': d.accountId},
            bearer: admin,
            body: body,
          );

      test(
        'sees an account\'s minutes and gives more, outside the caps',
        () async {
          await plansOn();
          await claim(alice);
          final r = await grant(
            alice,
            const GrantCallTimeRequest(
              voiceMinutes: 250,
              videoMinutes: 5,
              reason: 'ticket 9',
            ).toJson(),
          );
          expect(r.status, 204, reason: r.body);

          final seen = await h.api.call(
            Routes.adminAccountCallTime,
            params: {'account': alice.accountId},
            bearer: admin,
          );
          final t = CallTime.fromJson(seen.json);
          expect(t.pool(CallPool.voice)!.minutes, 350);
          expect(t.pool(CallPool.video)!.minutes, 35);
          // Gifts do not use up or block the daily claim.
          expect(t.canClaim, isFalse);
          expect((await time(alice)).pool(CallPool.voice)!.minutes, 350);
        },
      );

      test('a gift expires after three days like a claim', () async {
        await plansOn();
        await grant(
          alice,
          const GrantCallTimeRequest(
            voiceMinutes: 10,
            videoMinutes: 0,
            reason: 'x',
          ).toJson(),
        );
        clock.advance(const Duration(days: 4));
        final t = await billing().callTime(alice.accountId);
        expect(t.pool(CallPool.voice)!.minutes, 0);
      });

      test('needs a reason, a minute and a known account', () async {
        await plansOn();
        expect(
          (await grant(alice, {
            'voice_minutes': 0,
            'video_minutes': 0,
            'reason': 'x',
          })).status,
          400,
        );
        expect(
          (await grant(alice, {'voice_minutes': 5, 'reason': ''})).status,
          400,
        );
        expect(
          (await grant(alice, {'voice_minutes': 5000, 'reason': 'x'})).status,
          400,
        );
        final gone = await h.api.call(
          Routes.adminGrantCallTime,
          params: {'account': Uuid.v7()},
          bearer: admin,
          body: const GrantCallTimeRequest(
            voiceMinutes: 5,
            videoMinutes: 0,
            reason: 'x',
          ).toJson(),
        );
        expect(gone.status, 404);
      });

      test('is audited, and a device cannot use the routes', () async {
        await plansOn();
        await grant(
          alice,
          const GrantCallTimeRequest(
            voiceMinutes: 5,
            videoMinutes: 0,
            reason: 'audit me',
          ).toJson(),
        );
        final audit = await h.api.call(Routes.adminAudit, bearer: admin);
        expect(audit.body, contains('call_time.grant'));
        final denied = await h.api.call(
          Routes.adminAccountCallTime,
          params: {'account': alice.accountId},
          bearer: alice.bearer,
        );
        expect(denied.status, anyOf(401, 403));
      });
    });

    group('a group call', () {
      test('is paid once by whoever made the room, whoever joins', () async {
        await plansOn();
        await claim(alice);
        const room = 'room-abcdef123456';
        final first = newCall();
        final starter = creds(await turn(alice, first, room: room));
        expect(starter.metered, isTrue);

        // Carol has no call time of her own and offers to the others as a
        // later arrival: she rides the room.
        final second = newCall();
        final joined = creds(await turn(carol, second, room: room));
        expect(joined.metered, isTrue);
        expect(joined.expiresAt, starter.expiresAt);
        expect((await time(carol)).pool(CallPool.voice)!.minutes, 0);

        // Both legs end; the room settles a minute after the last one.
        await signal(first, CallSignalKind.offer, alice, bob);
        await turn(bob, first, role: CallRole.callee);
        clock.advance(const Duration(minutes: 2, seconds: 30));
        await signal(first, CallSignalKind.end, alice, bob);
        expect(
          (await billing().callTime(
            alice.accountId,
          )).pool(CallPool.voice)!.minutes,
          0,
          reason: 'still held: another leg may be going',
        );
        clock.advance(const Duration(minutes: 2));
        await billing().periodic
            .singleWhere((j) => j.name == 'billing.settle_calls')
            .run();
        expect(
          (await billing().callTime(
            alice.accountId,
          )).pool(CallPool.voice)!.minutes,
          100 - 3,
        );
      });

      test('a Premium starter pays nothing for Free members', () async {
        await plansOn();
        final dave = await h.registerGlobal('+8801711000004'); // trial
        const room = 'room-zyxwvu987654';
        await turn(dave, newCall(), room: room);
        final joined = creds(await turn(bob, newCall(), room: room));
        expect(joined.metered, isFalse);
      });
    });

    test('a deleted account takes its claims and calls with it', () async {
      await plansOn();
      await claim(alice);
      await turn(alice, newCall());
      await h.env.platform.db.tx(
        (tx) => h.identity.api.deleteAccount(tx, alice.accountId),
      );
      final schema = h.env.platform.schemas.of('billing');
      final left = await h.env.platform.db.queryOne(
        'SELECT (SELECT count(*) FROM $schema.call_claims) AS c, '
        '(SELECT count(*) FROM $schema.call_reservations) AS r, '
        '(SELECT count(*) FROM $schema.call_reservation_calls) AS m',
      );
      expect(left!.integer('c'), 0);
      expect(left.integer('r'), 0);
      expect(left.integer('m'), 0);
    });
  });
}
