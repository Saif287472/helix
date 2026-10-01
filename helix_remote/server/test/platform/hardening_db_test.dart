import 'dart:async';
import 'dart:io';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/modules/backup/module.dart';
import 'package:helix_remote_server/src/modules/messaging/module.dart';
import 'package:helix_remote_server/src/platform/bus/event_bus.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/postgres_db.dart';
import 'package:helix_remote_server/src/platform/ephemeral/ephemeral_store.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';
import 'package:test/test.dart';

import '../support/flows.dart';
import '../support/harness.dart';
import '../support/test_client.dart';
import '../support/test_database.dart';
import '../support/test_platform.dart';
import '../support/test_socket.dart';

/// S7 hardening that needs Postgres: nested transactions, int4 bounds,
/// batched presence reads, the LISTEN reconnect, sealed idempotency rows,
/// the metrics token and gauges, send limits, WebSocket frame limits and
/// 400s for malformed input end to end.
void main() {
  group('Db', skip: databaseTestSkipReason, () {
    late PostgresDb db;
    late String prefix;
    late String table;

    setUp(() async {
      // One connection: a nested tx that took a second one would hang.
      db = await PostgresDb.open(
        Platform.environment[testDatabaseUrlVariable]!,
        maxConnections: 1,
      );
      prefix = randomPrefix();
      table = '${prefix}db.items';
      await db.execute('CREATE SCHEMA ${prefix}db');
      await db.execute('CREATE TABLE $table (id text PRIMARY KEY, n int4)');
    });

    tearDown(() async {
      await db.close();
      await dropSchemas(prefix);
    });

    Future<void> insert(SqlSession s, String id) =>
        s.execute('INSERT INTO $table VALUES (@id:text, 1)', {'id': id});

    Future<int> count() async => (await db.queryOne(
      'SELECT count(*)::int8 AS n FROM $table',
    ))!.integer('n');

    test('a nested tx joins the outer one (L2)', () async {
      final order = <String>[];
      await db
          .tx((outer) async {
            await insert(outer, 'a');
            await db.tx((inner) async {
              // Sees the outer transaction's uncommitted row.
              expect(
                await inner.queryOne(
                  'SELECT id FROM $table WHERE id = @id:text',
                  {'id': 'a'},
                ),
                isNotNull,
              );
              await insert(inner, 'b');
              inner.afterCommit(() async => order.add('inner'));
            });
            outer.afterCommit(() async => order.add('outer'));
          })
          .timeout(const Duration(seconds: 10));
      expect(await count(), 2);
      expect(order, ['inner', 'outer']);

      // The inner work rolls back with the outer transaction.
      await expectLater(
        db.tx((outer) async {
          await db.tx((inner) => insert(inner, 'c'));
          throw StateError('roll back');
        }),
        throwsStateError,
      );
      expect(await count(), 2);
    });

    test('int4 parameters out of range are refused, not wrapped (#17)', () {
      expect(
        () => db.execute('INSERT INTO $table VALUES (@id:text, @n:int4)', {
          'id': 'x',
          'n': 1 << 32,
        }),
        throwsA(isA<DbInvalidValue>()),
      );
    });

    test('presence for many devices is one read (L3)', () async {
      final store = PostgresEphemeralStore(db, '${prefix}db');
      await db.execute(
        'CREATE TABLE ${prefix}db.ephemeral (key text PRIMARY KEY, '
        'value text NOT NULL, expires_at timestamptz NOT NULL)',
      );
      await store.put('k1', 'v1', const Duration(minutes: 1));
      await store.put('k2', 'v2', const Duration(minutes: 1));
      await store.put('gone', 'v', Duration.zero);
      expect(await store.getAll(['k1', 'k2', 'gone', 'nope']), {
        'k1': 'v1',
        'k2': 'v2',
      });
      expect(await store.getAll(const []), isEmpty);
      final memory = InMemoryEphemeralStore();
      await memory.put('k1', 'v1', const Duration(minutes: 1));
      expect(await memory.getAll(['k1', 'k2']), {'k1': 'v1'});
    });

    test(
      'LISTEN reconnects after its backend is terminated and the bus resyncs (D6)',
      () async {
        final bus = PostgresEventBus(db, prefix: prefix);
        final hints = <Map<String, Object?>>[];
        final resyncs = <Map<String, Object?>>[];
        bus.subscribe('t').listen(hints.add);
        bus.subscribe(EventBus.resyncTopic).listen(resyncs.add);
        await bus.ready;
        await bus.publish('t', {'n': 1});
        await _until(() => hints.isNotEmpty);

        final restored = db.listenRestored.first;
        final pid = await db.listenerBackendPid();
        final admin = await openTestDb();
        try {
          await admin.execute('SELECT pg_terminate_backend(@pid:int4)', {
            'pid': pid,
          });
        } finally {
          await admin.close();
        }
        await restored.timeout(const Duration(seconds: 20));
        expect(await db.listenerBackendPid(), isNot(pid));
        await _until(() => resyncs.isNotEmpty);

        await bus.publish('t', {'n': 2});
        await _until(() => hints.length == 2);
        expect(hints.last, {'n': 2});
        await bus.close();
      },
    );
  });

  group('server', skip: databaseTestSkipReason, () {
    late Harness h;
    const metricsToken = 'metrics-token-for-tests-0123456789abcdef';

    setUp(() async {
      h = await Harness.start(extra: {'HELIX_METRICS_TOKEN': metricsToken});
    });

    tearDown(() => h.stop());

    test(
      'stored idempotent responses are sealed and still replay (#16)',
      () async {
        final alice = await h.registerGlobal(aliceNumber);
        final second = await secondDevice(h, alice, aliceNumber);
        final body = SendMessageRequest(
          id: Uuid.v7(),
          recipients: [
            Recipient(
              account: alice.account.id,
              devices: [DevicePayload(device: second.id, payload: bytes(16))],
            ),
          ],
        ).toJson();
        final headers = {HelixHeaders.idempotencyKey: 'key-1'};
        final first = await h.api.call(
          Routes.sendMessage,
          bearer: alice.bearer,
          body: body,
          headers: headers,
        );
        expect(first.status, 200);
        final row = await h.env.platform.db.queryOne(
          'SELECT response FROM ${h.env.prefix}platform.idempotency',
        );
        final stored = row!.string('response');
        expect(stored, startsWith('e1:'));
        expect(stored, isNot(contains('accepted_at')));
        final again = await h.api.call(
          Routes.sendMessage,
          bearer: alice.bearer,
          body: body,
          headers: headers,
        );
        expect(again.headers['idempotent-replay'], 'true');
        expect(again.body, first.body);
      },
    );

    test(
      'HELIX_METRICS_TOKEN opens metrics with the new gauges (D4)',
      () async {
        final ok = await h.api.call(Routes.metrics, bearer: metricsToken);
        expect(ok.status, 200);
        expect(ok.body, contains('helix_jobs_dead 0.0'));
        expect(ok.body, contains('helix_mailbox_backlog 0.0'));
        expect(ok.body, contains('helix_http_body_bytes_in_flight'));
        expect(
          (await h.api.call(Routes.metrics, bearer: '${metricsToken}x')).status,
          401,
        );
        // The token opens nothing else.
        expect(
          (await h.api.call(Routes.adminAccounts, bearer: metricsToken)).status,
          401,
        );
      },
    );

    test('sends are limited per device and per account (#15)', () async {
      final alice = await h.registerGlobal(aliceNumber);
      final second = await secondDevice(h, alice, aliceNumber);
      final limiter = h.env.platform.rateLimiter;
      Future<int> sendOne(TestDevice from, String to) async =>
          (await send(h, from, {
            alice.account.id: [to],
          })).status;
      // Buckets refill while the test runs, so drain until refused and
      // then expect a refusal within a few sends.
      Future<void> drain(RateLimitPolicy policy, String key) async {
        while ((await limiter.hit(policy, key)).allowed) {}
      }

      Future<bool> refused(TestDevice from, String to) async {
        for (var i = 0; i < 20; i++) {
          if (await sendOne(from, to) == 429) return true;
        }
        return false;
      }

      expect(await sendOne(alice, second.id), 200);
      await drain(MessagingModule.sendPerDevice, 'device:${alice.id}');
      expect(await refused(alice, second.id), isTrue);
      // The other device has its own device bucket but shares the account's.
      expect(await sendOne(second, alice.id), 200);
      await drain(
        MessagingModule.sendPerAccount,
        'account:${alice.account.id}',
      );
      expect(await refused(second, alice.id), isTrue);
    });

    test('a WebSocket message over the limit drops the socket (#15)', () async {
      final alice = await h.registerGlobal(aliceNumber);
      final socket = await TestSocket.connect(h.server.baseUri, alice.bearer);
      await socket.hello();
      socket.ping('n1');
      expect(await socket.next(), isA<PongFrame>());
      socket.sendRaw('x' * 70000);
      await socket.closed;
    });

    test(
      'oversized shapes and out-of-range values are 400s (#1, #17)',
      () async {
        final alice = await h.registerGlobal(aliceNumber);
        final flat = await h.api.call(
          Routes.putFullBackup,
          bearer: alice.bearer,
          body: FullBackup(
            backupId: Uuid.v7(),
            version: 1,
            envelope: {
              'chunks': List.filled(BackupModule.maxEnvelopeValues, 0),
            },
          ).toJson(),
        );
        expect(flat.status, 400);
        expect(flat.errorCode, 'bad_request');

        final huge = await h.api.call(
          Routes.putHistoryBackup,
          bearer: alice.bearer,
          body: HistoryBackup(version: 1 << 40, data: bytes(8)).toJson(),
        );
        expect(huge.status, 400);
        expect(huge.errorCode, 'invalid_field');

        final client = HttpClient();
        try {
          final request = await client.getUrl(
            h.server.baseUri.replace(path: '/v1/keys/%FF%FE'),
          );
          request.headers.set('authorization', 'Bearer ${alice.bearer}');
          final response = await request.close();
          await response.drain<void>();
          expect(response.statusCode, 400);
        } finally {
          client.close(force: true);
        }
      },
    );
  });
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('condition not met');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
