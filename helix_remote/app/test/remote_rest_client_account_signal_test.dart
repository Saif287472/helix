import 'dart:convert';
import 'dart:io';

import 'package:helix_remote/app/account_restriction.dart';
import 'package:helix_remote/app/remote_rest_client.dart';
import 'package:test/test.dart';

// Plain `package:test`, not flutter_test: the widget binding replaces
// HttpClient with a fake that answers 400, which would hide the real
// responses these tests depend on.
void main() {
  group('REST client account signals', () {
    late HttpServer server;
    late List<AccountSignal> signals;
    late HelixRemoteRestClientImpl client;

    /// Serves every request with [status], [body] and, when [suspended], the
    /// backend's suspension marker.
    Future<void> serve(
      int status,
      Object body, {
      bool suspended = false,
    }) async {
      server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((request) async {
        request.response.statusCode = status;
        if (suspended) {
          request.response.headers.set(kAccountStatusHeader, 'suspended');
        }
        request.response.write(jsonEncode(body));
        await request.response.close();
      });
      signals = [];
      client = HelixRemoteRestClientImpl(
        baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
        timeoutMs: 2000,
        onAccountSignal: signals.add,
      )..accessToken = 'token';
    }

    tearDown(() => server.close(force: true));

    test(
      'an authenticated success without the marker reports active',
      () async {
        await serve(200, {'devices': <Object>[]});
        await client.listDevices();
        expect(signals, [AccountSignal.active]);
      },
    );

    test('the suspension marker reports suspended, never active', () async {
      await serve(200, {'devices': <Object>[]}, suspended: true);
      await client.listDevices();
      expect(signals, [AccountSignal.suspended]);
    });

    test('a refused action reports refusedWhileSuspended', () async {
      await serve(403, {
        'error': 'Forbidden: Account suspended',
        'code': 'account_suspended',
      }, suspended: true);
      await expectLater(client.listDevices(), throwsA(anything));
      expect(signals, [
        AccountSignal.suspended,
        AccountSignal.refusedWhileSuspended,
      ]);
    });

    test('account_blocked and phone_blocked report blocked', () async {
      await serve(403, {'error': 'blocked', 'code': 'account_blocked'});
      await expectLater(client.listDevices(), throwsA(anything));
      expect(signals, [AccountSignal.blocked]);

      await server.close(force: true);
      await serve(403, {'error': 'blocked', 'code': 'phone_blocked'});
      await expectLater(client.listDevices(), throwsA(anything));
      expect(signals, [AccountSignal.blocked]);
    });

    test('an unauthenticated success says nothing about the account', () async {
      await serve(200, {'devices': <Object>[]});
      client.accessToken = null;
      await client.listDevices();
      expect(signals, isEmpty);
    });
  });
}
