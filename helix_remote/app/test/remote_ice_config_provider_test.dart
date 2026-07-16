import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/remote_ice_config_provider.dart';
import 'package:helix_remote_api/api/rest_client.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';

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
}

class _FakeRestClient implements HelixRemoteRestClient {
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
