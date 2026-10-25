import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/theme/orbit_app_theme.dart';
import 'package:orbit_ui/orbit_ui.dart' show OrbitTokens;

/// What Appearance draws: the theme in use and every theme on this device,
/// each with the tokens its own card is drawn in.
///
/// That is the two themes the app ships *and* every pack this person has
/// downloaded: a theme you got is chosen where you choose themes, not only on
/// the page that got it. The built-ins keep their order, and the packs follow
/// in the order their cards read.
final appearanceProvider =
    Provider<({OrbitTokens current, List<OrbitTokens> themes})>((ref) {
      final library = ref.watch(themeLibraryProvider);
      final packs = [
        for (final id in library.keys)
          if (!builtInThemeIds.contains(id)) id,
      ]..sort((a, b) => library[a]!.meta.name.compareTo(library[b]!.meta.name));
      return (
        current: ref.watch(orbitTokensProvider),
        themes: [
          for (final id in [...builtInThemeIds, ...packs]) ?library[id],
        ],
      );
    });

/// Draws the app in another theme from now on; this device remembers it.
final chooseThemeProvider = Provider<Future<void> Function(String id)>(
  (ref) => ref.read(themeChoiceProvider.notifier).choose,
);
