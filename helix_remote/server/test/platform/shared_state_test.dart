import 'dart:async';

import 'package:helix_remote_server/src/platform/bus/event_bus.dart';
import 'package:helix_remote_server/src/platform/clock.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
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

    test('ephemeral store: compare-and-set replace and deleteIf', () async {
      final store = PostgresEphemeralStore(db, schemas.platform);
      final other = PostgresEphemeralStore(otherNode, schemas.platform);
      const ttl = Duration(seconds: 30);

      await store.put('route:d', 'node-a|c1', ttl);
      await other.put('route:d', 'node-b|c2', ttl);
      expect(
        await store.replace('route:d', 'node-a|c1', 'node-a|c1', ttl),
        isFalse,
        reason: 'a newer value is never overwritten',
      );
      expect(await store.deleteIf('route:d', 'node-a|c1'), isFalse);
      expect(await store.get('route:d'), 'node-b|c2');
      expect(
        await other.replace('route:d', 'node-b|c2', 'node-b|c2', ttl),
        isTrue,
      );
      expect(await store.deleteIf('route:d', 'node-b|c2'), isTrue);
      expect(await other.get('route:d'), isNull);
      expect(await store.replace('route:d', 'node-b|c2', 'x', ttl), isFalse);
    });

    test(
      'a fan-out parks one value per device in one statement (AUD-3-1)',
      () async {
        const ttl = Duration(seconds: 60);
        final store = PostgresEphemeralStore(db, schemas.platform);
        final devices = List.generate(1100, (i) => 'dev-$i');
        await store.putAll({
          for (final d in devices) 'msg:eph:r:$d': '{"to":"$d"}',
        }, ttl);
        expect(
          await store.getAll([for (final d in devices) 'msg:eph:r:$d']),
          hasLength(1100),
          reason: 'every device got its own value',
        );
        expect(await store.get('msg:eph:r:dev-7'), '{"to":"dev-7"}');

        // An existing key is replaced, not skipped, and a later TTL wins.
        await store.put('msg:eph:r:dev-7', 'stale', const Duration(seconds: 1));
        await store.putAll({
          'msg:eph:r:dev-7': 'fresh',
          'msg:eph:r:new': 'added',
        }, const Duration(seconds: 30));
        expect(await store.get('msg:eph:r:dev-7'), 'fresh');
        expect(await store.get('msg:eph:r:new'), 'added');

        final counting = _CountingSession();
        await PostgresEphemeralStore(
          counting,
          schemas.platform,
        ).putAll({for (final d in devices) 'msg:eph:r:$d': 'v'}, ttl);
        expect(
          counting.statements,
          1,
          reason: 'a thousand devices must not cost a thousand round trips',
        );
        await PostgresEphemeralStore(
          counting,
          schemas.platform,
        ).putAll({}, ttl);
        expect(counting.statements, 1, reason: 'an empty batch issues nothing');
      },
    );

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

    test(
      'rate limiter: a hit can cost several tokens, at most the capacity',
      () async {
        final a = PostgresRateLimiter(db, schemas.platform);
        final b = PostgresRateLimiter(otherNode, schemas.platform);
        const policy = RateLimitPolicy(
          'weighted',
          capacity: 10,
          perSecond: 0.001,
        );
        expect((await a.hit(policy, 'k', cost: 4)).allowed, isTrue);
        expect((await b.hit(policy, 'k', cost: 4)).allowed, isTrue);
        final denied = await a.hit(policy, 'k', cost: 4);
        expect(denied.allowed, isFalse, reason: 'two tokens left');
        expect(denied.retryAfter, greaterThan(const Duration(seconds: 1000)));
        expect((await b.hit(policy, 'k', cost: 2)).allowed, isTrue);
        expect(
          (await a.hit(policy, 'fresh', cost: 1000)).allowed,
          isTrue,
          reason: 'a cost over the capacity takes the whole bucket',
        );
        expect((await a.hit(policy, 'fresh')).allowed, isFalse);
      },
    );

    test('rate limiter: concurrent hits never exceed capacity', () async {
      final a = PostgresRateLimiter(db, schemas.platform);
      final b = PostgresRateLimiter(otherNode, schemas.platform);
      const policy = RateLimitPolicy('burst', capacity: 5, perSecond: 0.0001);
      final results = await Future.wait([
        for (var i = 0; i < 20; i++) (i.isEven ? a : b).hit(policy, 'same'),
      ]);
      expect(results.where((r) => r.allowed).length, 5);
    });

    test(
      'rate limiter: the sweep keeps a bucket until it is full again',
      () async {
        final limiter = PostgresRateLimiter(db, schemas.platform);
        final daily = RateLimitPolicy.per('daily', 2, const Duration(days: 1));
        final minute = RateLimitPolicy.per(
          'minute',
          2,
          const Duration(minutes: 1),
        );
        expect((await limiter.hit(daily, 'k', cost: 2)).allowed, isTrue);
        expect((await limiter.hit(minute, 'k', cost: 2)).allowed, isTrue);
        // Two hours without a hit. The sweep used to drop every bucket idle
        // for an hour, which gave a day-long budget back in full.
        await db.execute(
          'UPDATE ${schemas.platform}.rate_buckets SET '
          "updated_at = updated_at - interval '2 hours', "
          "full_at = full_at - interval '2 hours'",
        );
        expect(await limiter.sweep(), 1, reason: 'the per-minute bucket only');
        expect((await limiter.hit(daily, 'k')).allowed, isFalse);
        expect((await limiter.hit(minute, 'k')).allowed, isTrue);
      },
    );

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

    test('putAll writes every key and expires them together', () async {
      final clock = ManualClock();
      final store = InMemoryEphemeralStore(clock: clock);
      await store.putAll({'a': '1', 'b': '2'}, const Duration(seconds: 10));
      clock.advance(const Duration(seconds: 9));
      expect(await store.getAll(['a', 'b']), {'a': '1', 'b': '2'});
      clock.advance(const Duration(seconds: 2));
      expect(await store.getAll(['a', 'b']), isEmpty);
      await store.put('a', 'old', const Duration(seconds: 10));
      await store.putAll({'a': 'new'}, const Duration(seconds: 10));
      expect(
        await store.get('a'),
        'new',
        reason: 'an existing key is replaced',
      );
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

    test('rate limiter: weighted hits wait for what they cost', () async {
      final clock = ManualClock();
      final limiter = InMemoryRateLimiter(clock: clock);
      const policy = RateLimitPolicy('w', capacity: 10, perSecond: 1);
      expect((await limiter.hit(policy, 'k', cost: 8)).allowed, isTrue);
      final denied = await limiter.hit(policy, 'k', cost: 5);
      expect(denied.allowed, isFalse);
      expect(denied.retryAfter, const Duration(seconds: 3));
      clock.advance(const Duration(seconds: 3));
      expect((await limiter.hit(policy, 'k', cost: 5)).allowed, isTrue);
      expect(
        (await limiter.hit(policy, 'big', cost: 99)).allowed,
        isTrue,
        reason: 'charged as the capacity',
      );
      expect((await limiter.hit(policy, 'big')).allowed, isFalse);
    });

    test('rate limiter: the sweep drops a bucket once it is full', () async {
      final clock = ManualClock();
      final limiter = InMemoryRateLimiter(clock: clock);
      final daily = RateLimitPolicy.per('daily', 2, const Duration(days: 1));
      final minute = RateLimitPolicy.per(
        'minute',
        2,
        const Duration(minutes: 1),
      );
      await limiter.hit(daily, 'k', cost: 2);
      await limiter.hit(minute, 'k', cost: 2);
      clock.advance(const Duration(hours: 2));
      expect(await limiter.sweep(), 1);
      expect((await limiter.hit(daily, 'k')).allowed, isFalse);
    });

    test('bus delivers to subscribers', () async {
      final bus = InMemoryEventBus();
      final got = bus.subscribe('t').first;
      await bus.publish('t', {'a': 1});
      expect(await got, {'a': 1});
    });
  });
}

/// A session that answers nothing but counts the statements it is given:
/// a fan-out is bounded by round trips, and this is how few they must be.
final class _CountingSession implements SqlSession {
  int statements = 0;

  void _count() => statements++;

  @override
  Future<List<Row>> query(
    String sql, [
    Map<String, Object?> params = const {},
  ]) async {
    _count();
    return const [];
  }

  @override
  Future<Row?> queryOne(
    String sql, [
    Map<String, Object?> params = const {},
  ]) async {
    _count();
    return null;
  }

  @override
  Future<int> execute(
    String sql, [
    Map<String, Object?> params = const {},
  ]) async {
    _count();
    return 0;
  }
}
