import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/settings/application/about_providers.dart';
import 'package:helix_remote/shared/widgets/inline_notice.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Settings > Advanced: facts about the server this phone is on, and a manual
/// sync.
///
/// It is a read-out, not a control panel. Which server a phone is on is chosen
/// when signing in (Helix Global unless a code or link says otherwise), so
/// there is nothing here to change it.
class AdvancedPage extends ConsumerWidget {
  const AdvancedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final facts = ref.watch(serverFactsProvider);
    final flags = ref.watch(serverFlagsProvider);
    final sync = ref.watch(syncNowProvider);
    final server = ref.watch(serverDetailsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Advanced')),
      body: ListView(
        children: [
          if (server.hasError)
            InlineNotice(
              kind: InlineNoticeKind.error,
              message:
                  'The server could not be reached, so its details are not '
                  'available.',
              action: TextButton(
                onPressed: () => ref.invalidate(serverDetailsProvider),
                child: const Text('Try again'),
              ),
            ),
          if (facts != null)
            HelixSettingsSection(
              title: 'Server',
              children: [
                for (final (label, value) in facts)
                  HelixSettingsTile(title: label, subtitle: value),
              ],
            ),
          if (flags.isNotEmpty)
            HelixSettingsSection(
              title: 'Server features',
              footer: 'Switched by the server\'s operator.',
              children: [
                for (final (label, on) in flags)
                  HelixSettingsTile(
                    icon: on
                        ? Icons.check_circle_outline
                        : Icons.circle_outlined,
                    title: label,
                    subtitle: on ? 'On' : 'Off',
                  ),
              ],
            ),
          if (sync.error != null)
            InlineNotice(kind: InlineNoticeKind.error, message: sync.error!),
          if (sync.notice != null)
            InlineNotice(kind: InlineNoticeKind.success, message: sync.notice!),
          HelixSettingsSection(
            title: 'Connection',
            footer:
                'Helix keeps a live connection and also checks for messages '
                'when it wakes. Use this if something seems stuck.',
            children: [
              HelixSettingsTile(
                icon: Icons.sync,
                title: 'Check for messages now',
                trailing: sync.busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: sync.busy
                    ? null
                    : ref.read(syncNowProvider.notifier).run,
              ),
            ],
          ),
          const SizedBox(height: HelixSpace.lg),
        ],
      ),
    );
  }
}
