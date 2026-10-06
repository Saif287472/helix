import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:http/http.dart' as http;

import 'fake_server.dart';

/// One group on the [FakeGroups] server.
final class FakeGroup {
  FakeGroup(this.id, this.encryptedState, this.settings, this.createdAt);

  final String id;
  final DateTime createdAt;
  Uint8List encryptedState;
  GroupSettings settings;
  int epoch = 0;

  /// Starts at 1 like the real server; the state blob's AAD binds it.
  int stateVersion = 1;

  /// Member accounts in join order, with their roles.
  final Map<String, GroupRole> roles = {};
  final Map<String, DateTime> joinedAt = {};
  final Set<String> bans = {};

  bool allows(GroupPermission permission, GroupRole role) =>
      permission == GroupPermission.everyone || role.canAdminister;
}

/// What the fake saw of one group send.
final class RecordedGroupSend {
  RecordedGroupSend(this.from, this.groupId, this.request, this.status);

  final FakeDevice from;
  final String groupId;
  final GroupMessageRequest request;
  final int status;
}

/// The groups module of the real server (REST_V2.md, groups), in memory:
/// roster authority with roles, epochs bumped by removals, the optimistic
/// state version, `roster_change` envelopes, and the group send with the
/// member-device digest (`device_list_stale` lists every member's devices),
/// distributions stored before the group message. Invite links and federation
/// are not modelled (the end-to-end tests cover them on the real server).
///
/// Plug it in with `FakeGroups(server)`; the engine's `GroupsClient` then
/// finds the routes on the fake.
final class FakeGroups {
  FakeGroups(this.server) {
    server.extensions.add(_handle);
  }

  final FakeServer server;
  final Map<String, FakeGroup> groups = {};
  final List<RecordedGroupSend> sends = [];
  final Set<String> _seenSends = {};

  /// Answers the next [times] `PUT state` calls with `version_conflict`
  /// (someone else wrote first).
  int conflictsOnNextState = 0;

  /// When set, `GET /v1/groups/{id}` answers with this epoch (an old answer
  /// arriving late), for roster-conflict tests.
  int? epochOverride;

  List<RecordedGroupSend> sendsOf(String groupId) => [
    for (final s in sends)
      if (s.groupId == groupId) s,
  ];

  /// Member devices by account, minus [except] (the sending device).
  Map<String, List<String>> devicesOf(FakeGroup group, {String? except}) => {
    for (final account in group.roles.keys)
      account: [
        for (final d
            in server.accounts[account]?.devices.values ?? const <FakeDevice>[])
          if (d.id != except) d.id,
      ],
  };

  /// Removes [account] from the group the way the server does (epoch bump,
  /// ownership handed on, `roster_change` to everyone including the removed).
  void removeMember(FakeGroup group, String account, {String? actor}) {
    final role = group.roles.remove(account);
    if (role == null) return;
    group.joinedAt.remove(account);
    if (group.roles.isEmpty) {
      groups.remove(group.id);
      _announce(group, RosterChangeKind.deleted, actor: actor, also: [account]);
      return;
    }
    if (role == GroupRole.owner) {
      final heir = group.roles.entries.firstWhere(
        (e) => e.value == GroupRole.admin,
        orElse: () => group.roles.entries.first,
      );
      group.roles[heir.key] = GroupRole.owner;
    }
    group.epoch++;
    _announce(
      group,
      actor == account ? RosterChangeKind.left : RosterChangeKind.removed,
      actor: actor,
      members: [account],
      also: [account],
    );
  }

  /// Puts [account] in the roster the way a hostile or buggy server could:
  /// with no announcement, or announced as added by [announceActor] (an
  /// admin's name, a forgery, or the account itself for a link join).
  void injectMember(
    FakeGroup group,
    String account, {
    String? announceActor,
    bool announce = false,
  }) {
    group.roles[account] = GroupRole.member;
    group.joinedAt[account] = server.now();
    if (announce) {
      _announce(
        group,
        RosterChangeKind.added,
        actor: announceActor,
        members: [account],
      );
    }
  }

  void _announce(
    FakeGroup group,
    RosterChangeKind change, {
    String? actor,
    List<String> members = const [],
    List<String> also = const [],
    bool adminsOnly = false,
  }) {
    final accounts = {
      for (final e in group.roles.entries)
        if (!adminsOnly || e.value.canAdminister) e.key,
      ...also,
    };
    for (final account in accounts) {
      for (final d
          in server.accounts[account]?.devices.values ?? const <FakeDevice>[]) {
        server.deliver(
          d.id,
          kind: EnvelopeKind.rosterChange,
          groupId: group.id,
          data: RosterChangeEvent(
            groupId: group.id,
            change: change,
            epoch: group.epoch,
            actor: actor,
            members: members,
          ).toJson(),
        );
      }
    }
  }

