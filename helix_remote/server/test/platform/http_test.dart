import 'dart:async';
import 'dart:convert';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/http/idempotency.dart';
import 'package:helix_remote_server/src/platform/http/pipeline.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/observability/log.dart';
import 'package:helix_remote_server/src/platform/observability/metrics.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

const _open = RateLimitPolicy('test.open', capacity: 100, perSecond: 100);

/// Accepts the bearer token `good` as device d1 of account a1.
final class _FakeAuth implements Authenticator {
  @override
  Future<DevicePrincipal?> device(String token) async => token == 'good'
      ? const DevicePrincipal(accountId: 'a1', deviceId: 'd1')
      : null;

  @override
  Future<AdminPrincipal?> admin(String token) async => null;

  @override
  Future<ServerPrincipal?> server(Request request, List<int> body) async =>
      null;
}

/// The store when writing the answer fails - the database that goes down
/// right after the handler committed (AUD-11a-2).
final class _RecordFails implements IdempotencyStore {
  _RecordFails(this._inner);

  final IdempotencyStore _inner;

  @override
  Future<IdempotencyClaim> claim(
    String principal,
    String key,
    String requestHash,
  ) => _inner.claim(principal, key, requestHash);

  @override
  Future<void> record(
    String principal,
    String key,
    StoredResponse response,
  ) async => throw StateError('the answer could not be written');

  @override
  Future<void> release(String principal, String key, String requestHash) =>
      _inner.release(principal, key, requestHash);

  @override
  Future<int> sweep() => _inner.sweep();
}

