import 'dart:async';

import 'package:helix_remote_server/src/platform/bus/event_bus.dart';
import 'package:helix_remote_server/src/platform/clock.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/db/postgres_db.dart';
import 'package:helix_remote_server/src/platform/db/schema_names.dart';
import 'package:helix_remote_server/src/platform/ephemeral/ephemeral_store.dart';
import 'package:helix_remote_server/src/platform/platform_migrations.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';
import 'package:test/test.dart';

import '../support/test_database.dart';
import '../support/test_platform.dart';

void main() {
  group('Postgres shared state', skip: databaseTestSkipReason, () {
    late PostgresDb db;
    late PostgresDb otherNode;
    late SchemaNames schemas;

    setUp(() async {
      db = await openTestDb();
      otherNode = await openTestDb();
      schemas = SchemaNames(prefix: randomPrefix());
      await MigrationRunner(db, schemas).run([platformMigrations]);
    });

    tearDown(() async {
      await db.close();
      await otherNode.close();
      await dropSchemas(schemas.prefix);
    });

    test('ephemeral store: TTL, putIfAbsent, take, scan, sweep', () async {
      final store = PostgresEphemeralStore(db, schemas.platform);
      final other = PostgresEphemeralStore(otherNode, schemas.platform);

      await store.put('route:a', 'node-1', const Duration(seconds: 30));
      expect(
        await other.get('route:a'),
        'node-1',
        reason: 'visible on another node',
      );

      expect(
        await store.putIfAbsent('chal:x', '1', const Duration(seconds: 30)),
        isTrue,
      );
      expect(
        await other.putIfAbsent('chal:x', '2', const Duration(seconds: 30)),
        isFalse,
      );
      expect(await other.take('chal:x'), '1');
      expect(await store.take('chal:x'), isNull, reason: 'single use');

      await store.put('route:b', 'node-2', const Duration(milliseconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await store.get('route:b'), isNull, reason: 'expired');
      expect(
        await store.putIfAbsent(
          'route:b',
          'node-3',
          const Duration(seconds: 5),
        ),
        isTrue,
        reason: 'expired keys count as absent',
      );

      await store.put('route_x', 'not a route', const Duration(seconds: 30));
      expect(
        (await store.scan('route:')).keys,
        unorderedEquals(['route:a', 'route:b']),
        reason: 'LIKE wildcards in the prefix are escaped',
      );

      await store.put('gone', 'x', const Duration(milliseconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await store.sweep(), greaterThanOrEqualTo(1));
    });

    test('rate limiter: capacity, refill, shared across nodes', () async {
      final a = PostgresRateLimiter(db, schemas.platform);
      final b = PostgresRateLimiter(otherNode, schemas.platform);
      const policy = RateLimitPolicy('test', capacity: 3, perSecond: 0.001);

      expect((await a.hit(policy, 'ip1')).allowed, isTrue);
      expect((await b.hit(policy, 'ip1')).allowed, isTrue);
      expect((await a.hit(policy, 'ip1')).allowed, isTrue);
      final denied = await b.hit(policy, 'ip1');
      expect(denied.allowed, isFalse);
      expect(denied.retryAfter, greaterThan(Duration.zero));
      expect(
        (await a.hit(policy, 'ip2')).allowed,
        isTrue,
        reason: 'keys are independent',
      );

      const fast = RateLimitPolicy('fast', capacity: 1, perSecond: 5);
      expect((await a.hit(fast, 'k')).allowed, isTrue);
      expect((await a.hit(fast, 'k')).allowed, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect((await a.hit(fast, 'k')).allowed, isTrue, reason: 'refilled');
    });

    test('rate limiter: concurrent hits never exceed capacity', () async {
      final a = PostgresRateLimiter(db, schemas.platform);
      final b = PostgresRateLimiter(otherNode, schemas.platform);
      const policy = RateLimitPolicy('burst', capacity: 5, perSecond: 0.0001);
      final results = await Future.wait([
        for (var i = 0; i < 20; i++) (i.isEven ? a : b).hit(policy, 'same'),
      ]);
      expect(results.where((r) => r.allowed).length, 5);
    });

    test('event bus: delivered across connections', () async {
      final busA = PostgresEventBus(db, prefix: schemas.prefix);
      final busB = PostgresEventBus(otherNode, prefix: schemas.prefix);
      final received = busB.subscribe('device.wake').first;
      await busB.ready;
      await busA.publish('device.wake', {'device': 'd1'});
      expect(await received.timeout(const Duration(seconds: 5)), {
        'device': 'd1',
      });
      await expectLater(
        busA.publish('big', {'x': 'y' * 9000}),
        throwsArgumentError,
      );
      await busA.close();
      await busB.close();
    });
  });

  group('in-memory variants', () {
    test('ephemeral store expires with the clock', () async {
      final clock = ManualClock();
      final store = InMemoryEphemeralStore(clock: clock);
      await store.put('k', 'v', const Duration(seconds: 10));
      clock.advance(const Duration(seconds: 9));
      expect(await store.get('k'), 'v');
      clock.advance(const Duration(seconds: 2));
      expect(await store.get('k'), isNull);
    });

    test('rate limiter refills with the clock', () async {
      final clock = ManualClock();
      final limiter = InMemoryRateLimiter(clock: clock);
      final policy = RateLimitPolicy.per('p', 2, const Duration(minutes: 1));
      expect((await limiter.hit(policy, 'k')).allowed, isTrue);
      expect((await limiter.hit(policy, 'k')).allowed, isTrue);
      final denied = await limiter.hit(policy, 'k');
      expect(denied.allowed, isFalse);
      expect(denied.retryAfter.inSeconds, inInclusiveRange(29, 31));
      clock.advance(const Duration(seconds: 30));
      expect((await limiter.hit(policy, 'k')).allowed, isTrue);
    });

    test('bus delivers to subscribers', () async {
      final bus = InMemoryEventBus();
      final got = bus.subscribe('t').first;
      await bus.publish('t', {'a': 1});
      expect(await got, {'a': 1});
    });
  });
}
