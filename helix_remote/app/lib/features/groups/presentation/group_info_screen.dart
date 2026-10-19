import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helix_remote/features/groups/application/group_actions.dart';
import 'package:helix_remote/features/groups/application/group_errors.dart';
import 'package:helix_remote/features/groups/application/group_info.dart';
import 'package:helix_remote/features/groups/application/group_invites.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote/features/groups/application/group_navigation.dart';
import 'package:helix_remote/features/groups/application/group_picture.dart';
import 'package:helix_remote/features/groups/groups_routes.dart';
import 'package:helix_remote/shared/pending_members.dart';
import 'package:orbit_ui/orbit_ui.dart' as orbit;

/// Connector: a group's page, its picture, name, description, who is in it
/// and what an admin can do about it, drawn by `orbit_ui`'s Group info
/// (`contracts/people_groups.md`).
///
/// Everything reads [groupInfoProvider]; every change goes through
/// [groupActionsProvider], whose answer is a sentence the page shows, so a
/// refusal (not an admin, a stale roster, a privacy setting) is always said
/// in plain words and never as an exception.
class GroupInfoScreen extends ConsumerWidget {
  const GroupInfoScreen({super.key, required this.groupId});

  final String groupId;

  static orbit.MemberAction _actionOf(MemberAction a) => switch (a) {
    MemberAction.makeAdmin => orbit.MemberAction.makeAdmin,
    MemberAction.removeAdmin => orbit.MemberAction.removeAdmin,
    MemberAction.makeOwner => orbit.MemberAction.makeOwner,
    MemberAction.remove => orbit.MemberAction.remove,
    MemberAction.ban => orbit.MemberAction.ban,
  };

  /// The four choices; null when the group's timer is none of them.
  static orbit.DisappearAfter? _afterOf(int? seconds) => switch (seconds ?? 0) {
    0 => orbit.DisappearAfter.off,
    86400 => orbit.DisappearAfter.day,
    604800 => orbit.DisappearAfter.week,
    7776000 => orbit.DisappearAfter.days90,
    _ => null,
  };

