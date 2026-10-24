import 'package:helix_remote_server/src/kernel/presence.dart';
import 'package:helix_remote_server/src/platform/clock.dart';
import 'package:helix_remote_server/src/platform/ephemeral/ephemeral_store.dart';
import 'package:test/test.dart';

/// "Online" is two facts: a socket wrote a route, and the node behind that
/// route is still renewing its own key. Before AUD-3-3 only the first was
/// read, so a node that died where it stood kept reporting its devices
/// reachable for the rest of the route TTL - and a call offer to one of them
/// was neither delivered nor parked, while the caller heard a normal ring.
void main() {
  group('presence', () {
    late ManualClock clock;
    late InMemoryEphemeralStore store;

    setUp(() {
      clock = ManualClock();
      store = InMemoryEphemeralStore(clock: clock);
    });

    Future<void> route(String device, String on) =>
        store.put(Presence.routeKey(device), '$on|conn', Presence.routeTtl);

    Future<void> nodeAlive(String on) =>
        store.put(Presence.nodeKey(on), '1', Presence.nodeTtl);

    test(
      'a route counts as online only while its node renews its key',
      () async {
        await route('d1', 'node-a');
        expect(
          await Presence.isOnline(store, 'd1'),
          isFalse,
          reason: 'a route nobody renews is a dead node leftover',
        );
        await nodeAlive('node-a');
        expect(await Presence.isOnline(store, 'd1'), isTrue);
        expect(await Presence.online(store, ['d1']), {'d1'});
      },
    );

    test(
      'a device on a dead node is offline, one on a live node is not',
      () async {
        await route('d1', 'node-a');
        await route('d2', 'node-b');
        await nodeAlive('node-a');
        expect(await Presence.online(store, ['d1', 'd2', 'd3']), {'d1'});
        expect(await Presence.online(store, const []), isEmpty);
      },
    );

    test('a node that stops beating loses its devices long before its '
        'routes expire', () async {
      await route('d1', 'node-a');
      await route('d2', 'node-a');
      await nodeAlive('node-a');
      expect(await Presence.online(store, ['d1', 'd2']), {'d1', 'd2'});

      clock.advance(Presence.nodeTtl + const Duration(seconds: 1));
      expect(
        await Presence.online(store, ['d1', 'd2']),
        isEmpty,
        reason: 'the node stopped renewing: nothing can reach them',
      );
      expect(
        await store.get(Presence.routeKey('d1')),
        'node-a|conn',
        reason: 'the route is still there; it was never the whole proof',
      );

      clock.advance(Presence.routeTtl);
      expect(await store.get(Presence.routeKey('d1')), isNull);
    });

    test('liveness is the shorter window, and renews several times over', () {
      expect(Presence.nodeTtl, lessThan(Presence.routeTtl));
      expect(
        Presence.nodeTtl.inMilliseconds ~/ Presence.nodeRefresh.inMilliseconds,
        greaterThanOrEqualTo(3),
        reason: 'one stalled round trip must not empty a node',
      );
    });

    test('the node a route names is read out of its value', () {
      expect(Presence.nodeOf('uuid-1|conn-7'), 'uuid-1');
      expect(Presence.nodeOf('uuid-1'), 'uuid-1', reason: 'defensive: no bar');
    });
  });
}
