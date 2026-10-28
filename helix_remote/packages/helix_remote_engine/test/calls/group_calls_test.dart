import 'dart:async';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../support/fake_call_network.dart';
import '../support/peers.dart';

/// Group calls: a room of pairwise calls, against the in-memory network with
/// fake media. The real sealing and server are the end-to-end tests' job.
void main() {
  late TestClock clock;
  late FakeCallNetwork net;

  setUp(() {
    clock = TestClock();
    net = FakeCallNetwork(clock);
  });
  tearDown(() => net.dispose());

  const chat = 'group:g1';

  /// Alice, Bob and Cara in one group; every device watching.
  Future<(CallDevice, CallDevice, CallDevice)> three() async {
    final alice = await net.add('alice');
    final bob = await net.add('bob');
    final cara = await net.add('cara');
    await net.makeGroup(chat, [alice, bob, cara]);
    for (final d in [alice, bob, cara]) {
      d.startWatching();
    }
    return (alice, bob, cara);
  }

  Future<void> untilRoom(
    CallDevice d,
    bool Function(GroupCallSnapshot room) test,
  ) => d.until(() => d.room != null && test(d.room!));

  GroupParticipantState? stateOf(CallDevice d, CallDevice other) => d
      .room
      ?.participants
      .where((p) => p.account == other.account)
      .map((p) => p.state)
      .firstOrNull;

  /// Both invited people have the invitation ringing, then both join.
  Future<void> bothJoin(CallDevice bob, CallDevice cara) async {
    await untilRoom(bob, (r) => r.phase == GroupCallPhase.ringing);
    await untilRoom(cara, (r) => r.phase == GroupCallPhase.ringing);
    await bob.groupService.accept();
    await cara.groupService.accept();
  }

  Future<void> everyoneConnected(List<CallDevice> devices) async {
    for (final d in devices) {
      await untilRoom(
        d,
        (r) =>
            r.phase == GroupCallPhase.active &&
            r.participants.every(
              (p) => p.state == GroupParticipantState.connected,
            ),
      );
    }
  }

  group('a room of three', () {
    test(
      'rings both, and once they join everyone is connected to everyone',
      () async {
        final (alice, bob, cara) = await three();
        final started = await alice.groupService.start(
          chat,
          invite: [bob.account, cara.account],
          video: true,
        );
        expect(started.participants, hasLength(2));
        await untilRoom(bob, (r) => r.phase == GroupCallPhase.ringing);
        await untilRoom(cara, (r) => r.phase == GroupCallPhase.ringing);
        expect(bob.room!.isIncoming, isTrue);
        expect(bob.room!.starter, alice.account);
        expect(bob.events.whereType<IncomingGroupCallEvent>(), hasLength(1));

        await bob.groupService.accept();
        await cara.groupService.accept();
        await everyoneConnected([alice, bob, cara]);
        // Three pairs: three links, each side holding two media sessions.
        expect(alice.media!.sessions, hasLength(2));
        expect(bob.media!.sessions, hasLength(2));
        expect(cara.media!.sessions, hasLength(2));
        expect(alice.media!.sessions.every((s) => s.config.video), isTrue);
        expect(alice.media!.sessions.map((s) => s.config.room).toSet(), {
          started.roomId,
        });
      },
    );

    test('between two invited people only one offers', () async {
      final (alice, bob, cara) = await three();
      await alice.groupService.start(chat, invite: [bob.account, cara.account]);
      await bothJoin(bob, cara);
      await everyoneConnected([alice, bob, cara]);
      final offersBetween = [
        for (final (from, to, p) in net.log)
          if (p.type == CallSignalType.offer &&
              {from, to}.containsAll({bob.device, cara.device}))
            (from, to),
      ];
      expect(offersBetween, hasLength(1));
      final smaller = bob.account.compareTo(cara.account) < 0 ? bob : cara;
      expect(offersBetween.single.$1, smaller.device);
    });

    test('leaving ends your links, and the others go on until alone', () async {
      final (alice, bob, cara) = await three();
      await alice.groupService.start(chat, invite: [bob.account, cara.account]);
      await bothJoin(bob, cara);
      await everyoneConnected([alice, bob, cara]);

      await cara.groupService.hangUp();
      expect(cara.room, isNull);
      await untilRoom(
        alice,
        (r) =>
            r.participants
                .where((p) => p.account == cara.account)
                .single
                .state ==
            GroupParticipantState.left,
      );
      expect(stateOf(bob, bob), isNull);
      await untilRoom(
        bob,
        (r) =>
            r.participants
                .where((p) => p.account == cara.account)
                .single
                .state ==
            GroupParticipantState.left,
      );
      expect(alice.room!.phase, GroupCallPhase.active);

      await bob.groupService.hangUp();
      await alice.until(() => alice.room == null);
      expect(
        alice.groupShown.whereType<GroupCallSnapshot>().last.end,
        GroupCallEnd.everyoneLeft,
      );
      // The starter's phone tells the group chat; the others post nothing.
      final (conversation, body) = alice.groupPosted.single;
      expect(conversation, chat);
      expect(body.outcome, CallOutcome.answered);
      expect(body.media, CallMedia.audio);
      expect(bob.groupPosted, isEmpty);
      expect(cara.groupPosted, isEmpty);
    });

    test('a declined invitation leaves the others in the room', () async {
      final (alice, bob, cara) = await three();
      await alice.groupService.start(chat, invite: [bob.account, cara.account]);
      await bob.until(() => bob.room != null);
      await cara.until(() => cara.room != null);
      await cara.groupService.decline();
      await bob.groupService.accept();
      await untilRoom(
        alice,
        (r) =>
            stateOf(alice, bob) == GroupParticipantState.connected &&
            stateOf(alice, cara) == GroupParticipantState.left,
      );
      expect(cara.room, isNull);
      expect(
        cara.groupShown.whereType<GroupCallSnapshot>().last.end,
        GroupCallEnd.declinedByMe,
      );
      // A later offer for the room Cara declined is refused: Bob learns she
      // is out from her answer to his own offer.
      await untilRoom(
        bob,
        (r) =>
            stateOf(bob, cara) == GroupParticipantState.left ||
            r.participants
                    .where((p) => p.account == alice.account)
                    .single
                    .state ==
                GroupParticipantState.connected,
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    test('mute and camera reach every link', () async {
      final (alice, bob, cara) = await three();
      await alice.groupService.start(
        chat,
        invite: [bob.account, cara.account],
        video: true,
      );
      await bothJoin(bob, cara);
      await everyoneConnected([alice, bob, cara]);
      await alice.groupService.setMuted(muted: true);
      await alice.groupService.setCameraEnabled(enabled: false);
      expect(alice.media!.sessions.every((s) => s.muted), isTrue);
      expect(alice.media!.sessions.every((s) => !s.videoEnabled), isTrue);
      expect(alice.room!.muted, isTrue);
      expect(alice.room!.cameraOn, isFalse);
    });
  });

  group('a room of four', () {
    test(
      'makes six links, three on each phone, and no pair offers twice',
      () async {
        final names = ['alice', 'bob', 'cara', 'dan'];
        final devices = [for (final n in names) await net.add(n)];
        await net.makeGroup(chat, devices);
        for (final d in devices) {
          d.startWatching();
        }
        final alice = devices.first;
        await alice.groupService.start(
          chat,
          invite: [for (final d in devices.skip(1)) d.account],
        );
        for (final d in devices.skip(1)) {
          await untilRoom(d, (r) => r.phase == GroupCallPhase.ringing);
        }
        for (final d in devices.skip(1)) {
          await d.groupService.accept();
        }
        await everyoneConnected(devices);
        for (final d in devices) {
          expect(d.media!.sessions, hasLength(3), reason: d.name);
        }
        final pairs = <Set<String>>[];
        for (final (from, to, p) in net.log) {
          if (p.type == CallSignalType.offer) pairs.add({from, to});
        }
        expect(pairs, hasLength(6));
        expect(
          pairs.toSet(),
          hasLength(6),
          reason: 'no pair offered both ways',
        );
      },
    );
  });

  group('who may be in a room', () {
    test('only group members can be invited, and at most three', () async {
      final alice = await net.add('alice');
      final bob = await net.add('bob');
      final cara = await net.add('cara');
      final dan = await net.add('dan');
      final erin = await net.add('erin');
      final outsider = await net.add('outsider');
      await net.makeGroup(chat, [alice, bob, cara, dan, erin]);

      expect(
        () => alice.groupService.start(chat, invite: [outsider.account]),
        throwsArgumentError,
      );
      expect(
        () => alice.groupService.start(
          chat,
          invite: [bob.account, cara.account, dan.account, erin.account],
        ),
        throwsArgumentError,
      );
      expect(
        () => alice.groupService.start(chat, invite: const []),
        throwsArgumentError,
      );
      expect(
        () => alice.groupService.start(chat, invite: [alice.account]),
        throwsArgumentError,
      );
    });

    test('an offer from someone the room does not name is ignored', () async {
      final (alice, bob, cara) = await three();
      final room = CallRoom(
        id: 'r1',
        group: chat,
        participants: [alice.account, bob.account],
      );
      // Cara is not named, so Bob never rings for her.
      await bob.groupService.onSignal(
        cara.account,
        cara.device,
        CallSignalPayload(
          type: CallSignalType.offer,
          callId: 'x1',
          media: CallMedia.audio,
          sdp: 'v=0',
          room: room,
        ),
      );
      expect(bob.room, isNull);
    });

    test('a blocked member cannot ring you into a room', () async {
      final (alice, bob, _) = await three();
      await bob.db.peopleDao.upsertPerson(
        PeopleCompanion.insert(
          accountId: alice.account,
          updatedAt: clock.now,
          blocked: const Value(true),
        ),
      );
      await alice.groupService.start(chat, invite: [bob.account]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bob.room, isNull);
    });
  });

  group('one call at a time', () {
    test(
      'a room refuses while a 1:1 call is live, and the call while in a room',
      () async {
        final (alice, bob, cara) = await three();
        await alice.service.startCall(bob.account);
        await bob.until(() => bob.current?.phase == CallPhase.ringing);
        await bob.service.accept();
        await alice.untilPhase(CallPhase.active);
        await expectLater(
          alice.groupService.start(chat, invite: [cara.account]),
          throwsA(
            isA<CallFailedException>().having(
              (e) => e.reason,
              'reason',
              CallFailure.busy,
            ),
          ),
        );
        await alice.service.hangUp();
        await bob.until(() => bob.current == null);

        await alice.groupService.start(chat, invite: [cara.account]);
        await expectLater(
          alice.service.startCall(bob.account),
          throwsA(isA<CallFailedException>()),
        );
      },
    );

    test('an invitation while busy is answered busy', () async {
      final (alice, bob, cara) = await three();
      await bob.service.startCall(cara.account);
      await cara.until(() => cara.current?.phase == CallPhase.ringing);
      await cara.service.accept();
      await bob.untilPhase(CallPhase.active);

      await alice.groupService.start(chat, invite: [bob.account]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bob.room, isNull);
      expect(net.received(alice, CallSignalType.end).map((p) => p.reason), [
        CallEndReason.busy,
      ]);
    });
  });

  group('invitations that nobody takes', () {
    test('the starter gives up after the ring time', () async {
      final alice = await net.add(
        'alice',
        config: const CallConfig(
          ringTimeout: Duration(milliseconds: 80),
          iceBatchDelay: Duration.zero,
          signalTimeout: Duration(seconds: 2),
        ),
      );
      final bob = await net.add('bob');
      await net.makeGroup(chat, [alice, bob]);
      alice.startWatching();
      bob.startWatching();
      await alice.groupService.start(chat, invite: [bob.account]);
      await bob.until(() => bob.room != null);
      await alice.until(() => alice.room == null);
      expect(
        alice.groupShown.whereType<GroupCallSnapshot>().last.end,
        GroupCallEnd.unanswered,
      );
      expect(alice.groupPosted.single.$2.outcome, CallOutcome.missed);
      // The withdrawn invitation stops ringing for Bob.
      await bob.until(() => bob.room == null);
    });

    test('an offline member rings when the offer is fetched', () async {
      final alice = await net.add('alice');
      final bob = await net.add('bob', online: false);
      await net.makeGroup(chat, [alice, bob]);
      alice.startWatching();
      bob.startWatching();
      await alice.groupService.start(chat, invite: [bob.account]);
      expect(bob.room, isNull);
      bob.online = true;
      expect(await bob.service.fetchPending(), isA<int>());
      await bob.until(() => bob.room != null);
      expect(bob.room!.phase, GroupCallPhase.ringing);
      await bob.groupService.accept();
      await untilRoom(
        alice,
        (r) => stateOf(alice, bob) == GroupParticipantState.connected,
      );
    });
  });

  test('a starter with no call time left never starts the room', () async {
    final (alice, bob, cara) = await three();
    alice.noCallTime = true;
    await expectLater(
      alice.groupService.start(chat, invite: [bob.account, cara.account]),
      throwsA(
        isA<CallFailedException>().having(
          (e) => e.reason,
          'reason',
          CallFailure.noCallTime,
        ),
      ),
    );
    expect(alice.room, isNull);
    expect(net.received(bob, CallSignalType.offer), isEmpty);
  });

  test('every leg asks for credentials with the room id', () async {
    final (alice, bob, cara) = await three();
    await alice.groupService.start(chat, invite: [bob.account, cara.account]);
    await bothJoin(bob, cara);
    await everyoneConnected([alice, bob, cara]);
    final room = alice.room!.roomId;
    expect(alice.turnRequests, hasLength(2));
    expect(alice.turnRequests.every((r) => r.$4 == room), isTrue);
    expect(alice.turnRequests.every((r) => r.$2 == CallRole.caller), isTrue);
    expect(bob.turnRequests.first.$2, CallRole.callee);
  });
}
