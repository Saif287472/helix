import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:helix_remote_backend/helix_remote_backend.dart';
import 'package:test/test.dart';

void main() {
  test('FCM delivery consumes the response stream exactly once', () async {
    final requests = <Map<String, dynamic>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestDone = Completer<void>();
    final subscription = server.listen((request) async {
      requests.add(
        jsonDecode(await utf8.decoder.bind(request).join())
            as Map<String, dynamic>,
      );
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'name': 'projects/test/messages/1'}));
      await request.response.close();
      requestDone.complete();
    });

    try {
      final provider = FcmPushProvider(
        projectId: 'test-project',
        tokenSource: FcmPushProvider.staticToken(
          projectId: 'test-project',
          accessToken: 'test-access-token',
        ).tokenSource,
        endpoint: Uri.parse('http://127.0.0.1:${server.port}/send'),
      );
      await provider.deliver(
        token: 'device-token',
        data: {
          'notification_type': 'incoming_call',
          'call_id': 'call-1',
          'is_video': true,
          'caller_display_name': 'Ada',
        },
      );
      await requestDone.future;

      final message = requests.single['message'] as Map<String, dynamic>;
      expect(message['data'], {
        'notification_type': 'incoming_call',
        'call_id': 'call-1',
        'is_video': 'true',
        'caller_display_name': 'Ada',
      });
      expect(message['notification'], {
        'title': 'Incoming video call',
        'body': 'Ada',
      });
      expect(message['android'], {
        'priority': 'HIGH',
        'notification': {
          'channel_id': 'helix_incoming_calls',
          'sound': 'default',
        },
      });
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test('APNs delivery sends correct headers and payload for alert notifications', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestHeaders = <String, String>{};
    var requestBody = '';
    var requestPath = '';
    final requestDone = Completer<void>();

    final subscription = server.listen((request) async {
      requestPath = request.uri.path;
      request.headers.forEach((name, values) {
        requestHeaders[name.toLowerCase()] = values.join(', ');
      });
      requestBody = await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = HttpStatus.ok
        ..write('{"status":"ok"}');
      await request.response.close();
      requestDone.complete();
    });

    try {
      final provider = ApnsPushProvider.staticToken(
        teamId: 'TEAM123456',
        keyId: 'KEY1234567',
        bundleId: 'com.example.helix',
        accessToken: 'test-apns-bearer',
        endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      await provider.deliver(
        token: '79a2957b4c8f9361ad22f986421375d04586d34bbf33583c2602be1b24df4ef3',
        tokenType: 'APNS',
        data: {
          'notification_type': 'new_message',
          'conversation_id': 'conv-123',
        },
      );
      await requestDone.future;

      expect(requestPath, '/3/device/79a2957b4c8f9361ad22f986421375d04586d34bbf33583c2602be1b24df4ef3');
      expect(requestHeaders['authorization'], 'bearer test-apns-bearer');
      expect(requestHeaders['apns-topic'], 'com.example.helix');
      expect(requestHeaders['apns-push-type'], 'alert');
      expect(requestHeaders['apns-priority'], '10');

      final bodyJson = jsonDecode(requestBody) as Map<String, dynamic>;
      expect(bodyJson['aps']['alert']['body'], 'You have a new message');
      expect(bodyJson['conversation_id'], 'conv-123');
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test('APNs delivery formats PushKit VoIP incoming call wake with .voip topic and priority 10', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requestHeaders = <String, String>{};
    var requestBody = '';
    final requestDone = Completer<void>();

    final subscription = server.listen((request) async {
      request.headers.forEach((name, values) {
        requestHeaders[name.toLowerCase()] = values.join(', ');
      });
      requestBody = await utf8.decoder.bind(request).join();
      request.response
        ..statusCode = HttpStatus.ok
        ..write('{"status":"ok"}');
      await request.response.close();
      requestDone.complete();
    });

    try {
      final provider = ApnsPushProvider.staticToken(
        teamId: 'TEAM123456',
        keyId: 'KEY1234567',
        bundleId: 'com.example.helix',
        accessToken: 'test-apns-bearer',
        endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      await provider.deliver(
        token: 'voip-token-123',
        tokenType: 'APNS_VOIP',
        data: {
          'notification_type': 'incoming_call',
          'call_id': 'call-777',
          'is_video': true,
          'caller_display_name': 'Bob',
        },
      );
      await requestDone.future;

      expect(requestHeaders['authorization'], 'bearer test-apns-bearer');
      expect(requestHeaders['apns-topic'], 'com.example.helix.voip');
      expect(requestHeaders['apns-push-type'], 'voip');
      expect(requestHeaders['apns-priority'], '10');
      expect(requestHeaders['apns-expiration'], '0');

      final bodyJson = jsonDecode(requestBody) as Map<String, dynamic>;
      expect(bodyJson['aps'], <String, dynamic>{});
      expect(bodyJson['notification_type'], 'incoming_call');
      expect(bodyJson['call_id'], 'call-777');
      expect(bodyJson['is_video'], 'true');
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test('APNs delivery throws ApnsTokenNotFoundException on 410 or BadDeviceToken', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.gone
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'reason': 'Unregistered'}));
      await request.response.close();
    });

    try {
      final provider = ApnsPushProvider.staticToken(
        teamId: 'TEAM123456',
        keyId: 'KEY1234567',
        bundleId: 'com.example.helix',
        accessToken: 'test-apns-bearer',
        endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
      );

      await expectLater(
        provider.deliver(
          token: 'expired-token',
          tokenType: 'APNS',
          data: {'notification_type': 'new_message'},
        ),
        throwsA(isA<ApnsTokenNotFoundException>()),
      );
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });

  test('CompositePushProvider correctly routes between FCM and APNs', () async {
    final deliveredTo = <String>[];

    final fcmMock = _MockPushProvider(onDeliver: (token, type) {
      deliveredTo.add('FCM:$token:$type');
    });
    final apnsMock = _MockPushProvider(onDeliver: (token, type) {
      deliveredTo.add('APNS:$token:$type');
    });

    final composite = CompositePushProvider(fcm: fcmMock, apns: apnsMock);
    expect(composite.isConfigured, isTrue);

    // Explicit APNS
    await composite.deliver(
      token: 'token1',
      tokenType: 'APNS',
      data: {'msg': '1'},
    );
    // Explicit APNS_VOIP
    await composite.deliver(
      token: 'token2',
      tokenType: 'APNS_VOIP',
      data: {'msg': '2'},
    );
    // Explicit FCM
    await composite.deliver(
      token: 'token3',
      tokenType: 'FCM',
      data: {'msg': '3'},
    );
    // Inferred APNs hex token (64 hex characters)
    await composite.deliver(
      token: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      data: {'msg': '4'},
    );
    // Inferred standard FCM token
    await composite.deliver(
      token: 'fcm-standard-token-sample',
      data: {'msg': '5'},
    );

    expect(deliveredTo, [
      'APNS:token1:APNS',
      'APNS:token2:APNS_VOIP',
      'FCM:token3:FCM',
      'APNS:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef:null',
      'FCM:fcm-standard-token-sample:null',
    ]);
  });
}

class _MockPushProvider implements PushProvider {
  _MockPushProvider({required this.onDeliver});
  final void Function(String token, String? tokenType) onDeliver;

  @override
  bool get isConfigured => true;

  @override
  Future<void> deliver({
    required String token,
    required Map<String, dynamic> data,
    String? tokenType,
  }) async {
    onDeliver(token, tokenType);
  }
}
