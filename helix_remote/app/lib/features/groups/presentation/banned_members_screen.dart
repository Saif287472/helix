import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/groups/application/group_actions.dart';
import 'package:helix_remote/features/groups/application/group_invites.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// People banned from the group, with a way to let them back.
///
/// The server keeps no ban list a device can read, so this shows the bans made
/// **on this device**; a ban an admin made on another phone is not listed here
/// (it still holds on the server).
class BannedMembersScreen extends ConsumerWidget {
  const BannedMembersScreen({super.key, required this.groupId});

  final String groupId;

  Future<void> _unban(
    BuildContext context,
    WidgetRef ref,
    PersonEntryView person,
  ) async {
    final result = await ref
        .read(groupActionsProvider)
        .unban(groupId, person.account);
    ref.invalidate(groupBansProvider(groupId));
    if (!context.mounted) return;
    final message = result.message;
    if (message != null) showHelixSnackBar(context, message);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bans = ref.watch(bannedViewsProvider(groupId));
    return Scaffold(
      appBar: AppBar(title: const Text('Banned people')),
      body: switch (bans) {
        AsyncError() => HelixErrorState(
          message: 'The list could not be loaded.',
          onRetry: () => ref.invalidate(groupBansProvider(groupId)),
        ),
        AsyncData(:final value) when value.isEmpty => const HelixEmptyState(
          icon: Icons.block,
          title: 'No one is banned',
          message:
              'People you remove and ban from this phone are listed here. '
              'Bans made on another device are not shown.',
        ),
        AsyncData(:final value) => ListView(
          children: [
            const Padding(
              padding: EdgeInsets.all(HelixSpace.md),
              child: Text(
                'Banned people cannot join through a link. Bans made on other '
                'devices are not listed here.',
              ),
            ),
            for (final person in value)
              ListTile(
                key: ValueKey('ban-${person.account}'),
                leading: HelixAvatar(model: person.avatar),
                title: Text(
                  person.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('Banned ${person.whenLabel}'),
                trailing: TextButton(
                  onPressed: () => _unban(context, ref, person),
                  child: const Text('Unban'),
                ),
              ),
          ],
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
