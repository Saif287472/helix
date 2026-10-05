import 'package:flutter/foundation.dart';
import 'package:helix_remote/core/engine/global_server.dart';

/// Why a server address is refused.
enum ServerUrlProblem {
  /// Not an absolute URL, or no host in it.
  notAUrl,

  /// `http://` to anything but the development hosts of a debug build.
  notHttps,

  /// A user name or password in the address (`https://a.example@b.example`
  /// reads as the first host and goes to the second), a query or a fragment.
  unusual,

  /// A host that is not plain ASCII, which could pass for another one.
  lookalikeHost,
}

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
  static const developmentHosts = {'localhost', '127.0.0.1', '10.0.2.2'};

  /// Null when [url] is acceptable, else the reason it is not.
  ///
  /// [debug] defaults to this build's mode; tests pass it explicitly.
  static ServerUrlProblem? check(Uri url, {bool? debug}) {
    final inDebug = debug ?? kDebugMode;
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
        inDebug &&
        developmentHosts.contains(url.host.toLowerCase())) {
      return null;
    }
    return ServerUrlProblem.notHttps;
  }

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
