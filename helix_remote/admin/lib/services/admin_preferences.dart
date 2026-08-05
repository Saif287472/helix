import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only persistence for Helix Admin.
///
/// The server URL, first-launch flag, and app-lock preference are
/// non-sensitive and live in SharedPreferences. The admin bearer token is
/// sensitive, so it lives in platform secure storage instead (Android
/// Keystore-backed / iOS Keychain, via flutter_secure_storage) rather than
/// SharedPreferences' plaintext file - the same approach already used for
/// secrets in app/ and packages/helix_remote_crypto.
class AdminPreferences {
  AdminPreferences(this._prefs, this._secureStorage);

  static const _introShownKey = 'intro_shown';
  static const _serverUrlKey = 'server_url';
  static const _appLockEnabledKey = 'app_lock_enabled';
  static const _adminTokenKey = 'admin_token';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage;

  static Future<AdminPreferences> load() async {
    return AdminPreferences(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
  }

  bool get introShown => _prefs.getBool(_introShownKey) ?? false;

  Future<void> setIntroShown(bool value) =>
      _prefs.setBool(_introShownKey, value);

  String? get serverUrl => _prefs.getString(_serverUrlKey);

  Future<void> setServerUrl(String value) =>
      _prefs.setString(_serverUrlKey, value);

  /// Whether opening the app requires a device unlock (biometrics or
  /// PIN/pattern/password) before the saved token can be used. Optional -
  /// defaults to off, since the token is already scoped to this device.
  bool get appLockEnabled => _prefs.getBool(_appLockEnabledKey) ?? false;

  Future<void> setAppLockEnabled(bool value) =>
      _prefs.setBool(_appLockEnabledKey, value);

  Future<String?> loadAdminToken() => _secureStorage.read(key: _adminTokenKey);

  Future<void> saveAdminToken(String value) =>
      _secureStorage.write(key: _adminTokenKey, value: value);

  Future<void> clearAdminToken() => _secureStorage.delete(key: _adminTokenKey);
}
