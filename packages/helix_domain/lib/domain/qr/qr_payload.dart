class QrPayload {
  final String displayName;
  final String deviceSuffix;
  final String localIp;
  final List<String> localIps;
  final int tcpPort;
  final String sessionId;

  const QrPayload({
    required this.displayName,
    required this.deviceSuffix,
    required this.localIp,
    this.localIps = const [],
    required this.tcpPort,
    required this.sessionId,
  });
}
