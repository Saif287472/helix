import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_calls/helix_remote_calls.dart';

void main() {
  group('RemoteIceConfig', () {
    test('defaults to relay-only and says so in the WebRTC configuration', () {
      const config = RemoteIceConfig(iceServers: []);
      expect(config.ipPrivacy, IpPrivacyMode.relayOnly);
      expect(config.toWebRtcConfiguration()['iceTransportPolicy'], 'relay');
    });

    test(
      'only an explicit direct-and-relay policy gathers direct candidates',
      () {
        const config = RemoteIceConfig(iceServers: []);
        final direct = config.withIpPrivacy(IpPrivacyMode.directAndRelay);
        expect(
          direct.toWebRtcConfiguration().containsKey('iceTransportPolicy'),
          isFalse,
        );
        // An unresolved "direct if verified" fails closed.
        final unresolved = config.withIpPrivacy(IpPrivacyMode.directIfVerified);
        expect(
          unresolved.toWebRtcConfiguration()['iceTransportPolicy'],
          'relay',
        );
      },
    );

    test('directIfVerified resolves per peer', () {
      expect(
        IpPrivacyMode.directIfVerified.resolveForPeer(peerVerified: true),
        IpPrivacyMode.directAndRelay,
      );
      expect(
        IpPrivacyMode.directIfVerified.resolveForPeer(peerVerified: false),
        IpPrivacyMode.relayOnly,
      );
      expect(
        IpPrivacyMode.strictest(
          IpPrivacyMode.directAndRelay,
          IpPrivacyMode.relayOnly,
        ),
        IpPrivacyMode.relayOnly,
      );
    });

    test('wire names round-trip and unknown names are null', () {
      for (final mode in IpPrivacyMode.values) {
        expect(IpPrivacyMode.fromWire(mode.wireName), mode);
      }
      expect(IpPrivacyMode.fromWire('nonsense'), isNull);
      expect(IpPrivacyMode.fromWire(null), isNull);
    });

    test('TURN credentials are added next to STUN and keep the policy', () {
      final config = RemoteIceConfig.defaultStun().withTurnCredentialUrls(
        turnUrls: const [
          'turn:turn.example.com:3478?transport=udp',
          'turns:turn.example.com:5349?transport=tcp',
        ],
        username: 'user',
        credential: 'cred',
      );
      final servers = config.toWebRtcIceServers();
      expect(
        servers.any((s) => (s['urls'] as String).startsWith('stun:')),
        isTrue,
      );
      expect(config.hasTurnServer, isTrue);
      expect(servers.where((s) => s.containsKey('credential')), hasLength(2));
      expect(config.ipPrivacy, IpPrivacyMode.directAndRelay);
      expect(RemoteIceConfig.defaultStun().hasTurnServer, isFalse);
    });
  });
}
