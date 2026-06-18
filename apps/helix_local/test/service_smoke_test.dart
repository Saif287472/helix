import 'package:flutter_test/flutter_test.dart';
import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix/providers/controllers/diagnostics_service.dart';
import 'package:helix/providers/controllers/qr_code_service.dart';
import 'package:helix/providers/controllers/session_service.dart';

void main() {
  group('QrCodeService smoke tests', () {
    const service = QrCodeService();

    test('encode/decode round-trips the current QR payload', () {
      const payload = QrPayload(
        displayName: 'Alice',
        deviceSuffix: 'a1b2',
        localIp: '192.168.1.10',
        localIps: ['192.168.1.10', '10.0.0.5'],
        tcpPort: 4242,
        sessionId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );

      final encoded = service.encode(payload);
      final decoded = service.decode(encoded);

      expect(encoded.startsWith('wsp:'), isTrue);
      expect(decoded, isNotNull);
      expect(decoded!.displayName, payload.displayName);
      expect(decoded.deviceSuffix, payload.deviceSuffix);
      expect(decoded.localIp, payload.localIp);
      expect(decoded.localIps, payload.localIps);
      expect(decoded.tcpPort, payload.tcpPort);
      expect(decoded.sessionId, payload.sessionId);
    });

    test('decode rejects non-Helix or malformed QR strings', () {
      expect(service.decode('hello'), isNull);
      expect(service.decode('wsp:not valid base64'), isNull);
    });

    test('payloadToPeers produces direct-IP peer stubs for all hosts', () {
      const payload = QrPayload(
        displayName: 'Alice',
        deviceSuffix: 'a1b2',
        localIp: '192.168.1.10',
        localIps: ['192.168.1.10', '10.0.0.5'],
        tcpPort: 4242,
        sessionId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );

      final peers = service.payloadToPeers(payload);

      expect(peers.map((p) => p.host), ['192.168.1.10', '10.0.0.5']);
      expect(peers.every((p) => p.source == PeerSource.directIp), isTrue);
      expect(peers.every((p) => p.port == 4242), isTrue);
    });
  });

  group('DiagnosticsService smoke tests', () {
    test('getDiagnostics returns caller-supplied listener state', () async {
      final service = DiagnosticsService();
      service.recordBindError('udp bind denied');

      final diagnostics = await service.getDiagnostics(
        tcpPort: 4242,
        tcpActive: true,
        mdnsActive: true,
        udpActive: true,
      );

      expect(diagnostics.tcpListenerActive, isTrue);
      expect(diagnostics.tcpListenerPort, 4242);
      expect(diagnostics.protocolVersion, '$kProtocolMajor.$kProtocolMinor');
    });
  });

  group('SessionService smoke tests', () {
    test('starts idle and exposes an empty session id before start', () {
      final service = SessionService();

      expect(service.state.phase, SessionPhase.idle);
      expect(service.sessionId, isEmpty);

      service.dispose();
    });
  });
}
