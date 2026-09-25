// Regression coverage for BulkSmsBdProvider - a real device hit
// "Failed to send verification SMS: Bad state: Stream has already been
// listened to." on every OTP request, caused by draining the HTTP response
// stream after it had already been fully consumed by .join(). These tests
// exercise the real BulkSmsBdProvider.send() (via apiBaseUri, pointed at a
// local HttpServer instead of the real gateway) so a regression of that
// stream-handling bug fails a test instead of only surfacing on a live
// device against the real gateway.

import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_backend/src/sms_provider.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late Uri apiBaseUri;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    apiBaseUri = Uri(
      scheme: 'http',
      host: 'localhost',
      port: server.port,
      path: '/api/smsapi',
    );
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test(
    'send() succeeds on a submitted (202) response without throwing',
    () async {
      server.listen((request) async {
        request.response.statusCode = 200;
        request.response.write(jsonEncode({'response_code': 202}));
        await request.response.close();
      });

      final provider = BulkSmsBdProvider(
        apiKey: 'key',
        senderId: 'sender',
        apiBaseUri: apiBaseUri,
      );

      // Must not throw - in particular, must not throw
      // "Bad state: Stream has already been listened to.".
      await provider.send(phoneNumber: '+8801712345678', message: 'test');
    },
  );

  test(
    'send() throws SmsDeliveryException on a rejected (non-202) response',
    () async {
      server.listen((request) async {
        request.response.statusCode = 200;
        request.response.write(
          jsonEncode({'response_code': 1006, 'error_message': 'Bad sender id'}),
        );
        await request.response.close();
      });

      final provider = BulkSmsBdProvider(
        apiKey: 'key',
        senderId: 'sender',
        apiBaseUri: apiBaseUri,
      );

      await expectLater(
        provider.send(phoneNumber: '+8801712345678', message: 'test'),
        throwsA(
          isA<SmsDeliveryException>().having(
            (e) => e.body,
            'body',
            contains('Bad sender id'),
          ),
        ),
      );
    },
  );

  test('send() throws SmsDeliveryException on a non-200 HTTP status', () async {
    server.listen((request) async {
      request.response.statusCode = 500;
      request.response.write('internal error');
      await request.response.close();
    });

    final provider = BulkSmsBdProvider(
      apiKey: 'key',
      senderId: 'sender',
      apiBaseUri: apiBaseUri,
    );

    await expectLater(
      provider.send(phoneNumber: '+8801712345678', message: 'test'),
      throwsA(isA<SmsDeliveryException>()),
    );
  });

  test('the destination number is sent without a leading +', () async {
    String? receivedNumber;
    server.listen((request) async {
      receivedNumber = request.uri.queryParameters['number'];
      request.response.statusCode = 200;
      request.response.write(jsonEncode({'response_code': 202}));
      await request.response.close();
    });

    final provider = BulkSmsBdProvider(
      apiKey: 'key',
      senderId: 'sender',
      apiBaseUri: apiBaseUri,
    );

    await provider.send(phoneNumber: '+8801712345678', message: 'test');
    expect(receivedNumber, '8801712345678');
  });

  // BulkSMSBD answers HTTP 200 even when it rejects the credential, so the
  // numeric response_code is the only signal. Without classifying it, an
  // invalid API key is indistinguishable from a transient gateway failure and
  // operators retry a credential that can never work.
  group('response-code classification', () {
    Future<SmsFailureReason> reasonFor(int code) async {
      server.listen((request) async {
        request.response.statusCode = 200;
        request.response.write(jsonEncode({'response_code': code}));
        await request.response.close();
      });
      final provider = BulkSmsBdProvider(
        apiKey: 'key',
        senderId: 'sender',
        apiBaseUri: apiBaseUri,
      );
      try {
        await provider.send(phoneNumber: '+8801712345678', message: 'test');
        fail('expected SmsDeliveryException for response_code $code');
      } on SmsDeliveryException catch (e) {
        return e.reason;
      }
    }

    test('1011 "user id not found in this key" is invalidCredentials', () async {
      expect(await reasonFor(1011), SmsFailureReason.invalidCredentials);
    });

    test('1009 is invalidCredentials', () async {
      expect(await reasonFor(1009), SmsFailureReason.invalidCredentials);
    });

    test('1010 is invalidCredentials', () async {
      expect(await reasonFor(1010), SmsFailureReason.invalidCredentials);
    });

    test('1030 is invalidSenderId', () async {
      expect(await reasonFor(1030), SmsFailureReason.invalidSenderId);
    });

    test('1031 is invalidSenderId', () async {
      expect(await reasonFor(1031), SmsFailureReason.invalidSenderId);
    });

    test('1002 is invalidDestination', () async {
      expect(await reasonFor(1002), SmsFailureReason.invalidDestination);
    });

    test('1006 is invalidDestination', () async {
      expect(await reasonFor(1006), SmsFailureReason.invalidDestination);
    });

    test('an unrecognised code falls back to rejected', () async {
      expect(await reasonFor(9999), SmsFailureReason.rejected);
    });
  });

  test(
    'the exception never reproduces the raw gateway body, which can echo '
    'the API key',
    () async {
      const secretKey = 'SUPER_SECRET_API_KEY_VALUE';
      server.listen((request) async {
        request.response.statusCode = 200;
        // BulkSMSBD's own text has been observed to quote the submitted key.
        request.response.write(
          jsonEncode({
            'response_code': 1011,
            'error_message': 'user id not found in this $secretKey key',
          }),
        );
        await request.response.close();
      });

      final provider = BulkSmsBdProvider(
        apiKey: secretKey,
        senderId: 'sender',
        apiBaseUri: apiBaseUri,
      );

      try {
        await provider.send(phoneNumber: '+8801712345678', message: 'test');
        fail('expected SmsDeliveryException');
      } on SmsDeliveryException catch (e) {
        // toString() feeds server logs and must stay free of the credential.
        expect(e.toString(), isNot(contains(secretKey)));
        expect(e.operatorMessage, isNot(contains(secretKey)));
        // ...but the operator still learns exactly what to fix.
        expect(e.operatorMessage, contains('HELIX_REMOTE_SMS_API_KEY'));
        expect(e.providerResponseCode, 1011);
      }
    },
  );

  test('a non-200 HTTP status is a gatewayError, not a credential problem', () async {
    server.listen((request) async {
      request.response.statusCode = 500;
      request.response.write('internal error');
      await request.response.close();
    });

    final provider = BulkSmsBdProvider(
      apiKey: 'key',
      senderId: 'sender',
      apiBaseUri: apiBaseUri,
    );

    await expectLater(
      provider.send(phoneNumber: '+8801712345678', message: 'test'),
      throwsA(
        isA<SmsDeliveryException>().having(
          (e) => e.reason,
          'reason',
          SmsFailureReason.gatewayError,
        ),
      ),
    );
  });
}
