import 'package:flutter/material.dart';
import 'package:helix_admin/src/features/common/format.dart';
import 'package:helix_admin/src/features/invites/invites_controller.dart';
import 'package:helix_admin/src/session/admin_session_controller.dart';
import 'package:helix_admin/src/widgets/dialogs.dart';
import 'package:helix_admin/src/widgets/paged_list.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

class InvitesScreen extends StatefulWidget {
  const InvitesScreen({super.key, required this.adminContext, this.pageSize});

  final AdminContext adminContext;
  final int? pageSize;

  @override
  State<InvitesScreen> createState() => _InvitesScreenState();
}

class _InvitesScreenState extends State<InvitesScreen> {
  late final InvitesController _invites;

  @override
  void initState() {
    super.initState();
    _invites = InvitesController(
      widget.adminContext,
      pageSize: widget.pageSize ?? PageRequest.defaultLimit,
    )..refresh();
  }

  @override
  void dispose() {
    _invites.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final result = await _invites.create();
    if (!mounted) return;
    final invite = result.invite;
    if (invite == null) {
      if (result.problem != null) showMessage(context, result.problem!);
      return;
    }
    await showCodeOnceDialog(
      context,
      title: 'Invite code',
      code: invite.inviteCode,
      expiresAt: invite.expiresAt,
      explanation:
          'Send this code to the person you are inviting. It works once.',
    );
  }

  Future<void> _cancel(AdminInvite invite) async {
    final confirmed = await showHelixDestructiveDialog(
      context,
      title: 'Cancel this invite?',
      message: 'The code stops working. Nobody can use it to sign up.',
      action: 'Cancel invite',
    );
    if (!confirmed) return;
    final problem = await _invites.cancel(invite.inviteId);
    if (mounted) showMessage(context, problem ?? 'Invite cancelled.');
  }

  @override
  Widget build(BuildContext context) {
    return PagedListView<AdminInvite>(
      controller: _invites,
      emptyIcon: Icons.local_activity_outlined,
      emptyTitle: 'No invites yet',
      emptyMessage: 'Create an invite to let someone sign up.',
      header: Padding(
        padding: const EdgeInsets.all(HelixSpace.md),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ListenableBuilder(
            listenable: _invites,
            builder: (context, _) => FilledButton.icon(
              onPressed: _invites.creating ? null : _create,
              icon: const Icon(Icons.add),
              label: const Text('Create invite'),
            ),
          ),
        ),
      ),
      itemBuilder: (context, invite) => ListenableBuilder(
        listenable: _invites,
        builder: (context, _) => _InviteTile(
          invite: invite,
          cancelling: _invites.isCancelling(invite.inviteId),
          onCancel: () => _cancel(invite),
        ),
      ),
    );
  }
}

class _InviteTile extends StatelessWidget {
  const _InviteTile({
    required this.invite,
    required this.cancelling,
    required this.onCancel,
  });

  final AdminInvite invite;
  final bool cancelling;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final redeemed = invite.redeemedBy;
    return ListTile(
      title: Text('Invite ${shortId(invite.inviteId)}'),
      subtitle: Text(
        [
          'Created ${formatTime(invite.createdAt)}',
          'expires ${formatTime(invite.expiresAt)}',
          if (invite.issuer != 'admin') 'issued by ${invite.issuer}',
          if (redeemed != null) 'used by ${shortId(redeemed)}',
        ].join(' · '),
      ),
      trailing: invite.status == InviteStatus.open
          ? TextButton(
              onPressed: cancelling ? null : onCancel,
              child: const Text('Cancel'),
            )
          : HelixStatusBadge(
              label: _label(invite.status),
              color: invite.status == InviteStatus.used
                  ? HelixStatusColors.positive
                  : HelixStatusColors.neutral,
            ),
    );
  }

  static String _label(InviteStatus status) => switch (status) {
    InviteStatus.open => 'Open',
    InviteStatus.used => 'Used',
    InviteStatus.cancelled => 'Cancelled',
    InviteStatus.expired => 'Expired',
    InviteStatus.unknown => 'Unknown',
  };
}