  Group _view(FakeGroup g) => Group(
    groupId: g.id,
    epoch: epochOverride ?? g.epoch,
    stateVersion: g.stateVersion,
    encryptedState: g.encryptedState,
    settings: g.settings,
    members: [
      for (final e in g.roles.entries)
        GroupMember(
          account: e.key,
          role: e.value,
          joinedAt: g.joinedAt[e.key]!,
        ),
    ],
    createdAt: g.createdAt,
  );

  // -------------------------------------------------------------- routes

  Future<http.Response?> _handle(ApiRoute route, FakeRequest r) async {
    if (route == Routes.createGroup) return _create(r);
    if (route == Routes.myGroups) return _mine(r);
    if (route == Routes.sendGroupMessage) return _send(r);
    final id = r.params['group_id'];
    if (id == null || !_isGroupRoute(route)) return null;
    final group = groups[id];
    final role = group?.roles[r.caller!.accountId];
    if (group == null || role == null) return server.error(ErrorCode.notFound);
    final me = r.caller!.accountId;
    if (route == Routes.group) return server.ok(_view(group).toJson());
    if (route == Routes.deleteGroup) {
      if (role != GroupRole.owner) return server.error(ErrorCode.forbidden);
      _announce(group, RosterChangeKind.deleted, actor: me);
      groups.remove(id);
      return server.empty();
    }
    if (route == Routes.setGroupState) {
      if (!group.allows(group.settings.editInfo, role)) {
        return server.error(ErrorCode.forbidden);
      }
      final req = SetGroupStateRequest.fromJson(r.json!);
      if (conflictsOnNextState > 0) {
        conflictsOnNextState--;
        return server.error(ErrorCode.versionConflict);
      }
      if (req.expectedVersion != group.stateVersion) {
        return server.error(ErrorCode.versionConflict);
      }
      group.encryptedState = req.encryptedState;
      group.stateVersion++;
      _announce(group, RosterChangeKind.stateChanged, actor: me);
      return server.ok(
        GroupVersionResponse(
          epoch: group.epoch,
          stateVersion: group.stateVersion,
        ).toJson(),
      );
    }
    if (route == Routes.setGroupSettings) {
      if (!role.canAdminister) return server.error(ErrorCode.forbidden);
      group.settings = GroupSettings.fromJson(r.json!);
      _announce(group, RosterChangeKind.settingsChanged, actor: me);
      return server.empty();
    }
    if (route == Routes.addGroupMembers) return _add(group, role, me, r);
    if (route == Routes.removeGroupMember) {
      final target = r.params['account']!;
      if (target != me) {
        final theirs = group.roles[target];
        if (theirs == null) return server.error(ErrorCode.notFound);
        if (!role.canAdminister || theirs == GroupRole.owner) {
          return server.error(ErrorCode.forbidden);
        }
      }
      removeMember(group, target, actor: me);
      return server.ok(
        GroupVersionResponse(
          epoch: group.epoch,
          stateVersion: group.stateVersion,
        ).toJson(),
      );
    }
    if (route == Routes.banFromGroup) {
      final target = r.params['account']!;
      if (!role.canAdminister || target == me) {
        return server.error(ErrorCode.forbidden);
      }
      final theirs = group.roles[target];
      if (theirs == GroupRole.owner) return server.error(ErrorCode.forbidden);
      group.bans.add(target);
      if (theirs != null) removeMember(group, target, actor: me);
      return server.empty();
    }
    if (route == Routes.unbanFromGroup) {
      if (!role.canAdminister) return server.error(ErrorCode.forbidden);
      group.bans.remove(r.params['account']);
      return server.empty();
    }
    if (route == Routes.setGroupRole) {
      final target = r.params['account']!;
      final theirs = group.roles[target];
      if (theirs == null) return server.error(ErrorCode.notFound);
      if (!role.canAdminister || theirs == GroupRole.owner) {
        return server.error(ErrorCode.forbidden);
      }
      final wanted = SetRoleRequest.fromJson(r.json!).role;
      if (wanted == GroupRole.owner) {
        if (role != GroupRole.owner) return server.error(ErrorCode.forbidden);
        group.roles[me] = GroupRole.admin;
      }
      group.roles[target] = wanted;
      _announce(
        group,
        RosterChangeKind.roleChanged,
        actor: me,
        members: [target],
      );
      return server.empty();
    }
    return null;
  }