  static int? _secondsOf(orbit.DisappearAfter after) => switch (after) {
    orbit.DisappearAfter.off => null,
    orbit.DisappearAfter.day => 86400,
    orbit.DisappearAfter.week => 604800,
    orbit.DisappearAfter.days90 => 7776000,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Roster-change feedback: say it when this device is taken out.
    ref.listen(groupSignalsProvider(groupId), (_, next) {
      final signal = next.value;
      if (signal is GroupMembershipEnded) {
        orbit.showOrbitToast(context, membershipEndedText(signal.reason));
      }
      if (signal is GroupMemberUnconfirmedArrived) {
        orbit.showOrbitToast(
          context,
          'A member was added by the server roster. Confirm or remove them '
          'below.',
        );
      }
    });
    final info = ref.watch(groupInfoProvider(groupId));
    final view = info.value;
    final status = switch (info) {
      AsyncError() => orbit.GroupInfoStatus.failed,
      AsyncData() when view == null => orbit.GroupInfoStatus.gone,
      AsyncData() => orbit.GroupInfoStatus.ready,
      _ => orbit.GroupInfoStatus.loading,
    };
    final snapshot = view?.snapshot;
    final pending = ref.watch(pendingMemberItemsProvider(groupId));
    final requests = snapshot?.canAdminister ?? false
        ? ref.watch(joinRequestsProvider(groupId)).value?.length ?? 0
        : 0;
    final pictureKey = view?.pictureKey;
    final bytes = pictureKey == null
        ? null
        : ref.watch(groupPictureProvider(pictureKey)).value;
    final actions = ref.read(groupActionsProvider);
    final members = ref.read(pendingMemberActionsProvider);

    String? said(GroupResult r) => r.message;

    // Leaving and deleting go back to Chats when they work, and say so.
    Future<String?> leaveWith(Future<GroupResult> Function() run) async {
      final result = await run();
      if (!context.mounted) return null;
      final message = result.message;
      if (message != null) orbit.showOrbitToast(context, message);
      if (result.ok) Navigator.of(context).popUntil((route) => route.isFirst);
      return null;
    }

    final seconds = snapshot?.disappearingSeconds;
    return orbit.GroupInfoScreen(
      model: orbit.GroupInfoModel(
        groupId: groupId,
        status: status,
        title: view?.title ?? '',
        avatar: orbit.HelixAvatarModel(
          name: view?.title ?? '',
          colorIndex: orbit.HelixAvatarModel.colorIndexFor(groupId),
          isGroup: true,
          image: bytes == null ? null : MemoryImage(bytes),
        ),
        memberCountLabel: view == null
            ? ''
            : [
                view.memberCountLabel,
                if (view.isFederated) 'on ${snapshot!.homeServer}',
              ].join(' · '),
        description: snapshot?.description?.trim(),
        isOwner: snapshot?.isOwner ?? false,
        canAdminister: snapshot?.canAdminister ?? false,
        canEditInfo: snapshot?.canEditInfo ?? false,
        canAddMembers: snapshot?.canAddMembers ?? false,
        disappearing: _afterOf(seconds) ?? orbit.DisappearAfter.off,
        disappearingLabel: _afterOf(seconds) == null
            ? disappearingLabel(seconds)
            : null,
        joinRequestCount: requests,
        members: [
          for (final m in view?.members ?? const <GroupMemberView>[])
            orbit.GroupMemberView(
              account: m.account,
              title: m.title,
              avatar: m.avatar,
              roleLabel: m.role == GroupMemberRole.member ? '' : m.role.label,
              detail: [
                ?m.server,
                if (!m.isSelf) ?m.names.secondary,
              ].join(' · '),
              notConfirmed: m.unconfirmed,
              isAdmin: m.role == GroupMemberRole.admin,
              canAct: m.actions.isNotEmpty,
              actions: {for (final a in m.actions) _actionOf(a)},
            ),
        ],
        pending: pending,
        hasPicture: pictureKey != null,
        note: snapshot?.nameUnavailable ?? false
            ? 'The group’s name is still arriving.'
            : null,
      ),
      actions: orbit.GroupInfoActions(
        onChoosePicture: () async =>
            said(await actions.chooseAndSetPicture(groupId)),
        onRemovePicture: () async =>
            said(await actions.setPicture(groupId, null)),
        onSaveInfo: (name, description) async {
          if (snapshot == null) return null;
          if (name.isNotEmpty && name != snapshot.title) {
            final renamed = await actions.rename(groupId, name);
            if (!renamed.ok) return said(renamed);
          }
          if (description != (snapshot.description ?? '')) {
            return said(await actions.setDescription(groupId, description));
          }
          return null;
        },
        onSetDisappearing: (after) async {
          final next = _secondsOf(after);
          if (next == seconds) return null;
          return said(await actions.setDisappearing(groupId, next));
        },
        onMemberAction: (account, action) async => said(switch (action) {
          orbit.MemberAction.makeAdmin => await actions.setRole(
            groupId,
            account,
            GroupMemberRole.admin,
          ),
          orbit.MemberAction.removeAdmin => await actions.setRole(
            groupId,
            account,
            GroupMemberRole.member,
          ),
          orbit.MemberAction.makeOwner => await actions.setRole(
            groupId,
            account,
            GroupMemberRole.owner,
          ),
          orbit.MemberAction.remove => await actions.removeMember(
            groupId,
            account,
          ),
          orbit.MemberAction.ban => await actions.ban(groupId, account),
        }),
        onConfirmPending: (account) => members.confirm(groupId, account),
        onRemovePending: (account) => members.remove(groupId, account),
        onOpenSettings: () => context.push(GroupRoutes.settings(groupId)),
        onOpenInviteLinks: () => context.push(GroupRoutes.invite(groupId)),
        onOpenJoinRequests: () => context.push(GroupRoutes.requests(groupId)),
        onOpenBanned: () => context.push(GroupRoutes.banned(groupId)),
        onAddMembers: () => context.push(GroupRoutes.addMembers(groupId)),
        onLeave: () => leaveWith(() => actions.leave(groupId)),
        onDelete: () => leaveWith(() => actions.deleteGroup(groupId)),
        onRetry: () => ref.invalidate(groupSnapshotProvider(groupId)),
      ),
    );
  }
}
