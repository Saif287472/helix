import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/groups/application/group_actions.dart';
import 'package:helix_remote/features/groups/application/group_info.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Who may edit the group's info, add people and send messages. Admins can
/// always do all three; only admins change these settings.
class GroupSettingsScreen extends ConsumerWidget {
  const GroupSettingsScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(groupInfoProvider(groupId));
    return Scaffold(
      appBar: AppBar(title: const Text('Group settings')),
      body: switch (info) {
        AsyncError() => HelixErrorState(
          message: 'This group could not be loaded.',
          onRetry: () => ref.invalidate(groupSnapshotProvider(groupId)),
        ),
        AsyncData(:final value) when value == null => const HelixEmptyState(
          icon: Icons.group_off_outlined,
          title: 'You are not in this group',
        ),
        AsyncData(:final value) => _Settings(view: value!),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Settings extends ConsumerWidget {
  const _Settings({required this.view});

  final GroupInfoView view;

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required GroupWho current,
    required GroupPermissions Function(GroupWho who) apply,
  }) async {
    if (!view.snapshot.canAdminister) return;
    final choice = await showHelixBottomSheet<GroupWho>(
      context,
      title: title,
      builder: (sheet) => RadioGroup<GroupWho>(
        groupValue: current,
        onChanged: (value) => Navigator.pop(sheet, value),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final who in GroupWho.values)
              RadioListTile<GroupWho>(title: Text(who.label), value: who),
          ],
        ),
      ),
    );
    if (choice == null || choice == current || !context.mounted) return;
    final result = await ref
        .read(groupActionsProvider)
        .setPermissions(view.id, apply(choice));
    final message = result.message;
    if (message != null && context.mounted) showHelixSnackBar(context, message);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permissions = view.snapshot.permissions;
    final admin = view.snapshot.canAdminister;
    return ListView(
      children: [
        if (!admin)
          const Padding(
            padding: EdgeInsets.all(HelixSpace.md),
            child: Text('Only admins can change these settings.'),
          ),
        HelixSettingsSection(
          title: 'Members can',
          footer: 'Admins can always do all of these.',
          children: [
            HelixSettingsTile(
              icon: Icons.edit_outlined,
              title: 'Edit group info',
              subtitle: permissions.editInfo.label,
              showChevron: admin,
              onTap: admin
                  ? () => _choose(
                      context,
                      ref,
                      title: 'Who can edit group info',
                      current: permissions.editInfo,
                      apply: (who) => permissions.copyWith(editInfo: who),
                    )
                  : null,
            ),
            HelixSettingsTile(
              icon: Icons.person_add_alt_1_outlined,
              title: 'Add members',
              subtitle: permissions.addMembers.label,
              showChevron: admin,
              onTap: admin
                  ? () => _choose(
                      context,
                      ref,
                      title: 'Who can add members',
                      current: permissions.addMembers,
                      apply: (who) => permissions.copyWith(addMembers: who),
                    )
                  : null,
            ),
            HelixSettingsTile(
              icon: Icons.chat_bubble_outline,
              title: 'Send messages',
              subtitle: permissions.sendMessages.label,
              showChevron: admin,
              onTap: admin
                  ? () => _choose(
                      context,
                      ref,
                      title: 'Who can send messages',
                      current: permissions.sendMessages,
                      apply: (who) => permissions.copyWith(sendMessages: who),
                    )
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}
