import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/settings/application/sound_packs.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: Settings > Notifications > Ringtone, drawn by `orbit_ui`'s
/// [orbit.RingtoneGalleryScreen] (`orbit/PORT_PLAN.md` Part C step 5).
///
/// The top group is what this device can ring with - the phone's own sound,
/// then every sound pack that passed its checks when it was read from the pack
/// folder. The lower group is what this account's server offers. Choosing one
/// takes effect on the next incoming call rather than on this screen: the sound
/// is played by the phone, as the sound of the channel a call arrives on.
class RingtonesPage extends ConsumerWidget {
  const RingtonesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.read(ringtonePageProvider);
    return orbit.RingtoneGalleryScreen(
      model: ref.watch(ringtoneGalleryProvider),
      actions: orbit.RingtoneGalleryActions(
        onUse: page.use,
        onGet: page.get,
        onUpdate: page.update,
        onDelete: page.delete,
        onRetry: page.retry,
      ),
    );
  }
}
