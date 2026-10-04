/// The paths of the settings-side pages (Phase A3b), as strings.
///
/// A feature may not import another feature, and presentation may not import
/// `core/`, so the pages that link to each other (Settings opens Backup,
/// Devices and Profile; sign-in opens the restore step) share their paths from
/// here. Each feature registers its own routes against these in its
/// `<feature>_routes.dart`.
abstract final class RoutePaths {
  /// The home tabs.
  static const home = '/home';

  // Profile
  static const profile = '/profile';

  // Devices
  static const devices = '/devices';
  static const devicesLink = '/devices/link';
  static const devicesActivity = '/devices/activity';

  /// The new device's side of linking: shows the QR code. Reachable while
  /// signed out, because that is when it is used.
  static const linkThisDevice = '/link-device';

  // Backup
  static const backup = '/backup';
  static const backupRestore = '/backup/restore';
  static const backupTransfer = '/backup/transfer';
  static const backupRecovery = '/backup/recovery';

  /// The step after a sign-in on a new device: restore or skip.
  static const restoreAfterSignIn = '/restore';

  // Settings pages
  static const account = '/settings/account';
  static const changePassword = '/settings/account/password';
  static const privacy = '/settings/privacy';
  static const blocked = '/settings/privacy/blocked';
  static const notifications = '/settings/notifications';
  static const chats = '/settings/chats';
  static const storage = '/settings/storage';
  static const about = '/settings/about';
  static const legal = '/settings/about/legal';
  static const advanced = '/settings/advanced';
}
