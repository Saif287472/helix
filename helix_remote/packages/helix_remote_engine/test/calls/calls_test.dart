import 'dart:async';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_engine/src/calls/call_log_mirror.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../support/fake_call_network.dart';
import '../support/peers.dart';

/// The call state machine against an in-memory network: two or three
/// devices, real database, fake media. The sealing and the real server are
/// covered by `server/test/client/engine/calls_test.dart`.
void main() {
  late TestClock clock;
  late FakeCallNetwork net;

  setUp(() {
    clock = TestClock();
    net = FakeCallNetwork(clock);
  });
  tearDown(() => net.dispose());

  /// Alice calls Bob and Bob accepts; both end up live.
  Future<String> connect(CallDevice alice, CallDevice bob) async {
    final call = await alice.service.startCall(bob.account);
    await bob.until(() => bob.current?.phase == CallPhase.ringing);
    await bob.service.accept();
    await alice.untilPhase(CallPhase.active);
    await bob.untilPhase(CallPhase.active);
    return call.callId;
  }

  group('a call between two devices', () {
    test('rings, is answered, carries candidates and hangs up', () async {
      final alice = await net.add('alice');
      final bob = await net.add('bob');
      alice.startWatching();
      bob.startWatching();

      final started = await alice.service.startCall(bob.account, video: true);
      expect(started.direction, CallDirection.outgoing);
      expect(started.video, isTrue);
      await bob.until(() => bob.current?.phase == CallPhase.ringing);
      expect(bob.current!.isIncoming, isTrue);
      expect(bob.current!.video, isTrue);
      expect(bob.current!.peer, alice.account);
      expect(bob.events.whereType<IncomingCallEvent>(), hasLength(1));
      // Bob's device tells Alice it is ringing.
      await alice.untilPhase(CallPhase.ringing);
      expect((await bob.logRow(started.callId))!.state, 'ringing');

      await bob.service.accept();
      await alice.untilPhase(CallPhase.active);
      await bob.untilPhase(CallPhase.active);
      // The answer went to Alice's device only, with Bob's SDP.
      expect(net.received(alice, CallSignalType.answer), hasLength(1));
      // Media: the offer and answer crossed, and the candidates each side
      // gathered reached the other.
      final aliceMedia = alice.media!.last;
      final bobMedia = bob.media!.last;
      expect(aliceMedia.localSdp, 'alice-offer-0');
      expect(bobMedia.remoteSdp, 'alice-offer-0');
      expect(aliceMedia.remoteSdp, 'bob-answer-0');
      await alice.until(() => aliceMedia.remoteCandidates.length == 2);
      await bob.until(() => bobMedia.remoteCandidates.length == 2);
      expect(bobMedia.config.video, isTrue);

      // Mute and camera go to the media and show in the snapshot.
      await alice.service.setMuted(muted: true);
      expect(aliceMedia.muted, isTrue);
      expect(alice.current!.muted, isTrue);
      await alice.service.setCameraEnabled(enabled: false);
      expect(aliceMedia.videoEnabled, isFalse);

      await alice.service.hangUp();
      await bob.until(() => bob.current == null);
      expect(alice.current, isNull);
      expect(aliceMedia.closed, isTrue);
      expect(bobMedia.closed, isTrue);

      // The log on both sides, with the times of the answer.
      final aliceRow = (await alice.logRow(started.callId))!;
      expect(
        [aliceRow.direction, aliceRow.state, aliceRow.video],
        ['outgoing', 'ended', true],
      );
      expect(aliceRow.answeredAt, isNotNull);
      expect(aliceRow.endedAt, isNotNull);
      final bobRow = (await bob.logRow(started.callId))!;
      expect([bobRow.direction, bobRow.state], ['incoming', 'ended']);
      expect(CallsDao.wasMissed(bobRow), isFalse);

      // The caller's device posts one chat entry with the outcome; the
      // callee's does not.
      expect(alice.posted, hasLength(1));
      final (peer, body) = alice.posted.single;
      expect(peer, bob.account);
      expect(body.callId, started.callId);
      expect(body.outcome, CallOutcome.answered);
      expect(body.media, CallMedia.video);
      expect(body.durationS, isNotNull);
      expect(bob.posted, isEmpty);

      // What the UI stream showed: phases in order, then ended, then null.
      expect(
        [for (final s in bob.shown) s?.phase],
        [
          null,
          CallPhase.ringing,
          CallPhase.connecting,
          CallPhase.active,
          CallPhase.ended,
          null,
        ],
      );
      expect(bob.shown[4]!.end, CallEnd.remoteHungUp);
      expect(
        alice.shown.where((s) => s?.end != null).single!.end,
        CallEnd.hungUp,
      );
    });

    test('the callee can hang up too', () async {
      final alice = await net.add('alice');
      final bob = await net.add('bob');
      alice.startWatching();
      final id = await connect(alice, bob);
      await bob.service.hangUp();
      await alice.until(() => alice.current == null);
      expect((await alice.logRow(id))!.state, 'ended');
      expect((await bob.logRow(id))!.state, 'ended');
      expect(
        alice.shown.where((s) => s?.end != null).single!.end,
        CallEnd.remoteHungUp,
      );
      // Still the caller's device that writes the chat entry.
      await alice.until(() => alice.posted.isNotEmpty);
      expect(alice.posted.single.$2.outcome, CallOutcome.answered);
      expect(bob.posted, isEmpty);
    });

    test('declined: both sides know, everywhere else stops ringing', () async {
      final alice = await net.add('alice');
      final bob = await net.add('bob');
      final call = await alice.service.startCall(bob.account);
      await bob.until(() => bob.current?.phase == CallPhase.ringing);
      await bob.service.decline();
      await alice.until(() => alice.current == null);
      expect(bob.current, isNull);
      expect(bob.stateCalls, [(call.callId, CallState.declined)]);
      final aliceRow = (await alice.logRow(call.callId))!;
      expect([aliceRow.direction, aliceRow.state], ['outgoing', 'declined']);
      final bobRow = (await bob.logRow(call.callId))!;
      expect([bobRow.direction, bobRow.state], ['incoming', 'declined']);
      expect(alice.posted.single.$2.outcome, CallOutcome.declined);
      // A call the user declined is not a missed call.
      expect(bob.events.whereType<MissedCallEvent>(), isEmpty);
    });

    test('cancelled before an answer: a missed call for the callee', () async {
      final alice = await net.add('alice');
      final bob = await net.add('bob');
      final call = await alice.service.startCall(bob.account);
      await bob.until(() => bob.current?.phase == CallPhase.ringing);
      await alice.service.hangUp();
      await bob.until(() => bob.current == null);
      final bobRow = (await bob.logRow(call.callId))!;
      expect([bobRow.direction, bobRow.state], ['missed', 'missed']);
      expect(CallsDao.wasMissed(bobRow), isTrue);
      final notice = bob.events.whereType<MissedCallEvent>().single.notice;
      expect(notice.kind, MessageKinds.missedCall);
      expect(notice.sender, alice.account);
      expect(notice.conversationId, 'direct:${alice.account}');
      expect(notice.messageId, call.callId);
      final aliceRow = (await alice.logRow(call.callId))!;
      expect([aliceRow.direction, aliceRow.state], ['outgoing', 'cancelled']);
      expect(alice.posted.single.$2.outcome, CallOutcome.missed);
    });

    test(
      'nobody answers: the caller gives up and the callee misses it',
      () async {
        final fast = const CallConfig(
          ringTimeout: Duration(milliseconds: 150),
          iceBatchDelay: Duration.zero,
          signalTimeout: Duration(seconds: 2),
        );
        final alice = await net.add('alice', config: fast);
        final bob = await net.add('bob', config: fast);
        final call = await alice.service.startCall(bob.account);
        await alice.until(() => alice.current == null);
        await bob.until(() => bob.current == null);
        final aliceRow = (await alice.logRow(call.callId))!;
        expect(
          [aliceRow.direction, aliceRow.state],
          ['outgoing', 'unanswered'],
        );
        final bobRow = (await bob.logRow(call.callId))!;
        expect(bobRow.state, 'missed');
        expect(bob.events.whereType<MissedCallEvent>(), hasLength(1));
        expect(alice.posted.single.$2.outcome, CallOutcome.missed);
        // Alice cancelled the offer on the way out.
        expect(
          net.received(bob, CallSignalType.end).single.reason,
          CallEndReason.cancelled,
        );
      },
    );

    test('media that never connects fails the call on both sides', () async {
      final fast = const CallConfig(
        connectTimeout: Duration(milliseconds: 150),
        iceBatchDelay: Duration.zero,
        signalTimeout: Duration(seconds: 2),
      );
      final alice = await net.add('alice', config: fast);
      final bob = await net.add('bob', config: fast);
      bob.media!.autoConnect = false;
      alice.media!.autoConnect = false;
      final call = await alice.service.startCall(bob.account);
      await bob.until(() => bob.current?.phase == CallPhase.ringing);
      await bob.service.accept();
      await alice.until(() => alice.current == null);
      await bob.until(() => bob.current == null);
      expect((await alice.logRow(call.callId))!.state, 'failed');
      expect((await bob.logRow(call.callId))!.state, 'failed');
      expect(alice.posted.single.$2.outcome, CallOutcome.failed);
    });

    test('a connection that breaks mid-call ends it as failed', () async {
      final alice = await net.add('alice');
      final bob = await net.add('bob');
      final id = await connect(alice, bob);
      alice.media!.last.fail();
      await alice.until(() => alice.current == null);
      await bob.until(() => bob.current == null);
      expect((await alice.logRow(id))!.state, 'failed');
      expect((await bob.logRow(id))!.state, 'failed');
      // It was answered, so it still counts as talked.
      expect((await alice.logRow(id))!.answeredAt, isNotNull);
    });
  });

  group('several devices', () {
    test('one callee device answers, the other stops; ICE goes to the '
        'answering device only', () async {
      final alice = await net.add('alice');
      final bob1 = await net.add('bob1', account: 'account-bob');
      final bob2 = await net.add('bob2', account: 'account-bob');
      final call = await alice.service.startCall('account-bob');
      await bob1.until(() => bob1.current?.phase == CallPhase.ringing);
      await bob2.until(() => bob2.current?.phase == CallPhase.ringing);

      await bob2.service.accept();
      await alice.untilPhase(CallPhase.active);
      await bob2.untilPhase(CallPhase.active);
      // The sibling stopped ringing and logs the call as answered elsewhere
      // (not as missed).
      await bob1.until(() => bob1.current == null);
      final row = await bob1.untilLogged(call.callId, 'answered_elsewhere');
      expect(row.direction, 'incoming');
      expect(CallsDao.wasMissed(row), isFalse);
      expect(bob1.events.whereType<MissedCallEvent>(), isEmpty);
      expect(bob2.stateCalls, [(call.callId, CallState.answered)]);

      await alice.until(() => alice.media!.last.remoteCandidates.length == 2);
      expect(net.received(bob2, CallSignalType.ice), isNotEmpty);
      expect(net.received(bob1, CallSignalType.ice), isEmpty);
      expect(bob1.media!.sessions, isEmpty);
    });

    test('two devices answer at once: the first answer wins and the second '
        'is told', () async {
      final alice = await net.add('alice');
      final bob1 = await net.add('bob1', account: 'account-bob');
      final bob2 = await net.add('bob2', account: 'account-bob');
      final call = await alice.service.startCall('account-bob');
      await bob1.until(() => bob1.current?.phase == CallPhase.ringing);
      await bob2.until(() => bob2.current?.phase == CallPhase.ringing);

      await Future.wait([bob1.service.accept(), bob2.service.accept()]);
      await alice.untilPhase(CallPhase.active);
      // Exactly one of them keeps the call.
      await Future.wait([
        bob1.until(() => bob1.current == null || bob2.current == null),
      ]);
      final live = [bob1, bob2].where((d) => d.current != null).toList();
      expect(live, hasLength(1));
      final lost = live.single == bob1 ? bob2 : bob1;
      final row = await lost.untilLogged(call.callId, 'answered_elsewhere');
      expect(row.direction, 'incoming');
      expect(alice.current!.phase, CallPhase.active);
    });

    test('the other devices of the caller never see the call', () async {
      final alice1 = await net.add('alice1', account: 'account-alice');
      final alice2 = await net.add('alice2', account: 'account-alice');
      final bob = await net.add('bob');
      await connect(alice1, bob);
      expect(alice2.current, isNull);
      expect(await alice2.db.callsDao.recent(), isEmpty);
    });
  });

  group('glare, busy and blocks', () {
    test('two calls at once: the smaller id survives on both ends', () async {
      final alice = await net.add('alice');
      final bob = await net.add('bob');
      final results = await Future.wait([
        alice.service.startCall(bob.account),
        bob.service.startCall(alice.account),
      ]);
      final winner = results
          .map((r) => r.callId)
          .reduce((a, b) => a.compareTo(b) < 0 ? a : b);
      // The winner's callee rings; the other call is gone without a trace.
      final callee = results[0].callId == winner ? bob : alice;
      final caller = callee == bob ? alice : bob;
      await callee.until(
        () => callee.current?.callId == winner && callee.current!.isIncoming,
        reason: 'the surviving call rings',
      );
      await caller.until(() => caller.current?.callId == winner);
      await callee.service.accept();
      await caller.untilPhase(CallPhase.active);
      await callee.untilPhase(CallPhase.active);
      final loser = results.firstWhere((r) => r.callId != winner).callId;
      for (final d in [alice, bob]) {
        expect(await d.logRow(loser), isNull, reason: '${d.name} forgot it');
        expect(d.current!.callId, winner);
      }
      expect(alice.posted.where((p) => p.$2.callId == loser), isEmpty);
      expect(bob.posted.where((p) => p.$2.callId == loser), isEmpty);
    });

    test('a device in a call answers another caller with busy', () async {
      final alice = await net.add('alice');
      final bob = await net.add('bob');
      final carol = await net.add('carol');
      final first = await connect(alice, bob);
      final second = await carol.service.startCall(bob.account);
      await carol.until(() => carol.current == null);
      expect(
        net.received(carol, CallSignalType.end).single.reason,
        CallEndReason.busy,
      );
      expect(carol.shown, isEmpty); // Never watched; the log tells it.
      expect((await carol.logRow(second.callId))!.state, 'unanswered');
      // Bob logs the missed call (and says so), while the first call lives.
      final bobRow = await bob.untilLogged(second.callId, 'missed');
      expect(bobRow.direction, 'missed');
      expect(bob.events.whereType<MissedCallEvent>(), hasLength(1));
      expect(bob.current!.callId, first);
      expect(bob.current!.phase, CallPhase.active);
      expect(carol.posted.single.$2.outcome, CallOutcome.missed);
    });

    test('a caller the callee blocked rings into the void', () async {
      final fast = const CallConfig(
        ringTimeout: Duration(milliseconds: 150),
        iceBatchDelay: Duration.zero,
        signalTimeout: Duration(seconds: 2),
      );
      final alice = await net.add('alice', config: fast);
      final bob = await net.add('bob');
      net.blocks.add((bob.account, alice.account));
      final call = await alice.service.startCall(bob.account);
      // Alice learns nothing: the call looks exactly like an unanswered one.
      expect(alice.current!.phase, CallPhase.calling);
      await alice.until(() => alice.current == null);
      expect((await alice.logRow(call.callId))!.state, 'unanswered');
      expect(bob.current, isNull);
      expect(await bob.db.callsDao.recent(), isEmpty);
      expect(bob.events, isEmpty);
    });

    test(
      'calling someone you blocked is refused; their offer is dropped',
      () async {
        final alice = await net.add('alice');
        final bob = await net.add('bob');
        Future<void> block(CallDevice d, String who) =>
            d.db.peopleDao.upsertPerson(
              PeopleCompanion.insert(
                accountId: who,
                updatedAt: clock.now,
                blocked: const Value(true),
              ),
            );
        await block(alice, bob.account);
        await expectLater(
          alice.service.startCall(bob.account),
          throwsA(
            isA<CallFailedException>().having(
              (e) => e.reason,
              'reason',
              CallFailure.blocked,
            ),
          ),
        );
        expect(alice.current, isNull);
        expect(await alice.db.callsDao.recent(), isEmpty);

        // Bob calls Alice, whose own list still blocks Bob (the server has not
        // filtered it): no ring, no row.
        await bob.service.startCall(alice.account);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(alice.current, isNull);
        expect(await alice.db.callsDao.recent(), isEmpty);
        expect(alice.events, isEmpty);
      },
    );
  });

  group('offline callee and pending calls', () {
    test(
      'a woken device sees who is calling, then rings and answers',
      () async {
        final alice = await net.add('alice');
        final bob = await net.add('bob', online: false);
        final call = await alice.service.startCall(bob.account);
        expect(net.log.where((l) => l.$2 == bob.device), hasLength(1));

        // The headless look: who is calling, nothing changes.
        final peeked = await bob.service.peekPending();
        expect(peeked.single.callId, call.callId);
        expect(peeked.single.caller, alice.account);
        expect(bob.current, isNull);
        expect(await bob.db.callsDao.recent(), isEmpty);

        // The app opens: the offer rings.
        bob.online = true;
        expect(await bob.service.fetchPending(), 1);
        expect(bob.current!.phase, CallPhase.ringing);
        expect(bob.current!.video, isFalse);
        expect(bob.events.whereType<IncomingCallEvent>(), hasLength(1));
        // Asking again does not ring twice.
        expect(await bob.service.fetchPending(), 0);
        expect((await bob.service.peekPending()), isEmpty);

        await bob.service.accept();
        await alice.untilPhase(CallPhase.active);
        await bob.untilPhase(CallPhase.active);
      },
    );

    test('an offer that expired is never rung', () async {
      final alice = await net.add('alice');
      final bob = await net.add('bob', online: false);
      await alice.service.startCall(bob.account);
      clock.advance(const Duration(minutes: 5));
      expect(await bob.service.peekPending(), isEmpty);
      expect(await bob.service.fetchPending(), 0);
      expect(bob.current, isNull);
    });

    test(
      'the caller hangs up before the callee wakes: nothing to ring',
      () async {
        final alice = await net.add('alice');
        final bob = await net.add('bob', online: false);
        await alice.service.startCall(bob.account);
        await alice.service.hangUp();
        expect(await bob.service.peekPending(), isEmpty);
        expect(await bob.service.fetchPending(), 0);
      },
    );

    test('a pending offer from a blocked caller is left alone', () async {
      final alice = await net.add('alice');
      final bob = await net.add('bob', online: false);
      await bob.db.peopleDao.upsertPerson(
        PeopleCompanion.insert(
          accountId: alice.account,
          updatedAt: clock.now,
          blocked: const Value(true),
        ),
      );
      await alice.service.startCall(bob.account);
      expect(await bob.service.peekPending(), isEmpty);
      expect(await bob.service.fetchPending(), 0);
    });
  });

  group('failures and edges', () {
    test('without a media factory a call cannot be placed or answered, but '
        'it still rings and can be declined', () async {
      final alice = await net.add('alice');
      final bob = await net.add('bob', media: false);
      await expectLater(
        bob.service.startCall(alice.account),
        throwsA(
          isA<CallFailedException>().having(
            (e) => e.reason,
            'reason',
            CallFailure.noMedia,
          ),
        ),
      );
      await alice.service.startCall(bob.account);
      await bob.until(() => bob.current?.phase == CallPhase.ringing);
      await expectLater(
        bob.service.accept(),
        throwsA(isA<CallFailedException>()),
      );
      expect(bob.current!.phase, CallPhase.ringing);
      await bob.service.decline();
      await alice.until(() => alice.current == null);
    });

    test(
      'a refused microphone ends the call as failed on both sides',
      () async {
        final alice = await net.add('alice');
        final bob = await net.add('bob');
        final call = await alice.service.startCall(bob.account);
        await bob.until(() => bob.current?.phase == CallPhase.ringing);
        bob.media!.failCreate = true;
        await expectLater(
          bob.service.accept(),
          throwsA(isA<CallFailedException>()),
        );
        await alice.until(() => alice.current == null);
        expect((await bob.logRow(call.callId))!.state, 'failed');
        expect((await alice.logRow(call.callId))!.state, 'failed');
      },
    );

    test(
      'the server refusing offers (rate limit) fails the call cleanly',
      () async {
        final alice = await net.add('alice');
        final bob = await net.add('bob');
        alice.failSends = const ApiException(
          status: 429,
          code: ErrorCode.rateLimited,
        );
        await expectLater(
          alice.service.startCall(bob.account),
          throwsA(
            isA<CallFailedException>().having(
              (e) => e.reason,
              'reason',
              CallFailure.rateLimited,
            ),
          ),
        );
        expect(alice.current, isNull);
        expect(alice.media!.last.closed, isTrue);
        expect(alice.posted, isEmpty, reason: 'the peer never heard of it');
        alice.failSends = null;
        await alice.service.startCall(bob.account); // The next one works.
      },
    );

    test('an offline network on hang-up still ends the call locally', () async {
      final alice = await net.add('alice');
      final bob = await net.add('bob');
      await connect(alice, bob);
      alice.failSends = StateError('offline');
      await alice.service.hangUp();
      expect(alice.current, isNull);
    });

    test('only one call at a time', () async {
      final alice = await net.add('alice');
      final bob = await net.add('bob');
      final carol = await net.add('carol');
      await alice.service.startCall(bob.account);
      await expectLater(
        alice.service.startCall(carol.account),
        throwsA(
          isA<CallFailedException>().having(
            (e) => e.reason,
            'reason',
            CallFailure.busy,
          ),
        ),
      );
    });

    test(
      'signals from the wrong device, account or call are ignored',
      () async {
        final alice = await net.add('alice');
        final bob = await net.add('bob');
        final mallory = await net.add('mallory');
        final id = await connect(alice, bob);

        Future<void> forge(
          CallDevice to,
          String account,
          String device,
          CallSignalPayload p,
        ) => to.service.onSignal(account, device, p);

        CallSignalPayload end(String callId) => CallSignalPayload(
          type: CallSignalType.end,
          callId: callId,
          reason: CallEndReason.hangup,
        );
        await forge(bob, mallory.account, mallory.device, end(id));
        await forge(bob, alice.account, 'another-device', end(id));
        await forge(bob, alice.account, alice.device, end('other-call'));
        await forge(
          bob,
          alice.account,
          alice.device,
          CallSignalPayload(
            type: CallSignalType.ice,
            callId: id,
            candidates: [const IceCandidatePayload(candidate: 'x')],
          ),
        ).catchError((Object _) {}); // Harmless: a candidate for the live call.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(bob.current!.phase, CallPhase.active);
        expect(alice.current!.phase, CallPhase.active);

        // The server's "answered elsewhere" notice only affects a ringing call.
        bob.service.onEndedElsewhere(id, CallState.answered);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(bob.current!.phase, CallPhase.active);
      },
    );

    test('release() hangs up, and a crash leftover is cleaned', () async {
      final alice = await net.add('alice');
      final bob = await net.add('bob');
      final id = await connect(alice, bob);
      await alice.service.release();
      await bob.until(() => bob.current == null);
      expect((await bob.logRow(id))!.state, 'ended');

      // A row left ringing by a kill is marked failed on the next start.
      await bob.db.callsDao.start(
        CallLogCompanion.insert(
          callId: 'stale-call',
          peerAccountId: alice.account,
          kind: 'direct',
          direction: 'incoming',
          state: 'ringing',
          startedAt: clock.now,
        ),
      );
      await bob.service.recoverUnfinished();
      expect((await bob.logRow('stale-call'))!.state, 'failed');
    });

    test(
      'TURN credentials reach the media as relay servers, never printed',
      () async {
        final alice = await net.add('alice');
        final bob = await net.add('bob');
        alice.turn = TurnCredentials(
          urls: const ['turn:turn.example:3478'],
          username: '1767225600:acct',
          credential: 'secret-credential',
          expiresAt: clock.now.add(const Duration(hours: 1)),
        );
        await alice.service.startCall(bob.account);
        final servers = alice.media!.last.config.iceServers;
        expect(servers.single.urls, ['turn:turn.example:3478']);
        expect(servers.single.credential, 'secret-credential');
        expect(servers.single.toString(), isNot(contains('secret')));
        // Bob's server has none configured: a direct connection is tried.
        await bob.until(() => bob.current != null);
        await bob.service.accept();
        expect(bob.media!.last.config.iceServers, isEmpty);
      },
    );
  });

  group('the call log on other devices', () {
    Future<CallLogRow?> mirror(
      CallDevice d,
      CallOutcome outcome, {
      required bool fromSelf,
      int? seconds,
    }) async {
      final created = await CallLogMirror.record(
        d.db,
        peer: 'peer',
        fromSelf: fromSelf,
        body: CallLogBody(
          callId: 'c-$outcome-$fromSelf',
          media: CallMedia.audio,
          outcome: outcome,
          durationS: seconds,
        ),
        sentAt: clock.now,
      );
      if (!created) return null;
      return d.logRow('c-$outcome-$fromSelf');
    }

    test(
      'a call this device never saw is learned from the chat entry',
      () async {
        final device = await net.add('d');
        final answered = await mirror(
          device,
          CallOutcome.answered,
          fromSelf: false,
          seconds: 90,
        );
        expect(
          [answered!.direction, answered.state],
          ['incoming', 'answered_elsewhere'],
        );
        expect(CallsDao.durationSeconds(answered), 90);
        expect(CallsDao.wasMissed(answered), isFalse);
        final missed = await mirror(
          device,
          CallOutcome.missed,
          fromSelf: false,
        );
        expect(CallsDao.wasMissed(missed!), isTrue);
        final mine = await mirror(device, CallOutcome.missed, fromSelf: true);
        expect([mine!.direction, mine.state], ['outgoing', 'unanswered']);
        expect(
          await mirror(device, CallOutcome.unknown, fromSelf: false),
          isNull,
        );
      },
    );

    test('a call this device logged itself is left alone', () async {
      final alice = await net.add('alice');
      final bob = await net.add('bob');
      final id = await connect(alice, bob);
      await bob.service.hangUp();
      await bob.until(() => bob.current == null);
      final before = (await bob.logRow(id))!;
      final created = await CallLogMirror.record(
        bob.db,
        peer: alice.account,
        fromSelf: false,
        body: CallLogBody(
          callId: id,
          media: CallMedia.audio,
          outcome: CallOutcome.missed,
        ),
        sentAt: clock.now,
      );
      expect(created, isFalse);
      expect((await bob.logRow(id))!.state, before.state);
    });
  });
}
