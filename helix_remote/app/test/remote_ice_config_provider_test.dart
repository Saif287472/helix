import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/remote_ice_config_provider.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote/app/remote_rest_client.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';
import 'support/group_call_rest_stubs.dart';

void main() {
  test(
    'runtime ICE provider fetches TURN URLs and caches until near expiry',
    () async {
      var now = DateTime.fromMillisecondsSinceEpoch(1000000);
      final rest = _FakeRestClient(
        () => {
          'urls': [
            'turn:turn.example.test:3478?transport=udp',
            'turn:turn.example.test:3478?transport=tcp',
            'turns:turn.example.test:5349?transport=tcp',
          ],
          'username': 'expiring-user',
          'credential': 'expiring-credential',
          'expires_at':
              now.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
        },
      );
      final provider = RemoteIceConfigProvider(
        restClient: rest,
        baseConfig: const RemoteIceConfig(
          iceServers: [IceServerConfig(url: 'stun:stun.example.test:3478')],
          ipPrivacy: IpPrivacyMode.relayOnly,
        ),
        clock: () => now,
      );

      final first = await provider.getIceConfig();
      final second = await provider.getIceConfig();
      expect(rest.calls, equals(1));
      expect(first.iceServers, hasLength(4));
      expect(second.iceServers.last.url, startsWith('turns:'));
      expect(
        first.toWebRtcConfiguration()['iceTransportPolicy'],
        equals('relay'),
      );

      now = now.add(const Duration(minutes: 56));
      await provider.getIceConfig();
      expect(rest.calls, equals(2));
    },
  );

  group('setup failures are classified, not flattened', () {
    test('a 503 means the server has no relay configured', () async {
      final provider = _providerFor(
        _ThrowingRestClient(
          const RemoteRestException(
            message: 'TURN is not configured',
            statusCode: 503,
          ),
        ),
      );
      await expectLater(
        provider.getIceConfig(),
        throwsA(
          isA<RemoteCallSetupException>()
              .having(
                (e) => e.failure,
                'failure',
                RemoteCallSetupFailure.turnNotConfigured,
              )
              .having(
                (e) => e.userMessage,
                'userMessage',
                contains('server admin'),
              ),
        ),
      );
    });

    test('an unreachable server is reported as a network failure', () async {
      final provider = _providerFor(
        _ThrowingRestClient(
          const RemoteRestException(
            message: 'connection refused',
            failureKind: RemoteRestFailureKind.serverDown,
          ),
        ),
      );
      await expectLater(
        provider.getIceConfig(),
        throwsA(
          isA<RemoteCallSetupException>().having(
            (e) => e.failure,
            'failure',
            RemoteCallSetupFailure.network,
          ),
        ),
      );
    });

    test('relay-only without a usable TURN server fails closed', () async {
      // Never falls back to STUN: relayOnly is a privacy guarantee, and
      // degrading it silently because of a server misconfiguration would
      // leak peers' IP addresses to each other with no notice.
      final provider = _providerFor(
        _FakeRestClient(
          () => {
            'urls': <String>['stun:only.example.test:3478'],
            'username': 'u',
            'credential': 'c',
            'expires_at':
                DateTime.now()
                    .add(const Duration(hours: 1))
                    .millisecondsSinceEpoch ~/
                1000,
          },
        ),
      );
      await expectLater(
        provider.getIceConfig(),
        throwsA(
          isA<RemoteCallSetupException>().having(
            (e) => e.failure,
            'failure',
            RemoteCallSetupFailure.turnUnavailable,
          ),
        ),
      );
    });
  });
}

// A server with no TURN relay answers the credential request with 503.
// Before this was classified here, the raw RemoteRestException travelled all
// the way up and the call layer could only say "check your connectivity" -
// for a server-side configuration problem the user cannot fix.
RemoteIceConfigProvider _providerFor(HelixRemoteRestClient rest) =>
    RemoteIceConfigProvider(
      restClient: rest,
      baseConfig: const RemoteIceConfig(
        iceServers: [IceServerConfig(url: 'stun:stun.example.test:3478')],
        ipPrivacy: IpPrivacyMode.relayOnly,
      ),
    );

class _ThrowingRestClient with GroupCallRestStubs implements HelixRemoteRestClient {
  _ThrowingRestClient(this._error);

  final Object _error;

  @override
  Future<Map<String, dynamic>> getTurnCredentials() async => throw _error;

  @override
  set accessToken(String? token) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRestClient with GroupCallRestStubs implements HelixRemoteRestClient {
  _FakeRestClient(this._response);

  final Map<String, dynamic> Function() _response;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> getTurnCredentials() async {
    calls++;
    return _response();
  }

  @override
  set accessToken(String? token) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
