import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Diagnostics
// ---------------------------------------------------------------------------

@immutable
class NetworkDiagnostics {
  final String? interfaceType;
  final String? localIp;
  final String? networkName;
  final bool mdnsAvailable;
  final bool udpBroadcastAvailable;
  final bool tcpListenerActive;
  final int tcpListenerPort;
  final bool clientIsolationSuspected;
  final String? firewallNote;
  final String protocolVersion;

  const NetworkDiagnostics({
    this.interfaceType,
    this.localIp,
    this.networkName,
    required this.mdnsAvailable,
    required this.udpBroadcastAvailable,
    required this.tcpListenerActive,
    required this.tcpListenerPort,
    required this.clientIsolationSuspected,
    this.firewallNote,
    required this.protocolVersion,
  });
}
