import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/platform/app_storage.dart';
import 'package:helix_remote/core/theme/orbit_packs.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The themes the app ships with (`orbit/contracts/you.md`, Appearance):
/// Orbit and Orbit Night. The others come as downloadable packs (Part C).
const builtInThemeIds = ['orbit', 'night'];

/// The theme a fresh install draws with.
const defaultThemeId = 'orbit';

/// Every built-in theme's tokens, by id. [main] reads them before the first
/// frame and overrides this provider, so a theme change never waits. The packs
/// this device holds are added by [downloadedThemesProvider].
final orbitThemeLibraryProvider = Provider<Map<String, OrbitTokens>>(
  (ref) => throw StateError(
    'The built-in themes are loaded in main() and passed as an override.',
  ),
);

/// The themes the packs downloaded on this device add, by id. [main] seeds it
/// from the pack folder before the first frame, so a theme someone chose from a
/// pack is on screen from the first frame rather than a frame later; the pack
/// store refreshes it after a download or a delete.
final downloadedThemesProvider =
    NotifierProvider<DownloadedThemes, Map<String, OrbitTokens>>(
      DownloadedThemes.new,
    );

/// What was in the pack folder when the app started.
final downloadedThemesAtStartupProvider = Provider<Map<String, OrbitTokens>>(
  (ref) => const {},
);

final class DownloadedThemes extends Notifier<Map<String, OrbitTokens>> {
  @override
  Map<String, OrbitTokens> build() =>
      ref.read(downloadedThemesAtStartupProvider);

  /// Re-reads every pack on this device, gate-checked. Called after one is
  /// downloaded or deleted. A pack that stops passing - or a folder that cannot
  /// be read - stops being a theme, and a screen drawing with it falls back to
  /// Orbit rather than to a half-loaded design.
  Future<void> reload() async {
    state = await ref.read(themePackStoreProvider).themeTokens();
  }
}

/// Every theme this device can draw with: the packs it holds, and the built-ins
/// over them. A pack never shadows a theme the app ships, whatever name it
/// claims - the built-ins are read last, and are the ones the app cannot lose.
final themeLibraryProvider = Provider<Map<String, OrbitTokens>>(
  (ref) => {
    ...ref.watch(downloadedThemesProvider),
    ...ref.watch(orbitThemeLibraryProvider),
  },
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

  /// Draws the app in theme [id] from now on and remembers it. An id this
  /// device cannot draw with - a pack that was never downloaded, or one that
  /// fails its checks - changes nothing.
  Future<void> choose(String id) async {
    if (id == state || !ref.read(themeLibraryProvider).containsKey(id)) return;
    state = id;
    await ref.read(deviceSettingsStoreProvider).writeTheme(id);
  }
}

/// The tokens every screen draws with: the chosen theme's, else Orbit's.
final orbitTokensProvider = Provider<OrbitTokens>((ref) {
  final themes = ref.watch(themeLibraryProvider);
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
/// outlive a sign-out (which wipes the account's database): the theme and the
/// ringtone. Nothing secret is kept here.
abstract interface class DeviceSettingsStore {
  Future<String?> readTheme();
  Future<void> writeTheme(String id);

  /// The sound an incoming call rings with: a sound pack's id, or null for the
  /// phone's own ringtone. Null is a choice, not a missing value - which is why
  /// it is not stored as a slug nobody could invent for the phone.
  Future<String?> readRingtone();
  Future<void> writeRingtone(String? id);
}

final deviceSettingsStoreProvider = Provider<DeviceSettingsStore>(
  (ref) => const FileDeviceSettingsStore(),
);

/// `device_settings.json` in the app's folder ([AppPaths.deviceSettingsFile]).
final class FileDeviceSettingsStore implements DeviceSettingsStore {
  const FileDeviceSettingsStore();

  static const _theme = 'theme';
  static const _ringtone = 'ringtone';

  @override
  Future<String?> readTheme() async {
    final theme = (await _read())[_theme];
    // Any pack id, built in or a pack's. What this device can actually draw
    // with is [themeLibraryProvider]'s question, and a name it has stops
    // having falls back to Orbit.
    return theme is String && isPackId(theme) ? theme : null;
  }

  @override
  Future<void> writeTheme(String id) => _write({_theme: id});

  @override
  Future<String?> readRingtone() async {
    final id = (await _read())[_ringtone];
    // The shape is a pack id's; whether this device still holds that pack is
    // [SoundPackStore]'s question, and one it has stopped holding rings with
    // the phone's own sound.
    return id is String && isPackId(id) ? id : null;
  }

  @override
  Future<void> writeRingtone(String? id) => _write({_ringtone: id});

  /// One key at a time, keeping the file's others: these are the device's
  /// choices, so choosing a theme must not forget the ringtone. A null value
  /// removes its key, which is how "the phone's own ringtone" is stored - as
  /// nothing, rather than as a word a pack could also be named by.
  Future<void> _write(Map<String, Object?> change) async {
    try {
      final data = await _read();
      change.forEach((key, value) {
        if (value == null) {
          data.remove(key);
        } else {
          data[key] = value;
        }
      });
      final file = await AppPaths.deviceSettingsFile();
      await file.writeAsString(jsonEncode(data), flush: true);
    } on FileSystemException {
      // The choice still holds until the app closes.
    }
  }

  /// The file, or nothing at all when it is missing, unreadable, or the app
  /// folder cannot be found. A device setting that cannot be read is the
  /// default, never a start-up failure.
  Future<Map<String, Object?>> _read() async {
    try {
      final file = await AppPaths.deviceSettingsFile();
      if (!await file.exists()) return {};
      final data = jsonDecode(await file.readAsString());
      return data is Map<String, Object?>
          ? Map<String, Object?>.from(data)
          : {};
    } on Object {
      return {};
    }
  }
}
