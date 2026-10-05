import 'dart:async';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_engine/testing.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../../support/flows.dart';
import '../../support/harness.dart';
import '../../support/test_database.dart';
import 'support.dart';

/// 1:1 calls through the real in-process server: sealed signals between real
/// engines (fake media), ringing and answering across a person's devices,
/// hang-ups, pending calls for a device that was offline, the call log, and
/// blocks.
void main() {
  group('engine calls', skip: databaseTestSkipReason, () {
    late Harness h;
    late EngineWorld world;

    setUp(() async {
      h = await Harness.start(
        extra: {
          'HELIX_TURN_URLS': 'turn:turn.helix.test:3478',
          'HELIX_TURN_SECRET': 'turn-secret-for-tests',
        },
      );
      world = EngineWorld(h);
    });
    tearDown(() async {
      await world.dispose();
      await h.stop();
    });

    /// Gives [user] a fake media factory and returns it.
    FakeCallMediaFactory media(EngineUser user) {
      final factory = FakeCallMediaFactory(label: user.name);
      user.engine.calls.mediaFactory = factory;
      return factory;
    }

    Future<CallSnapshot> waitForCall(
      EngineUser user,
      bool Function(CallSnapshot call) test, {
      String? reason,
    }) async {
      CallSnapshot? found;
      await settle(() async {
        final call = user.engine.calls.current;
        expect(call, isNotNull, reason: '${user.name} has no call');
        expect(test(call!), isTrue, reason: reason ?? '${user.name}: $call');
        found = call;
      });
      return found!;
    }

    Future<void> waitForNoCall(EngineUser user) => settle(
      () async => expect(
        user.engine.calls.current,
        isNull,
        reason: '${user.name} is still in a call',
      ),
    );

    Future<CallLogRow> logOf(
      EngineUser user,
      String callId, {
      String? state,
    }) async {
      late CallLogRow row;
      await settle(() async {
        final found = await user.db.callsDao.byId(callId);
        expect(found, isNotNull, reason: '${user.name} has no log of $callId');
        if (state != null) expect(found!.state, state);
        row = found!;
      });
      return row;
    }

    CallLogBody callBody(MessageRow row) =>
        CallLogBody.fromJson(JsonReader.decode(row.payload!));

    Future<List<MessageRow>> callEntries(
      EngineUser user,
      EngineUser peer,
    ) async => [
      for (final m in await messagesWith(user, peer))
        if (m.kind == 'call_log') m,
    ];

    test('two callee devices ring, one answers, the other stops; ICE goes to '
        'the answering device; the call log is on every side', () async {
      final alice = await world.register('alice', aliceNumber);
      final bob1 = await world.register('bob1', bobNumber);
      final aliceMedia = media(alice);
      media(bob1);

      // Alice knows only bob1 when bob2 appears: the offer first meets
      // `device_list_stale` and is repaired before it rings anyone.
      final chat = await alice.engine.chats.openDirect(bob1.account);
      await alice.engine.chats.sendText(chat.id, 'hi');
      await waitForText(bob1, alice, 'hi');
      final bob2 = await world.link(bob1, 'bob2');
      final bob2Media = media(bob2);
      final bob1Media = bob1.engine.calls.mediaFactory! as FakeCallMediaFactory;
      expect((await alice.db.peopleDao.devicesOf(bob1.account)).length, 1);

      final started = await alice.engine.calls.startCall(
        bob1.account,
        video: true,
      );
      expect(started.phase, CallPhase.calling);
      final ring1 = await waitForCall(
        bob1,
        (c) => c.phase == CallPhase.ringing,
      );
      await waitForCall(bob2, (c) => c.phase == CallPhase.ringing);
      expect(ring1.callId, started.callId);
      expect(ring1.peer, alice.account);
      expect(ring1.video, isTrue);
      // The caller learns a device is ringing.
      await waitForCall(alice, (c) => c.phase == CallPhase.ringing);
      expect((await alice.db.peopleDao.devicesOf(bob1.account)).length, 2);
      // TURN credentials from the real server reached the media session.
      final servers = aliceMedia.last.config.iceServers;
      expect(servers.single.urls, ['turn:turn.helix.test:3478']);
      expect(servers.single.username, matches(RegExp(r'^\d+:[A-Za-z0-9_-]+$')));
      expect(
        servers.single.username,
        isNot(contains(alice.account)),
        reason: 'the TURN name crosses the network in the clear',
      );
      expect(servers.single.credential, isNotEmpty);

      await bob2.engine.calls.accept();
      await waitForCall(alice, (c) => c.phase == CallPhase.active);
      await waitForCall(bob2, (c) => c.phase == CallPhase.active);
      // The other device stopped ringing and logged "answered elsewhere";
      // it is not a missed call.
      await waitForNoCall(bob1);
      final elsewhere = await logOf(
        bob1,
        started.callId,
        state: 'answered_elsewhere',
      );
      expect(CallsDao.wasMissed(elsewhere), isFalse);
      // ICE reached the answering device and nobody else.
      await settle(() async {
        expect(bob2Media.last.remoteCandidates, hasLength(2));
        expect(aliceMedia.last.remoteCandidates, hasLength(2));
      });
      expect(bob1Media.sessions, isEmpty);
      expect(bob2Media.last.remoteSdp, aliceMedia.last.localSdp);
      expect(aliceMedia.last.remoteSdp, bob2Media.last.localSdp);

      await alice.engine.calls.hangUp();
      await waitForNoCall(bob2);
      await waitForNoCall(alice);

      // The log of both sides, from the same call id.
      final aliceRow = await logOf(alice, started.callId, state: 'ended');
      expect([aliceRow.direction, aliceRow.video], ['outgoing', true]);
      expect(aliceRow.answeredAt, isNotNull);
      final bobRow = await logOf(bob2, started.callId, state: 'ended');
      expect(bobRow.direction, 'incoming');
      expect(bobRow.peerAccountId, alice.account);
      expect(CallsDao.durationSeconds(bobRow), isNotNull);

      // The caller posted one chat entry; every device of Bob and Alice
      // shows the call in the chat, with the same outcome.
      for (final (user, peer) in [
        (alice, bob1),
        (bob1, alice),
        (bob2, alice),
      ]) {
        late List<MessageRow> entries;
        await settle(() async {
          entries = await callEntries(user, peer);
          expect(entries, hasLength(1), reason: '${user.name}: call entry');
        });
        final body = callBody(entries.single);
        expect(body.callId, started.callId);
        expect(body.outcome, CallOutcome.answered);
        expect(body.media, CallMedia.video);
      }
      // A device that only saw the chat entry would write the same log row;
      // a device that saw the call keeps its own (no second alert).
      expect(
        (await bob1.db.callsDao.byId(started.callId))!.state,
        'answered_elsewhere',
      );
      expect(bob1.engine.calls.current, isNull);
    });

    test('hang-up from either side, and a decline', () async {
      final alice = await world.register('alice', aliceNumber);
      final bob = await world.register('bob', bobNumber);
      media(alice);
      media(bob);

      // The callee hangs up.
      final first = await alice.engine.calls.startCall(bob.account);
      await waitForCall(bob, (c) => c.phase == CallPhase.ringing);
      await bob.engine.calls.accept();
      await waitForCall(alice, (c) => c.phase == CallPhase.active);
      await waitForCall(bob, (c) => c.phase == CallPhase.active);
      final ended = alice.engine.calls.watchCurrent().firstWhere(
        (c) => c?.phase == CallPhase.ended,
      );
      await bob.engine.calls.hangUp();
      expect((await ended)!.end, CallEnd.remoteHungUp);
      await waitForNoCall(bob);
      await logOf(alice, first.callId, state: 'ended');
      await logOf(bob, first.callId, state: 'ended');

      // The caller hangs up.
      final second = await alice.engine.calls.startCall(
        bob.account,
        video: false,
      );
      await waitForCall(bob, (c) => c.callId == second.callId);
      await bob.engine.calls.accept();
      await waitForCall(alice, (c) => c.phase == CallPhase.active);
      await waitForCall(bob, (c) => c.phase == CallPhase.active);
      await alice.engine.calls.hangUp();
      await waitForNoCall(bob);
      await logOf(bob, second.callId, state: 'ended');

      // The callee declines.
      final third = await alice.engine.calls.startCall(bob.account);
      await waitForCall(bob, (c) => c.callId == third.callId);
      await bob.engine.calls.decline();
      await waitForNoCall(alice);
      final declined = await logOf(alice, third.callId, state: 'declined');
      expect(declined.direction, 'outgoing');
      final mine = await logOf(bob, third.callId, state: 'declined');
      expect(mine.direction, 'incoming');

      // Alice's chat shows all three calls with their outcomes, and so does
      // Bob's.
      for (final (user, peer) in [(alice, bob), (bob, alice)]) {
        await settle(() async {
          final bodies = [
            for (final m in await callEntries(user, peer)) callBody(m),
          ];
          expect(
            {for (final b in bodies) b.callId: b.outcome},
            {
              first.callId: CallOutcome.answered,
              second.callId: CallOutcome.answered,
              third.callId: CallOutcome.declined,
            },
            reason: '${user.name}\'s chat entries',
          );
        });
      }
      // The call log is newest first, on both sides.
      final aliceLog = await alice.engine.calls.log();
      expect(
        [for (final r in aliceLog) r.callId],
        [third.callId, second.callId, first.callId],
      );
    });

    test('an offline callee: the offer waits, a headless run names the '
        'caller, the foreground app rings it on connect', () async {
      final alice = await world.register('alice', aliceNumber);
      final bob = await world.register('bob', bobNumber, realtime: false);
      await bob.engine.stop();
      media(alice);
      media(bob);
      // Alice and Bob have met, so Bob's device knows Alice.
      final chat = await alice.engine.chats.openDirect(bob.account);
      await alice.engine.chats.sendText(chat.id, 'ping');
      await bob.engine.syncOnce();

      final started = await alice.engine.calls.startCall(bob.account);
      expect(started.phase, CallPhase.calling);

      // The FCM isolate: sync, then see who is calling without opening it.
      final summary = await bob.engine.syncOnce();
      expect(summary.pendingCalls, hasLength(1));
      expect(summary.pendingCalls.single.callId, started.callId);
      expect(summary.pendingCalls.single.caller, alice.account);
      expect(
        summary.pendingCalls.single.expiresAt.isAfter(DateTime.now()),
        isTrue,
      );
      expect(bob.engine.calls.current, isNull);
      expect(await bob.db.callsDao.recent(), isEmpty);

      // The app opens: connecting the socket rings the pending offer by
      // itself, and the call goes on.
      await bob.engine.start();
      final ring = await waitForCall(bob, (c) => c.phase == CallPhase.ringing);
      expect(ring.callId, started.callId);
      expect(ring.video, isFalse);
      expect(await bob.engine.calls.fetchPending(), 0, reason: 'rings once');
      await bob.engine.calls.accept();
      await waitForCall(alice, (c) => c.phase == CallPhase.active);
      await waitForCall(bob, (c) => c.phase == CallPhase.active);
      await settle(() async {
        expect(alice.engine.calls.current!.phase, CallPhase.active);
      });
      await bob.engine.calls.hangUp();
      await waitForNoCall(alice);
      await logOf(alice, started.callId, state: 'ended');
    });

    test('a caller who gives up while the callee is offline leaves no ring '
        'and one missed-call notice from the chat entry', () async {
      final alice = await world.register('alice', aliceNumber);
      final bob = await world.register('bob', bobNumber, realtime: false);
      await bob.engine.stop();
      media(alice);
      media(bob);
      final chat = await alice.engine.chats.openDirect(bob.account);
      await alice.engine.chats.sendText(chat.id, 'ping');
      await bob.engine.syncOnce();

      final started = await alice.engine.calls.startCall(bob.account);
      await alice.engine.calls.hangUp();
      await waitForNoCall(alice);
      // The server dropped the offer with the hang-up: nothing to ring.
      final summary = await bob.engine.syncOnce();
      expect(summary.pendingCalls, isEmpty);
      expect(await bob.engine.calls.fetchPending(), 0);
      expect(bob.engine.calls.current, isNull);

      // Bob never saw it ring, but the caller's chat entry arrives with the
      // headless run: a missed call in the log and ONE notice.
      final notices = <IncomingNotice>[];
      await settle(() async {
        notices.addAll((await bob.engine.syncOnce()).notices);
        final row = await bob.db.callsDao.byId(started.callId);
        expect(row, isNotNull);
        expect(row!.direction, 'missed');
        expect(CallsDao.wasMissed(row), isTrue);
      });
      expect(notices, hasLength(1));
      expect(notices.single.kind, 'call_log');
      expect(notices.single.preview, 'Missed voice call');
      expect(notices.single.sender, alice.account);
      expect(await callEntries(bob, alice), hasLength(1));
    });

    test(
      'a blocked caller rings into the void; blocking is also local',
      () async {
        final alice = await world.register('alice', aliceNumber);
        final bob = await world.register('bob', bobNumber);
        media(alice);
        media(bob);
        final chat = await alice.engine.chats.openDirect(bob.account);
        await alice.engine.chats.sendText(chat.id, 'ping');
        await waitForText(bob, alice, 'ping');

        await bob.engine.people.block(alice.account);
        final started = await alice.engine.calls.startCall(bob.account);
        // The caller learns nothing: it looks like any call nobody answers.
        expect(alice.engine.calls.current!.phase, CallPhase.calling);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(alice.engine.calls.current!.phase, CallPhase.calling);
        expect(bob.engine.calls.current, isNull);
        expect(await bob.db.callsDao.recent(), isEmpty);
        expect((await bob.api.calls.pending()).calls, isEmpty);
        await alice.engine.calls.hangUp();
        final row = await logOf(alice, started.callId, state: 'cancelled');
        expect(row.direction, 'outgoing');

        // Alice cannot call someone she blocked.
        await alice.engine.people.block(bob.account);
        await expectLater(
          alice.engine.calls.startCall(bob.account),
          throwsA(
            isA<CallFailedException>().having(
              (e) => e.reason,
              'reason',
              CallFailure.blocked,
            ),
          ),
        );
        // Unblocked on both sides, calls work again.
        await alice.engine.people.unblock(bob.account);
        await bob.engine.people.unblock(alice.account);
        final again = await alice.engine.calls.startCall(bob.account);
        await waitForCall(bob, (c) => c.callId == again.callId);
        await bob.engine.calls.decline();
        await waitForNoCall(alice);
      },
    );

    test('both call each other at once: one call survives', () async {
      final alice = await world.register('alice', aliceNumber);
      final bob = await world.register('bob', bobNumber);
      media(alice);
      media(bob);
      final chat = await alice.engine.chats.openDirect(bob.account);
      await alice.engine.chats.sendText(chat.id, 'ping');
      await waitForText(bob, alice, 'ping');

      final calls = await Future.wait([
        alice.engine.calls.startCall(bob.account),
        bob.engine.calls.startCall(alice.account),
      ]);
      final winner = calls
          .map((c) => c.callId)
          .reduce((a, b) => a.compareTo(b) < 0 ? a : b);
      final callee = calls[0].callId == winner ? bob : alice;
      final caller = callee == bob ? alice : bob;
      await waitForCall(
        callee,
        (c) => c.callId == winner && c.phase == CallPhase.ringing,
      );
      await callee.engine.calls.accept();
      await waitForCall(caller, (c) => c.phase == CallPhase.active);
      await waitForCall(callee, (c) => c.phase == CallPhase.active);
      expect(caller.engine.calls.current!.callId, winner);
      await callee.engine.calls.hangUp();
      await waitForNoCall(caller);
      // The loser left no trace in either log.
      for (final user in [alice, bob]) {
        expect(
          [for (final r in await user.db.callsDao.recent()) r.callId],
          [winner],
        );
      }
    });

    test('a call from a stranger rings: anyone can call anyone', () async {
      final alice = await world.register('alice', aliceNumber);
      final bob = await world.register('bob', bobNumber);
      media(alice);
      media(bob);
      // No chat, no earlier contact: the offer starts the session.
      final started = await alice.engine.calls.startCall(bob.account);
      await waitForCall(bob, (c) => c.callId == started.callId);
      expect(
        (await bob.db.peopleDao.byAccount(alice.account))!.identityKey,
        isNotNull,
        reason: 'the caller\'s identity key is pinned like for a message',
      );
      await bob.engine.calls.accept();
      await waitForCall(alice, (c) => c.phase == CallPhase.active);
      await bob.engine.calls.hangUp();
      await waitForNoCall(alice);
    });
  });
}
