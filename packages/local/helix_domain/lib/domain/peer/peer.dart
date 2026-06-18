import 'package:meta/meta.dart';

// ---------------------------------------------------------------------------
// Peer source
// ---------------------------------------------------------------------------

enum PeerSource { mdns, udpBroadcast, secretCode, directIp }

// ---------------------------------------------------------------------------
// Peer
// ---------------------------------------------------------------------------

@immutable
class Peer {
  final String sessionId;
  final String displayName;
  final String deviceSuffix;
  final String host;
  final int port;
  final PeerSource source;
  final DateTime seenAt;
  final int protocolMajor;
  final int protocolMinor;

  const Peer({
    required this.sessionId,
    required this.displayName,
    required this.deviceSuffix,
    required this.host,
    required this.port,
    required this.source,
    required this.seenAt,
    required this.protocolMajor,
    required this.protocolMinor,
  });

  Peer copyWith({DateTime? seenAt, String? host, int? port}) => Peer(
    sessionId: sessionId,
    displayName: displayName,
    deviceSuffix: deviceSuffix,
    host: host ?? this.host,
    port: port ?? this.port,
    source: source,
    seenAt: seenAt ?? this.seenAt,
    protocolMajor: protocolMajor,
    protocolMinor: protocolMinor,
  );

  @override
  bool operator ==(Object other) =>
      other is Peer && sessionId == other.sessionId;

  @override
  int get hashCode => sessionId.hashCode;
}
