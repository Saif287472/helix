import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/features/groups/application/group_errors.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote/features/groups/application/group_picture.dart';
import 'package:helix_remote/features/groups/application/groups_port.dart';

/// How an action ended: done (with an optional note to show) or failed (with
/// the sentence to show).
@immutable
final class GroupResult {
  const GroupResult.ok([this.message]) : ok = true;

  const GroupResult.failed(String this.message) : ok = false;

  final bool ok;
  final String? message;
}

/// Everything a person does to a group from its screens.
///
/// Each method asks the engine, which talks to the server first, and returns a
/// [GroupResult] whose message is a plain sentence: success notes ("Added 2
/// people") and failures (not allowed, stale roster, privacy refusal) alike.
/// A screen shows the message; it never sees an exception.
final groupActionsProvider = Provider<GroupActions>(GroupActions.new);

final class GroupActions {
  GroupActions(this._ref);

  final Ref _ref;

  Future<GroupsPort> get _port => _ref.read(groupsPortProvider.future);

  PeopleDirectory get _names =>
      _ref.read(peopleDirectoryProvider).value ?? PeopleDirectory.empty;

  Future<GroupResult> _run(
    Future<String?> Function(GroupsPort port) action, {
    GroupContext context = GroupContext.general,
  }) async {
    try {
      return GroupResult.ok(await action(await _port));
    } on Object catch (error) {
      return GroupResult.failed(groupErrorText(error, context: context));
    }
  }

  Future<GroupResult> rename(String groupId, String name) => _run((port) async {
    await port.rename(groupId, name);
    return null;
  });

  Future<GroupResult> setDescription(String groupId, String? description) =>
      _run((port) async {
        await port.setDescription(groupId, description);
        return null;
      });

  /// Chooses a picture from the phone and sets it; ok with no message when the
  /// person chose nothing.
  Future<GroupResult> chooseAndSetPicture(String groupId) async {
    final bytes = await _ref.read(groupPicturePickerProvider).pick();
    if (bytes == null) return const GroupResult.ok();
    return setPicture(groupId, bytes);
  }

  Future<GroupResult> setPicture(String groupId, Uint8List? picture) =>
      _run((port) async {
        await port.setPicture(groupId, picture);
        return null;
      });

  Future<GroupResult> setPermissions(
    String groupId,
    GroupPermissions permissions,
  ) => _run((port) async {
    await port.setPermissions(groupId, permissions);
    return null;
  });

  Future<GroupResult> setDisappearing(String groupId, int? seconds) =>
      _run((port) async {
        await port.setDisappearing(groupId, seconds);
        return null;
      });

  /// Adds [accounts]. People whose privacy settings, a ban or a missing
  /// account kept them out are named in the message, each with what to do.
  Future<GroupResult> addMembers(
    String groupId,
    Iterable<String> accounts,
  ) async {
    try {
      final outcome = await (await _port).addMembers(groupId, accounts);
      final lines = <String>[
        if (outcome.added.isNotEmpty)
          outcome.added.length == 1
              ? 'Added 1 person.'
              : 'Added ${outcome.added.length} people.',
        for (final entry in outcome.rejected.entries)
          addRejectionText(entry.value, _names.displayOf(entry.key)),
      ];
      final message = lines.isEmpty ? null : lines.join('\n');
      return outcome.added.isEmpty && outcome.rejected.isNotEmpty
          ? GroupResult.failed(message!)
          : GroupResult.ok(message);
    } on Object catch (error) {
      return GroupResult.failed(
        groupErrorText(error, context: GroupContext.members),
      );
    }
  }

  Future<GroupResult> removeMember(String groupId, String account) =>
      _run((port) async {
        await port.removeMember(groupId, account);
        return '${_names.displayOf(account)} was removed.';
      });

  Future<GroupResult> ban(String groupId, String account) => _run((port) async {
    await port.ban(groupId, account);
    return '${_names.displayOf(account)} was removed and banned.';
  });

  Future<GroupResult> unban(String groupId, String account) =>
      _run((port) async {
        await port.unban(groupId, account);
        return '${_names.displayOf(account)} can join again.';
      });

  Future<GroupResult> setRole(
    String groupId,
    String account,
    GroupMemberRole role,
  ) => _run((port) async {
    await port.setRole(groupId, account, role);
    final name = _names.displayOf(account);
    return switch (role) {
      GroupMemberRole.owner => '$name is now the owner.',
      GroupMemberRole.admin => '$name is now an admin.',
      GroupMemberRole.member => '$name is no longer an admin.',
    };
  });

  Future<GroupResult> leave(String groupId) => _run((port) async {
    await port.leave(groupId);
    return 'You left this group.';
  });

  Future<GroupResult> deleteGroup(String groupId) => _run((port) async {
    await port.deleteGroup(groupId);
    return 'The group was deleted.';
  });
}
