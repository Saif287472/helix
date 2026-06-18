import 'package:helix_local_protocol/application/contracts/gateways.dart';
import 'package:helix_local_protocol/application/contracts/use_cases.dart';
import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/domain/models.dart';

class DiagnosticsUseCaseImpl implements DiagnosticsUseCase {
  final DiagnosticsGateway _gateway;
  final List<String> _bindErrors = [];

  DiagnosticsUseCaseImpl({required this._gateway});

  @override
  void recordBindError(String message) {
    _bindErrors.add(message);
    if (_bindErrors.length > 20) {
      _bindErrors.removeAt(0);
    }
  }

  @override
  Future<NetworkDiagnostics> getDiagnostics({
    int tcpPort = 0,
    bool tcpActive = false,
    bool mdnsActive = false,
    bool udpActive = false,
  }) async {
    final localIp = await _gateway.getWifiIP();
    final networkName = await _gateway.getWifiName();
    final interfaceType = await _gateway.getConnectivityType();

    final mdnsBindFailed = _bindErrors.any(
      (e) =>
          e.toLowerCase().contains('mdns') ||
          e.toLowerCase().contains('multicast'),
    );
    final mdnsAvailable = mdnsActive && !mdnsBindFailed;

    final udpBindFailed = _bindErrors.any(
      (e) =>
          e.toLowerCase().contains('udp') || e.toLowerCase().contains('bind'),
    );
    final udpBroadcastAvailable = udpActive && !udpBindFailed;

    String? firewallNote;
    if (isWindows) {
      if (_bindErrors.isNotEmpty ||
          (!mdnsAvailable && !udpBroadcastAvailable)) {
        firewallNote =
            'Windows Firewall may be blocking UDP port $kUdpDiscoveryPort '
            'or TCP port $tcpPort. Allow Helix through the firewall to '
            'enable peer discovery.';
      }
    }

    const clientIsolationSuspected = false;

    return NetworkDiagnostics(
      interfaceType: interfaceType,
      localIp: localIp,
      networkName: networkName,
      mdnsAvailable: mdnsAvailable,
      udpBroadcastAvailable: udpBroadcastAvailable,
      tcpListenerActive: tcpActive,
      tcpListenerPort: tcpPort,
      clientIsolationSuspected: clientIsolationSuspected,
      firewallNote: firewallNote,
      protocolVersion: '$kProtocolMajor.$kProtocolMinor',
    );
  }
}
