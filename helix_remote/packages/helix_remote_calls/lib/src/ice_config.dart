/// IP privacy mode for Remote calls.
///
/// Declared in order of increasing strictness so [strictest] can compare by
/// [Enum.index]. Do not reorder.
///
/// A note on what `relayOnly` does and does not buy you, because it is easy
/// to over-trust: setting `iceTransportPolicy: 'relay'` constrains only
/// *this* peer's candidate gathering and which pairs it will try. It does
/// nothing about the candidates the *remote* peer sends, which arrive
/// through signaling regardless and carry their address. So relay-only is
/// symmetric protection only when both sides honour it - and "honour" is the
/// operative word for anything enforced purely client-side. That is why the
/// negotiated policy is also enforced on the server, which sees every
/// candidate and can drop the ones that would leak.
enum IpPrivacyMode {
  /// Allow host, srflx, and relay candidates. Peers learn each other's IP
  /// addresses. Never a default and never reached by fallback - it has to be
  /// chosen.
  directAndRelay('direct_and_relay'),

  /// Direct candidates only with a peer whose identity has been verified;
  /// relay-only with everyone else. Resolve with [resolveForPeer] before
  /// using this to build a WebRTC configuration.
  directIfVerified('direct_if_verified'),

  /// Only relay candidates. Peers never learn each other's addresses.
  relayOnly('relay_only');

  const IpPrivacyMode(this.wireName);

  /// Stable name used on the wire and in config files. Deliberately not
  /// [Enum.name]: renaming a Dart identifier must not silently change a
  /// negotiated protocol value.
  final String wireName;

  static IpPrivacyMode? fromWire(String? value) {
    if (value == null) return null;
    for (final mode in IpPrivacyMode.values) {
      if (mode.wireName == value) return mode;
    }
    return null;
  }

  /// The stricter of two policies. Call setup uses this so a peer that wants
  /// relay-only cannot be talked into anything looser by the other side.
  static IpPrivacyMode strictest(IpPrivacyMode a, IpPrivacyMode b) =>
      a.index >= b.index ? a : b;

  /// True only for [directAndRelay]. [directIfVerified] deliberately answers
  /// false: it is not a decision, it is a decision *rule*, and anything
  /// asking this question of an unresolved policy should get the safe
  /// answer. Resolve it with [resolveForPeer] first.
  bool get allowsDirectCandidates => this == IpPrivacyMode.directAndRelay;

  /// Collapses [directIfVerified] into a concrete policy for one peer.
  IpPrivacyMode resolveForPeer({required bool peerVerified}) =>
      this == IpPrivacyMode.directIfVerified
      ? (peerVerified ? IpPrivacyMode.directAndRelay : IpPrivacyMode.relayOnly)
      : this;
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
  }) => withTurnCredentialUrls(
    turnUrls: [turnUrl],
    username: username,
    credential: credential,
  );

  RemoteIceConfig withTurnCredentialUrls({
    required List<String> turnUrls,
    required String username,
    required String credential,
  }) {
    return RemoteIceConfig(
      iceServers: [
        ...iceServers,
        for (final url in turnUrls)
          IceServerConfig(url: url, username: username, credential: credential),
      ],
      ipPrivacy: ipPrivacy,
    );
  }

  RemoteIceConfig withIpPrivacy(IpPrivacyMode mode) {
    return RemoteIceConfig(iceServers: iceServers, ipPrivacy: mode);
  }

  List<Map<String, dynamic>> toWebRtcIceServers() =>
      iceServers.map((s) => s.toMap()).toList();

  bool get hasTurnServer => iceServers.any(
    (server) =>
        server.url.startsWith('turn:') || server.url.startsWith('turns:'),
  );

  Map<String, dynamic> toWebRtcConfiguration() {
    return {
      'iceServers': toWebRtcIceServers(),
      // Note the inverted test: relay unless the policy explicitly permits
      // direct. Written this way so an unresolved [IpPrivacyMode
      // .directIfVerified] - or any policy added later - fails closed rather
      // than silently gathering host candidates because it happened not to
      // equal `relayOnly`.
      if (!ipPrivacy.allowsDirectCandidates) 'iceTransportPolicy': 'relay',
    };
  }
}
