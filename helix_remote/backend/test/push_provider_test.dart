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
        data: {'notification_type': 'incoming_call', 'call_id': 'call-1'},
      );
      await requestDone.future;

      expect(requests.single['message'], isA<Map<String, dynamic>>());
    } finally {
      await subscription.cancel();
      await server.close(force: true);
    }
  });
}
