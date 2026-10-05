import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/session_providers.dart';
import 'package:helix_remote/core/groups/pending_member_copy.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/features/groups/application/group_info.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote/features/groups/application/groups_port.dart';

// Members the server's roster lists that this device has not confirmed.
//
// The roster is the server's word, and a server (or someone who got hold of
// an invite link) can add a member that no admin of the group announced.
// The engine then holds that member back: it gives them neither its sender
// key nor the group key, so what this device sends stays unreadable to them,
// and leaves a notice in the chat. This is where the person decides: confirm
// (they get the keys from now on) or, for an admin, remove them.

/// One member waiting for the person's yes.
@immutable
final class PendingMemberView {
  const PendingMemberView({
    required this.account,
    required this.name,
    required this.reason,
    required this.canRemove,
  });

  final String account;
  final String name;
  final PendingReason reason;

  /// The viewer is an admin who may remove this member (the group's rules,
  /// not a guess). Everyone else can only confirm, or leave the group.
  final bool canRemove;

  String get title => 'Confirm $name?';

  String get explanation => pendingReasonSentence(name, reason.wire);

  @override
  bool operator ==(Object other) =>
      other is PendingMemberView &&
      other.account == account &&
      other.name == name &&
      other.reason == reason &&
      other.canRemove == canRemove;

  @override
  int get hashCode => Object.hash(account, name, reason, canRemove);
}

/// The members of [groupId] waiting for confirmation, live (empty for none).
final pendingMembersProvider = StreamProvider.autoDispose
    .family<List<PendingMemberView>, String>((ref, groupId) async* {
      final port = await ref.watch(groupsPortProvider.future);
      final names =
          ref.watch(peopleDirectoryProvider).value ?? PeopleDirectory.empty;
      // Whether the viewer may remove people comes from the group's own
      // snapshot (their role), so a plain member is never offered a button the
      // server would refuse.
      final snapshot = ref.watch(groupSnapshotProvider(groupId)).value;
      yield* port.watchPendingMembers(groupId).map((pending) {
        final byAccount = {
          for (final m in snapshot?.members ?? const <GroupMemberInfo>[])
            m.account: m,
        };
        return [
          for (final p in pending)
            PendingMemberView(
              account: p.account,
              name: names.displayOf(
                p.account,
                fallbackName: byAccount[p.account]?.nameHint,
              ),
              reason: p.reason,
              canRemove: _mayRemove(snapshot, byAccount[p.account]),
            ),
        ];
      });
    });

bool _mayRemove(GroupSnapshot? group, GroupMemberInfo? target) {
  if (group == null || target == null) return group?.canAdminister ?? false;
  // Same rule as the member menu: the owner removes anyone but themselves, an
  // admin removes ordinary members.
  if (target.isSelf || target.role == GroupMemberRole.owner) return false;
  return switch (group.selfRole) {
    GroupMemberRole.owner => true,
    GroupMemberRole.admin => target.role == GroupMemberRole.member,
    GroupMemberRole.member => false,
  };
}

/// What the in-app banner says about a member that just appeared as waiting.
String unconfirmedBannerText({
  required String name,
  required String groupTitle,
}) => groupTitle.isEmpty
    ? '$name was added to a group by the server roster. Review it.'
    : '$name was added to "$groupTitle" by the server roster. Review it.';

/// A member waiting for confirmation appeared in any group, with the name the
/// person would see for them. For the app-wide banner.
final class UnconfirmedMemberAlert {
  const UnconfirmedMemberAlert({required this.groupId, required this.message});

  final String groupId;
  final String message;
}

final unconfirmedMemberAlertsProvider = StreamProvider<UnconfirmedMemberAlert>((
  ref,
) async* {
  // Only a signed-in device has groups (and a runtime to ask).
  if (ref.watch(authStateProvider).value != AppAuthState.ready) return;
  final port = await ref.watch(groupsPortProvider.future);
  // The names as they are when an event arrives, without restarting the
  // stream (and dropping the event) every time one changes.
  var names = PeopleDirectory.empty;
  ref.listen(peopleDirectoryProvider, (_, next) {
    names = next.value ?? names;
  }, fireImmediately: true);
  yield* port.unconfirmedMembers().map(
    (event) => UnconfirmedMemberAlert(
      groupId: event.groupId,
      message: unconfirmedBannerText(
        name: names.displayOf(event.account),
        groupTitle: event.groupTitle,
      ),
    ),
  );
});
