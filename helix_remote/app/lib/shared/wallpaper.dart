import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/local_settings.dart';
import 'package:helix_remote/core/security/app_settings.dart';
import 'package:orbit_ui/models.dart' show HelixWallpaper;

/// The wallpaper for every chat that has not chosen its own.
final defaultWallpaperProvider = settingProvider(AppSettings.wallpaper);

/// A chat's own wallpaper, or null when it follows the default.
final chatWallpaperChoiceProvider =
    StreamProvider.family<HelixWallpaper?, String>(
      (ref, conversationId) => ref
          .watch(localSettingsProvider)
          .watch(AppSettings.chatWallpaper(conversationId))
          .map(wallpaperNamed),
    );

/// What a chat is drawn on: its own choice, else the default, else the
/// theme's own.
final chatWallpaperProvider = Provider.family<HelixWallpaper, String>(
  (ref, conversationId) =>
      ref.watch(chatWallpaperChoiceProvider(conversationId)).value ??
      ref.watch(defaultWallpaperProvider).value ??
      HelixWallpaper.theme,
);

/// Sets the wallpaper for every chat.
final setDefaultWallpaperProvider =
    Provider<Future<void> Function(HelixWallpaper wallpaper)>(
      (ref) =>
          (wallpaper) => ref
              .read(localSettingsProvider)
              .set(AppSettings.wallpaper, wallpaper),
    );

/// The wallpaper a stored name stands for; a name this version does not know,
/// or none, is null (follow the default).
HelixWallpaper? wallpaperNamed(String name) {
  for (final w in HelixWallpaper.values) {
    if (w.name == name) return w;
  }
  return null;
}
