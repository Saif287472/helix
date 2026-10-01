import 'dart:typed_data';

import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:helix_remote_server/src/kernel/crypto.dart';
import 'package:helix_remote_server/src/modules/groups/data/group_store.dart';
import 'package:helix_remote_server/src/modules/identity/api.dart';
import 'package:helix_remote_server/src/modules/messaging/api.dart';
import 'package:helix_remote_server/src/modules/people/api.dart';
import 'package:helix_remote_server/src/platform/db/db.dart';
import 'package:helix_remote_server/src/platform/db/migrations.dart';
import 'package:helix_remote_server/src/platform/http/request.dart';
import 'package:helix_remote_server/src/platform/http/routes.dart';
import 'package:helix_remote_server/src/platform/module.dart';
import 'package:helix_remote_server/src/platform/ratelimit/rate_limiter.dart';
import 'package:shelf/shelf.dart';

/// Group roster authority (REST_V2.md "groups"). The server enforces who is
/// in a group and what each role may do; names, pictures and messages are
/// end-to-end encrypted (CRYPTO_V2.md §7, §9).
final class GroupsModule extends ModuleBase implements ProvidesAccountExport {
  GroupsModule(
    super.context, {
    required this.identity,
    required this.messaging,
    required this.people,
  }) {
    _store = GroupStore(schema);
    identity.onAccountDeleted(_accountDeleted);
  }

