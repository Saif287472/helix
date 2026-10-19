import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/groups/application/group_invites.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: invite links, make one, share it, revoke it, and choose
/// whether new people need an admin's approval, drawn by `orbit_ui`'s Invite
/// with a link.
///
/// The link carries the key that opens the group's name and picture preview
/// (in the part after `#`, which a browser never sends to a server); the
/// server keeps only a hash of it, so a link it lists but this device did not
/// make (this run) shows when it was made and can only be revoked.
class GroupInviteScreen extends ConsumerWidget {
  const GroupInviteScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(groupInviteProvider(groupId));
    final controller = ref.read(groupInviteProvider(groupId).notifier);
    final name = ref.watch(groupTitleProvider(groupId));
    final sharer = ref.read(linkSharerProvider);
    String? urlOf(String id) =>
        state.links.where((l) => l.linkId == id).firstOrNull?.link;
    return orbit.InviteLinksScreen(
      model: orbit.InviteLinksModel(
        approveNew: state.requiresApproval,
        links: ref.watch(inviteLinkItemsProvider(groupId)),
        loading: state.loading,
        creating: state.working,
        error: state.error,
      ),
      actions: orbit.InviteLinksActions(
        onSetApprove: controller.setRequiresApproval,
        onCreate: controller.create,
        onShare: (id) {
          final url = urlOf(id);
          if (url != null) sharer.share(url, groupName: name);
        },
        onCopy: (id) async {
          final url = urlOf(id);
          if (url != null) await sharer.copy(url);
        },
        onRevoke: controller.revoke,
      ),
    );
  }
}
