import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/theme/orbit_app_theme.dart';
import 'package:orbit_ui/orbit_ui.dart' show OrbitTokens;

/// What Appearance draws: the theme in use and every theme on this device,
/// each with the tokens its own card is drawn in.
final appearanceProvider =
    Provider<({OrbitTokens current, List<OrbitTokens> themes})>((ref) {
      final library = ref.watch(orbitThemeLibraryProvider);
      return (
        current: ref.watch(orbitTokensProvider),
        themes: [for (final id in builtInThemeIds) ?library[id]],
      );
    });

/// Draws the app in another theme from now on; this device remembers it.
final chooseThemeProvider = Provider<Future<void> Function(String id)>(
  (ref) => ref.read(themeChoiceProvider.notifier).choose,
);
