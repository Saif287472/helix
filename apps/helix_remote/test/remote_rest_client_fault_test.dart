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
        client.registerAccount(
          accountId: 'account',
          username: 'alice',
          accountIdentityPublicKey: 'account_pk',
          deviceId: 'device',
          deviceSigningPublicKey: 'signing_pk',
          deviceAgreementPublicKey: 'agreement_pk',
          accountRegistrationSignature: 'account_sig',
          deviceRegistrationSignature: 'device_sig',
          deviceName: 'Phone',
        ),
        throwsA(isA<RemoteRestException>()),
      );

      expect(requestCount, equals(1));
      expect(seenHeaders['idempotency'], isNull);
    },
  );
}
