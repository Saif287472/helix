import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/groups/application/group_invites.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: invite links, make one, share it, revoke it, and choose
/// whether new people need an admin's approval, drawn by `orbit_ui`'s Invite
/// with a link.
///
/// The link carries the key that opens the group's name and picture preview
/// (in the part after `#`, which a browser never sends to a server); the
/// server keeps only a hash of it.
class GroupInviteScreen extends ConsumerWidget {
  const GroupInviteScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(groupInviteProvider(groupId));
    final controller = ref.read(groupInviteProvider(groupId).notifier);
    final name = ref.watch(groupTitleProvider(groupId));
    final sharer = ref.read(linkSharerProvider);
    InviteLinkInfo? linkOf(String id) =>
        state.links.where((l) => l.linkId == id).firstOrNull;
    return orbit.InviteLinksScreen(
      model: orbit.InviteLinksModel(
        approveNew: state.requiresApproval,
        links: [
          for (final l in state.links)
            orbit.InviteLinkItem(
              id: l.linkId,
              url: l.link,
              approve: l.requiresApproval,
            ),
        ],
        creating: state.working,
        error: state.error,
      ),
      actions: orbit.InviteLinksActions(
        onSetApprove: controller.setRequiresApproval,
        onCreate: controller.create,
        onShare: (id) {
          final link = linkOf(id);
          if (link != null) sharer.share(link.link, groupName: name);
        },
        onCopy: (id) async {
          final link = linkOf(id);
          if (link != null) await sharer.copy(link.link);
        },
        onRevoke: controller.revoke,
      ),
    );
  }
}
