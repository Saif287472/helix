import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/groups/application/create_group.dart';
import 'package:helix_remote/features/groups/application/group_actions.dart';
import 'package:helix_remote/features/groups/application/group_errors.dart';
import 'package:helix_remote/features/groups/application/group_info.dart';
import 'package:helix_remote/features/groups/application/group_invites.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote/features/groups/application/group_navigation.dart';
import 'package:helix_remote/features/groups/groups_routes.dart';
import 'package:helix_remote/features/groups/presentation/widgets/group_avatar.dart';
import 'package:helix_remote/shared/widgets/pending_members_prompt.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The default disappearing-message timers a group offers, in seconds.
const kGroupDisappearingChoices = <(String, int?)>[
  ('Off', null),
  ('24 hours', 86400),
  ('7 days', 604800),
  ('90 days', 7776000),
];

/// What a timer of [seconds] is called.
String disappearingLabel(int? seconds) {
  if (seconds == null || seconds <= 0) return 'Off';
  for (final (label, value) in kGroupDisappearingChoices) {
    if (value == seconds) return label;
  }
  final days = seconds ~/ 86400;
  if (days >= 1 && seconds % 86400 == 0) {
    return days == 1 ? '1 day' : '$days days';
  }
  final hours = seconds ~/ 3600;
  return hours >= 1 ? '$hours hours' : '$seconds seconds';
}

/// A group's page: picture, name, description, who is in it and what an admin
/// can do about it.
///
/// Everything reads [groupInfoProvider]; every change goes through
/// [groupActionsProvider], whose answer is a sentence this screen shows, so a
/// refusal (not an admin, a stale roster, a privacy setting) is always said in
/// plain words and never as an exception.
class GroupInfoScreen extends ConsumerWidget {
  const GroupInfoScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Roster-change feedback: say it when this device is taken out.
    ref.listen(groupSignalsProvider(groupId), (_, next) {
      final signal = next.value;
      if (signal is GroupMembershipEnded) {
        showHelixSnackBar(context, membershipEndedText(signal.reason));
      }
      if (signal is GroupMemberUnconfirmedArrived) {
        showHelixSnackBar(
          context,
          'A member was added by the server roster. Confirm or remove them '
          'below.',
        );
      }
    });
    final info = ref.watch(groupInfoProvider(groupId));
    return Scaffold(
      appBar: AppBar(title: const Text('Group info')),
      body: switch (info) {
        AsyncError() => HelixErrorState(
          message: 'This group could not be loaded.',
          onRetry: () => ref.invalidate(groupSnapshotProvider(groupId)),
        ),
        AsyncData(:final value) when value == null => HelixEmptyState(
          icon: Icons.group_off_outlined,
          title: 'You are not in this group',
          message:
              'You left it, were removed, or it was deleted. Its messages stay '
              'in your chats.',
          action: FilledButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Go back'),
          ),
        ),
        AsyncData(:final value) => _GroupBody(view: value!),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _GroupBody extends ConsumerWidget {
  const _GroupBody({required this.view});

  final GroupInfoView view;

  void _report(BuildContext context, GroupResult result) {
    final message = result.message;
    if (message != null && context.mounted) showHelixSnackBar(context, message);
  }

  Future<void> _editInfo(BuildContext context, WidgetRef ref) async {
    final edited = await showHelixBottomSheet<(String, String)>(
      context,
      title: 'Edit group info',
      builder: (sheet) => _EditInfoForm(
        name: view.snapshot.title,
        description: view.snapshot.description ?? '',
      ),
    );
    if (edited == null || !context.mounted) return;
    final actions = ref.read(groupActionsProvider);
    final (name, description) = edited;
    if (name.trim().isNotEmpty && name.trim() != view.snapshot.title) {
      final result = await actions.rename(view.id, name.trim());
      if (!context.mounted) return;
      if (!result.ok) return _report(context, result);
    }
    if (description.trim() != (view.snapshot.description ?? '')) {
      final result = await actions.setDescription(view.id, description.trim());
      if (context.mounted) _report(context, result);
    }
  }

  Future<void> _changePicture(BuildContext context, WidgetRef ref) async {
    final remove = view.pictureKey != null;
    final choice = await showHelixBottomSheet<String>(
      context,
      title: 'Group picture',
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose a picture'),
            onTap: () => Navigator.pop(sheet, 'choose'),
          ),
          if (remove)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove picture'),
              onTap: () => Navigator.pop(sheet, 'remove'),
            ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    final actions = ref.read(groupActionsProvider);
    final result = choice == 'remove'
        ? await actions.setPicture(view.id, null)
        : await actions.chooseAndSetPicture(view.id);
    if (context.mounted) _report(context, result);
  }

  Future<void> _chooseDisappearing(BuildContext context, WidgetRef ref) async {
    final current = view.snapshot.disappearingSeconds;
    final choice = await showHelixBottomSheet<int>(
      context,
      title: 'Disappearing messages',
      builder: (sheet) => RadioGroup<int>(
        groupValue: current ?? 0,
        onChanged: (value) => Navigator.pop(sheet, value ?? 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: HelixSpace.md),
              child: Text(
                'New messages in this group disappear after this long, for '
                'everyone.',
              ),
            ),
            for (final (label, seconds) in kGroupDisappearingChoices)
              RadioListTile<int>(title: Text(label), value: seconds ?? 0),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    final seconds = choice == 0 ? null : choice;
    if (seconds == current) return;
    final result = await ref
        .read(groupActionsProvider)
        .setDisappearing(view.id, seconds);
    if (context.mounted) _report(context, result);
  }

  Future<void> _memberMenu(
    BuildContext context,
    WidgetRef ref,
    GroupMemberView member,
  ) async {
    if (member.actions.isEmpty) return;
    final action = await showHelixBottomSheet<MemberAction>(
      context,
      title: member.title,
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in member.actions)
            ListTile(
              leading: Icon(_iconOf(action)),
              title: Text(
                action.label,
                style:
                    action == MemberAction.ban || action == MemberAction.remove
                    ? TextStyle(color: Theme.of(sheet).colorScheme.error)
                    : null,
              ),
              onTap: () => Navigator.pop(sheet, action),
            ),
        ],
      ),
    );
    if (action == null || !context.mounted) return;
    await _apply(context, ref, member, action);
  }

