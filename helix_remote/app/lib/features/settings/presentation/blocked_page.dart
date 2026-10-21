import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/settings/application/privacy_providers.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: Settings > Privacy > Blocked, drawn by `orbit_ui`'s
/// [orbit.BlockedScreen]. The screen asks before it unblocks.
class BlockedPage extends ConsumerWidget {
  const BlockedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedProvider);
    ref.listen(blockedActionsProvider.select((s) => s.error), (_, next) {
      if (next != null) orbit.showOrbitToast(context, next, error: true);
    });
    final people = blocked.value;
    if (people == null) {
      return orbit.OrbitYouPage(
        title: 'Blocked',
        children: [
          if (blocked.hasError)
            orbit.OrbitLoadFailed(
              title: 'The blocked list could not be loaded.',
              onRetry: () => ref.invalidate(blockedProvider),
            )
          else
            const orbit.OrbitPageLoading(),
        ],
      );
    }
    return orbit.BlockedScreen(
      model: orbit.BlockedModel(
        people: [
          for (final p in people)
            orbit.BlockedPersonItem(
              account: p.id,
              name: p.name,
              avatar: orbit.HelixAvatarModel(
                name: p.name,
                colorIndex: orbit.HelixAvatarModel.colorIndexFor(p.id),
              ),
            ),
        ],
      ),
      actions: orbit.BlockedActions(
        onUnblock: ref.read(blockedActionsProvider.notifier).unblock,
      ),
    );
  }
}
