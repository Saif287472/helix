import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/clock.dart';
import 'package:helix_remote_server/src/platform/config/server_config.dart';
import 'package:helix_remote_server/src/platform/http/idempotency.dart';
import 'package:helix_remote_server/src/platform/http/pipeline.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/http/websocket_limits.dart';
import 'package:helix_remote_server/src/platform/observability/log.dart';
import 'package:helix_remote_server/src/platform/observability/metrics.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// S7 hardening of the HTTP platform, config and observability (no
/// database): auth before body, the body budget, S2S pre-checks, client
/// addresses, malformed input, JSON shape limits, WebSocket frame limits,
/// idempotency sealing, the shared boolean parser and the log file sink.
const _open = RateLimitPolicy('test.open', capacity: 100, perSecond: 100);

final class _Auth implements Authenticator {
  int serverCalls = 0;

  @override
  Future<DevicePrincipal?> device(String token) async => token == 'good'
      ? const DevicePrincipal(accountId: 'a1', deviceId: 'd1')
      : null;

  @override
  Future<AdminPrincipal?> admin(String token) async => null;

  @override
  Future<ServerPrincipal?> server(Request request, Uint8List body) async {
    serverCalls++;
    return null;
  }
}

final class _Peer implements HttpConnectionInfo {
  _Peer(String address) : remoteAddress = InternetAddress(address);

  @override
  final InternetAddress remoteAddress;

  @override
  int get remotePort => 40000;

  @override
  int get localPort => 8080;
}

/// A body stream that records whether anyone read it.
final class _Body {
  bool read = false;

  Stream<List<int>> stream(List<int> bytes) async* {
    read = true;
    yield bytes;
  }
}

