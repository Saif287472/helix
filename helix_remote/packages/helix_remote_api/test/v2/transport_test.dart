import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

void main() {
  late FakeHttp server;
  late List<Duration> slept;
  late MemorySessionStore store;
  late DeviceSessionAuth auth;
  late int refreshCalls;

  HelixTransport transport({
    AuthProvider? withAuth,
    RetryPolicy retry = const RetryPolicy(),
    Duration timeout = const Duration(seconds: 30),
  }) => HelixTransport(
    baseUrl: Uri.parse('https://helix.test/base'),
    client: server.client,
    auth: withAuth ?? auth,
    clientName: 'cli/2.0.0',
    retry: retry,
    timeout: timeout,
    sleep: (d) async => slept.add(d),
    random: Random(1),
  );

  setUp(() {
    server = FakeHttp();
    slept = [];
    refreshCalls = 0;
    store = MemorySessionStore(session('t1'));
    auth = DeviceSessionAuth(
      store: store,
      refresher: (refreshToken) async {
        refreshCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return session('t${refreshCalls + 1}');
      },
    );
  });

  group('requests', () {
    test('build URLs from the catalog under the base path', () async {
      server.handler = (_) => ok(
        AccountKeys(
          account: 'id@other.example',
          identityKey: Uint8List(32),
          devices: const [],
        ).toJson(),
      );
      await KeysClient(
        transport(),
      ).accountKeys('id@other.example', devices: ['d1', 'd2']);
      final url = server.seen.single.url;
      expect(url.path, '/base/v1/keys/id%40other.example');
      expect(url.queryParametersAll['device'], ['d1', 'd2']);
    });

    test('device requests carry the bearer, a request id and the client; '
        'unsafe ones an idempotency key', () async {
      server.handler = (_) => noContent();
      final t = transport();
      await t.empty(Routes.setHelixName, json: {'name': 'alice'});
      await t.send(Routes.devices);
      final put = server.seen[0];
      expect(put.bearer, 't1');
      expect(put.headers[HelixHeaders.client], 'cli/2.0.0');
      expect(put.headers[HelixHeaders.requestId], isNotEmpty);
      expect(put.headers[HelixHeaders.idempotencyKey], isNotEmpty);
      expect(put.headers['content-type'], startsWith('application/json'));
      expect(jsonDecode(put.body), {'name': 'alice'});
      final get = server.seen[1];
      expect(get.headers.containsKey(HelixHeaders.idempotencyKey), isFalse);
      expect(
        get.headers[HelixHeaders.requestId],
        isNot(put.headers[HelixHeaders.requestId]),
      );
    });

    test('public routes never carry the device token', () async {
      server.handler = (_) =>
          ok(const InviteLookupResponse(valid: true).toJson());
      await IdentityClient(transport()).inviteLookup('HLX-CODE');
      expect(server.seen.single.headers, isNot(contains('authorization')));
    });

    test('an explicit bearer (the link poll token) replaces the session', () {
      server.handler = (_) =>
          ok(const LinkPollResponse(status: LinkStatus.pending).toJson());
      return IdentityClient(transport())
          .pollLink(
            'link',
            pollToken: 'poll-secret',
            wait: const Duration(seconds: 3),
          )
          .then((r) {
            expect(r.status, LinkStatus.pending);
            expect(server.seen.single.bearer, 'poll-secret');
            expect(server.seen.single.url.queryParameters['wait_s'], '3');
          });
    });

    test('message sends use the message id as the idempotency key', () async {
      server.handler = (_) =>
          ok(SendMessageResponse(acceptedAt: DateTime.utc(2026)).toJson());
      final id = Uuid.v7();
      await MessagingClient(
        transport(),
      ).send(SendMessageRequest(id: id, recipients: const []));
      expect(server.seen.single.headers[HelixHeaders.idempotencyKey], id);
    });

    test('a device transport refuses admin routes and S2S routes', () async {
      final t = transport();
      expect(() => t.send(Routes.adminAccounts), throwsStateError);
      expect(() => t.send(Routes.s2sMessages), throwsArgumentError);
      expect(server.seen, isEmpty);
    });

    test('device routes without any session are signed out', () async {
      await store.clear();
      final t = HelixTransport(
        baseUrl: Uri.parse('https://helix.test'),
        client: server.client,
        auth: DeviceSessionAuth(
          store: MemorySessionStore(),
          refresher: (_) => throw StateError('no refresh'),
        ),
      );
      await expectLater(
        t.send(Routes.account),
        throwsA(
          isA<SignedOutException>().having(
            (e) => e.reason,
            'reason',
            SignedOutReason.noSession,
          ),
        ),
      );
    });
  });

  group('refresh', () {
    test('concurrent 401s refresh once and every request retries with the '
        'new token', () async {
      server.handler = (r) => r.bearer == 't1'
          ? apiError(ErrorCode.tokenExpired)
          : ok(const DeviceList(devices: []).toJson());
      final client = IdentityClient(transport());
      final results = await Future.wait([
        for (var i = 0; i < 5; i++) client.devices(),
      ]);
      expect(results, hasLength(5));
      expect(refreshCalls, 1);
      expect((await store.read())!.accessToken, 't2');
      final retried = server.seen.where((r) => r.bearer == 't2');
      expect(retried, hasLength(5));
    });

    test('a token about to expire is refreshed before it is sent', () async {
      await store.write(session('t1', ttl: const Duration(seconds: 10)));
      server.handler = (_) => noContent();
      await transport().send(Routes.devices);
      expect(refreshCalls, 1);
      expect(server.seen.single.bearer, 't2');
    });

    test('a refused refresh clears the session and signs out', () async {
      final signedOut = <SignedOutException>[];
      final a = DeviceSessionAuth(
        store: store,
        refresher: (_) async => throw const ApiException(
          status: 401,
          code: ErrorCode.unauthenticated,
        ),
      );
      a.signedOut.listen(signedOut.add);
      server.handler = (_) => apiError(ErrorCode.unauthenticated);
      await expectLater(
        transport(withAuth: a).send(Routes.devices),
        throwsA(
          isA<SignedOutException>()
              .having(
                (e) => e.reason,
                'reason',
                SignedOutReason.refreshRejected,
              )
              .having((e) => e.code, 'code', ErrorCode.unauthenticated),
        ),
      );
      expect(await store.read(), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(signedOut, hasLength(1));
    });

    test('a refused refresh tries the reauthenticate hook first', () async {
      final a = DeviceSessionAuth(
        store: store,
        refresher: (_) async =>
            throw const ApiException(status: 403, code: ErrorCode.forbidden),
        reauthenticate: () async => session('signed-in-again'),
      );
      server.handler = (r) =>
          r.bearer == 't1' ? apiError(ErrorCode.unauthenticated) : noContent();
      await transport(withAuth: a).send(Routes.devices);
      expect(server.seen.last.bearer, 'signed-in-again');
      expect((await store.read())!.accessToken, 'signed-in-again');
    });

    test('a refresh that gets no answer keeps the session', () async {
      final a = DeviceSessionAuth(
        store: store,
        refresher: (_) async => throw const NetworkException(),
      );
      server.handler = (_) => apiError(ErrorCode.unauthenticated);
      await expectLater(
        transport(withAuth: a).send(Routes.devices),
        throwsA(isA<NetworkException>()),
      );
      expect((await store.read())!.accessToken, 't1');
    });

    test('a request that failed with an older token takes the newer one '
        'without refreshing again', () async {
      await auth.refresh('t1');
      expect(refreshCalls, 1);
      expect(await auth.refresh('t1'), 't2');
      expect(refreshCalls, 1);
    });

    test(
      'admin tokens are not refreshed: a 401 signs the console out',
      () async {
        final admin = AdminTokenAuth(
          session: AdminSession(
            token: 'admin-token',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );
        server.handler = (_) => apiError(ErrorCode.unauthenticated);
        await expectLater(
          transport(withAuth: admin).send(Routes.adminAccounts),
          throwsA(
            isA<SignedOutException>().having(
              (e) => e.reason,
              'reason',
              SignedOutReason.sessionEnded,
            ),
          ),
        );
        expect(admin.session, isNull);
        expect(server.seen.single.bearer, 'admin-token');
      },
    );
  });

  group('errors', () {
    test('a 401 invalid_credentials is a wrong password, not a rejected '
        'token: no refresh and the admin session stays', () async {
      final admin = AdminTokenAuth(
        session: AdminSession(
          token: 'admin-token',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      server.handler = (_) => apiError(ErrorCode.invalidCredentials);
      await expectLater(
        transport(withAuth: admin).send(Routes.adminPassword),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ErrorCode.invalidCredentials,
          ),
        ),
      );
      expect(admin.session, isNotNull);
      expect(server.seen, hasLength(1));
    });

    test('every protocol error code maps to a typed ApiException', () async {
      final t = transport(retry: RetryPolicy.none);
      for (final code in ErrorCode.values) {
        if (code == ErrorCode.unknown) continue;
        server.handler = (_) => apiError(code);
        await expectLater(
          t.send(Routes.devices),
          throwsA(
            isA<ApiException>()
                .having((e) => e.code, 'code', code)
                .having((e) => e.status, 'status', code.status),
          ),
          reason: code.wire,
        );
      }
    });

    test('an unknown code keeps its status; a body that is not a v2 error '
        'maps by status class', () async {
      final t = transport(retry: RetryPolicy.none);
      server.handler = (_) =>
          http.Response('{"error":{"code":"brand_new"}}', 418);
      await expectLater(
        t.send(Routes.devices),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', ErrorCode.unknown)
              .having((e) => e.status, 'status', 418),
        ),
      );
      for (final (status, code) in [
        (502, ErrorCode.unavailable),
        (404, ErrorCode.notFound),
        (500, ErrorCode.internal),
        (401, ErrorCode.unauthenticated),
      ]) {
        server.handler = (_) => http.Response('<html>proxy</html>', status);
        await expectLater(
          t.send(Routes.serverInfo),
          throwsA(isA<ApiException>().having((e) => e.code, 'code', code)),
        );
      }
    });

    test('device_list_stale carries the stale device lists', () async {
      const stale = StaleDevices(
        accounts: [
          StaleAccountDevices(account: 'bob', missing: ['b2'], extra: ['b0']),
        ],
      );
      server.handler = (_) =>
          apiError(ErrorCode.deviceListStale, details: stale.toJson());
      try {
        await MessagingClient(
          transport(),
        ).send(SendMessageRequest(id: Uuid.v7(), recipients: const []));
        fail('expected device_list_stale');
      } on ApiException catch (e) {
        expect(e.code, ErrorCode.deviceListStale);
        expect(e.staleDevices!.accounts.single.missing, ['b2']);
        expect(e.staleDevices!.accounts.single.extra, ['b0']);
      }
    });

    test('password_locked carries locked_until and is not retried', () async {
      final until = DateTime.utc(2026, 10, 2, 12);
      server.handler = (_) => apiError(
        ErrorCode.passwordLocked,
        details: {'locked_until': toWireTime(until)},
        retryAfter: const Duration(minutes: 15),
      );
      try {
        await transport().send(Routes.setPassword, json: {});
        fail('expected password_locked');
      } on ApiException catch (e) {
        expect(e.lockedUntil, until);
        expect(e.retryAfter, const Duration(minutes: 15));
      }
      expect(server.seen, hasLength(1));
    });

    test('a malformed 2xx body is a MalformedResponseException naming the '
        'field', () async {
      server.handler = (_) => ok({'devices': 'nope'});
      await expectLater(
        IdentityClient(transport()).devices(),
        throwsA(
          isA<MalformedResponseException>().having(
            (e) => e.path,
            'path',
            'devices',
          ),
        ),
      );
    });

    test('exceptions never repeat tokens or bodies', () async {
      server.handler = (_) => http.Response(
        jsonEncode({
          'error': {'code': 'forbidden', 'message': 'no'},
          'secret': 'body-secret',
        }),
        403,
      );
      final t = transport(retry: RetryPolicy.none);
      Object? error;
      try {
        await t.send(Routes.setHelixName, json: {'name': 'request-secret'});
      } on Object catch (e) {
        error = e;
      }
      final text = error.toString();
      expect(text, contains('forbidden'));
      for (final secret in [
        't1',
        'refresh-t1',
        'body-secret',
        'request-secret',
      ]) {
        expect(text, isNot(contains(secret)));
      }
      expect(
        const SignedOutException(SignedOutReason.noSession).toString(),
        isNot(contains('t1')),
      );
    });
  });

  group('retries', () {
    test('a GET waits out Retry-After on 503 and then succeeds', () async {
      var calls = 0;
      server.handler = (_) => ++calls == 1
          ? apiError(
              ErrorCode.maintenance,
              retryAfter: const Duration(seconds: 7),
            )
          : ok(const DeviceList(devices: []).toJson());
      await IdentityClient(transport()).devices();
      expect(calls, 2);
      expect(slept, [const Duration(seconds: 7)]);
    });

    test(
      'Retry-After in the body is honoured when the header is missing',
      () async {
        var calls = 0;
        server.handler = (_) => ++calls == 1
            ? apiError(
                ErrorCode.rateLimited,
                retryAfter: const Duration(seconds: 4),
                header: false,
              )
            : noContent();
        await transport().send(Routes.devices);
        expect(slept, [const Duration(seconds: 4)]);
      },
    );

    test('a device POST retries 429 with the same idempotency key', () async {
      var calls = 0;
      server.handler = (_) => ++calls < 3
          ? apiError(
              ErrorCode.rateLimited,
              retryAfter: const Duration(seconds: 2),
            )
          : ok(const AckResponse(deleted: 1).toJson());
      await MessagingClient(transport()).ack(5);
      expect(calls, 3);
      final keys = {
        for (final r in server.seen) r.headers[HelixHeaders.idempotencyKey],
      };
      expect(keys, hasLength(1));
      final ids = {
        for (final r in server.seen) r.headers[HelixHeaders.requestId],
      };
      expect(ids, hasLength(1), reason: 'one logical request');
    });

    test(
      'public POSTs are never retried (a repeated refresh is reuse)',
      () async {
        server.handler = (_) => apiError(ErrorCode.unavailable);
        await expectLater(
          IdentityClient(transport()).refresh('r'),
          throwsA(isA<ApiException>()),
        );
        expect(server.seen, hasLength(1));
        server.seen.clear();
        server.handler = (_) => throw http.ClientException('reset');
        await expectLater(
          IdentityClient(transport()).refresh('r'),
          throwsA(isA<NetworkException>()),
        );
        expect(server.seen, hasLength(1));
      },
    );

    test('a Retry-After beyond the cap is thrown, not waited', () async {
      server.handler = (_) =>
          apiError(ErrorCode.rateLimited, retryAfter: const Duration(hours: 1));
      await expectLater(
        transport().send(Routes.devices),
        throwsA(
          isA<ApiException>().having(
            (e) => e.retryAfter,
            'retryAfter',
            const Duration(hours: 1),
          ),
        ),
      );
      expect(slept, isEmpty);
    });

    test(
      'connection failures back off exponentially up to maxAttempts',
      () async {
        server.handler = (_) => throw http.ClientException('refused');
        await expectLater(
          transport(
            retry: const RetryPolicy(maxAttempts: 4, jitter: 0),
          ).send(Routes.devices),
          throwsA(isA<NetworkException>()),
        );
        expect(server.seen, hasLength(4));
        expect(slept, const [
          Duration(milliseconds: 500),
          Duration(seconds: 1),
          Duration(seconds: 2),
        ]);
      },
    );

    test('client errors are not retried', () async {
      server.handler = (_) => apiError(ErrorCode.invalidField);
      await expectLater(
        transport().send(Routes.devices),
        throwsA(isA<ApiException>()),
      );
      expect(server.seen, hasLength(1));
    });
  });

  group('timeouts and cancellation', () {
    test('a request with no answer times out', () async {
      server.handler = (_) => Completer<http.Response>().future;
      await expectLater(
        transport(
          retry: RetryPolicy.none,
          timeout: const Duration(milliseconds: 50),
        ).send(Routes.devices),
        throwsA(
          isA<NetworkException>().having((e) => e.timedOut, 'timedOut', true),
        ),
      );
    });

    test('cancelling aborts an in-flight request', () async {
      server.handler = (_) => Completer<http.Response>().future;
      final cancel = CancellationToken();
      final future = transport().send(Routes.devices, cancel: cancel);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      cancel.cancel();
      await expectLater(future, throwsA(isA<RequestCancelledException>()));
    });

    test('a cancelled token stops a request before it is sent', () async {
      final cancel = CancellationToken()..cancel();
      await expectLater(
        transport().send(Routes.devices, cancel: cancel),
        throwsA(isA<RequestCancelledException>()),
      );
      expect(server.seen, isEmpty);
    });
  });

  group('response size caps', () {
    test(
      'a JSON body over the cap is refused by its declared length',
      () async {
        server.handler = (_) =>
            http.Response.bytes(Uint8List(defaultMaxResponseBytes + 1), 200);
        await expectLater(
          IdentityClient(transport()).devices(),
          throwsA(isA<ResponseTooLargeException>()),
        );
      },
    );

    test('a body of unknown length is cut off while it streams in', () async {
      var pulled = 0;
      final client = MockClient.streaming((request, body) async {
        final chunks = Stream<List<int>>.periodic(const Duration(), (_) {
          pulled++;
          return Uint8List(1024 * 1024);
        });
        return http.StreamedResponse(chunks, 200);
      });
      final t = HelixTransport(
        baseUrl: Uri.parse('https://helix.test'),
        client: client,
        auth: auth,
        retry: RetryPolicy.none,
      );
      await expectLater(
        IdentityClient(t).devices(),
        throwsA(
          isA<ResponseTooLargeException>().having(
            (e) => e.limit,
            'limit',
            defaultMaxResponseBytes,
          ),
        ),
      );
      expect(pulled, lessThan(10), reason: 'it stopped reading at the cap');
    });

    test('a per-call cap applies; a body within it comes through', () async {
      server.handler = (_) => http.Response.bytes(Uint8List(100), 200);
      final response = await transport().send(
        Routes.devices,
        maxResponseBytes: 100,
      );
      expect(response.body, hasLength(100));
      await expectLater(
        transport().send(Routes.devices, maxResponseBytes: 99),
        throwsA(isA<ResponseTooLargeException>()),
      );
    });

    test(
      'media: a ranged request answered with the whole object, or with '
      'more than the range, is refused; the cap bounds the download',
      () async {
        final media = MediaClient(transport());
        server.handler = (_) => http.Response.bytes(Uint8List(10), 200);
        await expectLater(
          media.download('m1', start: 4, end: 6),
          throwsA(isA<RangeNotHonoredException>()),
        );
        // From byte 0 the whole object is a fine answer, within the cap.
        final first = await media.download(
          'm1',
          start: 0,
          end: 5,
          maxBytes: 10,
        );
        expect(first.partial, isFalse);
        await expectLater(
          media.download('m1', start: 0, end: 5, maxBytes: 9),
          throwsA(isA<ResponseTooLargeException>()),
        );
        server.handler = (_) => http.Response.bytes(
          Uint8List(10),
          206,
          headers: {'content-range': 'bytes 4-13/20'},
        );
        await expectLater(
          media.download('m1', start: 4, end: 6),
          throwsA(isA<RangeNotHonoredException>()),
        );
      },
    );
  });

  group('media', () {
    test('a download redirect is followed without the device token', () async {
      server.handler = (r) => r.url.host == 'helix.test'
          ? http.Response(
              '',
              302,
              headers: {'location': 'https://bucket.example/obj?sig=abc'},
            )
          : http.Response.bytes(
              [1, 2, 3],
              206,
              headers: {'content-range': 'bytes 4-6/10'},
            );
      final download = await MediaClient(
        transport(),
      ).download('m1', start: 4, end: 6);
      expect(download.bytes, [1, 2, 3]);
      expect(download.partial, isTrue);
      expect(download.size, 10);
      final [api, bucket] = server.seen;
      expect(api.bearer, 't1');
      expect(api.headers['range'], 'bytes=4-6');
      expect(bucket.url.host, 'bucket.example');
      expect(bucket.headers, isNot(contains('authorization')));
      expect(bucket.headers['range'], 'bytes=4-6');
    });

    test('a resumable upload resumes from the stored offset', () async {
      final data = List<int>.generate(10, (i) => i);
      var stored = 0;
      var conflicted = false;
      server.handler = (r) {
        final offset = int.parse(r.headers[MediaHeaders.uploadOffset]!);
        if (offset == 4 && !conflicted) {
          // An earlier attempt of this chunk landed partly.
          conflicted = true;
          stored = 6;
          return apiError(ErrorCode.conflict, details: {'upload_offset': 6});
        }
        stored = offset + r.request.bodyBytes.length;
        return http.Response(
          '',
          204,
          headers: {
            MediaHeaders.uploadOffset: '$stored',
            MediaHeaders.uploadLength: '10',
          },
        );
      };
      final progress = <int>[];
      await MediaClient(transport()).upload(
        UploadTarget(
          mediaId: 'm1',
          url: '/v1/media/m1/content',
          expiresAt: DateTime.utc(2027),
        ),
        data,
        chunkSize: 4,
        onProgress: (sent, _) => progress.add(sent),
      );
      expect(stored, 10);
      expect(server.seen.map((r) => r.headers[MediaHeaders.uploadOffset]), [
        '0',
        '4',
        '6',
      ]);
      expect(progress.last, 10);
    });

    test('a presigned upload is one PUT with the target headers and no '
        'token', () async {
      server.handler = (_) => http.Response('', 200);
      await MediaClient(transport()).upload(
        UploadTarget(
          mediaId: 'm1',
          url: 'https://bucket.example/m1?X-Amz-Signature=s',
          headers: const {'x-amz-acl': 'private'},
          expiresAt: DateTime.utc(2027),
          resumable: false,
        ),
        [1, 2, 3],
      );
      final put = server.seen.single;
      expect(put.method, 'PUT');
      expect(put.headers['x-amz-acl'], 'private');
      expect(put.headers, isNot(contains('authorization')));
      expect(put.request.bodyBytes, [1, 2, 3]);
    });
  });
}
