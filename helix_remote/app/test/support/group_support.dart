import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:helix_remote/core/people/name_lookup.dart';
import 'package:helix_remote/features/groups/application/group_invites.dart';
import 'package:helix_remote/features/groups/application/group_models.dart';
import 'package:helix_remote/features/groups/application/group_navigation.dart';
import 'package:helix_remote/features/groups/application/group_picture.dart';
import 'package:helix_remote/features/groups/application/groups_port.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// A [GroupsPort] the test drives: it holds one group, records every call, and
/// can be made to fail the next one.
class FakeGroupsPort implements GroupsPort {
  FakeGroupsPort({GroupSnapshot? group}) : _group = group;

  GroupSnapshot? _group;
  final StreamController<GroupSnapshot?> _changes =
      StreamController<GroupSnapshot?>.broadcast();
  final StreamController<GroupSignal> _signals =
      StreamController<GroupSignal>.broadcast();
  final StreamController<List<GroupCandidate>> _people =
      StreamController<List<GroupCandidate>>.broadcast();

  List<GroupCandidate> candidates = const [];
  List<JoinRequestInfo> requests = const [];
  List<BannedInfo> banned = const [];
  GroupCandidate? lookupResult;

  /// Every call made, as a short string.
  final List<String> calls = [];

  /// Makes the next call throw this.
  Object? failWith;

  /// Makes every read of the join requests fail.
  Object? failRequests;

  AddMembersOutcome addOutcome = const AddMembersOutcome(
    added: ['a'],
    rejected: {},
  );
  CreatedGroupInfo created = const CreatedGroupInfo(
    groupId: 'new-group',
    conversationId: 'group:new-group',
  );
  InvitePreviewInfo preview = const InvitePreviewInfo(
    groupId: 'g1',
    memberCount: 3,
    requiresApproval: false,
    name: 'Book club',
    description: 'We read on Sundays',
  );
  JoinOutcome joinOutcome = JoinOutcome.joined;

  void set(GroupSnapshot? group) {
    _group = group;
    _changes.add(group);
  }

  void signal(GroupSignal signal) => _signals.add(signal);

  void _maybeFail() {
    final failure = failWith;
    if (failure != null) {
      failWith = null;
      throw failure;
    }
  }

  @override
  Stream<GroupSnapshot?> watch(String groupId) async* {
    yield _group;
    yield* _changes.stream;
  }

  @override
  Stream<List<GroupCandidate>> watchCandidates() async* {
    yield candidates;
    yield* _people.stream;
  }

  @override
  Future<GroupCandidate?> lookup(String query) async {
    calls.add('lookup $query');
    _maybeFail();
    final found = lookupResult;
    if (found != null) {
      candidates = [...candidates, found];
      _people.add(candidates);
    }
    return found;
  }

  @override
  Future<CreatedGroupInfo> create({
    required String name,
    required Iterable<String> members,
    String? description,
    Uint8List? picture,
  }) async {
    calls.add(
      'create $name [${members.join(',')}]${picture == null ? '' : ' +picture'}',
    );
    _maybeFail();
    return created;
  }

  @override
  Future<void> rename(String groupId, String name) async {
    calls.add('rename $name');
    _maybeFail();
  }

  @override
  Future<void> setDescription(String groupId, String? description) async {
    calls.add('description $description');
    _maybeFail();
  }

  @override
  Future<void> setPicture(String groupId, Uint8List? picture) async {
    calls.add(picture == null ? 'picture removed' : 'picture set');
    _maybeFail();
  }

  @override
  Future<void> setPermissions(
    String groupId,
    GroupPermissions permissions,
  ) async {
    calls.add(
      'permissions add:${permissions.addMembers.name} '
      'edit:${permissions.editInfo.name} send:${permissions.sendMessages.name}',
    );
    _maybeFail();
  }

  @override
  Future<void> setDisappearing(String groupId, int? seconds) async {
    calls.add('disappearing $seconds');
    _maybeFail();
  }

  @override
  Future<AddMembersOutcome> addMembers(
    String groupId,
    Iterable<String> accounts,
  ) async {
    calls.add('add ${accounts.join(',')}');
    _maybeFail();
    return addOutcome;
  }

  @override
  Future<void> removeMember(String groupId, String account) async {
    calls.add('remove $account');
    _maybeFail();
  }

  @override
  Future<void> leave(String groupId) async {
    calls.add('leave');
    _maybeFail();
  }

  @override
  Future<void> setRole(
    String groupId,
    String account,
    GroupMemberRole role,
  ) async {
    calls.add('role $account ${role.name}');
    _maybeFail();
  }

  @override
  Future<void> ban(String groupId, String account) async {
    calls.add('ban $account');
    _maybeFail();
  }

  @override
  Future<void> unban(String groupId, String account) async {
    calls.add('unban $account');
    _maybeFail();
    banned = [
      for (final b in banned)
        if (b.account != account) b,
    ];
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    calls.add('delete');
    _maybeFail();
  }

