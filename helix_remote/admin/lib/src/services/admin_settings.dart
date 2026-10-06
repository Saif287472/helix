import 'package:shared_preferences/shared_preferences.dart';

/// Local, non-secret settings: the last server address (so the sign-in form
/// is pre-filled) and whether opening the console needs a device unlock.
/// The admin token is not here; see `TokenVault`.
abstract interface class AdminSettings {
  String? get serverUrl;

  Future<void> setServerUrl(String value);

  bool get appLockEnabled;

  Future<void> setAppLockEnabled(bool value);
}

final class PrefsAdminSettings implements AdminSettings {
  PrefsAdminSettings(this._prefs);

  static const _serverUrlKey = 'server_url';
  static const _appLockKey = 'app_lock_enabled';

  final SharedPreferences _prefs;

  static Future<PrefsAdminSettings> load() async =>
      PrefsAdminSettings(await SharedPreferences.getInstance());

  @override
  String? get serverUrl => _prefs.getString(_serverUrlKey);

  @override
  Future<void> setServerUrl(String value) =>
      _prefs.setString(_serverUrlKey, value);

  @override
  bool get appLockEnabled => _prefs.getBool(_appLockKey) ?? false;

  @override
  Future<void> setAppLockEnabled(bool value) =>
      _prefs.setBool(_appLockKey, value);
}

/// For tests.
final class MemoryAdminSettings implements AdminSettings {
  MemoryAdminSettings({this.serverUrl, this.appLockEnabled = false});

  @override
  String? serverUrl;

  @override
  bool appLockEnabled;

  @override
  Future<void> setServerUrl(String value) async => serverUrl = value;

  @override
  Future<void> setAppLockEnabled(bool value) async => appLockEnabled = value;
}
