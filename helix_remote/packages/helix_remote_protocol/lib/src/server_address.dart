/// Why a server address is refused.
enum ServerUrlProblem {
  /// Not an absolute URL, or no host in it.
  notAUrl,

  /// `http://` to anything but the development hosts, where those are
  /// allowed.
  notHttps,

  /// A user name or password in the address (`https://a.example@b.example`
  /// reads as the first host and goes to the second), a query or a fragment.
  unusual,

  /// A host that is not plain ASCII, which could pass for another one.
  lookalikeHost,
}

/// Which servers a Helix client will talk to at all: the one rule every
/// client applies (the app, the CLI), so a password-derived key and the
/// tokens never cross the network in cleartext (AUD-13-1).
abstract final class ServerAddressRule {
  /// Hosts that may be reached over plain `http` where
  /// [allowDevelopmentHttp] is set: the emulator's loopback and a server on
  /// the developer's own machine. A release build of the app has no
  /// exception.
  static const developmentHosts = {'localhost', '127.0.0.1', '10.0.2.2'};

  /// Null when [url] is acceptable, else the reason it is not.
  static ServerUrlProblem? check(
    Uri url, {
    required bool allowDevelopmentHttp,
  }) {
    if (!url.hasScheme || url.host.isEmpty) return ServerUrlProblem.notAUrl;
    if (url.userInfo.isNotEmpty || url.hasQuery || url.hasFragment) {
      return ServerUrlProblem.unusual;
    }
    if (!RegExp(r'^[A-Za-z0-9.\-]+$|^\[[0-9A-Fa-f:.]+\]$').hasMatch(url.host)) {
      return ServerUrlProblem.lookalikeHost;
    }
    final scheme = url.scheme.toLowerCase();
    if (scheme == 'https') return null;
    if (scheme == 'http' &&
        allowDevelopmentHttp &&
        developmentHosts.contains(url.host.toLowerCase())) {
      return null;
    }
    return ServerUrlProblem.notHttps;
  }
}
