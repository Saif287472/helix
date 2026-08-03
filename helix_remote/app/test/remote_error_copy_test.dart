import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/remote_error_copy.dart';
import 'package:helix_remote/app/remote_rest_client.dart';

void main() {
  group('RemoteUserErrorCopy', () {
    final emulatorBackend = Uri.parse('http://10.0.2.2:8000');
    final physicalDeviceBackend = Uri.parse('http://127.0.0.1:8000');

    RemoteRestException failure(
      RemoteRestFailureKind kind, {
      int? statusCode,
      Uri? uri,
    }) => RemoteRestException(
      message: 'raw SocketException details should not leak',
      uri: uri ?? emulatorBackend,
      statusCode: statusCode,
      failureKind: kind,
    );

    test('refresh copy distinguishes server-down, network, and timeout', () {
      expect(
        RemoteUserErrorCopy.refreshFailure(
          failure(RemoteRestFailureKind.serverDown),
          emulatorBackend,
        ),
        allOf(
          contains('server is unreachable'),
          contains('Start the Helix Remote backend on your PC'),
          isNot(contains('SocketException')),
        ),
      );

      expect(
        RemoteUserErrorCopy.refreshFailure(
          failure(RemoteRestFailureKind.noInternet),
          emulatorBackend,
        ),
        contains('Reconnect to Wi-Fi or mobile data'),
      );

      expect(
        RemoteUserErrorCopy.refreshFailure(
          failure(RemoteRestFailureKind.timeout),
          emulatorBackend,
        ),
        contains('did not respond in time'),
      );
    });

    test('refresh copy maps auth and server HTTP failures', () {
      expect(
        RemoteUserErrorCopy.authExpired(),
        allOf(contains('session expired'), contains('revoked')),
      );

      expect(
        RemoteUserErrorCopy.refreshFailure(
          failure(RemoteRestFailureKind.http, statusCode: 503),
          emulatorBackend,
        ),
        contains('server is having trouble'),
      );

      expect(
        RemoteUserErrorCopy.refreshFailure(
          failure(RemoteRestFailureKind.unknown),
          emulatorBackend,
        ),
        allOf(contains('unexpected error'), isNot(contains('SocketException'))),
      );
    });

    test('registration copy gives Android localhost and conflict guidance', () {
      expect(
        RemoteUserErrorCopy.registrationFailure(
          failure(RemoteRestFailureKind.serverDown),
          physicalDeviceBackend,
        ),
        allOf(
          contains('localhost points to the phone'),
          contains('HELIX_REMOTE_HOST'),
          isNot(contains('SocketException')),
        ),
      );

      expect(
        RemoteUserErrorCopy.registrationFailure(
          failure(RemoteRestFailureKind.http, statusCode: 409),
          emulatorBackend,
        ),
        contains('already registered'),
      );

      expect(
        RemoteUserErrorCopy.registrationFailure(
          failure(RemoteRestFailureKind.noInternet),
          emulatorBackend,
        ),
        allOf(contains('Network unavailable'), contains('try again')),
      );
    });

    test(
      'profile update copy surfaces the server\'s own rate-limit message',
      () {
        final rateLimited = RemoteRestException(
          message:
              '{"error":"You can only change your display name once every '
              '30 days. Try again on 2026-09-02.","next_allowed_at":123}',
          uri: emulatorBackend,
          statusCode: 429,
          failureKind: RemoteRestFailureKind.http,
        );
        expect(
          RemoteUserErrorCopy.profileUpdateFailure(rateLimited),
          equals(
            'You can only change your display name once every 30 days. '
            'Try again on 2026-09-02.',
          ),
        );
      },
    );

    test(
      'profile update copy falls back to generic text when the body is not '
      'JSON',
      () {
        expect(
          RemoteUserErrorCopy.profileUpdateFailure(
            failure(RemoteRestFailureKind.http, statusCode: 429),
          ),
          contains('once every 30 days'),
        );
        expect(
          RemoteUserErrorCopy.profileUpdateFailure(
            failure(RemoteRestFailureKind.noInternet),
          ),
          allOf(contains('Network unavailable'), contains('try again')),
        );
      },
    );
  });
}
