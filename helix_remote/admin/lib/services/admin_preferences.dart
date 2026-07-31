import 'package:shared_preferences/shared_preferences.dart';

/// Local-only persistence for Helix Admin. Deliberately narrow: only the
/// server URL and whether the first-launch intro has been shown survive a
/// restart. The admin bearer token is never written here - re-entering it
/// each session is the intentional default (see AI_GUARDRAILS' credential-
/// handling caution), so callers must not add a token key to this store.
class AdminPreferences {
  AdminPreferences(this._prefs);

  static const _introShownKey = 'intro_shown';
  static const _serverUrlKey = 'server_url';

  final SharedPreferences _prefs;

  static Future<AdminPreferences> load() async {
    return AdminPreferences(await SharedPreferences.getInstance());
  }

  bool get introShown => _prefs.getBool(_introShownKey) ?? false;

  Future<void> setIntroShown(bool value) =>
      _prefs.setBool(_introShownKey, value);

  String? get serverUrl => _prefs.getString(_serverUrlKey);

  Future<void> setServerUrl(String value) =>
      _prefs.setString(_serverUrlKey, value);
}
