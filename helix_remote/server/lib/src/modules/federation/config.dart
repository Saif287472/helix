import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/config/server_config.dart';

/// Federation settings. Whether federation is on at all is the operator's
/// `federation_enabled` setting (ops; default `HELIX_FEDERATION_ENABLED`).
final class FederationConfig {
  const FederationConfig({
    required this.localDomain,
    required this.apiBase,
    required this.allow,
    required this.allowPrivate,
    required this.scheme,
    this.timeout = const Duration(seconds: 5),
  });

  /// This server's domain: the authority of `HELIX_PUBLIC_BASE_URL`
  /// (`host` or `host:port`), lowercase. Local accounts are `uuid@<this>`
  /// to other servers.
  final String localDomain;

  /// Where peers reach this server's API (the public base URL, no trailing
  /// slash).
  final String apiBase;

  /// `HELIX_FEDERATION_ALLOW`: if non-empty, the only peer domains this
  /// server talks to.
  final Set<String> allow;

  /// `HELIX_FEDERATION_ALLOW_PRIVATE`: also talk to peers on loopback and
  /// private addresses (self-hosted LANs, tests). Link-local addresses (cloud
  /// metadata services) are always refused.
  final bool allowPrivate;

  /// `https`, or `http` with `HELIX_FEDERATION_HTTP=true` in dev mode only.
  final String scheme;

  final Duration timeout;

  factory FederationConfig.from(ServerConfig config) {
    final env = config.env;
    bool flag(String name) => envFlag(env, name);
    final base = config.publicBaseUrl;
    final host = base.host.toLowerCase();
    final domain = base.hasPort ? '$host:${base.port}' : host;
    final allow = (env['HELIX_FEDERATION_ALLOW'] ?? '')
        .split(',')
        .map((d) => d.trim().toLowerCase())
        .where((d) => d.isNotEmpty)
        .toSet();
    final problems = [
      if (!AccountAddress.isValidDomain(domain))
        'HELIX_PUBLIC_BASE_URL must have a DNS name or IPv4 host for federation',
      for (final d in allow)
        if (!AccountAddress.isValidDomain(d))
          'HELIX_FEDERATION_ALLOW has an invalid domain "$d"',
    ];
    if (problems.isNotEmpty) throw ConfigError(problems);
    var apiBase = base.toString();
    while (apiBase.endsWith('/')) {
      apiBase = apiBase.substring(0, apiBase.length - 1);
    }
    return FederationConfig(
      localDomain: domain,
      apiBase: apiBase,
      allow: allow,
      allowPrivate: flag('HELIX_FEDERATION_ALLOW_PRIVATE'),
      scheme: config.devMode && flag('HELIX_FEDERATION_HTTP')
          ? 'http'
          : 'https',
    );
  }
}
