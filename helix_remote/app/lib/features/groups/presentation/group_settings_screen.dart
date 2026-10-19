import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/groups/application/group_actions.dart';
import 'package:helix_remote/features/groups/application/group_info.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: who may edit the group's info, add people and send messages,
/// drawn by `orbit_ui`'s Group settings. Admins can always do all three;
/// only admins change these settings.
class GroupSettingsScreen extends ConsumerWidget {
  const GroupSettingsScreen({super.key, required this.groupId});

  final String groupId;

  static orbit.GroupWho _whoOf(GroupWho w) => switch (w) {
    GroupWho.everyone => orbit.GroupWho.everyone,
    GroupWho.admins => orbit.GroupWho.admins,
  };

  static GroupWho _appWhoOf(orbit.GroupWho w) => switch (w) {
    orbit.GroupWho.everyone => GroupWho.everyone,
    orbit.GroupWho.admins => GroupWho.admins,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(groupInfoProvider(groupId));
    final view = info.value;
    final permissions = view?.snapshot.permissions ?? const GroupPermissions();
    final actions = ref.read(groupActionsProvider);

    Future<String?> set(
      GroupPermissions Function(GroupWho who) apply,
      orbit.GroupWho who,
    ) async =>
        (await actions.setPermissions(groupId, apply(_appWhoOf(who)))).message;

    return orbit.GroupSettingsScreen(
      model: orbit.GroupSettingsModel(
        status: switch (info) {
          AsyncError() => orbit.GroupInfoStatus.failed,
          AsyncData() when view == null => orbit.GroupInfoStatus.gone,
          AsyncData() => orbit.GroupInfoStatus.ready,
          _ => orbit.GroupInfoStatus.loading,
        },
        canChange: view?.snapshot.canAdminister ?? false,
        editInfo: _whoOf(permissions.editInfo),
        addMembers: _whoOf(permissions.addMembers),
        sendMessages: _whoOf(permissions.sendMessages),
      ),
      actions: orbit.GroupSettingsActions(
        onEditInfo: (who) => set((w) => permissions.copyWith(editInfo: w), who),
        onAddMembers: (who) =>
            set((w) => permissions.copyWith(addMembers: w), who),
        onSendMessages: (who) =>
            set((w) => permissions.copyWith(sendMessages: w), who),
        onRetry: () => ref.invalidate(groupSnapshotProvider(groupId)),
      ),
    );
  }
}
