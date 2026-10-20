import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The themes the app ships with (`orbit/contracts/you.md`, Appearance):
/// Orbit and Orbit Night. The others come as downloadable packs (Part C).
const builtInThemeIds = ['orbit', 'night'];

/// The theme a fresh install draws with.
const defaultThemeId = 'orbit';

/// Every built-in theme's tokens, by id. [main] reads them before the first
/// frame and overrides this provider, so a theme change never waits.
final orbitThemeLibraryProvider = Provider<Map<String, OrbitTokens>>(
  (ref) => throw StateError(
    'The built-in themes are loaded in main() and passed as an override.',
  ),
);

/// The theme chosen when the app started; [main] reads it from
/// [DeviceSettingsStore] before the first frame.
final initialThemeIdProvider = Provider<String>((ref) => defaultThemeId);

/// The chosen theme's id, a device setting: it is kept beside the database
/// rather than in it, so it survives signing out (Review 1).
final themeChoiceProvider = NotifierProvider<ThemeChoice, String>(
  ThemeChoice.new,
);

final class ThemeChoice extends Notifier<String> {
  @override
  String build() => ref.watch(initialThemeIdProvider);

  /// Draws the app in theme [id] from now on and remembers it. An id that is
  /// not built in (a pack not downloaded) changes nothing.
  Future<void> choose(String id) async {
    if (!builtInThemeIds.contains(id) || id == state) return;
    state = id;
    await ref.read(deviceSettingsStoreProvider).writeTheme(id);
  }
}

/// The tokens every screen draws with: the chosen theme's, else Orbit's.
final orbitTokensProvider = Provider<OrbitTokens>((ref) {
  final themes = ref.watch(orbitThemeLibraryProvider);
  return themes[ref.watch(themeChoiceProvider)] ?? themes[defaultThemeId]!;
});

/// Reads a built-in theme from `orbit_ui`'s assets.
Future<OrbitTokens> loadOrbitTokens({
  AssetBundle? bundle,
  String id = defaultThemeId,
}) async {
  final raw = await (bundle ?? rootBundle).loadString(
    'packages/orbit_ui/assets/themes/$id.json',
  );
  return OrbitTokens.fromThemeJson(jsonDecode(raw) as Map<String, Object?>);
}

/// Every built-in theme, by id.
Future<Map<String, OrbitTokens>> loadBuiltInThemes({
  AssetBundle? bundle,
}) async => {
  for (final id in builtInThemeIds)
    id: await loadOrbitTokens(bundle: bundle, id: id),
};

// --------------------------------------------------------- device settings

/// Settings that belong to this device rather than to the account, so they
/// outlive a sign-out (which wipes the account's database): today only the
/// theme. Nothing secret is kept here.
abstract interface class DeviceSettingsStore {
  Future<String?> readTheme();
  Future<void> writeTheme(String id);
}

final deviceSettingsStoreProvider = Provider<DeviceSettingsStore>(
  (ref) => const FileDeviceSettingsStore(),
);

/// `device_settings.json` in the app's folder ([AppPaths.deviceSettingsFile]).
final class FileDeviceSettingsStore implements DeviceSettingsStore {
  const FileDeviceSettingsStore();

  @override
  Future<String?> readTheme() async {
    try {
      final file = await AppPaths.deviceSettingsFile();
      if (!await file.exists()) return null;
      final data = jsonDecode(await file.readAsString());
      final theme = data is Map ? data['theme'] : null;
      return theme is String && builtInThemeIds.contains(theme) ? theme : null;
    } on Object {
      // Unreadable or no app folder: the default theme.
      return null;
    }
  }

  @override
  Future<void> writeTheme(String id) async {
    try {
      final file = await AppPaths.deviceSettingsFile();
      await file.writeAsString(jsonEncode({'theme': id}), flush: true);
    } on FileSystemException {
      // The choice still holds until the app closes.
    }
  }
}
