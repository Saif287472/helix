import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/groups/application/group_invites.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Invite links: make one, share it, revoke it, and choose whether new people
/// need an admin's approval.
///
/// The link carries the key that opens the group's name and picture preview
/// (in the part after `#`, which a browser never sends to a server); the
/// server keeps only a hash of it. Links made here live in memory only, so
/// they can be shared and revoked until the app closes; make a new one after
/// that.
class GroupInviteScreen extends ConsumerWidget {
  const GroupInviteScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(groupInviteProvider(groupId));
    final controller = ref.read(groupInviteProvider(groupId).notifier);
    final name = ref.watch(groupTitleProvider(groupId));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return HelixSettingsScaffold(
      title: 'Invite with a link',
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(HelixSpace.md),
            child: Text(
              'Anyone with a link can ask to join this group. Share it only '
              'with people you want in.',
            ),
          ),
          HelixSettingsSwitchTile(
            title: 'Admins approve new members',
            subtitle: state.requiresApproval
                ? 'People who use the link wait for an admin to let them in.'
                : 'People who use the link join straight away.',
            value: state.requiresApproval,
            onChanged: controller.setRequiresApproval,
          ),
          Padding(
            padding: const EdgeInsets.all(HelixSpace.md),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                onPressed: state.working ? null : controller.create,
                icon: state.working
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_link),
                label: const Text('Create link'),
              ),
            ),
          ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: HelixSpace.md),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  state.error!,
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ),
          if (state.links.isEmpty)
            Padding(
              padding: const EdgeInsets.all(HelixSpace.lg),
              child: Text(
                'Links you make appear here so you can share or revoke them.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final link in state.links)
            _LinkCard(
              key: ValueKey(link.linkId),
              link: link,
              groupName: name,
              busy: state.working,
              onRevoke: () async {
                final sure = await showHelixDestructiveDialog(
                  context,
                  title: 'Revoke this link?',
                  message:
                      'It stops working at once. People who already joined '
                      'stay in the group.',
                  action: 'Revoke',
                );
                if (sure) await controller.revoke(link.linkId);
              },
            ),
        ],
      ),
    );
  }
}

class _LinkCard extends ConsumerWidget {
  const _LinkCard({
    super.key,
    required this.link,
    required this.groupName,
    required this.busy,
    required this.onRevoke,
  });

  final InviteLinkInfo link;
  final String groupName;
  final bool busy;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sharer = ref.read(linkSharerProvider);
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: HelixSpace.md,
        vertical: HelixSpace.xs,
      ),
      child: Padding(
        padding: const EdgeInsets.all(HelixSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  link.requiresApproval
                      ? Icons.how_to_reg_outlined
                      : Icons.link,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: HelixSpace.xs),
                Expanded(
                  child: Text(
                    link.requiresApproval
                        ? 'Admins approve new members'
                        : 'Joins straight away',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: HelixSpace.xs),
            SelectableText(
              link.link,
              maxLines: 2,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: HelixSpace.xs),
            Wrap(
              spacing: HelixSpace.xs,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () =>
                      sharer.share(link.link, groupName: groupName),
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await sharer.copy(link.link);
                    if (context.mounted) {
                      showHelixSnackBar(context, 'Link copied.');
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
                ),
                TextButton.icon(
                  onPressed: busy ? null : onRevoke,
                  icon: Icon(Icons.link_off, color: scheme.error),
                  label: Text('Revoke', style: TextStyle(color: scheme.error)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
