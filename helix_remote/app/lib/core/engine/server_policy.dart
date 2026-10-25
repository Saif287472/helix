import 'package:flutter/foundation.dart';
import 'package:helix_remote/core/engine/global_server.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ServerAddressRule, ServerUrlProblem;

export 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ServerUrlProblem;

/// Which servers the app will talk to at all.
///
/// The one place the rule lives: sign-in checks a code's server before any
/// request is made, the remembered server is checked on start, and
/// `ServerUrlNotifier.use` refuses anything that gets past both. Android's
/// network security config does not cover Dart's own sockets, so this is what
/// stands between the app and a cleartext connection.
abstract final class ServerPolicy {
  /// Hosts a **debug** build may reach over plain `http` (the emulator's
  /// loopback, a server on the developer's machine). A release build has no
  /// exception.
  static const developmentHosts = ServerAddressRule.developmentHosts;

  /// Null when [url] is acceptable, else the reason it is not. The rule
  /// itself is shared with the CLI (`ServerAddressRule`).
  ///
  /// [debug] defaults to this build's mode; tests pass it explicitly.
  static ServerUrlProblem? check(Uri url, {bool? debug}) =>
      ServerAddressRule.check(url, allowDevelopmentHttp: debug ?? kDebugMode);

  /// Whether [url] is Helix Global's own address.
  static bool isGlobal(Uri url) => sameServer(url, kGlobalServerUrl);

  /// Whether two addresses name the same server (scheme, host and port).
  static bool sameServer(Uri a, Uri b) =>
      a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
      a.host.toLowerCase() == b.host.toLowerCase() &&
      _portOf(a) == _portOf(b);

  /// The name a person is asked to recognise: the host, and the port when it
  /// is not the scheme's own. Never the server's self-chosen name, which the
  /// server controls.
  static String displayHost(Uri url) {
    final host = url.host.toLowerCase();
    final port = _portOf(url);
    final standard = url.scheme.toLowerCase() == 'http' ? 80 : 443;
    return port == standard ? host : '$host:$port';
  }

  static int _portOf(Uri url) {
    if (url.hasPort && url.port != 0) return url.port;
    return url.scheme.toLowerCase() == 'http' ? 80 : 443;
  }
}

/// Thrown when something tries to point the app at an address
/// [ServerPolicy] refuses.
final class InsecureServerUrl implements Exception {
  const InsecureServerUrl(this.problem);

  final ServerUrlProblem problem;

  @override
  String toString() => 'the server address was refused: ${problem.name}';
}