  final IdentityApi identity;
  final MessagingApi messaging;
  final PeopleApi people;
  late final GroupStore _store;

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
      'SELECT group_id, role, joined_at FROM $schema.members WHERE account_id = @a:uuid ORDER BY joined_at',
      {'a': accountId},
    );
    return [
      for (final r in rows)
        {
          'group_id': r.string('group_id'),
          'role': r.string('role'),
          'joined_at': toWireTime(r.time('joined_at')),
        },
    ];
  }

  @override
  String get name => 'groups';

  @override
  List<Migration> get migrations => const [
    Migration(1, 'groups_baseline', GroupStore.baseline),
  ];

  @override
  void routes(RouteRegistry r) {
    r
      ..add(name, Routes.createGroup, _create, maxBodyBytes: 256 * 1024)
      ..add(name, Routes.myGroups, _mine, allowSuspended: true)
      ..add(name, Routes.group, _get, allowSuspended: true)
      ..add(name, Routes.deleteGroup, _delete)
      ..add(name, Routes.setGroupState, _setState, maxBodyBytes: 256 * 1024)
      ..add(name, Routes.setGroupSettings, _setSettings)
      ..add(name, Routes.addGroupMembers, _addMembers)
      ..add(name, Routes.removeGroupMember, _removeMember, allowSuspended: true)
      ..add(name, Routes.setGroupRole, _setRole)
      ..add(name, Routes.banFromGroup, _ban)
      ..add(name, Routes.unbanFromGroup, _unban)
      ..add(name, Routes.createInviteLink, _createLink)
      ..add(name, Routes.revokeInviteLink, _revokeLink)
      ..add(name, Routes.previewInviteLink, _preview)
      ..add(name, Routes.joinGroup, _join)
      ..add(name, Routes.joinRequests, _joinRequests)
      ..add(name, Routes.resolveJoinRequest, _resolveJoin)
      ..add(
        name,
        Routes.sendGroupMessage,
        _send,
        maxBodyBytes: 8 * 1024 * 1024,
      );
  }

  // ---------------------------------------------------------------- helpers

  Never _notFound() => throw const ApiError(ErrorCode.notFound);

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

  Future<Group> _view(SqlSession db, Row g) async => Group(
    groupId: g.string('id'),
    epoch: g.integer('epoch'),
    stateVersion: g.integer('state_version'),
    encryptedState: g.bytes('encrypted_state'),
    settings: _store.settings(g),
    members: await _store.members(db, g.string('id')),
    createdAt: g.time('created_at'),
  );

  /// Tells every member device (and [also]) what changed, in [tx].
  Future<void> _announce(
    Tx tx,
    String groupId,
    RosterChangeKind change, {
    required String? actor,
    List<String> members = const [],
    List<String> also = const [],
    bool adminsOnly = false,
  }) async {
    final roster = await _store.members(tx, groupId);
    final row = await _store.group(tx, groupId);
    final epoch = row?.integer('epoch') ?? 0;
    final accounts = {
      for (final m in roster)
        if (!adminsOnly || m.role.canAdminister) m.account,
      ...also,
    };
    final devices = await identity.activeDevicesOf(tx, accounts);
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
  }

  // ----------------------------------------------------------------- routes

  Future<Response> _create(HelixRequest q) async {
    final me = q.device.accountId;
    final decision = await context.rateLimiter.hit(_creates, me);
    if (!decision.allowed) {
      throw ApiError(ErrorCode.rateLimited, retryAfter: decision.retryAfter);
    }
    final req = q.json(CreateGroupRequest.fromJson);
    if (!Uuid.isValid(req.groupId) ||
        req.encryptedState.length > Group.maxStateBytes) {
      throw const ApiError(ErrorCode.invalidField);
    }
    final wanted = req.members.toSet()..remove(me);
    if (wanted.any((a) => !Uuid.isValid(a)) ||
        wanted.length >= Group.maxMembers) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'members'},
      );
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
        if (await identity.account(tx, account) == null) continue;
        if (!await people.mayAddToGroup(tx, adder: me, target: account)) {
          continue;
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
      return _view(tx, (await _store.group(tx, req.groupId))!);
    });
    return jsonResponse(group.toJson(), status: 201);
  }

  Future<Response> _mine(HelixRequest q) async => jsonResponse(
    GroupList(
      groups: await _store.groupsOf(context.db, q.device.accountId),
    ).toJson(),
  );

  Future<Response> _get(HelixRequest q) async {
    final id = q.uuidParam('group_id');
    await _requireMember(context.db, id, q.device.accountId);
    return jsonResponse(
      (await _view(context.db, await _groupOr404(context.db, id))).toJson(),
    );
  }

  Future<Response> _delete(HelixRequest q) async {
    final id = q.uuidParam('group_id');
    final me = q.device.accountId;
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

  Future<Response> _setState(HelixRequest q) async {
    final id = q.uuidParam('group_id');
    final me = q.device.accountId;
    final req = q.json(SetGroupStateRequest.fromJson);
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

  Future<Response> _setSettings(HelixRequest q) async {
    final id = q.uuidParam('group_id');
    final me = q.device.accountId;
    final settings = q.json(GroupSettings.fromJson);
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

  Future<Response> _addMembers(HelixRequest q) async {
    final id = q.uuidParam('group_id');
    final me = q.device.accountId;
    final req = q.json(AddMembersRequest.fromJson);
    final response = await context.db.tx((tx) async {
      final g = await _groupOr404(tx, id, forUpdate: true);
      final role = await _requireMember(tx, id, me);
      if (!_allowed(_store.settings(g).addMembers, role)) {
        throw const ApiError(ErrorCode.forbidden);
      }
      final added = <String>[];
      final rejected = <String, AddMemberRejection>{};
      var count = await _store.memberCount(tx, id);
      for (final account in req.accounts.toSet()) {
        if (!Uuid.isValid(account) ||
            await identity.account(tx, account) == null) {
          rejected[account] = AddMemberRejection.notFound;
        } else if (await _store.role(tx, id, account) != null) {
          rejected[account] = AddMemberRejection.alreadyMember;
        } else if (await _store.isBanned(tx, id, account)) {
          rejected[account] = AddMemberRejection.banned;
        } else if (!await people.mayAddToGroup(
          tx,
          adder: me,
          target: account,
        )) {
          rejected[account] = AddMemberRejection.privacy;
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
        added: added,
        rejected: rejected,
        epoch: g.integer('epoch'),
      );
    });
    return jsonResponse(response.toJson());
  }

  /// Removes [target]: a leave if it is [actor]. Bumps the epoch, hands
  /// ownership on if the owner leaves, and deletes an empty group.
  Future<int> _remove(
    Tx tx,
    String groupId,
    String actor,
    String target, {
    bool banned = false,
  }) async {
    final role = await _store.role(tx, groupId, target);
    if (role == null) _notFound();
    await _store.removeMember(tx, groupId, target);
    if (banned) await _store.ban(tx, groupId, target);
    final remaining = await _store.members(tx, groupId);
    if (remaining.isEmpty) {
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

  Future<Response> _removeMember(HelixRequest q) async {
    final id = q.uuidParam('group_id');
    final target = q.uuidParam('account');
    final me = q.device.accountId;
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

  Future<Response> _setRole(HelixRequest q) async {
    final id = q.uuidParam('group_id');
    final target = q.uuidParam('account');
    final me = q.device.accountId;
    final role = q.json(SetRoleRequest.fromJson).role;
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

  Future<Response> _ban(HelixRequest q) async {
    final id = q.uuidParam('group_id');
    final target = q.uuidParam('account');
    final me = q.device.accountId;
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

  Future<Response> _unban(HelixRequest q) async {
    final id = q.uuidParam('group_id');
    if (!(await _requireMember(
      context.db,
      id,
      q.device.accountId,
    )).canAdminister) {
      throw const ApiError(ErrorCode.forbidden);
    }
    await _store.unban(context.db, id, q.uuidParam('account'));
    return noContent();
  }

  Future<Response> _createLink(HelixRequest q) async {
    final id = q.uuidParam('group_id');
    final req = q.json(CreateInviteLinkRequest.fromJson);
    if (!(await _requireMember(
      context.db,
      id,
      q.device.accountId,
    )).canAdminister) {
      throw const ApiError(ErrorCode.forbidden);
    }
    if (req.encryptedPreview.length > Group.maxStateBytes) {
      throw const ApiError(ErrorCode.payloadTooLarge);
    }
    final token = 'grp_${encodeBytes(randomBytes(24))}';
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

  Future<Response> _revokeLink(HelixRequest q) async {
    final id = q.uuidParam('group_id');
    if (!(await _requireMember(
      context.db,
      id,
      q.device.accountId,
    )).canAdminister) {
      throw const ApiError(ErrorCode.forbidden);
    }
    if (!await _store.revokeLink(context.db, id, q.uuidParam('link_id'))) {
      _notFound();
    }
    return noContent();
  }

  Future<Row> _link(String token) async =>
      await _store.linkByHash(context.db, sha256Bytes(token.codeUnits)) ??
      (throw const ApiError(
        ErrorCode.expired,
        message: 'this link no longer works',
      ));

  Future<Response> _preview(HelixRequest q) async {
    final decision = await context.rateLimiter.hit(
      _previews,
      q.device.accountId,
    );
    if (!decision.allowed) {
      throw ApiError(ErrorCode.rateLimited, retryAfter: decision.retryAfter);
    }
    final link = await _link(q.json(InviteTokenRequest.fromJson).token);
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

  Future<Response> _join(HelixRequest q) async {
    final me = q.device.accountId;
    final link = await _link(q.json(InviteTokenRequest.fromJson).token);
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

  Future<Response> _joinRequests(HelixRequest q) async {
    final id = q.uuidParam('group_id');
    if (!(await _requireMember(
      context.db,
      id,
      q.device.accountId,
    )).canAdminister) {
      throw const ApiError(ErrorCode.forbidden);
    }
    return jsonResponse(
      JoinRequestList(
        requests: await _store.joinRequests(context.db, id),
      ).toJson(),
    );
  }

  Future<Response> _resolveJoin(HelixRequest q) async {
    final id = q.uuidParam('group_id');
    final me = q.device.accountId;
    final approve = q.json(ResolveJoinRequest.fromJson).approve;
    await context.db.tx((tx) async {
      await _groupOr404(tx, id, forUpdate: true);
      if (!(await _requireMember(tx, id, me)).canAdminister) {
        throw const ApiError(ErrorCode.forbidden);
      }
      final account =
          await _store.takeJoinRequest(tx, id, q.uuidParam('request_id')) ??
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
  /// pairwise sender-key distributions (CRYPTO_V2.md §7).
  Future<Response> _send(HelixRequest q) async {
    final groupId = q.uuidParam('group_id');
    final me = q.device;
    final req = q.json(GroupMessageRequest.fromJson);
    if (!Uuid.isValid(req.id)) {
      throw const ApiError(ErrorCode.invalidField, details: {'field': 'id'});
    }
    if (req.payload.isEmpty ||
        req.payload.length > SendMessageRequest.maxPayloadBytes) {
      throw const ApiError(ErrorCode.payloadTooLarge);
    }
    final g = await _groupOr404(context.db, groupId);
    final role = await _requireMember(context.db, groupId, me.accountId);
    if (!_allowed(_store.settings(g).sendMessages, role)) {
      throw const ApiError(ErrorCode.forbidden);
    }

    final roster = await _store.members(context.db, groupId);
    final devices = await identity.activeDevicesOf(
      context.db,
      roster.map((m) => m.account),
    );
    final byAccount = {
      for (final e in devices.entries)
        e.key: [
          for (final d in e.value)
            if (d.id != me.deviceId) d.id,
        ],
    };
    if (!constantTimeEquals(membersDigest(byAccount), req.devicesDigest)) {
      // The client's view of the group's devices is out of date: send it
      // the full current lists (in `missing`) so it can distribute its
      // sender key and retry.
      throw ApiError(
        ErrorCode.deviceListStale,
        message: 'the group device list changed',
        details: StaleDevices(
          accounts: [
            for (final e in byAccount.entries)
              StaleAccountDevices(account: e.key, missing: e.value),
          ],
        ).toJson(),
      );
    }
    final memberDevices = {for (final list in byAccount.values) ...list};
    final distributions = <String, Uint8List>{};
    for (final recipient in req.distributions) {
      for (final d in recipient.devices) {
        if (!memberDevices.contains(d.device) ||
            d.payload.length > SendMessageRequest.maxPayloadBytes) {
          throw const ApiError(
            ErrorCode.invalidField,
            details: {'field': 'distributions'},
          );
        }
        distributions[d.device] = d.payload;
      }
    }
    final from = EnvelopeSender(account: me.accountId, device: me.deviceId);
    final fanOut = {for (final d in memberDevices) d: req.payload};
    final message = Delivery(
      kind: EnvelopeKind.groupMessage,
      id: req.id,
      from: from,
      groupId: groupId,
      urgent: req.urgent,
    );
    final distribution = Delivery(kind: EnvelopeKind.message, from: from);

    if (req.ephemeral) {
      await messaging.deliverEphemeral(fanOut, message);
      return jsonResponse(
        SendMessageResponse(acceptedAt: context.clock.now()).toJson(),
      );
    }
    await context.db.tx((tx) async {
      // Distributions first, so each device has the key before the message.
      await messaging.deliver(tx, distributions, distribution);
      await messaging.deliver(tx, fanOut, message);
    });
    return jsonResponse(
      SendMessageResponse(acceptedAt: context.clock.now()).toJson(),
    );
  }

  Future<void> _accountDeleted(Tx tx, String accountId) async {
    for (final groupId in await _store.groupIdsOf(tx, accountId)) {
      await _remove(tx, groupId, accountId, accountId);
    }
  }
}
