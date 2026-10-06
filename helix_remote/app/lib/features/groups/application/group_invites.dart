import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/clock.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/features/groups/application/group_actions.dart';
import 'package:helix_remote/features/groups/application/group_errors.dart';
import 'package:helix_remote/features/groups/application/group_info.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote/features/groups/application/groups_port.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart'
    show HelixAvatarModel, HelixPersonNames;
import 'package:share_plus/share_plus.dart';

/// Hands a link to the phone's share sheet, or the clipboard.
///
/// An interface so tests assert what was shared. The link is a secret (it
/// carries the key that opens the group's preview), so only the person's own
/// share sheet or clipboard ever sees it.
abstract interface class LinkSharer {
  Future<void> share(String link, {required String groupName});

  Future<void> copy(String link);
}

final class PlatformLinkSharer implements LinkSharer {
  const PlatformLinkSharer();

  @override
  Future<void> share(String link, {required String groupName}) async {
    await SharePlus.instance.share(
      ShareParams(
        text: 'Join the group "$groupName" on Helix: $link',
        subject: 'Join $groupName on Helix',
      ),
    );
  }

  @override
  Future<void> copy(String link) =>
      Clipboard.setData(ClipboardData(text: link));
}

final linkSharerProvider = Provider<LinkSharer>(
  (ref) => const PlatformLinkSharer(),
);

/// The invite links made for one group during this session.
///
/// The server keeps only a link's hash and offers no list, and the link itself
/// is a secret, so links live in memory only: they are here to be shared or
/// revoked while the app runs. A link made earlier cannot be re-shown; make
/// another (and revoke from here the ones made now).
@immutable
final class GroupInviteState {
  const GroupInviteState({
    this.links = const [],
    this.requiresApproval = false,
    this.working = false,
    this.error,
  });

  /// Newest first.
  final List<InviteLinkInfo> links;

  /// The mode the next link is made in.
  final bool requiresApproval;
  final bool working;
  final String? error;

  GroupInviteState copyWith({
    List<InviteLinkInfo>? links,
    bool? requiresApproval,
    bool? working,
    String? error,
    bool clearError = false,
  }) => GroupInviteState(
    links: links ?? this.links,
    requiresApproval: requiresApproval ?? this.requiresApproval,
    working: working ?? this.working,
    error: clearError ? null : error ?? this.error,
  );
}

final groupInviteProvider =
    NotifierProvider.family<GroupInviteController, GroupInviteState, String>(
      GroupInviteController.new,
    );

final class GroupInviteController extends Notifier<GroupInviteState> {
  GroupInviteController(this.groupId);

  final String groupId;

  @override
  GroupInviteState build() => const GroupInviteState();

  void setRequiresApproval(bool value) =>
      state = state.copyWith(requiresApproval: value, clearError: true);

  /// Makes a link in the chosen mode.
  Future<void> create() async {
    if (state.working) return;
    state = state.copyWith(working: true, clearError: true);
    try {
      final port = await ref.read(groupsPortProvider.future);
      final link = await port.createInviteLink(
        groupId,
        requiresApproval: state.requiresApproval,
      );
      state = state.copyWith(links: [link, ...state.links], working: false);
    } on Object catch (error) {
      state = state.copyWith(
        working: false,
        error: groupErrorText(error, context: GroupContext.link),
      );
    }
  }

  /// Revokes [linkId]: the link stops working at once.
  Future<void> revoke(String linkId) async {
    if (state.working) return;
    state = state.copyWith(working: true, clearError: true);
    try {
      final port = await ref.read(groupsPortProvider.future);
      await port.revokeInviteLink(groupId, linkId);
      state = state.copyWith(
        links: [
          for (final link in state.links)
            if (link.linkId != linkId) link,
        ],
        working: false,
      );
    } on Object catch (error) {
      state = state.copyWith(
        working: false,
        error: groupErrorText(error, context: GroupContext.link),
      );
    }
  }
}

/// The people waiting for an admin's answer, refreshed when a new request
/// arrives.
final joinRequestsProvider = FutureProvider.autoDispose
    .family<List<JoinRequestInfo>, String>((ref, groupId) async {
      final port = await ref.watch(groupsPortProvider.future);
      final sub = port.signals(groupId).listen((signal) {
        if (signal is GroupJoinRequestArrived) ref.invalidateSelf();
      });
      ref.onDispose(sub.cancel);
      return port.joinRequests(groupId);
    });

/// Answers join requests.
final joinRequestActionsProvider = Provider<JoinRequestActions>(
  JoinRequestActions.new,
);

final class JoinRequestActions {
  JoinRequestActions(this._ref);

  final Ref _ref;

  Future<GroupResult> approve(String groupId, String requestId) =>
      _answer(groupId, requestId, approve: true);

  Future<GroupResult> reject(String groupId, String requestId) =>
      _answer(groupId, requestId, approve: false);

  Future<GroupResult> _answer(
    String groupId,
    String requestId, {
    required bool approve,
  }) async {
    try {
      final port = await _ref.read(groupsPortProvider.future);
      if (approve) {
        await port.approveJoinRequest(groupId, requestId);
      } else {
        await port.rejectJoinRequest(groupId, requestId);
      }
      _ref.invalidate(joinRequestsProvider(groupId));
      return const GroupResult.ok();
    } on Object catch (error) {
      // The request may already have been answered by another admin.
      _ref.invalidate(joinRequestsProvider(groupId));
      return GroupResult.failed(groupErrorText(error));
    }
  }
}

/// The people this device banned from the group.
final groupBansProvider = FutureProvider.autoDispose
    .family<List<BannedInfo>, String>((ref, groupId) async {
      final port = await ref.watch(groupsPortProvider.future);
      return port.bans(groupId);
    });