void main() {
  late _Auth auth;
  late BodyBudget budget;
  final clock = ManualClock(DateTime.utc(2026, 10, 2, 12));

  Handler build(
    void Function(RouteRegistry r) register, {
    bool trustRealIp = false,
    int budgetBytes = 1024 * 1024,
  }) {
    auth = _Auth();
    budget = BodyBudget(budgetBytes);
    final limiter = InMemoryRateLimiter();
    final registry = RouteRegistry();
    register(registry);
    return HttpPipeline(
      log: Log(sink: MemorySink()),
      metrics: Metrics(),
      rateLimiter: limiter,
      trustedProxies: const {'127.0.0.1'},
      trustRealIp: trustRealIp,
    ).wrap(
      registry.build(
        authenticator: auth,
        rateLimiter: limiter,
        idempotency: InMemoryIdempotencyStore(),
        bodyBudget: budget,
        clock: clock,
      ),
    );
  }

  Future<Response> call(
    Handler handler,
    String method,
    String path, {
    Map<String, String> headers = const {},
    Object? body,
    String peer = '127.0.0.1',
  }) async => handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: headers,
      body: body,
      context: {'shelf.io.connection_info': _Peer(peer)},
    ),
  );

  Future<String?> codeOf(Response r) async =>
      ((jsonDecode(await r.readAsString()) as Map)['error'] as Map)['code']
          as String?;

  group('auth before body (#1)', () {
    test('a bad bearer is refused without reading the body', () async {
      final handler = build(
        (r) => r.add('keys', Routes.addOneTimePrekeys, (req) => noContent()),
      );
      final body = _Body();
      final response = await call(
        handler,
        'POST',
        '/v1/keys/one-time-prekeys',
        headers: {'authorization': 'Bearer nope'},
        body: body.stream(utf8.encode('{}')),
      );
      expect(response.statusCode, 401);
      expect(body.read, isFalse);
    });

    test('S2S routes refuse bad signature headers before the body', () async {
      final handler = build(
        (r) => r.add('federation', Routes.s2sMessages, (req) => noContent()),
      );
      final now = clock.now().millisecondsSinceEpoch;
      final signature = encodeBytes(List.filled(64, 1));
      for (final headers in [
        <String, String>{},
        {
          HelixHeaders.s2sServer: 'evil..example',
          HelixHeaders.s2sTimestamp: '$now',
          HelixHeaders.s2sSignature: signature,
        },
        {
          HelixHeaders.s2sServer: 'peer.example',
          HelixHeaders.s2sTimestamp: '${now - 6 * 60 * 1000}',
          HelixHeaders.s2sSignature: signature,
        },
        {
          HelixHeaders.s2sServer: 'peer.example',
          HelixHeaders.s2sTimestamp: '$now',
          HelixHeaders.s2sSignature: 'short',
        },
      ]) {
        final body = _Body();
        final response = await call(
          handler,
          'POST',
          '/v1/s2s/messages',
          headers: headers,
          body: body.stream(utf8.encode('{}')),
        );
        expect(response.statusCode, 401, reason: '$headers');
        expect(body.read, isFalse, reason: '$headers');
      }
      expect(auth.serverCalls, 0);

      // Plausible headers: the body is read and the signature verified.
      final body = _Body();
      final response = await call(
        handler,
        'POST',
        '/v1/s2s/messages',
        headers: {
          HelixHeaders.s2sServer: 'peer.example',
          HelixHeaders.s2sTimestamp: '$now',
          HelixHeaders.s2sSignature: signature,
        },
        body: body.stream(utf8.encode('{}')),
      );
      expect(response.statusCode, 401);
      expect(body.read, isTrue);
      expect(auth.serverCalls, 1);
    });

    test(
      'bodies over the node budget get unavailable, then it frees',
      () async {
        final handler = build(
          (r) => r.add('keys', Routes.addOneTimePrekeys, (req) => noContent()),
          budgetBytes: 10,
        );
        final headers = {'authorization': 'Bearer good'};
        final over = await call(
          handler,
          'POST',
          '/v1/keys/one-time-prekeys',
          headers: headers,
          body: 'x' * 11,
        );
        expect(over.statusCode, 503);
        expect(await codeOf(over), 'unavailable');
        expect(over.headers['retry-after'], isNotNull);
        // Chunked (no content-length) bodies are counted as they arrive.
        final chunked = await call(
          handler,
          'POST',
          '/v1/keys/one-time-prekeys',
          headers: headers,
          body: Stream.fromIterable([List.filled(6, 1), List.filled(6, 1)]),
        );
        expect(chunked.statusCode, 503);
        expect(budget.inFlight, 0);
        final fits = await call(
          handler,
          'POST',
          '/v1/keys/one-time-prekeys',
          headers: headers,
          body: 'x' * 10,
        );
        expect(fits.statusCode, 204);
        expect(budget.inFlight, 0);
      },
    );

    test('an extra bearer opens only the route that declares it', () async {
      final handler = build((r) {
        r.add(
          'ops',
          Routes.metrics,
          (req) => Response.ok(req.admin.adminId),
          extraBearer: (t) async => t == 'scrape'
              ? const AdminPrincipal(adminId: 'metrics-token')
              : null,
        );
        r.add('ops', Routes.live, (req) => Response.ok(''), rateLimit: _open);
      });
      final ok = await call(
        handler,
        'GET',
        '/v1/ops/metrics',
        headers: {'authorization': 'Bearer scrape'},
      );
      expect(ok.statusCode, 200);
      final wrong = await call(
        handler,
        'GET',
        '/v1/ops/metrics',
        headers: {'authorization': 'Bearer scrapes'},
      );
      expect(wrong.statusCode, 401);
      expect(
        () => RouteRegistry().add(
          'ops',
          Routes.live,
          (req) => Response.ok(''),
          rateLimit: _open,
          extraBearer: (t) async => null,
        ),
        throwsArgumentError,
      );
    });
  });

  group('client address (#8)', () {
    Handler ipEcho({bool trustRealIp = false}) => build(
      (r) => r.add(
        'ops',
        Routes.live,
        (req) => Response.ok(req.clientIp),
        rateLimit: _open,
      ),
      trustRealIp: trustRealIp,
    );

    Future<String> ip(
      Handler h, {
      Map<String, String> headers = const {},
      String peer = '127.0.0.1',
    }) async => (await call(
      h,
      'GET',
      '/v1/health/live',
      headers: headers,
      peer: peer,
    )).readAsString();

    test('X-Real-IP is ignored unless configured', () async {
      final h = ipEcho();
      expect(await ip(h, headers: {'x-real-ip': '9.9.9.9'}), '127.0.0.1');
      expect(
        await ip(ipEcho(trustRealIp: true), headers: {'x-real-ip': '9.9.9.9'}),
        '9.9.9.9',
      );
    });

    test('X-Forwarded-For: the rightmost hop that is not a proxy', () async {
      final h = ipEcho();
      // A client-written hop on the left never wins over what Caddy appended.
      expect(
        await ip(h, headers: {'x-forwarded-for': '1.1.1.1, 203.0.113.7'}),
        '203.0.113.7',
      );
      expect(
        await ip(h, headers: {'x-forwarded-for': '203.0.113.7, 127.0.0.1'}),
        '203.0.113.7',
      );
      // Headers from an untrusted peer are not believed at all.
      expect(
        await ip(
          h,
          headers: {'x-forwarded-for': '1.1.1.1', 'x-real-ip': '2.2.2.2'},
          peer: '198.51.100.4',
        ),
        '198.51.100.4',
      );
    });
  });

  group('malformed input is a 400 (#17)', () {
    test('JSON nesting and value counts are bounded before decoding', () {
      checkJsonShape(utf8.encode('{"a":[1,2,{"b":"x"}]}'), maxDepth: 3);
      expect(
        () => checkJsonShape(utf8.encode('[' * 65 + ']' * 65), maxDepth: 64),
        throwsA(isA<ApiError>()),
      );
      // Brackets inside strings are text, not nesting.
      checkJsonShape(utf8.encode('["${'[' * 100}"]'), maxDepth: 2);
      expect(
        () => checkJsonShape(
          utf8.encode('[${List.filled(11, '0').join(',')}]'),
          maxDepth: 4,
          maxNodes: 11,
        ),
        throwsA(isA<ApiError>()),
      );
      checkJsonShape(
        utf8.encode('{"k":"v","n":123,"t":true}'),
        maxDepth: 4,
        maxNodes: 7,
      );
    });

    test('a deep body is a bad_request, not a stack overflow', () async {
      final handler = build(
        (r) => r.add('keys', Routes.addOneTimePrekeys, (req) {
          req.json(AddOneTimePrekeysRequest.fromJson);
          return noContent();
        }),
      );
      final response = await call(
        handler,
        'POST',
        '/v1/keys/one-time-prekeys',
        headers: {'authorization': 'Bearer good'},
        body: '[' * 100000 + ']' * 100000,
      );
      expect(response.statusCode, 400);
      expect(await codeOf(response), 'bad_request');
    });
  });

  group('WebSocket frame limit (#15)', () {
    List<int> frame(int opcode, int length, {bool fin = true}) {
      final header = <int>[(fin ? 0x80 : 0) | opcode];
      if (length < 126) {
        header.add(0x80 | length);
      } else if (length < 65536) {
        header.addAll([0x80 | 126, length >> 8, length & 255]);
      } else {
        header.add(0x80 | 127);
        for (var shift = 56; shift >= 0; shift -= 8) {
          header.add((length >> shift) & 255);
        }
      }
      return [...header, 1, 2, 3, 4, ...List.filled(length, 0x61)];
    }

    test('small frames pass, split anywhere', () {
      final guard = WebSocketFrameGuard(1000);
      final bytes = [...frame(1, 10), ...frame(9, 4), ...frame(1, 500)];
      for (final b in bytes) {
        expect(guard.accept([b]), isTrue);
      }
    });

    test('a frame or fragmented message over the limit is refused', () {
      expect(WebSocketFrameGuard(1000).accept(frame(1, 1001)), isFalse);
      // The header alone is enough: the payload is never buffered.
      expect(
        WebSocketFrameGuard(1000).accept(frame(2, 70000).sublist(0, 14)),
        isFalse,
      );
      final guard = WebSocketFrameGuard(1000);
      expect(guard.accept(frame(1, 600, fin: false)), isTrue);
      expect(guard.accept(frame(0, 600)), isFalse);
      expect(WebSocketFrameGuard(1000).accept(frame(9, 126)), isFalse);
    });
  });

  group('idempotency sealing (#16)', () {
    final keys = {'k1': List.filled(32, 7), 'k2': List.filled(32, 8)};

    test('bodies open only for the same request, under a known key', () async {
      final sealer = IdempotencySealer(keys, 'k1');
      final sealed = await sealer.seal(
        '{"secret":"HLX-INV-abc"}',
        principal: 'device:d1',
        key: 'key-1',
        requestHash: 'h1',
      );
      expect(sealed, isNot(contains('HLX-INV')));
      expect(
        await sealer.open(
          sealed,
          principal: 'device:d1',
          key: 'key-1',
          requestHash: 'h1',
        ),
        '{"secret":"HLX-INV-abc"}',
      );
      expect(
        await sealer.open(
          sealed,
          principal: 'device:d2',
          key: 'key-1',
          requestHash: 'h1',
        ),
        isNull,
      );
      // Rotation: a newer active key still opens rows sealed under k1.
      expect(
        await IdempotencySealer(
          keys,
          'k2',
        ).open(sealed, principal: 'device:d1', key: 'key-1', requestHash: 'h1'),
        isNotNull,
      );
      expect(
        await IdempotencySealer(
          {'k2': keys['k2']!},
          'k2',
        ).open(sealed, principal: 'device:d1', key: 'key-1', requestHash: 'h1'),
        isNull,
      );
    });
  });

  group('config (D1, D2)', () {
    Map<String, String> base() => {
      'HELIX_DATABASE_URL': 'postgresql://localhost/x',
      'HELIX_JWT_KEYS': '{"a":"${encodeBytes(List.filled(32, 1))}"}',
    };

    test('one boolean syntax everywhere', () {
      for (final v in ['1', 'true', 'YES', ' True ']) {
        expect(parseEnvFlag(v), isTrue);
      }
      for (final v in ['0', 'false', 'no']) {
        expect(parseEnvFlag(v), isFalse);
      }
      expect(parseEnvFlag(null), isNull);
      expect(parseEnvFlag(''), isNull);
      expect(() => parseEnvFlag('on'), throwsFormatException);
      expect(envFlag({'X': '1'}, 'X'), isTrue);
      expect(() => envFlag({'X': 'maybe'}, 'X'), throwsA(isA<ConfigError>()));
    });

    test('new settings have defaults and are validated', () {
      final config = ServerConfig.fromEnv(base());
      expect(config.dbPoolSize, 10);
      expect(config.maxInFlightBodyBytes, 256 * 1024 * 1024);
      expect(config.trustRealIp, isFalse);
      expect(config.metricsToken, isNull);
      final custom = ServerConfig.fromEnv({
        ...base(),
        'HELIX_DB_POOL_SIZE': '25',
        'HELIX_TRUST_X_REAL_IP': 'yes',
        'HELIX_METRICS_TOKEN': 'm' * 32,
      });
      expect(custom.dbPoolSize, 25);
      expect(custom.trustRealIp, isTrue);
      expect(custom.metricsToken, 'm' * 32);
      try {
        ServerConfig.fromEnv({
          ...base(),
          'HELIX_DB_POOL_SIZE': '0',
          'HELIX_METRICS_TOKEN': 'short',
          'HELIX_GLOBAL_MODE': 'maybe',
        });
        fail('expected a ConfigError');
      } on ConfigError catch (e) {
        expect(e.problems, hasLength(3), reason: 'all problems at once');
        expect(e.toString(), isNot(contains('short')));
      }
    });

    test('HELIX_LOG_FILE: lines go to the file as well', () async {
      final dir = Directory.systemTemp.createTempSync('helix_log_');
      try {
        final path = '${dir.path}${Platform.pathSeparator}server.log';
        final file = FileSink.open(path);
        final memory = MemorySink();
        Log(sink: TeeSink([memory, file])).info('hello', {'n': 1});
        await file.close();
        expect(memory.lines, hasLength(1));
        expect(File(path).readAsStringSync().trim(), memory.lines.single);
        expect(
          () => FileSink.open('${dir.path}${Platform.pathSeparator}no/such/x'),
          throwsA(isA<FileSystemException>()),
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  group('metrics (D4)', () {
    test('collected gauges are read before rendering', () async {
      final m = Metrics();
      var backlog = 3.0;
      m
        ..collectedGauge('helix_backlog', 'backlog', () async => backlog)
        ..collectedGauge(
          'helix_broken',
          'broken',
          () async => throw StateError('db down'),
        );
      expect(m.render(), contains('helix_backlog NaN'));
      await m.collect();
      expect(m.render(), contains('helix_backlog 3.0'));
      backlog = 5;
      await m.collect();
      expect(m.render(), contains('helix_backlog 5.0'));
      expect(m.render(), contains('helix_broken NaN'));
    });
  });
}
