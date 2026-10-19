import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/groups/application/group_actions.dart';
import 'package:helix_remote/features/groups/application/group_invites.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: people banned from the group, with a way to let them back,
/// drawn by `orbit_ui`'s Banned people.
///
/// The server keeps no ban list a device can read, so this shows the bans
/// made **on this device**; a ban an admin made on another phone is not
/// listed here (it still holds on the server).
class BannedMembersScreen extends ConsumerWidget {
  const BannedMembersScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bans = ref.watch(bannedViewsProvider(groupId));
    return orbit.BannedPeopleScreen(
      model: orbit.BannedPeopleModel(
        people: [
          for (final p in bans.value ?? const <PersonEntryView>[])
            orbit.PersonEntryView(
              account: p.account,
              title: p.title,
              whenLabel: 'Banned ${p.whenLabel}',
              avatar: p.avatar,
            ),
        ],
        loading: bans.isLoading && !bans.hasValue,
        loadFailed: bans.hasError && !bans.hasValue,
      ),
      actions: orbit.BannedPeopleActions(
        onUnban: (account) async {
          final result = await ref
              .read(groupActionsProvider)
              .unban(groupId, account);
          ref.invalidate(groupBansProvider(groupId));
          return result.message;
        },
        onRetry: () => ref.invalidate(groupBansProvider(groupId)),
      ),
    );
  }
}
