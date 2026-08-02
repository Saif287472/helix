import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/admin_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // TestWidgetsFlutterBinding installs a global HttpOverrides that forces
    // every HttpClient request to 400, so real requests below (even ones
    // meant to fail with a connection error) wouldn't exercise the actual
    // code path being tested without this reset.
    HttpOverrides.global = null;
  });

  group('verifyLoginDetailed', () {
    late HttpServer server;
    late int responseStatusCode;

    setUp(() async {
      responseStatusCode = 200;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = responseStatusCode;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{}');
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    String baseUrl() => 'http://${server.address.address}:${server.port}';

    test('a 200 response is ok', () async {
      final client = AdminClient(baseUrl: baseUrl(), token: 't');
      expect(
        await client.verifyLoginDetailed(),
        equals(AdminLoginStatus.ok),
      );
      expect(await client.verifyLogin(), isTrue);
    });

    test('a 401 response is unauthorized, not just "not ok"', () async {
      responseStatusCode = 401;
      final client = AdminClient(baseUrl: baseUrl(), token: 't');
      expect(
        await client.verifyLoginDetailed(),
        equals(AdminLoginStatus.unauthorized),
      );
      expect(await client.verifyLogin(), isFalse);
    });

    test('a 403 response is unauthorized', () async {
      responseStatusCode = 403;
      final client = AdminClient(baseUrl: baseUrl(), token: 't');
      expect(
        await client.verifyLoginDetailed(),
        equals(AdminLoginStatus.unauthorized),
      );
    });

    test('a 500 response is unreachable, not unauthorized', () async {
      responseStatusCode = 500;
      final client = AdminClient(baseUrl: baseUrl(), token: 't');
      expect(
        await client.verifyLoginDetailed(),
        equals(AdminLoginStatus.unreachable),
      );
    });

    test(
      'a connection failure (e.g. offline, weak signal) is unreachable, '
      'never unauthorized - the caller must not treat this as proof the '
      'token is bad',
      () async {
        // Nothing listens here - a real socket-level connection failure.
        final client = AdminClient(
          baseUrl: 'http://127.0.0.1:1',
          token: 't',
        );
        expect(
          await client.verifyLoginDetailed(),
          equals(AdminLoginStatus.unreachable),
        );
        expect(await client.verifyLogin(), isFalse);
      },
    );
  });
}