  static IconData _iconOf(MemberAction action) => switch (action) {
    MemberAction.makeAdmin => Icons.admin_panel_settings_outlined,
    MemberAction.removeAdmin => Icons.remove_moderator_outlined,
    MemberAction.makeOwner => Icons.verified_user_outlined,
    MemberAction.remove => Icons.person_remove_outlined,
    MemberAction.ban => Icons.block,
  };

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    GroupMemberView member,
    MemberAction action,
  ) async {
    final actions = ref.read(groupActionsProvider);
    final name = member.names.display;
    final Future<GroupResult>? pending;
    switch (action) {
      case MemberAction.makeAdmin:
        pending = actions.setRole(
          view.id,
          member.account,
          GroupMemberRole.admin,
        );
      case MemberAction.removeAdmin:
        pending = actions.setRole(
          view.id,
          member.account,
          GroupMemberRole.member,
        );
      case MemberAction.makeOwner:
        final sure = await showHelixConfirmDialog(
          context,
          title: 'Make $name the owner?',
          message:
              'They will own the group. You become an admin and cannot undo '
              'this yourself.',
          confirmLabel: 'Make owner',
        );
        pending = sure
            ? actions.setRole(view.id, member.account, GroupMemberRole.owner)
            : null;
      case MemberAction.remove:
        final sure = await showHelixDestructiveDialog(
          context,
          title: 'Remove $name?',
          message:
              '$name will be taken out of the group. The group key changes, so '
              'they cannot read anything new.',
          action: 'Remove',
        );
        pending = sure ? actions.removeMember(view.id, member.account) : null;
      case MemberAction.ban:
        final sure = await showHelixDestructiveDialog(
          context,
          title: 'Remove and ban $name?',
          message:
              '$name will be removed and cannot join again through a link '
              'until you unban them.',
          action: 'Ban',
        );
        pending = sure ? actions.ban(view.id, member.account) : null;
    }
    if (pending == null) return;
    final result = await pending;
    if (context.mounted) _report(context, result);
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final sure = await showHelixDestructiveDialog(
      context,
      title: 'Leave "${view.title}"?',
      message:
          'You will stop getting its messages. Its history stays in your '
          'chats. You can only come back if someone adds you or sends a link.',
      action: 'Leave',
    );
    if (!sure || !context.mounted) return;
    final result = await ref.read(groupActionsProvider).leave(view.id);
    if (!context.mounted) return;
    _report(context, result);
    if (result.ok) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final sure = await showHelixDestructiveDialog(
      context,
      title: 'Delete "${view.title}"?',
      message:
          'The group is deleted for everyone and nobody can send to it any '
          'more. This cannot be undone.',
      action: 'Delete group',
    );
    if (!sure || !context.mounted) return;
    final result = await ref.read(groupActionsProvider).deleteGroup(view.id);
    if (!context.mounted) return;
    _report(context, result);
    if (result.ok) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final snapshot = view.snapshot;
    final requests = snapshot.canAdminister
        ? ref.watch(joinRequestsProvider(view.id)).value?.length ?? 0
        : 0;
    final description = snapshot.description?.trim() ?? '';
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(HelixSpace.lg),
          child: Column(
            children: [
              InkResponse(
                onTap: snapshot.canEditInfo
                    ? () => _changePicture(context, ref)
                    : null,
                radius: 56,
                child: GroupAvatar(
                  model: view.avatar,
                  pictureKey: view.pictureKey,
                  semanticLabel: snapshot.canEditInfo
                      ? 'Group picture. Double tap to change.'
                      : 'Group picture',
                ),
              ),
              const SizedBox(height: HelixSpace.sm),
              Semantics(
                header: true,
                child: Text(
                  view.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              Text(
                [
                  view.memberCountLabel,
                  if (view.isFederated) 'on ${snapshot.homeServer}',
                ].join(' · '),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (snapshot.nameUnavailable)
                Padding(
                  padding: const EdgeInsets.only(top: HelixSpace.xs),
                  child: Text(
                    'The group\'s name is still arriving.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: HelixSpace.sm),
                  child: Text(description, textAlign: TextAlign.center),
                ),
              if (snapshot.canEditInfo)
                Padding(
                  padding: const EdgeInsets.only(top: HelixSpace.sm),
                  child: OutlinedButton.icon(
                    onPressed: () => _editInfo(context, ref),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit group info'),
                  ),
                ),
            ],
          ),
        ),
        PendingMembersPrompt(groupId: view.id),
        HelixSettingsSection(
          title: 'Group',
          children: [
            HelixSettingsTile(
              icon: Icons.timer_outlined,
              title: 'Disappearing messages',
              subtitle: disappearingLabel(snapshot.disappearingSeconds),
              onTap: snapshot.canAdminister
                  ? () => _chooseDisappearing(context, ref)
                  : null,
            ),
            if (snapshot.canAdminister) ...[
              HelixSettingsTile(
                icon: Icons.tune,
                title: 'Group settings',
                subtitle: 'Who can edit, add people and send',
                showChevron: true,
                onTap: () => context.push(GroupRoutes.settings(view.id)),
              ),
              HelixSettingsTile(
                icon: Icons.link,
                title: 'Invite with a link',
                showChevron: true,
                onTap: () => context.push(GroupRoutes.invite(view.id)),
              ),
              HelixSettingsTile(
                icon: Icons.how_to_reg_outlined,
                title: 'Join requests',
                subtitle: requests == 0
                    ? 'Nobody is waiting'
                    : requests == 1
                    ? '1 person is waiting'
                    : '$requests people are waiting',
                showChevron: true,
                onTap: () => context.push(GroupRoutes.requests(view.id)),
              ),
              HelixSettingsTile(
                icon: Icons.block,
                title: 'Banned people',
                showChevron: true,
                onTap: () => context.push(GroupRoutes.banned(view.id)),
              ),
            ],
          ],
        ),
        HelixSectionHeader(title: view.memberCountLabel),
        if (snapshot.canAddMembers)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: const Icon(Icons.person_add_alt_1),
            ),
            title: const Text('Add members'),
            onTap: () => context.push(GroupRoutes.addMembers(view.id)),
          ),
        for (final member in view.members)
          _MemberTile(
            key: ValueKey('member-${member.account}'),
            member: member,
            onTap: member.actions.isEmpty
                ? null
                : () => _memberMenu(context, ref, member),
          ),
        const SizedBox(height: HelixSpace.sm),
        HelixSettingsSection(
          children: [
            HelixSettingsTile(
              icon: Icons.logout,
              title: 'Leave group',
              destructive: true,
              onTap: () => _leave(context, ref),
            ),
            if (snapshot.isOwner)
              HelixSettingsTile(
                icon: Icons.delete_forever_outlined,
                title: 'Delete group',
                destructive: true,
                onTap: () => _delete(context, ref),
              ),
          ],
        ),
        const SizedBox(height: HelixSpace.xl),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({super.key, required this.member, required this.onTap});

  final GroupMemberView member;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = member.subtitle;
    return Semantics(
      container: true,
      button: onTap != null,
      label: [
        member.title,
        if (subtitle.isNotEmpty) subtitle,
        if (onTap != null) 'Double tap for actions',
      ].join(', '),
      excludeSemantics: true,
      onTap: onTap,
      child: ListTile(
        leading: HelixAvatar(model: member.avatar),
        title: Text(member.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: onTap == null
            ? null
            : Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
        onTap: onTap,
      ),
    );
  }
}

/// The name and description fields of the edit sheet; pops with both.
class _EditInfoForm extends StatefulWidget {
  const _EditInfoForm({required this.name, required this.description});

  final String name;
  final String description;

  @override
  State<_EditInfoForm> createState() => _EditInfoFormState();
}

class _EditInfoFormState extends State<_EditInfoForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.name,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.description,
  );

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        HelixSpace.md,
        0,
        HelixSpace.md,
        HelixSpace.md + inset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            maxLength: kGroupNameMaxLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Group name'),
          ),
          const SizedBox(height: HelixSpace.sm),
          TextField(
            controller: _description,
            maxLength: 500,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: HelixSpace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: HelixSpace.xs),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, (_name.text, _description.text)),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