  @override
  Future<List<BannedInfo>> bans(String groupId) async {
    _maybeFail();
    return banned;
  }

  @override
  Future<InviteLinkInfo> createInviteLink(
    String groupId, {
    required bool requiresApproval,
    DateTime? expiresAt,
  }) async {
    calls.add('link approval:$requiresApproval');
    _maybeFail();
    return InviteLinkInfo(
      linkId: 'link-${calls.length}',
      link: 'https://example.org/open#HLX-GRP-secret${calls.length}',
      requiresApproval: requiresApproval,
    );
  }

  @override
  Future<void> revokeInviteLink(String groupId, String linkId) async {
    calls.add('revoke $linkId');
    _maybeFail();
  }

  @override
  Future<InvitePreviewInfo> previewInvite(String link) async {
    calls.add('preview');
    _maybeFail();
    return preview;
  }

  @override
  Future<JoinResultInfo> joinWithLink(String link) async {
    calls.add('join');
    _maybeFail();
    return JoinResultInfo(groupId: preview.groupId, outcome: joinOutcome);
  }

  @override
  Future<List<JoinRequestInfo>> joinRequests(String groupId) async {
    // A provider retries a failed read, so this one keeps failing.
    if (failRequests != null) throw failRequests!;
    _maybeFail();
    return requests;
  }

  @override
  Future<void> approveJoinRequest(String groupId, String requestId) async {
    calls.add('approve $requestId');
    _maybeFail();
    requests = [
      for (final r in requests)
        if (r.requestId != requestId) r,
    ];
  }

  @override
  Future<void> rejectJoinRequest(String groupId, String requestId) async {
    calls.add('reject $requestId');
    _maybeFail();
    requests = [
      for (final r in requests)
        if (r.requestId != requestId) r,
    ];
  }

  @override
  Future<void> refresh(String groupId) async {}

  @override
  Stream<GroupSignal> signals(String groupId) => _signals.stream;
}

/// A real 1x1 PNG, so a picked picture decodes.
final Uint8List tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

/// A picker that returns [bytes].
final class FakePicker implements GroupPicturePicker {
  FakePicker([this.bytes]);

  Uint8List? bytes;

  @override
  Future<Uint8List?> pick() async => bytes;
}

final class FakeSharer implements LinkSharer {
  final List<String> shared = [];
  final List<String> copied = [];

  @override
  Future<void> share(String link, {required String groupName}) async =>
      shared.add('$groupName|$link');

  @override
  Future<void> copy(String link) async => copied.add(link);
}

/// The overrides that take the group screens off the runtime.
List<Override> groupOverrides({
  required FakeGroupsPort port,
  PeopleNames names = PeopleNames.empty,
  FakePicker? picker,
  FakeSharer? sharer,
  String? Function(String conversationId)? chatLocation,
}) => [
  groupsPortProvider.overrideWith((ref) async => port),
  peopleNamesProvider.overrideWith((ref) => Stream.value(names)),
  groupPicturePickerProvider.overrideWithValue(picker ?? FakePicker()),
  linkSharerProvider.overrideWithValue(sharer ?? FakeSharer()),
  groupPictureProvider.overrideWith((ref, key) async => null),
  ?(chatLocation == null
      ? null
      : groupChatLocationProvider.overrideWithValue(chatLocation)),
];

const _ada = HelixPersonNames(
  phoneBookName: 'Ada Lovelace',
  number: '+8801711000001',
);
const _bob = HelixPersonNames(nickname: 'Bob', number: '+8801711000002');
const _carol = HelixPersonNames(helixName: 'carol');

/// People the group tests know.
const testNames = PeopleNames({
  'self': HelixPersonNames(nickname: 'Me'),
  'ada': _ada,
  'bob': _bob,
  'carol': _carol,
});

/// The signed-in person is `self`; the group has Ada (owner or admin), Bob and
/// Carol, with [self] holding [role].
GroupSnapshot testGroup({
  GroupMemberRole role = GroupMemberRole.owner,
  GroupPermissions permissions = const GroupPermissions(),
  int? disappearing,
  String title = 'Book club',
  String? description = 'We read on Sundays',
  String? homeServer,
  List<GroupMemberInfo>? members,
}) => GroupSnapshot(
  id: 'g1',
  title: title,
  description: description,
  selfRole: role,
  permissions: permissions,
  disappearingSeconds: disappearing,
  homeServer: homeServer,
  members:
      members ??
      [
        GroupMemberInfo(account: 'self', role: role, isSelf: true),
        GroupMemberInfo(
          account: 'ada',
          role: role == GroupMemberRole.owner
              ? GroupMemberRole.admin
              : GroupMemberRole.owner,
        ),
        const GroupMemberInfo(account: 'bob', role: GroupMemberRole.member),
        const GroupMemberInfo(account: 'carol', role: GroupMemberRole.member),
      ],
);
