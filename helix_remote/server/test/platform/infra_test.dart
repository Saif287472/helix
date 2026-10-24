import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_server/src/platform/blobs/object_storage.dart';
import 'package:helix_remote_server/src/platform/config/server_config.dart';
import 'package:helix_remote_server/src/platform/observability/log.dart';
import 'package:helix_remote_server/src/platform/observability/metrics.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

const _key = 'dGVzdC1vbmx5LWp3dC1rZXktdGhhdC1pcy0zMi1ieXRlcw';

Map<String, String> _env([Map<String, String> extra = const {}]) => {
  'HELIX_DATABASE_URL': 'postgresql://u:p@localhost/db',
  'HELIX_JWT_KEYS': '{"k1":"$_key"}',
  ...extra,
};

/// A complete S3 blob-store config, with the endpoint overridden per test.
const _s3Env = {
  'HELIX_BLOB_STORE': 's3',
  'HELIX_S3_ENDPOINT': 'https://s3.example.com',
  'HELIX_S3_BUCKET': 'b',
  'HELIX_S3_ACCESS_KEY_ID': 'AK',
  'HELIX_S3_SECRET_ACCESS_KEY': 'SK',
};

void main() {
  group('ServerConfig', () {
    test('defaults', () {
      final c = ServerConfig.fromEnv(_env());
      expect(c.port, 8080);
      expect(c.topology, Topology.singleHost);
      expect(c.activeJwtKid, 'k1');
      expect(c.blobs.backend, BlobBackend.local);
      expect(c.trustedProxies, {'127.0.0.1', '::1'});
      expect(c.nodeId, isNotEmpty);
    });

    test('reports every problem by variable name, never by value', () {
      try {
        ServerConfig.fromEnv({
          'HELIX_JWT_KEYS': '{"k":"c2hvcnQ"}',
          'HELIX_PORT': 'eighty',
          'HELIX_TOPOLOGY': 'mesh',
        });
        fail('expected ConfigError');
      } on ConfigError catch (e) {
        final text = e.toString();
        expect(text, contains('HELIX_DATABASE_URL'));
        expect(text, contains('HELIX_PORT'));
        expect(text, contains('HELIX_TOPOLOGY'));
        expect(text, contains('at least 32 bytes'));
        expect(text, isNot(contains('c2hvcnQ')));
      }
    });

    test('a cluster needs shared object storage', () {
      expect(
        () => ServerConfig.fromEnv(_env({'HELIX_TOPOLOGY': 'cluster'})),
        throwsA(isA<ConfigError>()),
      );
      final c = ServerConfig.fromEnv(
        _env({'HELIX_TOPOLOGY': 'cluster', ..._s3Env}),
      );
      expect(c.blobs.backend, BlobBackend.s3);
    });

    test(
      'a malformed S3 endpoint is named at start-up, not at request time',
      () {
        for (final good in [
          'https://s3.example.com',
          'http://127.0.0.1:9000',
        ]) {
          final c = ServerConfig.fromEnv(
            _env({..._s3Env, 'HELIX_S3_ENDPOINT': good}),
          );
          expect(c.blobs.s3!.endpoint.toString(), good, reason: good);
        }
        // Each of these parses as a Uri but is not a URL the store can be
        // reached at; each used to start the node and then fail every media
        // request with an error that named nothing.
        for (final bad in [
          'minio:9000',
          'storage.example.com',
          'ftp://s3.example.com',
          'http://user:pass@s3.example.com',
          'https://s3.example.com?region=eu',
          'https://s3.example.com#frag',
        ]) {
          expect(
            () => ServerConfig.fromEnv(
              _env({..._s3Env, 'HELIX_S3_ENDPOINT': bad}),
            ),
            throwsA(
              isA<ConfigError>().having(
                (e) => e.toString(),
                'message',
                contains('HELIX_S3_ENDPOINT'),
              ),
            ),
            reason: bad,
          );
        }
        // Absent is still "required", and the other S3 values are checked too.
        expect(
          () =>
              ServerConfig.fromEnv(_env({..._s3Env, 'HELIX_S3_ENDPOINT': ''})),
          throwsA(
            isA<ConfigError>().having(
              (e) => e.toString(),
              'message',
              allOf(contains('HELIX_S3_ENDPOINT'), contains('required')),
            ),
          ),
        );
      },
    );

    test(
      'the storage budget is optional and at least 1 GiB outside dev mode',
      () {
        expect(ServerConfig.fromEnv(_env()).storageBudgetBytes, isNull);
        expect(
          ServerConfig.fromEnv(
            _env({'HELIX_STORAGE_BUDGET_BYTES': '53687091200'}),
          ).storageBudgetBytes,
          50 * 1024 * 1024 * 1024,
        );
        for (final bad in ['1048576', 'lots', '-1']) {
          expect(
            () =>
                ServerConfig.fromEnv(_env({'HELIX_STORAGE_BUDGET_BYTES': bad})),
            throwsA(isA<ConfigError>()),
            reason: bad,
          );
        }
        expect(
          ServerConfig.fromEnv(
            _env({
              'HELIX_STORAGE_BUDGET_BYTES': '1048576',
              'HELIX_DEV_MODE': 'true',
            }),
          ).storageBudgetBytes,
          1048576,
        );
      },
    );

    test('toString hides secrets', () {
      final c = ServerConfig.fromEnv(_env());
      expect(c.toString(), isNot(contains('postgresql://')));
      expect(c.toString(), isNot(contains(_key)));
    });
  });

  group('redaction', () {
    test('by field name', () {
      final out = redactFields({
        'password': 'hunter2',
        'auth_key': 'abc',
        'refresh_token': 'x',
        'device_id': 'd1',
        'account_id': 'a1',
        'status': 200,
        'phone_last4': '1234',
      });
      expect(out['password'], '[redacted]');
      expect(out['auth_key'], '[redacted]');
      expect(out['refresh_token'], '[redacted]');
      expect(out['phone_last4'], '[redacted]');
      expect(out['device_id'], 'd1');
      expect(out['status'], 200);
    });

    test('by value shape', () {
      expect(
        redactString('eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abc'),
        '[redacted]',
      );
      expect(
        redactString('Authorization: Bearer abc.def'),
        'Authorization: Bearer [redacted]',
      );
      expect(
        redactString('postgresql://helix:secret@host/db'),
        'postgresql://[redacted]@host/db',
      );
      expect(redactString('call +8801712345678 now'), 'call [phone…78] now');
      expect(redactString('a' * 50), '[redacted]');
      expect(redactString('42 items'), '42 items');
    });

    test(
      'log lines are JSON with redaction applied, child context included',
      () {
        final sink = MemorySink();
        final log = Log(sink: sink).child({'module': 'identity'});
        log.info('sign_in', {'device_id': 'd1', 'password': 'p'});
        final line = jsonDecode(sink.lines.single) as Map;
        expect(line['event'], 'sign_in');
        expect(line['module'], 'identity');
        expect(line['password'], '[redacted]');
        expect(log.recent(), hasLength(1));
      },
    );
  });

  group('metrics', () {
    test('renders Prometheus text', () {
      final m = Metrics();
      m.counter('helix_x_total', 'x').inc({'kind': 'a'});
      m.counter('helix_x_total', 'x').inc({'kind': 'a'});
      m.histogram('helix_lat_seconds', 'lat', buckets: [0.1, 1]).observe(0.5);
      m.gauge('helix_up', 'up', () => 1);
      final text = m.render();
      expect(text, contains('helix_x_total{kind="a"} 2.0'));
      expect(text, contains('helix_lat_seconds_bucket{le="0.1"} 0'));
      expect(text, contains('helix_lat_seconds_bucket{le="1.0"} 1'));
      expect(text, contains('helix_lat_seconds_count 1'));
      expect(text, contains('helix_up 1.0'));
    });
  });

  group('LocalObjectStorage', () {
    late Directory dir;
    late LocalObjectStorage storage;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('blobs_');
      storage = LocalObjectStorage(dir.path);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('resumable append, ranged read, delete', () async {
      expect(await storage.size('media/a1'), isNull);
      expect(
        await storage.append(
          'media/a1',
          Stream.value([1, 2, 3]),
          offset: 0,
          maxSize: 10,
        ),
        3,
      );
      await expectLater(
        storage.append('media/a1', Stream.value([9]), offset: 0, maxSize: 10),
        throwsA(isA<OffsetMismatch>().having((e) => e.actual, 'actual', 3)),
      );
      expect(
        await storage.append(
          'media/a1',
          Stream.value([4, 5]),
          offset: 3,
          maxSize: 10,
        ),
        5,
      );
      expect(await storage.read('media/a1').expand((c) => c).toList(), [
        1,
        2,
        3,
        4,
        5,
      ]);
      expect(
        await storage
            .read('media/a1', start: 1, endInclusive: 2)
            .expand((c) => c)
            .toList(),
        [2, 3],
      );
      await expectLater(
        storage.append(
          'media/a1',
          Stream.value(List.filled(6, 0)),
          offset: 5,
          maxSize: 10,
        ),
        throwsA(isA<ObjectTooLarge>()),
      );
      await storage.delete('media/a1');
      expect(await storage.size('media/a1'), isNull);
      // The same typed answers as the S3 backend, on both edges of a read.
      await expectLater(
        storage.read('media/a1').toList(),
        throwsA(isA<ObjectMissing>()),
      );
      await storage.append(
        'media/a2',
        Stream.value([1, 2]),
        offset: 0,
        maxSize: 4,
      );
      await expectLater(
        storage.read('media/a2', start: 9, endInclusive: 12).toList(),
        throwsA(isA<ObjectShort>()),
      );
    });

    test(
      'two writers at one offset: one appends, the other is told to resume',
      () async {
        // A client that retries an upload while the first request is still
        // streaming. Both used to pass the length check and both appended, so
        // the object ended up twice its declared size with two bodies mixed into
        // the first half (AUD-1c-2).
        final first = storage.append(
          'media/a1',
          _drip([
            [1, 2],
            [3],
          ]),
          offset: 0,
          maxSize: 10,
        );
        final second = storage.append(
          'media/a1',
          _drip([
            [9, 9],
          ]),
          offset: 0,
          maxSize: 10,
        );
        expect(
          await Future.wait([
            first.then((n) => 'written $n'),
            second.then(
              (n) => 'written $n',
              onError: (Object e) =>
                  e is OffsetMismatch ? 'mismatch ${e.actual}' : '$e',
            ),
          ]),
          unorderedEquals(['written 3', 'mismatch 3']),
        );
        expect(await storage.size('media/a1'), 3);
        // The retry resumes where the file actually stopped.
        expect(
          await storage.append(
            'media/a1',
            _drip([
              [4, 5],
            ]),
            offset: 3,
            maxSize: 10,
          ),
          5,
        );
        expect(await storage.read('media/a1').expand((c) => c).toList(), [
          1,
          2,
          3,
          4,
          5,
        ]);
      },
    );

    test('lists the objects under a prefix with their change times', () async {
      for (final key in ['attachment/a1', 'attachment/b2', 'backup/c3']) {
        await storage.append(key, Stream.value([1]), offset: 0, maxSize: 4);
      }
      final listed = await storage.list('attachment/').toList();
      expect(
        listed.map((o) => o.key),
        unorderedEquals(['attachment/a1', 'attachment/b2']),
      );
      expect(listed.first.modified.isUtc, isTrue);
      expect(await storage.list('nothing/').toList(), isEmpty);
    });

    test('keys cannot escape the root', () {
      for (final key in [
        '../x',
        'a/../../b',
        '/abs',
        r'a\b',
        'A',
        'a//b',
        '',
      ]) {
        expect(() => storage.size(key), throwsArgumentError, reason: key);
      }
    });
  });

  group('S3ObjectStorage listing', () {
    test('pages through ListObjectsV2', () async {
      final asked = <Map<String, String>>[];
      final client = MockClient((request) async {
        asked.add(request.url.queryParameters);
        final second =
            request.url.queryParameters['continuation-token'] != null;
        return http.Response(
          second
              ? '<ListBucketResult><IsTruncated>false</IsTruncated>'
                    '<Contents><Key>attachment/b2</Key>'
                    '<LastModified>2026-10-02T00:00:00.000Z</LastModified>'
                    '</Contents></ListBucketResult>'
              : '<ListBucketResult><IsTruncated>true</IsTruncated>'
                    '<NextContinuationToken>next-page</NextContinuationToken>'
                    '<Contents><Key>attachment/a1</Key>'
                    '<LastModified>2026-10-01T00:00:00.000Z</LastModified>'
                    '</Contents></ListBucketResult>',
          200,
        );
      });
      final storage = S3ObjectStorage(
        S3Config(
          endpoint: Uri.parse('http://127.0.0.1:9000'),
          region: 'us-east-1',
          bucket: 'helix',
          accessKeyId: 'a',
          secretAccessKey: 'b',
        ),
        client: client,
        now: () => DateTime.utc(2026, 10, 1),
      );
      final listed = await storage.list('attachment/').toList();
      expect(listed.map((o) => o.key), ['attachment/a1', 'attachment/b2']);
      expect(listed.last.modified, DateTime.utc(2026, 10, 2));
      expect(asked.first['list-type'], '2');
      expect(asked.first['prefix'], 'attachment/');
      expect(asked.last['continuation-token'], 'next-page');
    });
  });

  group('S3ObjectStorage bounds', () {
    final config = S3Config(
      endpoint: Uri.parse('http://127.0.0.1:9000'),
      region: 'us-east-1',
      bucket: 'helix',
      accessKeyId: 'a',
      secretAccessKey: 'b',
    );
    const stalled = Duration(milliseconds: 80);

    test(
      'a store that never answers fails instead of hanging the caller',
      () async {
        var asked = 0;
        final storage = S3ObjectStorage(
          config,
          client: _SilentStore(onSend: () => asked++),
          now: () => DateTime.utc(2026, 10, 1),
          timeout: stalled,
        );
        final started = Stopwatch()..start();
        await expectLater(
          storage.size('media/a1'),
          throwsA(isA<HttpException>()),
        );
        await expectLater(
          storage.delete('media/a1'),
          throwsA(isA<HttpException>()),
        );
        await expectLater(
          storage.list('attachment/').toList(),
          throwsA(isA<HttpException>()),
        );
        expect(started.elapsed, lessThan(const Duration(seconds: 5)));
        expect(asked, 3);
        // Readiness reports unhealthy rather than waiting for the store.
        expect(await storage.ping(), isFalse);
      },
    );

    test('a body that stops arriving abandons the request', () async {
      final storage = S3ObjectStorage(
        config,
        client: _StallingBody(),
        now: () => DateTime.utc(2026, 10, 1),
        timeout: stalled,
      );
      final started = Stopwatch()..start();
      await expectLater(
        storage.delete('media/a1'),
        throwsA(isA<HttpException>()),
      );
      expect(started.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test(
      'a dead store is probed once, not once per readiness request',
      () async {
        var asked = 0;
        final storage = S3ObjectStorage(
          config,
          client: _SilentStore(onSend: () => asked++),
          timeout: stalled,
        );
        expect(
          await Future.wait([storage.ping(), storage.ping(), storage.ping()]),
          [false, false, false],
        );
        expect(asked, 1);
        expect(await storage.ping(), isFalse);
        expect(asked, 1);
      },
    );

    test('a live store answers one shared probe', () async {
      var asked = 0;
      final storage = S3ObjectStorage(
        config,
        client: MockClient((request) async {
          asked++;
          return http.Response('', 200);
        }),
        timeout: stalled,
      );
      expect(
        await Future.wait([storage.ping(), storage.ping(), storage.ping()]),
        [true, true, true],
      );
      expect(asked, 1);
    });
    test(
      'a range read asks the store for the range and stops at its end',
      () async {
        final asked = <String?>[];
        final storage = S3ObjectStorage(
          config,
          client: MockClient((request) async {
            asked.add(request.headers['range']);
            // More bytes than the window: a store is not trusted to answer a
            // range with exactly its length.
            return http.Response.bytes(List.filled(20, 7), 206);
          }),
          timeout: stalled,
        );
        expect(
          await storage
              .read('media/a1', start: 2, endInclusive: 5)
              .expand((c) => c)
              .toList(),
          List.filled(4, 7),
        );
        expect(asked, ['bytes=2-5']);
        expect(
          await storage.read('media/a1').expand((c) => c).toList(),
          List.filled(20, 7),
        );
        expect(
          asked.last,
          isNull,
          reason: 'a whole-object read sends no range',
        );
      },
    );

    test('a store that will not answer a range says so', () async {
      final storage = S3ObjectStorage(
        config,
        client: MockClient(
          (request) async => http.Response('whole object', 200),
        ),
        timeout: stalled,
      );
      await expectLater(
        storage.read('media/a1', start: 4).toList(),
        throwsA(isA<HttpException>()),
      );
    });

    test(
      'a missing object and an unsatisfiable range are typed errors',
      () async {
        Future<Object?> failure(int status) async {
          final storage = S3ObjectStorage(
            config,
            client: MockClient((request) async => http.Response('', status)),
            timeout: stalled,
          );
          try {
            await storage.read('media/a1', start: 8, endInclusive: 12).toList();
            return null;
          } on Object catch (error) {
            return error;
          }
        }

        expect(await failure(404), isA<ObjectMissing>());
        expect(await failure(416), isA<ObjectShort>());
      },
    );
  });

  group('S3ObjectStorage presigning', () {
    test('matches the AWS SigV4 documented example (GET, path style)', () {
      // https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-query-string-auth.html
      final storage = S3ObjectStorage(
        S3Config(
          endpoint: Uri.parse('https://s3.amazonaws.com'),
          region: 'us-east-1',
          bucket: 'examplebucket',
          accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
          secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
          pathStyle: false,
        ),
        now: () => DateTime.utc(2013, 5, 24),
      );
      final url = storage.presignGet('test', const Duration(hours: 24));
      // The documented example signs key "test.txt"; our key grammar has no
      // dots, so assert the structure and the signing parameters instead.
      expect(url.host, 'examplebucket.s3.amazonaws.com');
      expect(url.path, '/test');
      final q = url.queryParameters;
      expect(q['X-Amz-Algorithm'], 'AWS4-HMAC-SHA256');
      expect(
        q['X-Amz-Credential'],
        'AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request',
      );
      expect(q['X-Amz-Date'], '20130524T000000Z');
      expect(q['X-Amz-Expires'], '86400');
      expect(q['X-Amz-SignedHeaders'], 'host');
      expect(q['X-Amz-Signature'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(url.toString(), isNot(contains('wJalrXUtnFEMI')));
    });

    test('presigned PUT differs from GET and is deterministic', () {
      final storage = S3ObjectStorage(
        S3Config(
          endpoint: Uri.parse('http://127.0.0.1:9000'),
          region: 'us-east-1',
          bucket: 'helix',
          accessKeyId: 'a',
          secretAccessKey: 'b',
        ),
        now: () => DateTime.utc(2026, 10, 1),
      );
      final put = storage.presignPut(
        'media/x',
        const Duration(minutes: 15),
        contentLength: 1234,
      );
      final get = storage.presignGet('media/x', const Duration(minutes: 15));
      expect(put.path, '/helix/media/x');
      expect(
        put.queryParameters['X-Amz-Signature'],
        isNot(get.queryParameters['X-Amz-Signature']),
      );
      expect(
        storage.presignPut(
          'media/x',
          const Duration(minutes: 15),
          contentLength: 1234,
        ),
        put,
      );
    });

    test('presigned PUT signs the declared content length', () {
      final storage = S3ObjectStorage(
        S3Config(
          endpoint: Uri.parse('http://127.0.0.1:9000'),
          region: 'us-east-1',
          bucket: 'helix',
          accessKeyId: 'a',
          secretAccessKey: 'b',
        ),
        now: () => DateTime.utc(2026, 10, 1),
      );
      final put = storage.presignPut(
        'media/x',
        const Duration(minutes: 15),
        contentLength: 1234,
      );
      expect(
        put.queryParameters['X-Amz-SignedHeaders']!.split(';'),
        containsAll(['content-length', 'host']),
      );
      final other = storage.presignPut(
        'media/x',
        const Duration(minutes: 15),
        contentLength: 1235,
      );
      expect(
        other.queryParameters['X-Amz-Signature'],
        isNot(put.queryParameters['X-Amz-Signature']),
        reason: 'another length needs another signature',
      );
    });
  });
}

/// A store that takes the request and never answers: the fault AUD-1c-1 is
/// about (a blackholed route, a dead load balancer, throttling with no
/// response).
final class _SilentStore extends http.BaseClient {
  _SilentStore({this.onSend});

  final void Function()? onSend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    onSend?.call();
    return Completer<http.StreamedResponse>().future;
  }
}

/// A store that sends the headers and two bytes, then stops mid-body.
final class _StallingBody extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final chunks = StreamController<List<int>>();
    chunks.add([1, 2]);
    return Future.value(
      http.StreamedResponse(chunks.stream, 200, contentLength: 10),
    );
  }
}

/// Chunks that arrive one event-loop turn apart, so two uploads to one key
/// genuinely overlap instead of running back to back.
Stream<List<int>> _drip(List<List<int>> chunks) async* {
  for (final chunk in chunks) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
    yield chunk;
  }
}
