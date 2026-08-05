// Server-side enforcement of a call's IP-privacy policy.
//
// Relay-only used to be a client-side promise. `iceTransportPolicy: 'relay'`
// constrains only the candidates the app itself gathers — it does nothing
// about candidates arriving from the far side, which pass through this
// server carrying the sender's address. These tests pin the server's half:
// that a non-relay candidate cannot reach the other party, and that the
// failure modes fail closed.

import 'package:test/test.dart';
import 'package:helix_remote_backend/src/call_media_policy.dart';

void main() {
  group('candidate classification', () {
    test('recognises a relay candidate', () {
      expect(
        isRelayCandidate(
          'candidate:1 1 udp 41885439 203.0.113.7 51234 typ relay '
          'raddr 198.51.100.4 rport 40000',
        ),
        isTrue,
      );
    });

    test('rejects host, srflx and prflx candidates', () {
      expect(
        isRelayCandidate(
          'candidate:2 1 udp 2122260223 192.168.1.5 54321 '
          'typ host generation 0',
        ),
        isFalse,
      );
      expect(
        isRelayCandidate(
          'candidate:3 1 udp 1686052607 198.51.100.4 40000 '
          'typ srflx raddr 192.168.1.5 rport 54321',
        ),
        isFalse,
      );
      expect(
        isRelayCandidate(
          'candidate:4 1 udp 1685987071 198.51.100.9 40001 '
          'typ prflx',
        ),
        isFalse,
      );
    });

    test('an unparseable candidate is not treated as relay', () {
      // Guessing is most expensive exactly where parsing failed.
      expect(isRelayCandidate('candidate:garbage'), isFalse);
      expect(isRelayCandidate(''), isFalse);
      expect(isRelayCandidate('typ'), isFalse);
    });
  });

  group('policy parsing fails closed', () {
    test('absent, unknown and non-string values all mean relay-only', () {
      expect(CallMediaPolicy.fromWire(null), CallMediaPolicy.relayOnly);
      expect(CallMediaPolicy.fromWire('nonsense'), CallMediaPolicy.relayOnly);
      expect(CallMediaPolicy.fromWire(42), CallMediaPolicy.relayOnly);
      // An old client that sends no policy at all must be relayed, not
      // exposed.
      expect(CallMediaPolicy.fromWire(''), CallMediaPolicy.relayOnly);
    });

    test('known wire names round-trip', () {
      for (final policy in CallMediaPolicy.values) {
        expect(CallMediaPolicy.fromWire(policy.wireName), policy);
      }
    });

    test('the stricter side wins, in both argument orders', () {
      expect(
        CallMediaPolicy.strictest(
          CallMediaPolicy.directAndRelay,
          CallMediaPolicy.relayOnly,
        ),
        CallMediaPolicy.relayOnly,
      );
      expect(
        CallMediaPolicy.strictest(
          CallMediaPolicy.relayOnly,
          CallMediaPolicy.directAndRelay,
        ),
        CallMediaPolicy.relayOnly,
      );
      expect(
        CallMediaPolicy.strictest(
          CallMediaPolicy.directIfVerified,
          CallMediaPolicy.directAndRelay,
        ),
        CallMediaPolicy.directIfVerified,
      );
    });

    test('an unresolved directIfVerified does not permit direct', () {
      expect(CallMediaPolicy.directIfVerified.permitsDirectCandidates, isFalse);
      expect(CallMediaPolicy.relayOnly.permitsDirectCandidates, isFalse);
      expect(CallMediaPolicy.directAndRelay.permitsDirectCandidates, isTrue);
    });
  });

  group('trickle candidates', () {
    test('a non-relay candidate is dropped, not forwarded', () {
      final decision = applyMediaPolicy(
        policy: CallMediaPolicy.relayOnly,
        candidate: 'candidate:2 1 udp 2122260223 192.168.1.5 54321 typ host',
      );
      expect(decision.allowed, isFalse);
      expect(decision.droppedCandidate, isTrue);
    });

    test('a relay candidate passes through', () {
      final decision = applyMediaPolicy(
        policy: CallMediaPolicy.relayOnly,
        candidate: 'candidate:1 1 udp 41885439 203.0.113.7 51234 typ relay',
      );
      expect(decision.allowed, isTrue);
      expect(decision.droppedCandidate, isFalse);
    });

    test('the end-of-candidates marker is left alone', () {
      final decision = applyMediaPolicy(
        policy: CallMediaPolicy.relayOnly,
        candidate: '',
      );
      expect(decision.allowed, isTrue);
    });

    test('direct_and_relay forwards everything untouched', () {
      final decision = applyMediaPolicy(
        policy: CallMediaPolicy.directAndRelay,
        candidate: 'candidate:2 1 udp 2122260223 192.168.1.5 54321 typ host',
      );
      expect(decision.allowed, isTrue);
      expect(decision.modified, isFalse);
    });
  });

  group('candidates inline in SDP', () {
    // Candidates usually arrive as separate trickle signals, but an offer
    // generated after gathering completes carries them inline. Filtering
    // only the trickle path would leave that hole wide open.
    const sdp =
        'v=0\r\n'
        'o=- 46117 2 IN IP4 127.0.0.1\r\n'
        'm=audio 51234 UDP/TLS/RTP/SAVPF 111\r\n'
        'a=candidate:2 1 udp 2122260223 192.168.1.5 54321 typ host\r\n'
        'a=candidate:3 1 udp 1686052607 198.51.100.4 40000 typ srflx '
        'raddr 192.168.1.5 rport 54321\r\n'
        'a=candidate:1 1 udp 41885439 203.0.113.7 51234 typ relay\r\n'
        'a=end-of-candidates\r\n';

    test('non-relay lines are stripped and relay lines kept', () {
      final decision = applyMediaPolicy(
        policy: CallMediaPolicy.relayOnly,
        sdp: sdp,
      );
      expect(decision.allowed, isTrue);
      expect(decision.strippedSdpCandidates, equals(2));
      expect(decision.sdp, isNot(contains('192.168.1.5')));
      expect(decision.sdp, isNot(contains('typ srflx')));
      expect(decision.sdp, contains('typ relay'));
      // Everything that is not a candidate survives untouched.
      expect(decision.sdp, contains('m=audio'));
      expect(decision.sdp, contains('a=end-of-candidates'));
      expect(decision.sdp, contains('v=0'));
    });

    test('CRLF line endings are preserved', () {
      final decision = applyMediaPolicy(
        policy: CallMediaPolicy.relayOnly,
        sdp: sdp,
      );
      expect(decision.sdp, contains('v=0\r\n'));
      expect(decision.sdp, isNot(contains('v=0\n\n')));
    });

    test('an SDP with no candidates is returned unchanged', () {
      const plain = 'v=0\r\nm=audio 51234 UDP/TLS/RTP/SAVPF 111\r\n';
      final decision = applyMediaPolicy(
        policy: CallMediaPolicy.relayOnly,
        sdp: plain,
      );
      expect(decision.sdp, equals(plain));
      expect(decision.strippedSdpCandidates, isZero);
    });

    test('direct_and_relay leaves the SDP alone', () {
      final decision = applyMediaPolicy(
        policy: CallMediaPolicy.directAndRelay,
        sdp: sdp,
      );
      expect(decision.sdp, equals(sdp));
      expect(decision.modified, isFalse);
    });
  });
}
