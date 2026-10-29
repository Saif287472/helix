import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import '../support/fake_call_network.dart';
import '../support/peers.dart';

/// "Silence unknown callers": a call from someone the callee does not know
/// does not ring; it is a missed call in the log, and nothing else.
void main() {
  late TestClock clock;
  late FakeCallNetwork net;

  setUp(() {
    clock = TestClock();
    net = FakeCallNetwork(clock);
  });
  tearDown(() => net.dispose());

  /// Waits for the signal to be handled: the call is in the log.
  Future<void> logged(CallDevice d, String callId) async {
    for (var i = 0; i < 300; i++) {
      if (await d.db.callsDao.byId(callId) != null) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('the call was never logged');
  }

  Future<void> silence(CallDevice d, {bool on = true}) => d.db.settingsDao.set(
    EngineSettings.silenceUnknownCallers,
    on,
    now: clock.now,
  );

  test('off by default: a stranger rings', () async {
    final alice = await net.add('alice');
    final bob = await net.add('bob');
    bob.startWatching();
    await alice.service.startCall(bob.account);
    await bob.until(() => bob.current?.phase == CallPhase.ringing);
    expect(bob.events.whereType<IncomingCallEvent>(), hasLength(1));
  });

  test(
    'on: a stranger does not ring, and is a missed call in the log',
    () async {
      final alice = await net.add('alice');
      final bob = await net.add('bob');
      bob.startWatching();
      await silence(bob);

      final started = await alice.service.startCall(bob.account);
      await logged(bob, started.callId);

      expect(bob.current, isNull);
      expect(bob.events, isEmpty, reason: 'no ring and no missed-call notice');
      final row = (await bob.logRow(started.callId))!;
      expect(row.direction, 'missed');
      expect(row.state, 'missed');
      expect(row.peerAccountId, alice.account);
      expect(
        net.received(alice, CallSignalType.ringing),
        isEmpty,
        reason: 'the caller is not told this phone is ringing',
      );
    },
  );

  group('on: someone known still rings', () {
    Future<void> rings(CallDevice alice, CallDevice bob) async {
      await alice.service.startCall(bob.account);
      await bob.until(() => bob.current?.phase == CallPhase.ringing);
      expect(bob.current!.peer, alice.account);
    }

    test('a name from the phone\'s contacts', () async {
      final alice = await net.add('alice');
      final bob = await net.add('bob');
      await silence(bob);
      await bob.db.peopleDao.upsertPerson(
        PeopleCompanion.insert(
          accountId: alice.account,
          updatedAt: clock.now,
          phonebookName: const Value('Alice A'),
        ),
      );
      await rings(alice, bob);
    });

    test('a name given here', () async {
      final alice = await net.add('alice');
      final bob = await net.add('bob');
      await silence(bob);
      await bob.db.peopleDao.upsertPerson(
        PeopleCompanion.insert(
          accountId: alice.account,
          updatedAt: clock.now,
          nickname: const Value('Ali'),
        ),
      );
      await rings(alice, bob);
    });

    test('someone you have written to', () async {
      final alice = await net.add('alice');
      final bob = await net.add('bob');
      await silence(bob);
      final chat = await bob.db.conversationsDao.ensureDirect(
        alice.account,
        now: clock.now,
      );
      await bob.db.messagesDao.insertMessage(
        MessagesCompanion.insert(
          messageId: 'm1',
          conversationId: chat.id,
          sender: bob.account,
          outgoing: true,
          sortKey: SortKey.of(clock.now, 'm1'),
          sentAt: clock.now,
          receivedAt: clock.now,
          kind: 'text',
          status: MessageStatus.sent,
        ),
      );
      await rings(alice, bob);
    });

    test('but not someone who only wrote to you', () async {
      final alice = await net.add('alice');
      final bob = await net.add('bob');
      bob.startWatching();
      await silence(bob);
      final chat = await bob.db.conversationsDao.ensureDirect(
        alice.account,
        now: clock.now,
      );
      await bob.db.messagesDao.insertMessage(
        MessagesCompanion.insert(
          messageId: 'm1',
          conversationId: chat.id,
          sender: alice.account,
          outgoing: false,
          sortKey: SortKey.of(clock.now, 'm1'),
          sentAt: clock.now,
          receivedAt: clock.now,
          kind: 'text',
          status: MessageStatus.received,
        ),
      );
      final started = await alice.service.startCall(bob.account);
      await logged(bob, started.callId);
      expect(bob.current, isNull);
    });
  });

  test('a pending offer from a stranger is not shown by a push, and is logged '
      'when the app opens it', () async {
    final alice = await net.add('alice');
    final bob = await net.add('bob', online: false);
    await silence(bob);
    final started = await alice.service.startCall(bob.account);

    expect(
      await bob.service.peekPending(),
      isEmpty,
      reason: 'no ringing notice',
    );
    expect(await bob.service.fetchPending(), 0);
    final row = await bob.logRow(started.callId);
    expect(row?.state, 'missed');
    expect(bob.current, isNull);
  });

  test('turning it off again lets a stranger ring', () async {
    final alice = await net.add('alice');
    final bob = await net.add('bob');
    await silence(bob);
    await silence(bob, on: false);
    await alice.service.startCall(bob.account);
    await bob.until(() => bob.current?.phase == CallPhase.ringing);
  });
}
