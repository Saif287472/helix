/// IP privacy mode for Remote calls.
enum IpPrivacyMode {
  /// Allow host, srflx, and relay candidates. Peer can see local IP.
  directAndRelay,

  /// Only relay candidates are forwarded. Local IP is never visible to peers.
  relayOnly,
}

class IceServerConfig {
  const IceServerConfig({required this.url, this.username, this.credential});

  final String url;
  final String? username;
  final String? credential;

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{'urls': url};
    if (username != null) map['username'] = username;
    if (credential != null) map['credential'] = credential;
    return map;
  }
}

/// ICE configuration for Remote calls.
///
/// Differs from Local by supporting STUN and TURN servers for
/// NAT traversal across the internet. No private-IP candidate filtering.
class RemoteIceConfig {
  const RemoteIceConfig({
    required this.iceServers,
    this.ipPrivacy = IpPrivacyMode.relayOnly,
  });

  /// Explicit development helper: two public STUN servers, no TURN.
  ///
  /// Production composition must inject deployment-specific STUN/TURN
  /// configuration instead of relying on this helper.
  factory RemoteIceConfig.defaultStun() {
    return const RemoteIceConfig(
      iceServers: [
        IceServerConfig(url: 'stun:stun.l.google.com:19302'),
        IceServerConfig(url: 'stun:stun1.l.google.com:19302'),
      ],
      ipPrivacy: IpPrivacyMode.directAndRelay,
    );
  }

  final List<IceServerConfig> iceServers;
  final IpPrivacyMode ipPrivacy;

  RemoteIceConfig withTurnCredentials({
    required String turnUrl,
    required String username,
    required String credential,
  }) {
    return RemoteIceConfig(
      iceServers: [
        ...iceServers,
        IceServerConfig(
          url: turnUrl,
          username: username,
          credential: credential,
        ),
      ],
      ipPrivacy: ipPrivacy,
    );
  }

  RemoteIceConfig withIpPrivacy(IpPrivacyMode mode) {
    return RemoteIceConfig(iceServers: iceServers, ipPrivacy: mode);
  }

  List<Map<String, dynamic>> toWebRtcIceServers() =>
      iceServers.map((s) => s.toMap()).toList();
}
