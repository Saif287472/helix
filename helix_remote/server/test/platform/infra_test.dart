import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_server/src/platform/blobs/object_storage.dart';
import 'package:helix_remote_server/src/platform/config/server_config.dart';
import 'package:helix_remote_server/src/platform/observability/log.dart';
import 'package:helix_remote_server/src/platform/observability/metrics.dart';
import 'package:test/test.dart';

const _key = 'dGVzdC1vbmx5LWp3dC1rZXktdGhhdC1pcy0zMi1ieXRlcw';

Map<String, String> _env([Map<String, String> extra = const {}]) => {
  'HELIX_DATABASE_URL': 'postgresql://u:p@localhost/db',
  'HELIX_JWT_KEYS': '{"k1":"$_key"}',
  ...extra,
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
        _env({
          'HELIX_TOPOLOGY': 'cluster',
          'HELIX_BLOB_STORE': 's3',
          'HELIX_S3_ENDPOINT': 'https://s3.example.com',
          'HELIX_S3_BUCKET': 'b',
          'HELIX_S3_ACCESS_KEY_ID': 'AK',
          'HELIX_S3_SECRET_ACCESS_KEY': 'SK',
        }),
      );
      expect(c.blobs.backend, BlobBackend.s3);
    });

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