/// Where joining through a link stands.
enum JoinStage {
  /// Waiting for a link.
  input,

  /// Reading the preview.
  loading,

  /// The preview is shown; the person decides.
  preview,

  /// Asking to join.
  joining,

  /// In the group.
  joined,

  /// Waiting for an admin to approve.
  pending,

  /// The link did not work; see [JoinState.error].
  failed,
}

@immutable
final class JoinState {
  const JoinState({
    this.stage = JoinStage.input,
    this.preview,
    this.groupId,
    this.error,
    this.alreadyMember = false,
  });

  final JoinStage stage;
  final InvitePreviewInfo? preview;

  /// The group joined (or already in).
  final String? groupId;
  final String? error;

  /// The preview names a group this account is already in.
  final bool alreadyMember;

  JoinState copyWith({
    JoinStage? stage,
    InvitePreviewInfo? preview,
    String? groupId,
    String? error,
    bool? alreadyMember,
  }) => JoinState(
    stage: stage ?? this.stage,
    preview: preview ?? this.preview,
    groupId: groupId ?? this.groupId,
    error: error,
    alreadyMember: alreadyMember ?? this.alreadyMember,
  );
}

/// Join by link: read the preview, then confirm.
///
/// The link is held in memory for the length of the flow only and never
/// written anywhere. Previewing changes nothing on the server; joining is a
/// separate, explicit step.
final joinByLinkProvider =
    NotifierProvider.autoDispose<JoinByLinkController, JoinState>(
      JoinByLinkController.new,
    );

final class JoinByLinkController extends Notifier<JoinState> {
  String? _link;

  @override
  JoinState build() => const JoinState();

  /// Reads the preview of [link].
  Future<void> preview(String link) async {
    final text = link.trim();
    if (text.isEmpty) return;
    _link = text;
    state = const JoinState(stage: JoinStage.loading);
    try {
      final port = await ref.read(groupsPortProvider.future);
      final preview = await port.previewInvite(text);
      final already = await _isMember(port, preview.groupId);
      state = JoinState(
        stage: JoinStage.preview,
        preview: preview,
        groupId: preview.groupId,
        alreadyMember: already,
      );
    } on Object catch (error) {
      state = JoinState(
        stage: JoinStage.failed,
        error: groupErrorText(error, context: GroupContext.link),
      );
    }
  }

  Future<bool> _isMember(GroupsPort port, String groupId) async {
    try {
      return await port
              .watch(groupId)
              .first
              .timeout(const Duration(seconds: 2)) !=
          null;
    } on Object {
      return false;
    }
  }

  /// Asks to join (or joins). The result is [JoinStage.joined] or, for an
  /// approval link, [JoinStage.pending].
  Future<void> join() async {
    final link = _link;
    final preview = state.preview;
    if (link == null || preview == null || state.stage == JoinStage.joining) {
      return;
    }
    state = state.copyWith(stage: JoinStage.joining);
    try {
      final port = await ref.read(groupsPortProvider.future);
      final result = await port.joinWithLink(link);
      state = JoinState(
        stage: result.outcome == JoinOutcome.joined
            ? JoinStage.joined
            : JoinStage.pending,
        preview: preview,
        groupId: result.groupId,
      );
    } on Object catch (error) {
      state = JoinState(
        stage: JoinStage.failed,
        preview: preview,
        error: groupErrorText(error, context: GroupContext.link),
      );
    }
  }

  /// Back to the link field.
  void reset() {
    _link = null;
    state = const JoinState();
  }
}

/// The group's own view for [groupId], used by the join-requests screen to name
/// the group; re-exported for symmetry with the info screen.
final groupTitleProvider = Provider.family<String, String>((ref, groupId) {
  final info = ref.watch(groupInfoProvider(groupId)).value;
  return info?.title ?? 'Group';
});

/// A join request or a ban, named and dated for a list.
@immutable
final class PersonEntryView {
  const PersonEntryView({
    required this.id,
    required this.account,
    required this.names,
    required this.whenLabel,
  });

  /// The request id (requests) or the account (bans).
  final String id;
  final String account;
  final HelixPersonNames names;

  /// "Today, 14:05", "12 Sep, 09:30".
  final String whenLabel;

  String get title => names.display;

  HelixAvatarModel get avatar => HelixAvatarModel(
    name: names.display,
    colorIndex: HelixAvatarModel.colorIndexFor(account),
  );
}

/// [joinRequestsProvider], named and dated.
final joinRequestViewsProvider = Provider.autoDispose
    .family<AsyncValue<List<PersonEntryView>>, String>((ref, groupId) {
      final requests = ref.watch(joinRequestsProvider(groupId));
      final names =
          ref.watch(peopleDirectoryProvider).value ?? PeopleDirectory.empty;
      final now = ref.watch(clockProvider)();
      return requests.whenData(
        (list) => [
          for (final r in list)
            PersonEntryView(
              id: r.requestId,
              account: r.account,
              names: names.nameOf(r.account).tileNames,
              whenLabel: formatWhen(r.createdAt, now),
            ),
        ],
      );
    });

/// [groupBansProvider], named and dated.
final bannedViewsProvider = Provider.autoDispose
    .family<AsyncValue<List<PersonEntryView>>, String>((ref, groupId) {
      final bans = ref.watch(groupBansProvider(groupId));
      final names =
          ref.watch(peopleDirectoryProvider).value ?? PeopleDirectory.empty;
      final now = ref.watch(clockProvider)();
      return bans.whenData(
        (list) => [
          for (final b in list)
            PersonEntryView(
              id: b.account,
              account: b.account,
              names: names.nameOf(b.account).tileNames,
              whenLabel: formatWhen(b.bannedAt, now),
            ),
        ],
      );
    });
