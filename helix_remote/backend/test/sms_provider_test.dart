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

  test('send() succeeds on a submitted (202) response without throwing', () async {
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
  });

  test('send() throws SmsDeliveryException on a rejected (non-202) response', () async {
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
  });

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
}
