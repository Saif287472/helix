/// Server-side enforcement of a call's negotiated IP-privacy policy.
///
/// Relay-only used to be a client-side promise: the app set
/// `iceTransportPolicy: 'relay'` and that was the whole of it. That
/// constrains only the candidates the app itself *gathers*; it does nothing
/// about candidates arriving from the far side, which travel through this
/// server and carry the sender's address. A peer running a modified client -
/// or simply an older build with a different setting - could therefore leak
/// its own address to the other party, or harvest theirs, with no way for
/// the honest side to prevent it.
///
/// The server sees every candidate, so it can make relay-only an actual
/// guarantee instead of an honour system. That is what this file is for.
library;

/// The negotiated policy for one call.
///
/// Mirrors `IpPrivacyMode` in `helix_remote_calls`, deliberately duplicated
/// rather than shared: the backend does not depend on the Flutter package,
/// and the wire names are the contract between them.
enum CallMediaPolicy {
  directAndRelay('direct_and_relay'),
  directIfVerified('direct_if_verified'),
  relayOnly('relay_only');

  const CallMediaPolicy(this.wireName);

  final String wireName;

  /// Unknown, absent and malformed values all resolve to [relayOnly].
  ///
  /// This is the single most important line in the file. A call whose policy
  /// the server cannot determine - an old client that sends no policy at
  /// all, a truncated frame, a backend restart that lost the negotiation -
  /// must be relayed, not exposed. Failing open here would mean the leak
  /// happens precisely in the situations nobody is watching.
  static CallMediaPolicy fromWire(Object? value) {
    if (value is String) {
      for (final policy in CallMediaPolicy.values) {
        if (policy.wireName == value) return policy;
      }
    }
    return CallMediaPolicy.relayOnly;
  }

  /// The stricter of two policies, so neither side can loosen the other's.
  static CallMediaPolicy strictest(CallMediaPolicy a, CallMediaPolicy b) =>
      a.index >= b.index ? a : b;

  /// True only for [directAndRelay]. [directIfVerified] is a rule, not a
  /// decision — the client resolves it against its own trust store before
  /// declaring a policy, so by the time it reaches the server it should
  /// already be one of the other two. If it arrives unresolved, treat it as
  /// strict.
  bool get permitsDirectCandidates => this == CallMediaPolicy.directAndRelay;
}

/// Whether a single ICE candidate line describes a relayed candidate.
///
/// The SDP candidate grammar (RFC 5245 §15.1) puts the type after a literal
/// `typ` token:
///
/// ```
/// candidate:FOUNDATION COMPONENT TRANSPORT PRIORITY IP PORT typ TYPE ...
/// ```
///
/// where TYPE is one of `host`, `srflx`, `prflx` or `relay`. Anything that
/// does not parse as an explicit `typ relay` is treated as not-relay,
/// including
/// candidates this code does not understand — an unparseable candidate is
/// exactly the case where guessing is most expensive.
bool isRelayCandidate(String candidate) {
  final tokens = candidate.trim().split(RegExp(r'\s+'));
  for (var i = 0; i + 1 < tokens.length; i++) {
    if (tokens[i] == 'typ') return tokens[i + 1] == 'relay';
  }
  return false;
}

/// Removes every non-relay `a=candidate:` line from an SDP blob.
///
/// Candidates usually arrive as separate trickle signals, but an offer or
/// answer generated after gathering completes carries them inline, and a
/// client is free to send one that way. Filtering only the trickle path
/// would leave that hole wide open.
///
/// Also drops `a=end-of-candidates` handling concerns: the attribute is left
/// alone, since removing candidates does not change that gathering finished.
String stripNonRelayCandidatesFromSdp(String sdp) {
  // SDP lines are CRLF-terminated by spec but LF appears in practice; split
  // on \n and preserve whatever line ending each line already carried.
  final lines = sdp.split('\n');
  final kept = <String>[];
  for (final line in lines) {
    final bare = line.endsWith('\r')
        ? line.substring(0, line.length - 1)
        : line;
    if (bare.startsWith('a=candidate:') &&
        !isRelayCandidate(bare.substring('a='.length))) {
      continue;
    }
    kept.add(line);
  }
  return kept.join('\n');
}

/// What enforcement decided about one signal.
class MediaPolicyDecision {
  const MediaPolicyDecision({
    required this.allowed,
    this.sdp,
    this.droppedCandidate = false,
    this.strippedSdpCandidates = 0,
  });

  /// False when the whole signal must be dropped rather than forwarded —
  /// a trickle candidate that would have leaked an address.
  final bool allowed;

  /// The SDP to forward, with offending lines removed. Null when the signal
  /// carried none.
  final String? sdp;

  /// True when a trickle ICE candidate was suppressed.
  final bool droppedCandidate;

  /// How many `a=candidate:` lines were removed from [sdp].
  final int strippedSdpCandidates;

  bool get modified => droppedCandidate || strippedSdpCandidates > 0;
}

/// Applies [policy] to one signaling frame.
///
/// Returns the frame to forward. Under [CallMediaPolicy.directAndRelay]
/// nothing is touched; otherwise non-relay candidates are removed from the
/// SDP and a non-relay trickle candidate causes the signal to be dropped
/// entirely — there is nothing left of an `ice` signal once its candidate is
/// gone, and forwarding an empty one would only confuse the far side.
MediaPolicyDecision applyMediaPolicy({
  required CallMediaPolicy policy,
  String? sdp,
  String? candidate,
}) {
  if (policy.permitsDirectCandidates) {
    return MediaPolicyDecision(allowed: true, sdp: sdp);
  }

  if (candidate != null && candidate.isNotEmpty) {
    // An empty candidate is the end-of-candidates marker, not an address, so
    // it is left alone by the isNotEmpty guard above.
    if (!isRelayCandidate(candidate)) {
      return const MediaPolicyDecision(allowed: false, droppedCandidate: true);
    }
  }

  if (sdp == null) return MediaPolicyDecision(allowed: true, sdp: sdp);

  final filtered = stripNonRelayCandidatesFromSdp(sdp);
  final removed =
      '\n'.allMatches(sdp).length - '\n'.allMatches(filtered).length;
  return MediaPolicyDecision(
    allowed: true,
    sdp: filtered,
    strippedSdpCandidates: removed,
  );
}
