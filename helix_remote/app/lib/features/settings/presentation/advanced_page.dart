import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/settings/application/about_providers.dart';
import 'package:helix_remote/shared/format.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: Advanced, drawn by `orbit_ui`'s [orbit.AdvancedScreen]: what
/// the server says about itself, the features its operator switched, and
/// Check for messages now.
class AdvancedPage extends ConsumerWidget {
  const AdvancedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(serverDetailsProvider);
    final server = details.value;
    final sync = ref.watch(syncNowProvider);
    ref.listen(syncNowProvider.select((s) => s.error), (_, next) {
      if (next != null) orbit.showOrbitToast(context, next, error: true);
    });

    return orbit.AdvancedScreen(
      model: orbit.AdvancedModel(
        serverName: server?.name ?? ref.watch(serverTitleProvider) ?? '',
        serverHost: server?.host ?? '',
        reachable: !details.hasError,
        serverVersion: server?.version ?? '',
        openSignUp: server?.openRegistration ?? true,
        maxAttachmentLabel: server == null
            ? ''
            : formatBytes(server.maxAttachmentBytes),
        termsVersion: server?.termsVersion ?? '',
        privacyVersion: server?.privacyVersion ?? '',
        features: [
          for (final (name, on) in ref.watch(serverFlagsProvider))
            (name: name, on: on),
        ],
        syncing: sync.busy,
        synced: sync.notice != null,
      ),
      actions: orbit.AdvancedActions(
        onSync: ref.read(syncNowProvider.notifier).run,
        onRetry: () => ref.invalidate(serverDetailsProvider),
      ),
    );
  }
}
