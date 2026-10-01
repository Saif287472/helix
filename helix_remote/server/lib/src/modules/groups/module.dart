import 'dart:async';
import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/kernel/crypto.dart';
import 'package:helix_remote_server/src/kernel/relay.dart';
import 'package:helix_remote_server/src/modules/groups/api.dart';
import 'package:helix_remote_server/src/modules/groups/application/frame.dart';
import 'package:helix_remote_server/src/modules/groups/data/group_store.dart';
import 'package:helix_remote_server/src/modules/identity/api.dart';
import 'package:helix_remote_server/src/modules/messaging/api.dart';
import 'package:helix_remote_server/src/modules/people/api.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/jobs/jobs.dart';
import 'package:helix_remote_server/src/platform/module.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';
import 'package:shelf/shelf.dart';

part 'federation.dart';

/// Who performs an operation: the stored form of the account (bare here,
/// `uuid@domain` for a member on another server) and the device, when
/// there is one.
final class _Actor {
  const _Actor(this.account, this.device);

  final String account;
  final String? device;
}

/// One group operation, shared by the client route and the S2S action
/// that runs it for a member on another server. Account ids in [body] and
/// [params] are in [frame]; so are the ids in the response.
typedef _Op =
    Future<Response> Function(
      _Actor actor,
      Frame frame,
      Map<String, String> params,
      JsonReader? body,
    );

/// Group roster authority (REST_V2.md "groups"). The server enforces who is
/// in a group and what each role may do; names, pictures and messages are
/// end-to-end encrypted (CRYPTO_V2.md §7, §9). A group lives on its home
/// server; members on other servers act through it (`federation.dart`).
final class GroupsModule extends ModuleBase implements ProvidesAccountExport {
  GroupsModule(
    super.context, {
    required this.identity,
    required this.messaging,
    required this.people,
  }) {
    _store = GroupStore(schema);
    api = _GroupsFacade(this);
    identity
      ..onAccountDeleted(_accountDeleted)
      ..onDeviceListChanged(_deviceListChanged);
  }

  final IdentityApi identity;
  final MessagingApi messaging;
  final PeopleApi people;
  late final GroupStore _store;
  late final GroupsApi api;
  GroupRelay? _relay;

  /// This server's domain once federation is installed.
  String? get _home => _relay?.localDomain;

  Frame get _localFrame => Frame.local(_home);

  static final _creates = RateLimitPolicy.per(
    'groups.create',
    20,
    const Duration(days: 1),
  );
  static final _previews = RateLimitPolicy.per(
    'groups.preview',
    60,
    const Duration(hours: 1),
  );

  /// Memberships and roles (group names and pictures are encrypted).
  @override
  Future<Object?> exportAccount(SqlSession s, String accountId) async {
    final rows = await s.query(
      'SELECT group_id, role, joined_at FROM $schema.members WHERE account_id = @a:text ORDER BY joined_at',
      {'a': accountId},
    );
    return [
      for (final r in rows)
        {
          'group_id': r.string('group_id'),
          'role': r.string('role'),
          'joined_at': toWireTime(r.time('joined_at')),
        },
      for (final g in await _store.remoteGroupsOf(s, accountId))
        {'group_id': g.groupId, 'home_server': g.home},
    ];
  }

  @override
  String get name => 'groups';

  @override
  List<Migration> get migrations => const [
    Migration(1, 'groups_baseline', GroupStore.baseline),
    Migration(2, 'group_federation', GroupStore.federation),
  ];

  @override
  Map<String, JobHandler> get jobs => {
    _syncJob: _runSync,
    _fanOutJob: _runFanOut,
    _devicesJob: _runDevices,
    _leaveJob: _runLeave,
  };

  late final Map<String, _Op> _ops = {
    'delete': _delete,
    'set_state': _setState,
    'set_settings': _setSettings,
    'add_members': _addMembers,
    'remove_member': _removeMember,
    'set_role': _setRole,
    'ban': _ban,
    'unban': _unban,
    'create_link': _createLink,
    'revoke_link': _revokeLink,
    'preview': _preview,
    'join': _join,
    'join_requests': _joinRequests,
    'resolve_join': _resolveJoin,
    'send': _send,
    'devices': _devices,
  };

