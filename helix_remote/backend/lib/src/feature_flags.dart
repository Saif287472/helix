import 'package:helix_remote_backend/src/database.dart';

/// Small, server-owned feature flags. Values are deliberately allow-listed:
/// an arbitrary configuration key must never become a remotely switchable
/// product capability by typo or by an admin UI bug.
class FeatureFlagService {
  FeatureFlagService(this._db);

  static const _prefix = 'feature_flag.';
  static const defaults = <String, bool>{
    'crash_reporting_upload': false,
    'minimal_analytics': false,
    'federation_directory_v2': false,
  };

  final BackendDatabase _db;

  bool isEnabled(String name) {
    final fallback = defaults[name];
    if (fallback == null) {
      throw ArgumentError.value(name, 'name', 'Unknown flag');
    }
    final stored = _db.getServerConfig('$_prefix$name');
    return stored == null ? fallback : stored == 'true';
  }

  Map<String, bool> snapshot() => {
    for (final name in defaults.keys) name: isEnabled(name),
  };

  void set(String name, bool enabled) {
    if (!defaults.containsKey(name)) {
      throw ArgumentError.value(name, 'name', 'Unknown flag');
    }
    _db.setServerConfig('$_prefix$name', enabled.toString());
  }
}
