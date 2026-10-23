import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/settings/application/theme_packs.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: You > Appearance > More themes, drawn by `orbit_ui`'s
/// [orbit.ThemeGalleryScreen] (`orbit/PORT_PLAN.md` Part C step 4).
///
/// The top group is what this device can draw with - the two themes built into
/// the app, then every pack that passed its checks when it was read from the
/// pack folder. The lower group is what this account's server offers; getting
/// one is a download, and a pack that fails a check is refused and never drawn
/// with. Nothing here is a server decision: the app only asks its own host for
/// the bytes the host already publishes.
class ThemePacksPage extends ConsumerWidget {
  const ThemePacksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.read(themePackPageProvider);
    return orbit.ThemeGalleryScreen(
      model: ref.watch(themeGalleryProvider),
      actions: orbit.ThemeGalleryActions(
        onUse: page.use,
        onGet: page.get,
        onUpdate: page.update,
        onDelete: page.delete,
        onRetry: page.retry,
      ),
    );
  }
}
