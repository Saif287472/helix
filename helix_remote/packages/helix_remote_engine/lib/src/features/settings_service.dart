import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/settings_keys.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Settings in two places:
///
/// - **Local, typed** ([get], [watch], [set], [reset]): preferences that
///   never leave the device, such as read receipts, typing indicators and
///   the default disappearing timer ([EngineSettings]); the app adds its
///   own `Setting` constants for UI preferences.
/// - **Server-side privacy** ([privacy], [setPrivacy]): who may see last
///   seen and online status, who may add this account to groups, discovery
///   by phone and by `~name`; and the `~Helix name` itself.
final class SettingsService {
  SettingsService(this._ctx);

  final EngineContext _ctx;

  Future<T> get<T>(Setting<T> setting) => _ctx.db.settingsDao.get(setting);

  Stream<T> watch<T>(Setting<T> setting) => _ctx.db.settingsDao.watch(setting);

  Future<void> set<T>(Setting<T> setting, T value) =>
      _ctx.db.settingsDao.set(setting, value, now: _ctx.now());

  Future<void> reset(Setting<Object?> setting) =>
      _ctx.db.settingsDao.reset(setting);

  Future<PrivacySettings> privacy() => _ctx.api.people.privacy();

  Future<void> setPrivacy(PrivacySettings settings) =>
      _ctx.api.people.setPrivacy(settings);

  /// Claims `~name` (3-32 characters, lower case, digits, `_` and `.`,
  /// starting with a letter). Throws `ApiException(name_taken)` when it is
  /// taken.
  Future<void> setHelixName(String name) async {
    final normalised = name.trim().toLowerCase().replaceFirst('~', '');
    if (!SetHelixNameRequest.pattern.hasMatch(normalised)) {
      throw ArgumentError.value(name, 'name', 'is not a valid Helix name');
    }
    await _ctx.api.identity.setHelixName(normalised);
    await _saveHelixName(normalised);
  }

  Future<void> clearHelixName() async {
    await _ctx.api.identity.clearHelixName();
    await _saveHelixName(null);
  }

  Future<void> _saveHelixName(String? name) async {
    final row = await _ctx.db.accountDao.current();
    if (row == null) return;
    await _ctx.db.accountDao.save(
      SelfAccountCompanion.insert(
        accountId: row.accountId,
        deviceId: row.deviceId,
        serverDomain: row.serverDomain,
        registeredAt: row.registeredAt,
        helixName: Value(name),
      ),
    );
  }

  /// Reads the account from the server (name, phone's last 4 digits) and
  /// stores the Helix name locally.
  Future<AccountInfo> refreshAccount() async {
    final info = await _ctx.api.identity.account();
    await _saveHelixName(info.helixName);
    return info;
  }
}
