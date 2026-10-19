import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/groups/application/group_actions.dart';
import 'package:helix_remote/features/groups/application/group_pending.dart';
import 'package:orbit_ui/orbit_ui.dart' show PendingMemberItem;

/// The group's members waiting for this person's yes, as the Orbit
/// conversation draws them above the messages ("Confirm NAME?").
///
/// The groups feature owns the logic; the conversation may not import it
/// (`test/architecture_test.dart`), so the two meet here; the group's info
/// page draws the same cards from it.
final pendingMemberItemsProvider = Provider.autoDispose
    .family<List<PendingMemberItem>, String>((ref, groupId) {
      final pending =
          ref.watch(pendingMembersProvider(groupId)).value ??
          const <PendingMemberView>[];
      return [
        for (final m in pending)
          PendingMemberItem(
            account: m.account,
            name: m.name,
            title: m.title,
            explanation:
                '${m.explanation} Until you confirm, what you send in this '
                'group stays unreadable to them.',
            canRemove: m.canRemove,
          ),
      ];
    });

/// Confirm or remove a waiting member; each returns the sentence to show.
final class PendingMemberActions {
  PendingMemberActions(this._ref);

  final Ref _ref;

  Future<String?> confirm(String groupId, String account) async =>
      (await _ref.read(groupActionsProvider).confirmMember(groupId, account))
          .message;

  Future<String?> remove(String groupId, String account) async =>
      (await _ref.read(groupActionsProvider).removeMember(groupId, account))
          .message;
}

final pendingMemberActionsProvider = Provider<PendingMemberActions>(
  PendingMemberActions.new,
);
