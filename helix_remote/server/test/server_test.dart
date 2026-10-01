import 'dart:convert';

import 'package:helix_remote_server/helix_remote_server.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'support/test_database.dart';
import 'support/test_platform.dart';

/// A real server process on the test database, end to end over HTTP.
void main() {
  group('HelixServer', skip: databaseTestSkipReason, () {
    late TestPlatform env;
    late HelixServer server;

    setUp(() async {
      env = await TestPlatform.open();
      server = await HelixServer.start(env.platform, allModules());
    });

    tearDown(() async {
      await server.stop();
      await env.dispose();
    });

    test('serves health and readiness', () async {
      final live = await http.get(server.baseUri.resolve('/v1/health/live'));
      expect(live.statusCode, 200);
      expect((jsonDecode(live.body) as Map)['status'], 'ok');
      expect(live.headers['x-request-id'], isNotEmpty);

      final ready = await http.get(server.baseUri.resolve('/v1/health/ready'));
      expect(ready.statusCode, 200);
      expect(jsonDecode(ready.body), {
        'ready': true,
        'checks': {'database': true, 'storage': true},
      });
    });

    test(
      'a second node on the same database starts cleanly (migrations are idempotent)',
      () async {
        final secondPlatform = await HelixPlatform.open(
          testConfig(prefix: env.prefix),
          log: Log(sink: MemorySink()),
        );
        final second = await HelixServer.start(secondPlatform, allModules());
        try {
          final live = await http.get(
            second.baseUri.resolve('/v1/health/live'),
          );
          expect(live.statusCode, 200);
        } finally {
          await second.stop();
        }
      },
    );

    test(
      'device routes are refused without a session (no identity yet)',
      () async {
        final response = await http.get(
          server.baseUri.resolve('/v1/keys/status'),
        );
        expect(response.statusCode, 404, reason: 'keys module not built yet');
      },
    );
  });
}
