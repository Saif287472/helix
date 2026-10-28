import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_server/helix_remote_server.dart';
import 'package:helix_remote_server/src/modules/identity/sms.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'support/harness.dart';
import 'support/test_database.dart';
import 'support/test_platform.dart';

/// A real server process on the test database, end to end over HTTP.
void main() {
  group('HelixServer', skip: databaseTestSkipReason, () {
    late Harness h;

    setUp(() async => h = await Harness.start());
    tearDown(() async => h.stop());

    test('serves health and readiness', () async {
      final live = await http.get(h.server.baseUri.resolve('/v1/health/live'));
      expect(live.statusCode, 200);
      expect((jsonDecode(live.body) as Map)['status'], 'ok');
      expect(live.headers['x-request-id'], isNotEmpty);

      final ready = await http.get(
        h.server.baseUri.resolve('/v1/health/ready'),
      );
      expect(ready.statusCode, 200);
      expect(jsonDecode(ready.body), {
        'ready': true,
        'checks': {'database': true, 'storage': true},
      });
    });

    test('a second node on the same database starts cleanly', () async {
      final secondPlatform = await HelixPlatform.open(
        testConfig(
          prefix: h.env.prefix,
          extra: {
            'HELIX_PHONE_PEPPER': testPepper,
            'HELIX_GLOBAL_MODE': 'true',
          },
        ),
        log: Log(sink: MemorySink()),
      );
      final second = await HelixServer.start(
        secondPlatform,
        allModules(sms: RecordingSmsProvider()),
      );
      try {
        final live = await http.get(second.baseUri.resolve('/v1/health/live'));
        expect(live.statusCode, 200);
      } finally {
        await second.stop();
        Directory(
          secondPlatform.config.blobs.directory!,
        ).deleteSync(recursive: true);
      }
    });

    test('every catalog route of the finished modules is served', () {
      expect(
        h.server.routes.missingFor({
          'identity',
          'keys',
          'messaging',
          'realtime',
          'people',
          'media',
          'backup',
          'groups',
          'calls',
          'ops',
          'admin',
          'compliance',
          'billing',
          'federation',
        }),
        isEmpty,
      );
    });

    test('device routes refuse requests without a session', () async {
      final response = await http.get(
        h.server.baseUri.resolve('/v1/keys/status'),
      );
      expect(response.statusCode, 401);
      expect((jsonDecode(response.body) as Map)['error'], {
        'code': 'unauthenticated',
      });
    });

    test('every periodic job is leased longer than it may run', () {
      // AUD-1b-2, over the list a real node runs: a job whose run outlives its
      // lease can be claimed a second time on another node while the first is
      // still going, and every sweep here is written for one writer.
      final scheduler = h.env.platform.periodic;
      expect(
        [for (final job in scheduler.jobs) job.name],
        containsAll(<String>[
          'platform.sweep_ephemeral',
          'messaging.expire',
          'people.purge_reports',
          'media.sweep_orphans',
          'media.reconcile',
        ]),
        reason: 'this checks the whole server, not a fixture',
      );
      for (final job in scheduler.jobs) {
        expect(
          scheduler.leaseFor(job),
          greaterThan(scheduler.limitFor(job)),
          reason:
              '${job.name} may still be running when another node claims it',
        );
      }
    });
  });
}