  @override
  void routes(RouteRegistry r) {
    r
      ..add(name, Routes.createGroup, _createRoute, maxBodyBytes: 256 * 1024)
      ..add(name, Routes.myGroups, _mine, allowSuspended: true)
      ..add(name, Routes.group, _get, allowSuspended: true)
      ..add(name, Routes.deleteGroup, _scoped('delete'))
      ..add(
        name,
        Routes.setGroupState,
        _scoped('set_state'),
        maxBodyBytes: 256 * 1024,
      )
      ..add(name, Routes.setGroupSettings, _scoped('set_settings'))
      ..add(name, Routes.addGroupMembers, _scoped('add_members'))
      ..add(
        name,
        Routes.removeGroupMember,
        _scoped('remove_member'),
        allowSuspended: true,
      )
      ..add(name, Routes.setGroupRole, _scoped('set_role'))
      ..add(name, Routes.banFromGroup, _scoped('ban'))
      ..add(name, Routes.unbanFromGroup, _scoped('unban'))
      ..add(name, Routes.createInviteLink, _scoped('create_link'))
      ..add(name, Routes.revokeInviteLink, _scoped('revoke_link'))
      ..add(name, Routes.previewInviteLink, _byToken('preview'))
      ..add(name, Routes.joinGroup, _byToken('join'))
      ..add(name, Routes.joinRequests, _scoped('join_requests'))
      ..add(name, Routes.resolveJoinRequest, _scoped('resolve_join'))
      ..add(
        name,
        Routes.sendGroupMessage,
        _scoped('send'),
        maxBodyBytes: 8 * 1024 * 1024,
      );
  }

  // ------------------------------------------------------------- adapters

  _Actor _actorOf(HelixRequest q) =>
      _Actor(q.device.accountId, q.device.deviceId);

  static JsonReader? _bodyOf(HelixRequest q) {
    final bytes = q.body;
    if (bytes == null || bytes.isEmpty) return null;
    return q.json((json) => json);
  }

  /// A group route: run here for groups homed here, or hand it to the home
  /// server for groups homed elsewhere that the caller belongs to.
  RouteHandler _scoped(String action) => (HelixRequest q) async {
    final id = q.uuidParam('group_id');
    final relay = _relay;
    if (relay != null && await _store.group(context.db, id) == null) {
      final home = await _store.remoteHome(context.db, id);
      if (home != null) return _proxy(relay, home, id, action, q);
    }
    return _ops[action]!(_actorOf(q), _localFrame, q.params, _bodyOf(q));
  };

  /// Preview and join: the token names the group's home server.
  RouteHandler _byToken(String action) => (HelixRequest q) async {
    final body = _bodyOf(q);
    final token = _decode(body, InviteTokenRequest.fromJson).token;
    final parts = groupInviteTokenParts(token);
    final relay = _relay;
    if (relay != null &&
        parts.domain != null &&
        parts.domain != relay.localDomain) {
      return _proxy(relay, parts.domain!, parts.groupId!, action, q);
    }
    return _ops[action]!(_actorOf(q), _localFrame, q.params, body);
  };

  Future<Response> _proxy(
    GroupRelay relay,
    String home,
    String groupId,
    String action,
    HelixRequest q,
  ) async {
    final S2SGroupActionResult result;
    try {
      result = await relay.action(
        home,
        groupId,
        S2SGroupAction(
          actor: '${q.device.accountId}@${relay.localDomain}',
          actorDevice: q.device.deviceId,
          action: action,
          params: {...q.params}..remove('group_id'),
          body: _bodyOf(q)?.json,
        ),
      );
    } on RelayUnavailable {
      throw const ApiError(
        ErrorCode.federationUnavailable,
        message: "the group's server cannot be reached",
      );
    }
    final body = result.body;
    return body == null
        ? Response(result.status)
        : jsonResponse(body, status: result.status);
  }

  // ---------------------------------------------------------------- helpers

  Never _notFound() => throw const ApiError(ErrorCode.notFound);

  static T _decode<T>(JsonReader? body, T Function(JsonReader json) decode) {
    if (body == null) {
      throw const ApiError(
        ErrorCode.badRequest,
        message: 'a JSON body is required',
      );
    }
    try {
      return decode(body);
    } on ProtocolFormatException catch (e) {
      throw ApiError(
        ErrorCode.invalidField,
        message: e.path.isEmpty ? 'malformed body' : 'invalid ${e.path}',
        details: e.path.isEmpty ? null : {'field': e.path},
      );
    }
  }

  static String _uuid(Map<String, String> params, String name) {
    final value = params[name];
    if (value == null || !Uuid.isValid(value)) {
      throw ApiError(
        ErrorCode.invalidField,
        message: '$name is not a valid id',
      );
    }
    return value;
  }

