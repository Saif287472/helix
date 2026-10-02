import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:test/test.dart';

import 'support.dart';

CallLogCompanion call(
  String id, {
  String peer = 'bob',
  String direction = 'outgoing',
  String state = 'ringing',
  DateTime? startedAt,
  bool video = false,
}) => CallLogCompanion.insert(
  callId: id,
  peerAccountId: peer,
  kind: 'direct',
  direction: direction,
  state: state,
  video: Value(video),
  startedAt: startedAt ?? t0,
);

void main() {
  late CallsDao calls;

  setUp(() => calls = memoryDb().callsDao);

  test('a call is logged at start and found by id', () async {
    await calls.start(call('c1', video: true, direction: 'incoming'));
    final row = (await calls.byId('c1'))!;
    expect(
      (row.peerAccountId, row.direction, row.video),
      ('bob', 'incoming', true),
    );
    expect((row.answeredAt, row.endedAt), (null, null));
    expect(await calls.byId('nope'), isNull);
  });

  test(
    'starting the same call id twice is one row (joined from pending)',
    () async {
      await calls.start(call('c1', state: 'ringing'));
      await calls.start(call('c1', state: 'active', startedAt: at(1)));
      expect(await calls.recent(), hasLength(1));
      expect((await calls.byId('c1'))!.state, 'active');
    },
  );

  test(
    'answered then ended gives a duration from the answer, not the ring',
    () async {
      await calls.start(call('c1', startedAt: at(0)));
      await calls.answered('c1', at: at(10));
      expect((await calls.byId('c1'))!.state, 'active');
      await calls.end('c1', state: 'ended', at: at(75));
      final row = (await calls.byId('c1'))!;
      expect(row.state, 'ended');
      expect(CallsDao.durationSeconds(row), 65);
      expect(CallsDao.wasMissed(row), isFalse);
    },
  );

  test('a call that rang out has no duration and counts as missed', () async {
    await calls.start(call('c1', direction: 'incoming'));
    await calls.end('c1', state: 'missed', at: at(30));
    final row = (await calls.byId('c1'))!;
    expect(CallsDao.durationSeconds(row), isNull);
    expect(CallsDao.wasMissed(row), isTrue);
    // Declined and failed calls are not "missed".
    await calls.start(call('c2', direction: 'incoming'));
    await calls.end('c2', state: 'declined', at: at(5));
    expect(CallsDao.wasMissed((await calls.byId('c2'))!), isFalse);
    // Nobody picking up a call this device placed is not a missed call.
    await calls.start(call('c3', direction: 'outgoing'));
    await calls.end('c3', state: 'ended', at: at(5));
    expect(CallsDao.wasMissed((await calls.byId('c3'))!), isFalse);
  });

  test('the log is newest first, limited, and per peer', () async {
    await calls.start(call('c1', peer: 'bob', startedAt: at(1)));
    await calls.start(call('c2', peer: 'carol', startedAt: at(2)));
    await calls.start(call('c3', peer: 'bob', startedAt: at(3)));
    expect((await calls.recent()).map((c) => c.callId), ['c3', 'c2', 'c1']);
    expect((await calls.recent(limit: 2)).map((c) => c.callId), ['c3', 'c2']);

    final withBob = collect(calls.watchWithPeer('bob'));
    final all = collect(calls.watchRecent());
    await eventually(() => withBob.isNotEmpty && all.isNotEmpty);
    expect(withBob.last.map((c) => c.callId), ['c3', 'c1']);
    await calls.start(call('c4', peer: 'bob', startedAt: at(4)));
    await eventually(() => withBob.last.first.callId == 'c4');
    await eventually(() => all.last.first.callId == 'c4');
  });

  test(
    'unfinished calls are the active and ringing ones, oldest first',
    () async {
      await calls.start(call('ringing', state: 'ringing', startedAt: at(2)));
      await calls.start(call('active', state: 'active', startedAt: at(1)));
      await calls.start(call('done', state: 'ended', startedAt: at(0)));
      expect((await calls.unfinished()).map((c) => c.callId), [
        'active',
        'ringing',
      ]);
    },
  );

  test('forget removes one call only', () async {
    await calls.start(call('c1'));
    await calls.start(call('c2'));
    await calls.forget('c1');
    expect((await calls.recent()).map((c) => c.callId), ['c2']);
  });
}
