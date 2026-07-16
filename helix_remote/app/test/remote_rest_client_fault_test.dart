import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:helix_remote/app/remote_rest_client.dart';

void main() {
  late HttpServer server;
  late int port;
  var requestCount = 0;
  final seenHeaders = <String, String?>{};

  setUp(() async {
    requestCount = 0;
    seenHeaders.clear();
    server = await HttpServer.bind('127.0.0.1', 0);
    port = server.port;
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test(
    'safe GET retries transient failures with Retry-After and correlation ID',
    () async {
      server.listen((request) async {
        requestCount++;
        seenHeaders['correlation'] = request.headers.value('x-correlation-id');
        if (requestCount == 1) {
          request.response.statusCode = 503;
          request.response.headers.set('Retry-After', '0');
          request.response.write(jsonEncode({'error': 'try again'}));
        } else {
          request.response.statusCode = 200;
          request.response.write(
            jsonEncode({'account_id': 'peer', 'devices': []}),
          );
        }
        await request.response.close();
      });

      final client = HelixRemoteRestClientImpl(
        baseUri: Uri.parse('http://127.0.0.1:$port'),
        timeoutMs: 1000,
      );
      addTearDown(client.close);

      final response = await client.getPreKeyBundle(accountId: 'peer');

      expect(response['account_id'], equals('peer'));
      expect(requestCount, equals(2));
      expect(seenHeaders['correlation'], isNotEmpty);
    },
  );

  test('registration POST retries with a stable idempotency key', () async {
    server.listen((request) async {
      requestCount++;
      seenHeaders['idempotency'] = request.headers.value('idempotency-key');
      if (requestCount == 1) {
        request.response.statusCode = 503;
        request.response.write(jsonEncode({'error': 'retry registration'}));
      } else {
        request.response.statusCode = 200;
        request.response.write(
          jsonEncode({
            'message': 'Registration successful',
            'account_id': 'account',
            'device_id': 'device',
          }),
        );
      }
      await request.response.close();
    });

    final client = HelixRemoteRestClientImpl(
      baseUri: Uri.parse('http://127.0.0.1:$port'),
      timeoutMs: 1000,
    );
    addTearDown(client.close);

    final response = await client.registerAccount(
      accountId: 'account',
      username: 'alice',
      displayName: 'Alice',
      accountIdentityPublicKey: 'account_pk',
      deviceId: 'device',
      deviceSigningPublicKey: 'signing_pk',
      deviceAgreementPublicKey: 'agreement_pk',
      accountRegistrationSignature: 'account_sig',
      deviceRegistrationSignature: 'device_sig',
      deviceName: 'Phone',
    );

    expect(response['account_id'], equals('account'));
    expect(requestCount, equals(2));
    expect(seenHeaders['idempotency'], equals('register:account:device'));
  });

  test(
    'non-idempotent POST is not blindly replayed on transient failure',
    () async {
      server.listen((request) async {
        requestCount++;
        seenHeaders['idempotency'] = request.headers.value('idempotency-key');
        request.response.statusCode = 503;
        request.response.write(jsonEncode({'error': 'do not replay'}));
        await request.response.close();
      });

      final client = HelixRemoteRestClientImpl(
        baseUri: Uri.parse('http://127.0.0.1:$port'),
        timeoutMs: 1000,
      );
      addTearDown(client.close);

      await expectLater(
        client.loginDevice(
          accountId: 'account',
          deviceId: 'device',
          signature: 'sig',
        ),
        throwsA(
          isA<RemoteRestException>()
              .having((e) => e.statusCode, 'statusCode', 503)
              .having(
                (e) => e.failureKind,
                'failureKind',
                RemoteRestFailureKind.http,
              ),
        ),
      );

      expect(requestCount, equals(1));
      expect(seenHeaders['idempotency'], isNull);
    },
  );

  test(
    'closed backend port reports a concrete transport failure kind',
    () async {
      final closedPort = port;
      await server.close(force: true);

      final client = HelixRemoteRestClientImpl(
        baseUri: Uri.parse('http://127.0.0.1:$closedPort'),
        timeoutMs: 100,
      );
      addTearDown(client.close);

      await expectLater(
        client.getPreKeyBundle(accountId: 'peer'),
        throwsA(
          isA<RemoteRestException>()
              .having((e) => e.statusCode, 'statusCode', isNull)
              .having(
                (e) => e.failureKind,
                'failureKind',
                anyOf(
                  RemoteRestFailureKind.serverDown,
                  RemoteRestFailureKind.timeout,
                ),
              ),
        ),
      );
    },
  );

  test('unresponsive backend is classified as timeout', () async {
    server.listen((request) async {
      requestCount++;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      request.response.statusCode = 200;
      request.response.write(jsonEncode({'account_id': 'peer', 'devices': []}));
      await request.response.close();
    });

    final client = HelixRemoteRestClientImpl(
      baseUri: Uri.parse('http://127.0.0.1:$port'),
      timeoutMs: 50,
    );
    addTearDown(client.close);

    await expectLater(
      client.getPreKeyBundle(accountId: 'peer'),
      throwsA(
        isA<RemoteRestException>()
            .having((e) => e.statusCode, 'statusCode', isNull)
            .having(
              (e) => e.failureKind,
              'failureKind',
              RemoteRestFailureKind.timeout,
            ),
      ),
    );

    expect(requestCount, greaterThanOrEqualTo(1));
  });
}
