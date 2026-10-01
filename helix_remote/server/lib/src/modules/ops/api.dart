import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';

/// Operator-set server settings (`PATCH /v1/admin/config`).
final class OpsSettings {
  const OpsSettings({
    required this.serverName,
    required this.maintenance,
    required this.federationEnabled,
    required this.flags,
  });

  final String serverName;
  final bool maintenance;
  final bool federationEnabled;

  /// Every known flag with its current value.
  final Map<String, bool> flags;
}

/// The ops module's facade: settings, feature flags, maintenance mode.
abstract interface class OpsApi {
  /// Allow-listed flags and their defaults. A flag that is not here cannot
  /// be switched remotely (a typo must never become a product capability).
  static const knownFlags = <String, bool>{
    'crash_reporting_upload': false,
    'minimal_analytics': false,
    'group_calls': false,
  };

  /// The current settings (cached; every node refreshes on change).
  Future<OpsSettings> settings();

  Future<bool> flag(String name);

  /// Applies [patch] and returns the new settings.
  Future<OpsSettings> update(Tx tx, AdminConfigPatch patch);

  /// Sets a known flag ([ArgumentError] for an unknown one).
  Future<void> setFlag(Tx tx, String name, bool enabled);

  /// Prometheus text of this node.
  String renderMetrics();
}
