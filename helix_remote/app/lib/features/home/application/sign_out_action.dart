import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/security/app_settings.dart';

/// Signs this device out.
///
/// The action lives in the application's layer so the Settings screen, which
/// has no engine import, can still perform it. What it actually does is the
/// engine's own `signOut` - which revokes this device on the server and
/// **always wipes the local database** - followed by forgetting the server and
/// the database key, because a sign-out that kept them would let the next
/// account on this device read the old one.
final signOutActionProvider = Provider<SignOutAction>(SignOutAction.new);

final class SignOutAction {
  SignOutAction(this._ref);

  final Ref _ref;

  Future<void> call() async {
    await _ref.read(signOutProvider)();
    // The engine wiped the rows; the keystore entries and the typed app
    // settings that live in them go with them.
    await _ref.read(secureKeyStoreProvider).forget();
  }
}

/// Clears the app's own settings, which is only ever needed after a reset.
final clearAppSettingsProvider = Provider<ClearAppSettings>(
  ClearAppSettings.new,
);

final class ClearAppSettings {
  ClearAppSettings(this._ref);

  final Ref _ref;

  Future<void> call() async {
    final runtime = await _ref.read(runtimeProvider.future);
    final settings = runtime.engine.settings;
    await settings.reset(AppSettings.appLockEnabled);
    await settings.reset(AppSettings.appLockRelockAfterSeconds);
    await settings.reset(AppSettings.notificationsPreview);
  }
}
