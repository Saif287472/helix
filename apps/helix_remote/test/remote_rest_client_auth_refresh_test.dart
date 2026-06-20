import 'dart:convert';
import 'dart:io';

import 'package:helix_remote/app/remote_rest_client.dart';
import 'package:test/test.dart';

String _fixtureValue(String value) => value;

void main() {
  late HttpServer server;
  late int port;
  var deviceRequestCount = 0;
  var refreshRequestCount = 0;
  var issuedFixture = 'fresh-token';

  setUp(() async {
    deviceRequestCount = 0;
    refreshRequestCount = 0;
    issuedFixture = 'fresh-token';
    server = await HttpServer.bind('127.0.0.1', 0);
    port = server.port;
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test(
    'P04-A01: expired access token refreshes once and retries operation',
    () async {
      server.listen((request) async {
        if (request.uri.path.endsWith('/accounts/refresh')) {
          refreshRequestCount++;
          request.response.statusCode = 200;
          request.response.write(
            jsonEncode({'token': issuedFixture, 'refresh_token': 'refresh-2'}),
          );
        } else if (request.uri.path.endsWith('/accounts/devices')) {
          deviceRequestCount++;
          final auth = request.headers.value('authorization');
          if (auth == 'Bearer $issuedFixture') {
            request.response.statusCode = 200;
            request.response.write(jsonEncode({'devices': []}));
          } else {
            request.response.statusCode = 401;
            request.response.write(jsonEncode({'error': 'expired'}));
          }
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      });

      late final HelixRemoteRestClientImpl client;
      client = HelixRemoteRestClientImpl(
        baseUri: Uri.parse('http://127.0.0.1:$port'),
        timeoutMs: 1000,
        refreshAuth: () async {
          final response = await client.refreshToken(refreshToken: 'refresh-1');
          client.accessToken = response['token'] as String;
          return true;
        },
      );
      addTearDown(client.close);
      client.accessToken = _fixtureValue('expired-token');

      final devices = await client.listDevices();

      expect(devices, isEmpty);
      expect(refreshRequestCount, equals(1));
      expect(deviceRequestCount, equals(2));
    },
  );

  test('P04-A02: simultaneous 401s share one refresh request', () async {
    server.listen((request) async {
      if (request.uri.path.endsWith('/accounts/refresh')) {
        refreshRequestCount++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        request.response.statusCode = 200;
        request.response.write(
          jsonEncode({'token': issuedFixture, 'refresh_token': 'refresh-2'}),
        );
      } else if (request.uri.path.endsWith('/accounts/devices')) {
        deviceRequestCount++;
        final auth = request.headers.value('authorization');
        if (auth == 'Bearer $issuedFixture') {
          request.response.statusCode = 200;
          request.response.write(jsonEncode({'devices': []}));
        } else {
          request.response.statusCode = 401;
          request.response.write(jsonEncode({'error': 'expired'}));
        }
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });

    late final HelixRemoteRestClientImpl client;
    client = HelixRemoteRestClientImpl(
      baseUri: Uri.parse('http://127.0.0.1:$port'),
      timeoutMs: 1000,
      refreshAuth: () async {
        final response = await client.refreshToken(refreshToken: 'refresh-1');
        client.accessToken = response['token'] as String;
        return true;
      },
    );
    addTearDown(client.close);
    client.accessToken = _fixtureValue('expired-token');

    await Future.wait([client.listDevices(), client.listDevices()]);

    expect(refreshRequestCount, equals(1));
    expect(deviceRequestCount, equals(4));
  });

  test('P04-A03: revoked refresh token leaves request unauthorized', () async {
    server.listen((request) async {
      if (request.uri.path.endsWith('/accounts/devices')) {
        deviceRequestCount++;
        request.response.statusCode = 401;
        request.response.write(jsonEncode({'error': 'expired'}));
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });

    final client = HelixRemoteRestClientImpl(
      baseUri: Uri.parse('http://127.0.0.1:$port'),
      timeoutMs: 1000,
      refreshAuth: () async => false,
    );
    addTearDown(client.close);
    client.accessToken = _fixtureValue('expired-token');

    await expectLater(
      client.listDevices(),
      throwsA(isA<RemoteRestException>()),
    );
    expect(deviceRequestCount, equals(1));
  });
}