  /// The stored form of the `account` path parameter.
  static String _target(Frame frame, Map<String, String> params) =>
      frame.stored(params['account'] ?? '') ??
      (throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'account'},
      ));

  Future<Row> _groupOr404(
    SqlSession db,
    String id, {
    bool forUpdate = false,
  }) async => await _store.group(db, id, forUpdate: forUpdate) ?? _notFound();

  /// The caller's role; members only (others get 404, so group ids do not
  /// leak whether a group exists).
  Future<GroupRole> _requireMember(
    SqlSession db,
    String groupId,
    String accountId,
  ) async => await _store.role(db, groupId, accountId) ?? _notFound();

  bool _allowed(GroupPermission p, GroupRole role) =>
      p == GroupPermission.everyone || role.canAdminister;

  Future<Group> _view(SqlSession db, Row g, Frame frame) async => Group(
    groupId: g.string('id'),
    epoch: g.integer('epoch'),
    stateVersion: g.integer('state_version'),
    encryptedState: g.bytes('encrypted_state'),
    settings: _store.settings(g),
    members: [
      for (final m in await _store.members(db, g.string('id')))
        GroupMember(
          account: frame.view(m.account),
          role: m.role,
          joinedAt: m.joinedAt,
        ),
    ],
    createdAt: g.time('created_at'),
    homeServer: frame.isLocal ? null : frame.home,
  );

  /// Tells every member device (and [also]) what changed, in [tx]: local
  /// devices directly, other servers through queued syncs.
  Future<void> _announce(
    Tx tx,
    String groupId,
    RosterChangeKind change, {
    required String? actor,
    List<String> members = const [],
    List<String> also = const [],
    bool adminsOnly = false,
  }) async {
    final version = await _store.bumpRosterVersion(tx, groupId);
    final roster = await _store.members(tx, groupId);
    final row = await _store.group(tx, groupId);
    final epoch = row?.integer('epoch') ?? 0;
    final accounts = {
      for (final m in roster)
        if (!adminsOnly || m.role.canAdminister) m.account,
      ...also,
    };
    final devices = await identity.activeDevicesOf(
      tx,
      accounts.where(Frame.isLocalId),
    );
    await messaging.deliver(
      tx,
      {
        for (final list in devices.values)
          for (final d in list) d.id: null,
      },
      Delivery(
        kind: EnvelopeKind.rosterChange,
        groupId: groupId,
        data: RosterChangeEvent(
          groupId: groupId,
          change: change,
          epoch: epoch,
          actor: actor,
          members: members,
        ).toJson(),
      ),
    );
    await _queueSyncs(
      tx,
      groupId,
      version: version,
      epoch: epoch,
      change: change,
      actor: actor,
      members: members,
      accounts: accounts.where((a) => !Frame.isLocalId(a)),
    );
  }

  // ----------------------------------------------------------------- routes

  Future<Response> _createRoute(HelixRequest q) {
    return _create(_actorOf(q), _localFrame, q.params, _bodyOf(q));
  }

  Future<Response> _create(
    _Actor actor,
    Frame frame,
    Map<String, String> params,
    JsonReader? body,
  ) async {
    final me = actor.account;
    final decision = await context.rateLimiter.hit(_creates, me);
    if (!decision.allowed) {
      throw ApiError(ErrorCode.rateLimited, retryAfter: decision.retryAfter);
    }
    final req = _decode(body, CreateGroupRequest.fromJson);
    if (!Uuid.isValid(req.groupId) ||
        req.encryptedState.length > Group.maxStateBytes) {
      throw const ApiError(ErrorCode.invalidField);
    }
    final wanted = <String>{};
    for (final input in req.members) {
      final account = frame.stored(input);
      if (account == null) {
        throw const ApiError(
          ErrorCode.invalidField,
          details: {'field': 'members'},
        );
      }
      if (account != me) wanted.add(account);
    }
    if (wanted.length >= Group.maxMembers) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'members'},
      );
    }
    if (await _store.remoteHome(context.db, req.groupId) != null) {
      throw const ApiError(ErrorCode.alreadyExists);
    }
    final group = await context.db.tx((tx) async {
      await _store.insertGroup(
        tx,
        id: req.groupId,
        encryptedState: req.encryptedState,
        settings: req.settings,
      );
      await _store.addMember(tx, req.groupId, me, GroupRole.owner);
      final added = <String>[];
      for (final account in wanted) {
        // Accounts on other servers are checked by their server when the
        // group reaches it (unknown or unwilling ones are removed then).
        if (Frame.isLocalId(account)) {
          if (await identity.account(tx, account) == null) continue;
          if (!await people.mayAddToGroup(tx, adder: me, target: account)) {
            continue;
          }
        }
        await _store.addMember(tx, req.groupId, account, GroupRole.member);
        added.add(account);
      }
      await _announce(
        tx,
        req.groupId,
        RosterChangeKind.created,
        actor: me,
        members: added,
      );
      return _view(tx, (await _store.group(tx, req.groupId))!, frame);
    });
    return jsonResponse(group.toJson(), status: 201);
  }

  Future<Response> _mine(HelixRequest q) async {
    final me = q.device.accountId;
    return jsonResponse(
      GroupList(
        groups: [
          ...await _store.groupsOf(context.db, me),
          for (final g in await _store.remoteGroupsOf(context.db, me))
            GroupSummary(
              groupId: g.groupId,
              epoch: g.epoch,
              stateVersion: g.stateVersion,
            ),
        ],
      ).toJson(),
    );
  }

  Future<Response> _get(HelixRequest q) async {
    final id = q.uuidParam('group_id');
    final me = q.device.accountId;
    final row = await _store.group(context.db, id);
    if (row != null) {
      await _requireMember(context.db, id, me);
      return jsonResponse((await _view(context.db, row, _localFrame)).toJson());
    }
    final relay = _relay;
    final cached = await _store.remoteGroup(context.db, id);
    if (relay == null || cached == null) _notFound();
    if (!(await _store.remoteMembers(context.db, id)).contains(me)) {
      _notFound();
    }
    Group? group;
    try {
      group = await relay.fetchGroup(cached.home, id);
    } on RelayUnavailable {
      // The home server is down: show the last snapshot it sent.
      group = Group.fromJson(JsonReader.of(cached.snapshot));
    }
    if (group == null || !group.members.any((m) => m.account == me)) {
      _notFound();
    }
    return jsonResponse(group.toJson());
  }

  Future<Response> _delete(
    _Actor actor,
    Frame frame,
    Map<String, String> params,
    JsonReader? body,
  ) async {
    final id = _uuid(params, 'group_id');
    final me = actor.account;
    await context.db.tx((tx) async {
      await _groupOr404(tx, id, forUpdate: true);
      if (await _requireMember(tx, id, me) != GroupRole.owner) {
        throw const ApiError(ErrorCode.forbidden);
      }
      await _announce(tx, id, RosterChangeKind.deleted, actor: me);
      await _store.deleteGroup(tx, id);
    });
    return noContent();
  }

  Future<Response> _setState(
    _Actor actor,
    Frame frame,
    Map<String, String> params,
    JsonReader? body,
  ) async {
    final id = _uuid(params, 'group_id');
    final me = actor.account;
    final req = _decode(body, SetGroupStateRequest.fromJson);
    if (req.encryptedState.length > Group.maxStateBytes) {
      throw const ApiError(ErrorCode.payloadTooLarge);
    }
    final version = await context.db.tx((tx) async {
      final g = await _groupOr404(tx, id, forUpdate: true);
      final role = await _requireMember(tx, id, me);
      if (!_allowed(_store.settings(g).editInfo, role)) {
        throw const ApiError(ErrorCode.forbidden);
      }
      final next = await _store.setState(
        tx,
        id,
        req.encryptedState,
        req.expectedVersion,
      );
      if (next == null) throw const ApiError(ErrorCode.versionConflict);
      await _announce(tx, id, RosterChangeKind.stateChanged, actor: me);
      return GroupVersionResponse(
        epoch: g.integer('epoch'),
        stateVersion: next,
      );
    });
    return jsonResponse(version.toJson());
  }

  Future<Response> _setSettings(
    _Actor actor,
    Frame frame,
    Map<String, String> params,
    JsonReader? body,
  ) async {
    final id = _uuid(params, 'group_id');
    final me = actor.account;
    final settings = _decode(body, GroupSettings.fromJson);
    await context.db.tx((tx) async {
      await _groupOr404(tx, id, forUpdate: true);
      if (!(await _requireMember(tx, id, me)).canAdminister) {
        throw const ApiError(ErrorCode.forbidden);
      }
      await _store.setSettings(tx, id, settings);
      await _announce(tx, id, RosterChangeKind.settingsChanged, actor: me);
    });
    return noContent();
  }

  Future<Response> _addMembers(
    _Actor actor,
    Frame frame,
    Map<String, String> params,
    JsonReader? body,
  ) async {
    final id = _uuid(params, 'group_id');
    final me = actor.account;
    final req = _decode(body, AddMembersRequest.fromJson);
    final response = await context.db.tx((tx) async {
      final g = await _groupOr404(tx, id, forUpdate: true);
      final role = await _requireMember(tx, id, me);
      if (!_allowed(_store.settings(g).addMembers, role)) {
        throw const ApiError(ErrorCode.forbidden);
      }
      final added = <String>[];
      final rejected = <String, AddMemberRejection>{};
      var count = await _store.memberCount(tx, id);
      for (final input in req.accounts.toSet()) {
        final account = frame.stored(input);
        final local = account != null && Frame.isLocalId(account);
        if (account == null ||
            (local && await identity.account(tx, account) == null)) {
          rejected[input] = AddMemberRejection.notFound;
        } else if (await _store.role(tx, id, account) != null) {
          rejected[input] = AddMemberRejection.alreadyMember;
        } else if (await _store.isBanned(tx, id, account)) {
          rejected[input] = AddMemberRejection.banned;
        } else if (local &&
            !await people.mayAddToGroup(tx, adder: me, target: account)) {
          rejected[input] = AddMemberRejection.privacy;
        } else if (count >= Group.maxMembers) {
          throw const ApiError(ErrorCode.groupFull);
        } else {
          await _store.addMember(tx, id, account, GroupRole.member);
          added.add(account);
          count++;
        }
      }
      if (added.isNotEmpty) {
        await _announce(
          tx,
          id,
          RosterChangeKind.added,
          actor: me,
          members: added,
        );
      }
      return AddMembersResponse(
        added: [for (final a in added) frame.view(a)],
        rejected: rejected,
        epoch: g.integer('epoch'),
      );
    });
    return jsonResponse(response.toJson());
  }

  /// Removes [target]: a leave if it is [actor] (null when this server
  /// removes someone, e.g. a member's server refused them). Bumps the
  /// epoch, hands ownership on if the owner leaves, and deletes an empty
  /// group.
  Future<int> _remove(
    Tx tx,
    String groupId,
    String? actor,
    String target, {
    bool banned = false,
  }) async {
    final role = await _store.role(tx, groupId, target);
    if (role == null) _notFound();
    await _store.removeMember(tx, groupId, target);
    if (banned) await _store.ban(tx, groupId, target);
    if (!Frame.isLocalId(target)) {
      await _store.forgetRemoteDevicesIfUnused(tx, target);
    }
    final remaining = await _store.members(tx, groupId);
    if (remaining.isEmpty) {
      await _announce(
        tx,
        groupId,
        RosterChangeKind.deleted,
        actor: actor,
        also: [target],
      );
      await _store.deleteGroup(tx, groupId);
      return 0;
    }
    if (role == GroupRole.owner) {
      final heir = remaining.firstWhere(
        (m) => m.role == GroupRole.admin,
        orElse: () => remaining.first,
      );
      await _store.setRole(tx, groupId, heir.account, GroupRole.owner);
    }
    final epoch = await _store.bumpEpoch(tx, groupId);
    await _announce(
      tx,
      groupId,
      actor == target ? RosterChangeKind.left : RosterChangeKind.removed,
      actor: actor,
      members: [target],
      also: [target],
    );
    return epoch;
  }

  Future<Response> _removeMember(
    _Actor actor,
    Frame frame,
    Map<String, String> params,
    JsonReader? body,
  ) async {
    final id = _uuid(params, 'group_id');
    final target = _target(frame, params);
    final me = actor.account;
    final result = await context.db.tx((tx) async {
      final g = await _groupOr404(tx, id, forUpdate: true);
      final myRole = await _requireMember(tx, id, me);
      if (target != me) {
        final theirs = await _store.role(tx, id, target) ?? _notFound();
        if (!myRole.canAdminister || theirs == GroupRole.owner) {
          throw const ApiError(ErrorCode.forbidden);
        }
      }
      final epoch = await _remove(tx, id, me, target);
      return GroupVersionResponse(
        epoch: epoch,
        stateVersion: g.integer('state_version'),
      );
    });
    return jsonResponse(result.toJson());
  }

  Future<Response> _setRole(
    _Actor actor,
    Frame frame,
    Map<String, String> params,
    JsonReader? body,
  ) async {
    final id = _uuid(params, 'group_id');
    final target = _target(frame, params);
    final me = actor.account;
    final role = _decode(body, SetRoleRequest.fromJson).role;
    await context.db.tx((tx) async {
      await _groupOr404(tx, id, forUpdate: true);
      final mine = await _requireMember(tx, id, me);
      final theirs = await _store.role(tx, id, target) ?? _notFound();
      if (!mine.canAdminister || theirs == GroupRole.owner) {
        throw const ApiError(ErrorCode.forbidden);
      }
      if (role == GroupRole.owner) {
        if (mine != GroupRole.owner) throw const ApiError(ErrorCode.forbidden);
        await _store.setRole(tx, id, me, GroupRole.admin);
      }
      await _store.setRole(tx, id, target, role);
      await _announce(
        tx,
        id,
        RosterChangeKind.roleChanged,
        actor: me,
        members: [target],
      );
    });
    return noContent();
  }

  Future<Response> _ban(
    _Actor actor,
    Frame frame,
    Map<String, String> params,
    JsonReader? body,
  ) async {
    final id = _uuid(params, 'group_id');
    final target = _target(frame, params);
    final me = actor.account;
    await context.db.tx((tx) async {
      await _groupOr404(tx, id, forUpdate: true);
      if (!(await _requireMember(tx, id, me)).canAdminister || target == me) {
        throw const ApiError(ErrorCode.forbidden);
      }
      final theirs = await _store.role(tx, id, target);
      if (theirs == GroupRole.owner) throw const ApiError(ErrorCode.forbidden);
      if (theirs != null) {
        await _remove(tx, id, me, target, banned: true);
      } else {
        await _store.ban(tx, id, target);
      }
    });
    return noContent();
  }

  Future<Response> _unban(
    _Actor actor,
    Frame frame,
    Map<String, String> params,
    JsonReader? body,
  ) async {
    final id = _uuid(params, 'group_id');
    if (!(await _requireMember(context.db, id, actor.account)).canAdminister) {
      throw const ApiError(ErrorCode.forbidden);
    }
    await _store.unban(context.db, id, _target(frame, params));
    return noContent();
  }

  Future<Response> _createLink(
    _Actor actor,
    Frame frame,
    Map<String, String> params,
    JsonReader? body,
  ) async {
    final id = _uuid(params, 'group_id');
    final req = _decode(body, CreateInviteLinkRequest.fromJson);
    if (!(await _requireMember(context.db, id, actor.account)).canAdminister) {
      throw const ApiError(ErrorCode.forbidden);
    }
    if (req.encryptedPreview.length > Group.maxStateBytes) {
      throw const ApiError(ErrorCode.payloadTooLarge);
    }
    // With federation, the token names the group and its home server so
    // people on other servers can join through their own.
    final home = _home;
    final secret = 'grp_${encodeBytes(randomBytes(24))}';
    final token = home == null ? secret : '$secret.$id@$home';
    final linkId = Uuid.v7();
    await _store.insertLink(
      context.db,
      id: linkId,
      groupId: id,
      tokenHash: sha256Bytes(token.codeUnits),
      req: req,
    );
    return jsonResponse(
      InviteLink(
        linkId: linkId,
        token: token,
        requiresApproval: req.requiresApproval,
        createdAt: context.clock.now(),
        expiresAt: req.expiresAt,
      ).toJson(),
      status: 201,
    );
  }

  Future<Response> _revokeLink(
    _Actor actor,
    Frame frame,
    Map<String, String> params,
    JsonReader? body,
  ) async {
    final id = _uuid(params, 'group_id');
    if (!(await _requireMember(context.db, id, actor.account)).canAdminister) {
      throw const ApiError(ErrorCode.forbidden);
    }
    if (!await _store.revokeLink(context.db, id, _uuid(params, 'link_id'))) {
      _notFound();
    }
    return noContent();
  }

  /// The live link for [token]; for an S2S action it must belong to the
  /// group the action names.
  Future<Row> _link(String token, Map<String, String> params) async {
    final link =
        await _store.linkByHash(context.db, sha256Bytes(token.codeUnits)) ??
        (throw const ApiError(
          ErrorCode.expired,
          message: 'this link no longer works',
        ));
    final expected = params['group_id'];
    if (expected != null && link.string('group_id') != expected) {
      throw const ApiError(
        ErrorCode.expired,
        message: 'this link no longer works',
      );
    }
    return link;
  }

  Future<Response> _preview(
    _Actor actor,
    Frame frame,
    Map<String, String> params,
    JsonReader? body,
  ) async {
    final decision = await context.rateLimiter.hit(_previews, actor.account);
    if (!decision.allowed) {
      throw ApiError(ErrorCode.rateLimited, retryAfter: decision.retryAfter);
    }
    final link = await _link(
      _decode(body, InviteTokenRequest.fromJson).token,
      params,
    );
    final groupId = link.string('group_id');
    return jsonResponse(
      InvitePreview(
        groupId: groupId,
        memberCount: await _store.memberCount(context.db, groupId),
        requiresApproval: link.boolean('requires_approval'),
        encryptedPreview: link.bytes('encrypted_preview'),
      ).toJson(),
    );
  }

  Future<Response> _join(
    _Actor actor,
    Frame frame,
    Map<String, String> params,
    JsonReader? body,
  ) async {
    final me = actor.account;
    final link = await _link(
      _decode(body, InviteTokenRequest.fromJson).token,
      params,
    );
    final groupId = link.string('group_id');
    final status = await context.db.tx((tx) async {
      await _groupOr404(tx, groupId, forUpdate: true);
      if (await _store.isBanned(tx, groupId, me)) {
        throw const ApiError(ErrorCode.forbidden);
      }
      if (await _store.role(tx, groupId, me) != null) return JoinStatus.joined;
      if (link.boolean('requires_approval')) {
        if (await _store.insertJoinRequest(tx, groupId, me) != null) {
          await _announce(
            tx,
            groupId,
            RosterChangeKind.joinRequested,
            actor: me,
            members: [me],
            adminsOnly: true,
          );
        }
        return JoinStatus.pending;
      }
      if (await _store.memberCount(tx, groupId) >= Group.maxMembers) {
        throw const ApiError(ErrorCode.groupFull);
      }
      await _store.addMember(tx, groupId, me, GroupRole.member);
      await _announce(
        tx,
        groupId,
        RosterChangeKind.added,
        actor: me,
        members: [me],
      );
      return JoinStatus.joined;
    });
    return jsonResponse(
      JoinGroupResponse(groupId: groupId, status: status).toJson(),
    );
  }

  Future<Response> _joinRequests(
    _Actor actor,
    Frame frame,
    Map<String, String> params,
    JsonReader? body,
  ) async {
    final id = _uuid(params, 'group_id');
    if (!(await _requireMember(context.db, id, actor.account)).canAdminister) {
      throw const ApiError(ErrorCode.forbidden);
    }
    return jsonResponse(
      JoinRequestList(
        requests: [
          for (final r in await _store.joinRequests(context.db, id))
            JoinRequest(
              requestId: r.requestId,
              account: frame.view(r.account),
              createdAt: r.createdAt,
            ),
        ],
      ).toJson(),
    );
  }

  Future<Response> _resolveJoin(
    _Actor actor,
    Frame frame,
    Map<String, String> params,
    JsonReader? body,
  ) async {
    final id = _uuid(params, 'group_id');
    final me = actor.account;
    final approve = _decode(body, ResolveJoinRequest.fromJson).approve;
    await context.db.tx((tx) async {
      await _groupOr404(tx, id, forUpdate: true);
      if (!(await _requireMember(tx, id, me)).canAdminister) {
        throw const ApiError(ErrorCode.forbidden);
      }
      final account =
          await _store.takeJoinRequest(tx, id, _uuid(params, 'request_id')) ??
          _notFound();
      if (!approve) return;
      if (await _store.memberCount(tx, id) >= Group.maxMembers) {
        throw const ApiError(ErrorCode.groupFull);
      }
      await _store.addMember(tx, id, account, GroupRole.member);
      await _announce(
        tx,
        id,
        RosterChangeKind.added,
        actor: me,
        members: [account],
      );
    });
    return noContent();
  }

  /// One sender-key ciphertext fanned out to every member device, plus
  /// pairwise sender-key distributions (CRYPTO_V2.md §7). Devices of
  /// members on other servers are reached through those servers.
  Future<Response> _send(
    _Actor actor,
    Frame frame,
    Map<String, String> params,
    JsonReader? body,
  ) async {
    final groupId = _uuid(params, 'group_id');
    final req = _decode(body, GroupMessageRequest.fromJson);
    final senderDevice = actor.device;
    if (!Uuid.isValid(req.id) ||
        senderDevice == null ||
        !Uuid.isValid(senderDevice)) {
      throw const ApiError(ErrorCode.invalidField, details: {'field': 'id'});
    }
    if (req.payload.isEmpty ||
        req.payload.length > SendMessageRequest.maxPayloadBytes) {
      throw const ApiError(ErrorCode.payloadTooLarge);
    }
    final g = await _groupOr404(context.db, groupId);
    final role = await _requireMember(context.db, groupId, actor.account);
    if (!_allowed(_store.settings(g).sendMessages, role)) {
      throw const ApiError(ErrorCode.forbidden);
    }

    // Every member device but the sending one, by stored account.
    final roster = [
      for (final m in await _store.members(context.db, groupId)) m.account,
    ];
    final local = await identity.activeDevicesOf(
      context.db,
      roster.where(Frame.isLocalId),
    );
    final remote = await _store.remoteDevicesOf(
      context.db,
      roster.where((a) => !Frame.isLocalId(a)),
    );
    final byAccount = <String, List<String>>{
      for (final account in roster)
        account: [
          for (final d
              in local[account]?.map((d) => d.id) ??
                  remote[account] ??
                  const <String>[])
            if (d != senderDevice) d,
        ],
    };
    // The sender computes the digest with ids as it sees them.
    final viewed = {
      for (final e in byAccount.entries) frame.view(e.key): e.value,
    };
    if (!constantTimeEquals(membersDigest(viewed), req.devicesDigest)) {
      // The client's view of the group's devices is out of date: send it
      // the full current lists (in `missing`) so it can distribute its
      // sender key and retry.
      throw ApiError(
        ErrorCode.deviceListStale,
        message: 'the group device list changed',
        details: StaleDevices(
          accounts: [
            for (final e in viewed.entries)
              StaleAccountDevices(account: e.key, missing: e.value),
          ],
        ).toJson(),
      );
    }
    final accountOf = {
      for (final e in byAccount.entries)
        for (final d in e.value) d: e.key,
    };
    final distributions = <String, Uint8List>{};
    for (final recipient in req.distributions) {
      for (final d in recipient.devices) {
        if (!accountOf.containsKey(d.device) ||
            d.payload.length > SendMessageRequest.maxPayloadBytes) {
          throw const ApiError(
            ErrorCode.invalidField,
            details: {'field': 'distributions'},
          );
        }
        distributions[d.device] = d.payload;
      }
    }

    final localDevices = [
      for (final e in accountOf.entries)
        if (Frame.isLocalId(e.value)) e.key,
    ];
    final from = EnvelopeSender(account: actor.account, device: senderDevice);
    final fanOut = {for (final d in localDevices) d: req.payload};
    final message = Delivery(
      kind: EnvelopeKind.groupMessage,
      id: req.id,
      from: from,
      groupId: groupId,
      urgent: req.urgent,
    );
    final distribution = Delivery(kind: EnvelopeKind.message, from: from);
    final remoteMessages = _remoteFanOut(
      groupId,
      req,
      actor: actor.account,
      senderDevice: senderDevice,
      accountOf: accountOf,
      distributions: distributions,
    );

    if (req.ephemeral) {
      await messaging.deliverEphemeral(fanOut, message);
      _sendEphemeral(groupId, remoteMessages);
      return jsonResponse(
        SendMessageResponse(acceptedAt: context.clock.now()).toJson(),
      );
    }
    await context.db.tx((tx) async {
      // Distributions first, so each device has the key before the message.
      await messaging.deliver(tx, {
        for (final d in localDevices)
          if (distributions[d] != null) d: distributions[d],
      }, distribution);
      await messaging.deliver(tx, fanOut, message);
      for (final entry in remoteMessages.entries) {
        await context.outbox.enqueue(
          tx,
          _fanOutJob,
          {
            'group_id': groupId,
            'domain': entry.key,
            'message': entry.value.toJson(),
          },
          maxAttempts: 12,
          dedupeKey: 'gfan:${entry.key}:${req.id}',
        );
      }
    });
    return jsonResponse(
      SendMessageResponse(acceptedAt: context.clock.now()).toJson(),
    );
  }

  Future<void> _accountDeleted(Tx tx, String accountId) async {
    for (final groupId in await _store.groupIdsOf(tx, accountId)) {
      await _remove(tx, groupId, accountId, accountId);
    }
    await _leaveRemoteGroups(tx, accountId);
  }
}

final class _GroupsFacade implements GroupsApi {
  _GroupsFacade(this._m);

  final GroupsModule _m;

  @override
  void setRelay(GroupRelay relay) => _m._relay = relay;

  @override
  Future<S2SGroupActionResult> receiveAction(
    String domain,
    String groupId,
    S2SGroupAction action,
  ) => _m._receiveAction(domain, groupId, action);

  @override
  Future<Group?> viewFor(String domain, String groupId) =>
      _m._viewFor(domain, groupId);

  @override
  Future<S2SGroupSyncResponse> receiveSync(
    String domain,
    String groupId,
    S2SGroupSync sync,
  ) => _m._receiveSync(domain, groupId, sync);

  @override
  Future<void> receiveMessage(
    String domain,
    String groupId,
    S2SGroupMessage message,
  ) => _m._receiveMessage(domain, groupId, message);
}
