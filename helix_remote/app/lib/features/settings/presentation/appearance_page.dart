import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/settings/application/appearance.dart';
import 'package:helix_remote/shared/route_paths.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: Appearance, the themes on this device each drawn in itself,
/// by `orbit_ui`'s [orbit.AppearanceScreen]. The choice is this device's
/// and stays when the account signs out. The one row under the cards opens
/// [ThemePacksPage], where the packs are got, updated and deleted.
class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(appearanceProvider);
    return orbit.AppearanceScreen(
      model: orbit.AppearanceModel(
        current: view.current,
        themes: [for (final t in view.themes) orbit.ThemeChoice(tokens: t)],
      ),
      actions: orbit.AppearanceActions(
        onPick: ref.read(chooseThemeProvider),
        onGetMore: () => context.push(RoutePaths.themePacks),
      ),
    );
  }
}
