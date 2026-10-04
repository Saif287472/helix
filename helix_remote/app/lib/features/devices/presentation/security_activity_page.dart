import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/devices/application/devices_providers.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Settings > Devices > Security activity: the account's own log of sign-ins,
/// new and removed devices, password changes and key resets, newest first.
///
/// It is the server's record, so it shows what happened on other devices too.
/// A key reset or a recovery is marked, because those are the entries that
/// mean somebody (maybe not you) moved the account.
class SecurityActivityPage extends ConsumerWidget {
  const SecurityActivityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(securityEventsProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Security activity')),
      body: switch (events) {
        AsyncData(:final value) when value.isEmpty => const HelixEmptyState(
          icon: Icons.shield_outlined,
          title: 'Nothing to show',
          message: 'Sign-ins, new devices and key changes appear here.',
        ),
        AsyncData(:final value) => ListView.builder(
          itemCount: value.length,
          itemBuilder: (context, index) {
            final event = value[index];
            return HelixSettingsTile(
              icon: event.needsAttention
                  ? Icons.warning_amber_rounded
                  : Icons.history,
              title: event.title,
              subtitle: [?event.detail, event.when].join(' - '),
              trailing: event.needsAttention
                  ? Icon(Icons.priority_high, color: scheme.error)
                  : null,
            );
          },
        ),
        AsyncError() => HelixErrorState(
          message: 'The activity could not be loaded.',
          onRetry: () => ref.invalidate(securityEventsProvider),
        ),
        _ => const Padding(
          padding: EdgeInsets.all(HelixSpace.lg),
          child: LinearProgressIndicator(),
        ),
      },
    );
  }
}
