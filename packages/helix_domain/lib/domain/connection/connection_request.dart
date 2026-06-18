// ---------------------------------------------------------------------------
// Connection request
// ---------------------------------------------------------------------------

enum RequestDirection { incoming, outgoing }

enum RequestStatus { pending, accepted, rejected, canceled, expired, blocked }

enum RequestSourceMethod { nearby, secretCode, directIp }

class ConnectionRequest {
  final String requestId;
  final RequestDirection direction;
  final String peerDisplayName;
  final String peerDeviceSuffix;
  final String peerSessionId;
  final String peerStaticKeyFingerprint;
  final String peerHost;
  final int peerPort;
  final RequestSourceMethod source;
  final DateTime createdAt;
  final DateTime expiresAt;
  RequestStatus status;
  bool isPossibleImpersonation;

  ConnectionRequest({
    required this.requestId,
    required this.direction,
    required this.peerDisplayName,
    required this.peerDeviceSuffix,
    required this.peerSessionId,
    required this.peerStaticKeyFingerprint,
    required this.peerHost,
    required this.peerPort,
    required this.source,
    required this.createdAt,
    required this.expiresAt,
    this.status = RequestStatus.pending,
    this.isPossibleImpersonation = false,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  Duration get remaining => expiresAt.difference(DateTime.now());
}