void main() {
  late MemorySink sink;
  late InMemoryRateLimiter limiter;
  late int sendCalls;

  Handler build(
    void Function(RouteRegistry r) register, {
    Future<bool> Function()? maintenance,
    BodyBudget? bodyBudget,
    IdempotencyStore? idempotency,
  }) {
    sink = MemorySink();
    limiter = InMemoryRateLimiter();
    final registry = RouteRegistry();
    register(registry);
    return HttpPipeline(
      log: Log(sink: sink),
      metrics: Metrics(),
      rateLimiter: limiter,
      trustedProxies: const {'127.0.0.1'},
      maintenance: maintenance,
    ).wrap(
      registry.build(
        authenticator: _FakeAuth(),
        rateLimiter: limiter,
        idempotency: idempotency ?? InMemoryIdempotencyStore(),
        bodyBudget: bodyBudget,
      ),
    );
  }

  Future<Response> call(
    Handler handler,
    String method,
    String path, {
    Map<String, String> headers = const {},
    Object? body,
  }) async => handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: headers,
      body: body,
    ),
  );

  Future<Map<String, Object?>> errorOf(Response r) async =>
      (jsonDecode(await r.readAsString()) as Map)['error']
          as Map<String, Object?>;

  group('RouteRegistry', () {
    test(
      'only catalog routes, by their own module, with limits on public ones',
      () {
        final r = RouteRegistry();
        Response ok(HelixRequest _) => Response.ok('');
        expect(
          () => r.add(
            'ops',
            const ApiRoute(
              HttpMethod.get,
              '/v1/secret',
              module: 'ops',
              access: RouteAccess.public,
            ),
            ok,
            rateLimit: _open,
          ),
          throwsArgumentError,
        );
        expect(
          () => r.add('identity', Routes.live, ok, rateLimit: _open),
          throwsArgumentError,
        );
        expect(
          () => r.add('ops', Routes.live, ok),
          throwsArgumentError,
          reason: 'public needs a limit',
        );
        r.add('ops', Routes.live, ok, rateLimit: _open);
        expect(
          () => r.add('ops', Routes.live, ok, rateLimit: _open),
          throwsArgumentError,
        );
        expect(r.missingFor({'ops'}), contains(Routes.ready));
      },
    );
  });

  group('pipeline', () {
    test(
      'device routes need a valid token; principal reaches the handler',
      () async {
        final handler = build(
          (r) => r.add('keys', Routes.keyStatus, (req) {
            return jsonResponse({'device': req.device.deviceId});
          }),
        );
        final anonymous = await call(handler, 'GET', '/v1/keys/status');
        expect(anonymous.statusCode, 401);
        expect((await errorOf(anonymous))['code'], 'unauthenticated');
        final bad = await call(
          handler,
          'GET',
          '/v1/keys/status',
          headers: {'authorization': 'Bearer nope'},
        );
        expect(bad.statusCode, 401);
        final good = await call(
          handler,
          'GET',
          '/v1/keys/status',
          headers: {'authorization': 'Bearer good'},
        );
        expect(good.statusCode, 200);
        expect(jsonDecode(await good.readAsString()), {'device': 'd1'});
        expect(good.headers['x-request-id'], isNotEmpty);
        expect(good.headers['cache-control'], 'no-store');
      },
    );

    test('literal routes win over parameter routes', () async {
      final handler = build((r) {
        r.add(
          'keys',
          Routes.accountKeys,
          (req) => Response.ok('account ${req.param('account')}'),
        );
        r.add('keys', Routes.keyStatus, (req) => Response.ok('status'));
      });
      final auth = {'authorization': 'Bearer good'};
      expect(
        await (await call(
          handler,
          'GET',
          '/v1/keys/status',
          headers: auth,
        )).readAsString(),
        'status',
      );
      expect(
        await (await call(
          handler,
          'GET',
          '/v1/keys/0192a4f0-0000-7000-8000-00000000000b',
          headers: auth,
        )).readAsString(),
        'account 0192a4f0-0000-7000-8000-00000000000b',
      );
    });

    test('a path parameter is decoded once, not twice', () async {
      final handler = build(
        (r) => r.add(
          'people',
          Routes.findByName,
          (req) => Response.ok(req.param('name')),
        ),
      );
      final auth = {'authorization': 'Bearer good'};
      Future<String> name(String encoded) async => (await call(
        handler,
        'GET',
        '/v1/people/by-name/$encoded',
        headers: auth,
      )).readAsString();

      // The wire value is percent-encoded, so a handler of a name with a space
      // or a non-ASCII letter needs the decode to happen at all.
      expect(await name('Helix%20Name'), 'Helix Name');
      // `%252F` is an encoded slash *inside* the value. It decodes to `%2F`; a
      // second decode would hand the handler a `/`, which is the one segment
      // the route match already decided it may not hold (AUD-1a-2, whose
      // premise - that shelf_router hands over a decoded path - is not true).
      expect(await name('%252F'), '%2F');
      // A name holding a literal `%` is addressable (sent as `%25`), not a
      // 400 from a decode that cannot read it.
      expect(await name('foo%25'), 'foo%');
      // A percent-escape that is not a whole UTF-8 sequence never reaches a
      // handler at all: shelf refuses the request while building it, so the
      // router's own decode only ever sees values that came through.
      await expectLater(
        call(handler, 'GET', '/v1/people/by-name/%E0%A4%A', headers: auth),
        throwsA(isA<ArgumentError>()),
      );
      // And a name that simply holds a stray `%` in the middle is addressable.
      expect(await name('a%zb'), 'a%zb');
    });

    test('routes of equal specificity are ordered by their template', () async {
      // `/v1/people/by-name/{name}` and `/v1/people/{account}/profile` score
      // the same and both answer `/v1/people/by-name/profile`, so the order
      // must come from the template, not from which registered first.
      void byName(RouteRegistry r) => r.add(
        'people',
        Routes.findByName,
        (req) => Response.ok('name ${req.param('name')}'),
      );
      void profile(RouteRegistry r) => r.add(
        'people',
        Routes.profile,
        (req) => Response.ok('profile ${req.param('account')}'),
      );
      for (final order in [(byName, profile), (profile, byName)]) {
        final handler = build((r) {
          order.$1(r);
          order.$2(r);
        });
        expect(
          await (await call(
            handler,
            'GET',
            '/v1/people/by-name/profile',
            headers: const {'authorization': 'Bearer good'},
          )).readAsString(),
          'name profile',
          reason: 'the literal segment comes before the parameter',
        );
      }
    });

    test('no two catalog routes can answer the same request', () {
      expect(RouteRegistry.ambiguousPairs(Routes.all), isEmpty);
      expect(
        RouteRegistry.ambiguousPairs([
          const ApiRoute(
            HttpMethod.get,
            '/v1/x/{one}',
            module: 'ops',
            access: RouteAccess.device,
          ),
          const ApiRoute(
            HttpMethod.get,
            '/v1/x/{other}',
            module: 'ops',
            access: RouteAccess.device,
          ),
        ]),
        hasLength(1),
        reason: 'whichever is added second would be unreachable',
      );
    });

    test(
      'malformed bodies name the field; unknown routes are JSON 404s',
      () async {
        final handler = build(
          (r) => r.add('keys', Routes.addOneTimePrekeys, (req) {
            final body = req.json(AddOneTimePrekeysRequest.fromJson);
            return jsonResponse({'n': body.keys.length});
          }),
        );
        final auth = {'authorization': 'Bearer good'};
        final bad = await call(
          handler,
          'POST',
          '/v1/keys/one-time-prekeys',
          headers: auth,
          body: '{"keys":[{"id":"x","public_key":"AA"}]}',
        );
        expect(bad.statusCode, 400);
        final error = await errorOf(bad);
        expect(error['code'], 'invalid_field');
        expect(error['details'], {'field': 'keys[0].id'});
        final missing = await call(handler, 'GET', '/v1/nowhere');
        expect(missing.statusCode, 404);
        expect((await errorOf(missing))['code'], 'not_found');
      },
    );

    test('bodies over the route limit are refused', () async {
      final handler = build(
        (r) => r.add(
          'keys',
          Routes.addOneTimePrekeys,
          (req) => noContent(),
          maxBodyBytes: 10,
        ),
      );
      final response = await call(
        handler,
        'POST',
        '/v1/keys/one-time-prekeys',
        headers: {'authorization': 'Bearer good'},
        body: 'x' * 11,
      );
      expect(response.statusCode, 413);
    });

    test(
      'a body that stops arriving is refused and stops holding the budget',
      () async {
        // The budget is node-wide, so before this fix one anonymous client
        // declaring 256 KiB and sending nothing kept its slice until the
        // operating system dropped the socket - around 1,024 such connections
        // answered every later request on the node with 503 "the server is
        // busy" (AUD-1a-1).
        final budget = BodyBudget(
          1024,
          idleGap: const Duration(milliseconds: 50),
          deadline: const Duration(seconds: 5),
        );
        final handler = build(
          (r) => r.add(
            'keys',
            Routes.addOneTimePrekeys,
            (req) => noContent(),
            maxBodyBytes: 1024,
          ),
          bodyBudget: budget,
        );
        final stalled = StreamController<List<int>>();
        addTearDown(stalled.close);

        final response = await call(
          handler,
          'POST',
          '/v1/keys/one-time-prekeys',
          headers: {'authorization': 'Bearer good', 'content-length': '1024'},
          body: stalled.stream,
        );

        expect(response.statusCode, 408);
        expect((await errorOf(response))['code'], 'request_timeout');
        expect(budget.inFlight, 0, reason: 'the reservation came back');

        final next = await call(
          handler,
          'POST',
          '/v1/keys/one-time-prekeys',
          headers: {'authorization': 'Bearer good'},
          body: '{}',
        );
        expect(next.statusCode, 204, reason: 'the node still takes bodies');
      },
    );

    test(
      'a body that dribbles for ever is refused at the overall deadline',
      () async {
        // An idle gap alone would be beaten by a client that sends one byte
        // every few milliseconds: it never goes quiet, and it never finishes.
        final budget = BodyBudget(
          1024 * 1024,
          idleGap: const Duration(seconds: 5),
          deadline: const Duration(milliseconds: 100),
        );
        final handler = build(
          (r) => r.add('keys', Routes.addOneTimePrekeys, (req) => noContent()),
          bodyBudget: budget,
        );

        final response = await call(
          handler,
          'POST',
          '/v1/keys/one-time-prekeys',
          headers: {'authorization': 'Bearer good'},
          body: Stream.periodic(
            const Duration(milliseconds: 10),
            (i) => const <int>[0],
          ),
        );

        expect(response.statusCode, 408);
        expect(budget.inFlight, 0);
      },
    );

    test('route rate limits apply per principal and set retry-after', () async {
      const tight = RateLimitPolicy('test.tight', capacity: 1, perSecond: 0.01);
      final handler = build(
        (r) => r.add(
          'ops',
          Routes.live,
          (req) => Response.ok('ok'),
          rateLimit: tight,
        ),
      );
      expect((await call(handler, 'GET', '/v1/health/live')).statusCode, 200);
      final limited = await call(handler, 'GET', '/v1/health/live');
      expect(limited.statusCode, 429);
      expect(int.parse(limited.headers['retry-after']!), greaterThan(0));
    });

    test(
      'idempotency keys replay the first response and catch reuse',
      () async {
        final handler = build(
          (r) => r.add('messaging', Routes.sendMessage, (req) {
            sendCalls++;
            return jsonResponse({'call': sendCalls});
          }),
        );
        sendCalls = 0;
        final headers = {
          'authorization': 'Bearer good',
          'idempotency-key': 'k1',
        };
        final first = await call(
          handler,
          'POST',
          '/v1/messages',
          headers: headers,
          body: '{"a":1}',
        );
        final again = await call(
          handler,
          'POST',
          '/v1/messages',
          headers: headers,
          body: '{"a":1}',
        );
        expect(await first.readAsString(), '{"call":1}');
        expect(await again.readAsString(), '{"call":1}');
        expect(again.headers['idempotent-replay'], 'true');
        expect(sendCalls, 1);
        final conflict = await call(
          handler,
          'POST',
          '/v1/messages',
          headers: headers,
          body: '{"a":2}',
        );
        expect(conflict.statusCode, 409);
        expect((await errorOf(conflict))['code'], 'idempotency_conflict');
      },
    );

    test(
      'two requests with one key at the same time: one runs, one is told to wait',
      () async {
        final entered = Completer<void>();
        final mayFinish = Completer<void>();
        sendCalls = 0;
        final handler = build(
          (r) => r.add('messaging', Routes.sendMessage, (req) async {
            sendCalls++;
            entered.complete();
            await mayFinish.future;
            return jsonResponse({'call': sendCalls});
          }),
        );
        final headers = {
          'authorization': 'Bearer good',
          'idempotency-key': 'k1',
        };
        final first = call(
          handler,
          'POST',
          '/v1/messages',
          headers: headers,
          body: '{"a":1}',
        );
        await entered.future;
        final duplicate = await call(
          handler,
          'POST',
          '/v1/messages',
          headers: headers,
          body: '{"a":1}',
        );
        expect(duplicate.statusCode, 503);
        expect((await errorOf(duplicate))['code'], 'unavailable');
        expect(duplicate.headers['retry-after'], isNotNull);
        expect(sendCalls, 1, reason: 'the duplicate never reached the handler');
        mayFinish.complete();
        expect(await (await first).readAsString(), '{"call":1}');
        final after = await call(
          handler,
          'POST',
          '/v1/messages',
          headers: headers,
          body: '{"a":1}',
        );
        expect(after.headers['idempotent-replay'], 'true');
        expect(await after.readAsString(), '{"call":1}');
        expect(sendCalls, 1);
      },
    );

    test(
      'a retry whose answer could not be written does not run the handler again',
      () async {
        sendCalls = 0;
        final handler = build(
          (r) => r.add('messaging', Routes.sendMessage, (req) {
            sendCalls++;
            return jsonResponse({'call': sendCalls});
          }),
          idempotency: _RecordFails(InMemoryIdempotencyStore()),
        );
        final headers = {
          'authorization': 'Bearer good',
          'idempotency-key': 'k1',
        };
        final lost = await call(
          handler,
          'POST',
          '/v1/messages',
          headers: headers,
          body: '{"a":1}',
        );
        expect(lost.statusCode, 500);
        final retry = await call(
          handler,
          'POST',
          '/v1/messages',
          headers: headers,
          body: '{"a":1}',
        );
        expect(retry.statusCode, 503);
        expect(
          sendCalls,
          1,
          reason: 'the first request committed: a second run would be twice',
        );
      },
    );

    test(
      'a request that failed gives the key back, so its retry runs',
      () async {
        sendCalls = 0;
        final handler = build(
          (r) => r.add('messaging', Routes.sendMessage, (req) {
            sendCalls++;
            throw const ApiError(ErrorCode.conflict);
          }),
        );
        final headers = {
          'authorization': 'Bearer good',
          'idempotency-key': 'k1',
        };
        expect(
          (await call(
            handler,
            'POST',
            '/v1/messages',
            headers: headers,
            body: '{"a":1}',
          )).statusCode,
          409,
        );
        expect(
          (await call(
            handler,
            'POST',
            '/v1/messages',
            headers: headers,
            body: '{"a":1}',
          )).statusCode,
          409,
        );
        expect(
          sendCalls,
          2,
          reason: 'a failed request committed nothing, so a retry may act',
        );
      },
    );

    test('a replay keeps every header the first answer carried', () async {
      sendCalls = 0;
      final handler = build(
        (r) => r.add('messaging', Routes.sendMessage, (req) {
          sendCalls++;
          return Response(
            429,
            body: jsonEncode({
              'error': {'code': 'rate_limited'},
            }),
            headers: {'retry-after': '7', 'x-helix-limit': '20'},
          );
        }),
      );
      final headers = {'authorization': 'Bearer good', 'idempotency-key': 'k1'};
      await call(
        handler,
        'POST',
        '/v1/messages',
        headers: headers,
        body: '{"a":1}',
      );
      final replay = await call(
        handler,
        'POST',
        '/v1/messages',
        headers: headers,
        body: '{"a":1}',
      );
      expect(sendCalls, 1);
      expect(replay.statusCode, 429);
      expect(replay.headers['retry-after'], '7');
      expect(replay.headers['x-helix-limit'], '20');
      expect(replay.headers['idempotent-replay'], 'true');
    });

    test('a replay of a 204 stays a 204 with no content type', () async {
      final handler = build(
        (r) => r.add(
          'messaging',
          Routes.sendMessage,
          (req) => Response(204, headers: {'x-helix-offset': '12'}),
        ),
      );
      final headers = {'authorization': 'Bearer good', 'idempotency-key': 'k1'};
      await call(
        handler,
        'POST',
        '/v1/messages',
        headers: headers,
        body: '{"a":1}',
      );
      final replay = await call(
        handler,
        'POST',
        '/v1/messages',
        headers: headers,
        body: '{"a":1}',
      );
      expect(replay.statusCode, 204);
      expect(replay.headers['content-type'], isNull);
      expect(replay.headers['x-helix-offset'], '12');
      expect(await replay.readAsString(), isEmpty);
    });

    test(
      'unexpected errors are 500s that leak nothing; the log has the type only',
      () async {
        final handler = build(
          (r) => r.add(
            'ops',
            Routes.live,
            (req) => throw StateError('secret detail'),
            rateLimit: _open,
          ),
        );
        final response = await call(handler, 'GET', '/v1/health/live');
        expect(response.statusCode, 500);
        final body = await response.readAsString();
        expect(body, isNot(contains('secret')));
        expect(sink.lines.join(), contains('StateError'));
        expect(sink.lines.join(), isNot(contains('secret detail')));
      },
    );

    test(
      'maintenance mode refuses everything except health and admin',
      () async {
        final handler = build((r) {
          r.add(
            'ops',
            Routes.live,
            (req) => Response.ok('ok'),
            rateLimit: _open,
          );
          r.add('keys', Routes.keyStatus, (req) => Response.ok('ok'));
        }, maintenance: () async => true);
        expect((await call(handler, 'GET', '/v1/health/live')).statusCode, 200);
        final refused = await call(
          handler,
          'GET',
          '/v1/keys/status',
          headers: {'authorization': 'Bearer good'},
        );
        expect(refused.statusCode, 503);
        expect((await errorOf(refused))['code'], 'maintenance');
      },
    );

    test('access log lines carry the route template, not ids', () async {
      final handler = build(
        (r) => r.add('keys', Routes.accountKeys, (req) => Response.ok('')),
      );
      await call(
        handler,
        'GET',
        '/v1/keys/0192a4f0-0000-7000-8000-00000000000b',
        headers: {'authorization': 'Bearer good'},
      );
      final line = sink.lines.last;
      expect(line, contains('/v1/keys/{account}'));
      expect(line, isNot(contains('0192a4f0-0000-7000-8000-00000000000b')));
    });

    test('an upload access line says how many bytes it carried', () async {
      final handler = build(
        (r) => r.add('keys', Routes.setSignedPrekey, (req) => Response.ok('')),
      );
      const auth = {'authorization': 'Bearer good'};
      await call(
        handler,
        'PUT',
        '/v1/keys/signed-prekey',
        headers: auth,
        body: 'x',
      );
      expect(sink.lines.last, contains('"bytes":1'));

      await call(handler, 'PUT', '/v1/keys/signed-prekey', headers: auth);
      expect(
        sink.lines.last,
        isNot(contains('"bytes"')),
        reason: 'a request without a body adds nothing to the line',
      );
    });
  });
}
