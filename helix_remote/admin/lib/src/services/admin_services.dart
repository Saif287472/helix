import 'package:helix_admin/src/api/admin_api_factory.dart';
import 'package:helix_admin/src/services/admin_settings.dart';
import 'package:helix_admin/src/services/device_lock.dart';
import 'package:helix_admin/src/services/token_vault.dart';

/// Everything the console needs from outside itself, in one place so tests
/// can replace each part.
final class AdminServices {
  const AdminServices({
    required this.loadSettings,
    required this.vault,
    required this.deviceLock,
    this.apiFactory = createAdminApi,
    this.now = DateTime.now,
  });

  /// The real services.
  factory AdminServices.production() => AdminServices(
    loadSettings: PrefsAdminSettings.load,
    vault: SecureTokenVault(),
    deviceLock: LocalAuthDeviceLock(),
  );

  /// `SharedPreferences` loads asynchronously; the session awaits this once
  /// at start.
  final Future<AdminSettings> Function() loadSettings;
  final TokenVault vault;
  final DeviceLock deviceLock;
  final AdminApiFactory apiFactory;
  final DateTime Function() now;
}
