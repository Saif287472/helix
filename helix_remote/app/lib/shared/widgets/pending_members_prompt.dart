import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/groups/application/group_actions.dart';
import 'package:helix_remote/features/groups/application/group_pending.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// "Confirm NAME?" for each member of a group that the server's roster added
/// without an admin's announcement (or who joined through a link).
///
/// Until the person confirms, this device gives that member neither its sender
/// key nor the group key, so nothing sent from here is readable to them. The
/// prompt is shown in the group's info page and above the group conversation
/// (that is why it is a shared widget: the conversation and the groups feature
/// may not import each other). Nothing is shown when nobody is waiting.
///
/// Confirm is the person's own trust decision and is offered to everybody.
/// Remove is only offered where the group's rules let this account do it (an
/// admin); a plain member is told to ask an admin or leave the group.
class PendingMembersPrompt extends ConsumerWidget {
  const PendingMembersPrompt({super.key, required this.groupId});

  /// The bare group id (not `group:<id>`).
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending =
        ref.watch(pendingMembersProvider(groupId)).value ??
        const <PendingMemberView>[];
    if (pending.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final member in pending)
          _PendingMemberCard(
            key: ValueKey('pending-${member.account}'),
            groupId: groupId,
            member: member,
          ),
      ],
    );
  }
}

class _PendingMemberCard extends ConsumerStatefulWidget {
  const _PendingMemberCard({
    super.key,
    required this.groupId,
    required this.member,
  });

  final String groupId;
  final PendingMemberView member;

  @override
  ConsumerState<_PendingMemberCard> createState() => _PendingMemberCardState();
}

class _PendingMemberCardState extends ConsumerState<_PendingMemberCard> {
  var _busy = false;

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await ref
        .read(groupActionsProvider)
        .confirmMember(widget.groupId, widget.member.account);
    if (!mounted) return;
    setState(() => _busy = false);
    _say(result);
  }

  Future<void> _remove() async {
    if (_busy) return;
    final name = widget.member.name;
    final sure = await showHelixDestructiveDialog(
      context,
      title: 'Remove $name?',
      message:
          '$name will be taken out of the group. The group key changes, so '
          'they cannot read anything new.',
      action: 'Remove',
    );
    if (!sure || !mounted) return;
    setState(() => _busy = true);
    final result = await ref
        .read(groupActionsProvider)
        .removeMember(widget.groupId, widget.member.account);
    if (!mounted) return;
    setState(() => _busy = false);
    _say(result);
  }

  void _say(GroupResult result) {
    final message = result.message;
    if (message != null) showHelixSnackBar(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final member = widget.member;
    const foreground = HelixStatusColors.onPendingSurface;
    return Semantics(
      container: true,
      label: member.title,
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: HelixSpace.md,
          vertical: HelixSpace.xs,
        ),
        padding: const EdgeInsets.all(HelixSpace.md),
        decoration: BoxDecoration(
          color: HelixStatusColors.pendingSurface,
          borderRadius: HelixRadius.card,
          border: Border.all(color: HelixStatusColors.pendingOutline),
        ),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: foreground),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    color: HelixStatusColors.pendingIcon,
                  ),
                  const SizedBox(width: HelixSpace.xs),
                  Expanded(
                    child: Text(
                      member.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HelixSpace.xs),
              Text(
                '${member.explanation} Until you confirm, what you send in '
                'this group stays unreadable to them.',
              ),
              if (!member.canRemove) ...[
                const SizedBox(height: HelixSpace.xs),
                const Text(
                  'Only an admin can remove someone. If you do not know '
                  'them, you can leave the group.',
                ),
              ],
              const SizedBox(height: HelixSpace.sm),
              Wrap(
                spacing: HelixSpace.xs,
                runSpacing: HelixSpace.xs,
                children: [
                  FilledButton(
                    onPressed: _busy ? null : _confirm,
                    child: const Text('Confirm'),
                  ),
                  if (member.canRemove)
                    OutlinedButton(
                      onPressed: _busy ? null : _remove,
                      child: const Text('Remove'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
