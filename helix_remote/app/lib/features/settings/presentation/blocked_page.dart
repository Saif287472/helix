import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/settings/application/privacy_providers.dart';
import 'package:helix_remote/shared/widgets/inline_notice.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Settings > Privacy > Blocked: the people who cannot message or call you.
///
/// Blocking is applied by the server (it drops their messages and calls) and
/// by this phone. Unblocking asks for confirmation, because the person can
/// reach you again at once.
class BlockedPage extends ConsumerWidget {
  const BlockedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blocked = ref.watch(blockedProvider);
    final action = ref.watch(blockedActionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Blocked')),
      body: switch (blocked) {
        AsyncData(:final value) when value.isEmpty => const HelixEmptyState(
          icon: Icons.block,
          title: 'Nobody is blocked',
          message:
              'People you block cannot message or call you. Block someone '
              'from their chat.',
        ),
        AsyncData(:final value) => ListView(
          children: [
            if (action.error != null)
              InlineNotice(
                kind: InlineNoticeKind.error,
                message: action.error!,
              ),
            for (final person in value)
              HelixSettingsTile(
                icon: Icons.block,
                title: person.name,
                trailing: action.busyId == person.id
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton(
                        onPressed: () =>
                            _unblock(context, ref, person.id, person.name),
                        child: const Text('Unblock'),
                      ),
              ),
          ],
        ),
        AsyncError() => HelixErrorState(
          message: 'The blocked list could not be loaded.',
          onRetry: () => ref.invalidate(blockedProvider),
        ),
        _ => const Padding(
          padding: EdgeInsets.all(HelixSpace.lg),
          child: LinearProgressIndicator(),
        ),
      },
    );
  }

  Future<void> _unblock(
    BuildContext context,
    WidgetRef ref,
    String id,
    String name,
  ) async {
    final ok = await showHelixConfirmDialog(
      context,
      title: 'Unblock $name?',
      message: 'They will be able to message and call you again.',
      confirmLabel: 'Unblock',
    );
    if (ok) await ref.read(blockedActionsProvider.notifier).unblock(id);
  }
}