  static final Set<ApiRoute> _groupRoutes = {
    Routes.group,
    Routes.deleteGroup,
    Routes.setGroupState,
    Routes.setGroupSettings,
    Routes.addGroupMembers,
    Routes.removeGroupMember,
    Routes.setGroupRole,
    Routes.banFromGroup,
    Routes.unbanFromGroup,
  };

  static bool _isGroupRoute(ApiRoute route) => _groupRoutes.contains(route);

  http.Response _create(FakeRequest r) {
    final req = CreateGroupRequest.fromJson(r.json!);
    final me = r.caller!.accountId;
    final group = FakeGroup(
      req.groupId,
      req.encryptedState,
      req.settings,
      server.now(),
    );
    groups[req.groupId] = group;
    group.roles[me] = GroupRole.owner;
    group.joinedAt[me] = group.createdAt;
    final added = <String>[];
    for (final account in req.members) {
      if (account == me || !server.accounts.containsKey(account)) continue;
      group.roles[account] = GroupRole.member;
      group.joinedAt[account] = group.createdAt;
      added.add(account);
    }
    _announce(group, RosterChangeKind.created, actor: me, members: added);
    return http.Response(
      _json(_view(group).toJson()),
      201,
      headers: {'content-type': 'application/json'},
    );
  }

  http.Response _mine(FakeRequest r) => server.ok(
    GroupList(
      groups: [
        for (final g in groups.values)
          if (g.roles.containsKey(r.caller!.accountId))
            GroupSummary(
              groupId: g.id,
              epoch: g.epoch,
              stateVersion: g.stateVersion,
            ),
      ],
    ).toJson(),
  );

  http.Response _add(
    FakeGroup group,
    GroupRole role,
    String me,
    FakeRequest r,
  ) {
    if (!group.allows(group.settings.addMembers, role)) {
      return server.error(ErrorCode.forbidden);
    }
    final req = AddMembersRequest.fromJson(r.json!);
    final added = <String>[];
    final rejected = <String, AddMemberRejection>{};
    for (final account in req.accounts.toSet()) {
      if (!server.accounts.containsKey(account)) {
        rejected[account] = AddMemberRejection.notFound;
      } else if (group.roles.containsKey(account)) {
        rejected[account] = AddMemberRejection.alreadyMember;
      } else if (group.bans.contains(account)) {
        rejected[account] = AddMemberRejection.banned;
      } else {
        group.roles[account] = GroupRole.member;
        group.joinedAt[account] = server.now();
        added.add(account);
      }
    }
    if (added.isNotEmpty) {
      _announce(group, RosterChangeKind.added, actor: me, members: added);
    }
    return server.ok(
      AddMembersResponse(
        added: added,
        rejected: rejected,
        epoch: group.epoch,
      ).toJson(),
    );
  }

  http.Response _send(FakeRequest r) {
    final from = r.caller!;
    final id = r.params['group_id']!;
    final group = groups[id];
    final role = group?.roles[from.accountId];
    if (group == null || role == null) return server.error(ErrorCode.notFound);
    if (!group.allows(group.settings.sendMessages, role)) {
      return server.error(ErrorCode.forbidden);
    }
    final request = GroupMessageRequest.fromJson(r.json!);
    final byAccount = devicesOf(group, except: from.id);
    final expected = membersDigest(byAccount);
    if (!_equal(expected, request.devicesDigest)) {
      sends.add(RecordedGroupSend(from, id, request, 409));
      return server.error(
        ErrorCode.deviceListStale,
        details: StaleDevices(
          accounts: [
            for (final e in byAccount.entries)
              StaleAccountDevices(account: e.key, missing: e.value),
          ],
        ).toJson(),
      );
    }
    sends.add(RecordedGroupSend(from, id, request, 200));
    if (!_seenSends.add('${from.id}/${request.id}')) {
      return server.ok(
        SendMessageResponse(acceptedAt: server.now(), replayed: true).toJson(),
      );
    }
    final sender = EnvelopeSender(account: from.accountId, device: from.id);
    if (!request.ephemeral) {
      // Distributions first, so the key is there before the message.
      for (final recipient in request.distributions) {
        for (final d in recipient.devices) {
          server.deliver(d.device, from: sender, payload: d.payload);
        }
      }
    }
    for (final devices in byAccount.values) {
      for (final device in devices) {
        server.deliver(
          device,
          kind: EnvelopeKind.groupMessage,
          id: request.id,
          from: sender,
          groupId: id,
          payload: request.payload,
          ephemeral: request.ephemeral,
          urgent: request.urgent,
        );
      }
    }
    return server.ok(SendMessageResponse(acceptedAt: server.now()).toJson());
  }

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _json(JsonMap map) => jsonEncode(map);
}
