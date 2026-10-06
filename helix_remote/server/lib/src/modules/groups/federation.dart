part of 'module.dart';

// Group federation (Phase S6c). A group lives on its home server, which
// keeps the roster. Members on other servers ("member servers") act through
// S2S actions; the home server pushes snapshots and roster changes to their
// servers (`groups.sync`), fans messages out to them (`groups.fanout`), and
// keeps the devices those servers report for their members. Every payload
// is rendered in the receiving server's frame (`Frame`).

const _syncJob = 'groups.sync';
const _fanOutJob = 'groups.fanout';
const _devicesJob = 'groups.devices';
const _leaveJob = 'groups.leave';

extension on GroupsModule {
  // ------------------------------------------------------------ home side

  /// Queues one sync per other server whose accounts are in [accounts].
  Future<void> _queueSyncs(
    Tx tx,
    String groupId, {
    required int version,
    required int epoch,
    required RosterChangeKind change,
    required String? actor,
    required List<String> members,
    required Iterable<String> accounts,
  }) async {
    final home = _home;
    if (home == null) return;
    final byDomain = <String, List<String>>{};
    for (final account in accounts) {
      byDomain.putIfAbsent(Frame.domainOf(account)!, () => []).add(account);
    }
    for (final entry in byDomain.entries) {
      final frame = Frame.of(home, entry.key);
      await context.outbox.enqueue(tx, _syncJob, {
        'group_id': groupId,
        'domain': entry.key,
        'version': version,
        'event': RosterChangeEvent(
          groupId: groupId,
          change: change,
          epoch: epoch,
          actor: actor == null ? null : frame.view(actor),
          members: [for (final m in members) frame.view(m)],
        ).toJson(),
        'notify': [for (final a in entry.value) frame.view(a)],
      }, maxAttempts: 12);
    }
  }

  Future<void> _runSync(Map<String, Object?> payload) async {
    final relay = _relay;
    final home = _home;
    if (relay == null || home == null) return;
    final groupId = payload['group_id']! as String;
    final domain = payload['domain']! as String;
    final row = await _store.group(context.db, groupId);
    final sync = S2SGroupSync(
      rosterVersion:
          row?.integer('roster_version') ?? payload['version']! as int,
      group: row == null
          ? null
          : await _view(context.db, row, Frame.of(home, domain)),
      event: RosterChangeEvent.fromJson(JsonReader.of(payload['event'])),
      notify: (payload['notify']! as List).cast<String>(),
    );
    final S2SGroupSyncResponse answer;
    try {
      answer = await relay.sync(domain, groupId, sync);
    } on ApiError catch (e) {
      log.warn('group_sync_refused', {'peer': domain, 'code': e.code.wire});
      return;
    }
    // RelayUnavailable propagates: the job retries.
    if (row == null) return;
    await context.db.tx((tx) async {
      if (await _store.group(tx, groupId, forUpdate: true) == null) return;
      for (final entry in answer.devices.entries) {
        final account = '${entry.key}@$domain';
        if (!Uuid.isValid(entry.key) ||
            await _store.role(tx, groupId, account) == null) {
          continue;
        }
        await _store.setRemoteDevices(
          tx,
          account,
          await _foreignDevices(tx, account, entry.value.take(64)),
        );
      }
      for (final bare in answer.rejected) {
        final account = '$bare@$domain';
        if (Uuid.isValid(bare) &&
            await _store.role(tx, groupId, account) != null) {
          await _remove(tx, groupId, null, account);
        }
      }
    });
  }

  /// Per other server: the message for its member devices.
  Map<String, S2SGroupMessage> _remoteFanOut(
    String groupId,
    GroupMessageRequest req, {
    required String actor,
    required String senderDevice,
    required Map<String, String> accountOf,
    required Map<String, Uint8List> distributions,
  }) {
    final home = _home;
    if (home == null) return const {};
    final devicesByDomain = <String, List<String>>{};
    for (final entry in accountOf.entries) {
      final domain = Frame.domainOf(entry.value);
      if (domain != null) {
        devicesByDomain.putIfAbsent(domain, () => []).add(entry.key);
      }
    }
    return {
      for (final entry in devicesByDomain.entries)
        entry.key: S2SGroupMessage(
          id: req.id,
          sender: Frame.of(home, entry.key).view(actor),
          senderDevice: senderDevice,
          payload: req.payload,
          devices: entry.value,
          distributions: [
            for (final d in entry.value)
              if (distributions[d] != null)
                DevicePayload(device: d, payload: distributions[d]!),
          ],
          urgent: req.urgent,
          ephemeral: req.ephemeral,
        ),
    };
  }

  /// Live-only group sends (typing) go out once, best effort.
  void _sendEphemeral(String groupId, Map<String, S2SGroupMessage> messages) {
    final relay = _relay;
    if (relay == null) return;
    for (final entry in messages.entries) {
      unawaited(
        relay.message(entry.key, groupId, entry.value).catchError((_) {}),
      );
    }
  }

  Future<void> _runFanOut(Map<String, Object?> payload) async {
    final relay = _relay;
    if (relay == null) return;
    final domain = payload['domain']! as String;
    try {
      await relay.message(
        domain,
        payload['group_id']! as String,
        S2SGroupMessage.fromJson(JsonReader.of(payload['message'])),
      );
    } on ApiError catch (e) {
      log.warn('group_fanout_refused', {'peer': domain, 'code': e.code.wire});
    }
  }

  Future<S2SGroupActionResult> _receiveAction(
    String domain,
    String groupId,
    S2SGroupAction action,
  ) async {
    final home = _home;
    final op = _ops[action.action];
    final actor = AccountAddress.tryParse(action.actor);
    Response response;
    try {
      if (home == null) {
        throw const ApiError(ErrorCode.federationUnavailable);
      }
      if (actor == null || actor.domain != domain) {
        throw const ApiError(
          ErrorCode.forbidden,
          message: 'the actor must belong to the calling server',
        );
      }
      if (op == null || !Uuid.isValid(groupId)) {
        throw const ApiError(ErrorCode.badRequest, message: 'unknown action');
      }
      response = await op(
        _Actor('${actor.id}@$domain', action.actorDevice),
        Frame.of(home, domain),
        {...action.params, 'group_id': groupId},
        action.body == null ? null : JsonReader.of(action.body),
      );
    } on ApiError catch (e) {
      response = errorResponse(e);
    }
    final text = await response.readAsString();
    return S2SGroupActionResult(
      status: response.statusCode,
      body: text.isEmpty ? null : JsonReader.decode(text).json,
    );
  }

  /// `devices` action: a member's server reports that member's devices.
  Future<Response> _devices(
    _Actor actor,
    Frame frame,
    Map<String, String> params,
    JsonReader? body,
  ) async {
    if (frame.isLocal) throw const ApiError(ErrorCode.forbidden);
    final id = GroupsModule._uuid(params, 'group_id');
    final devices = GroupsModule._decode(body, (j) => j.strings('devices'));
    if (devices.length > 64 || devices.any((d) => !Uuid.isValid(d))) {
      throw const ApiError(
        ErrorCode.invalidField,
        details: {'field': 'devices'},
      );
    }
    await context.db.tx((tx) async {
      await _requireMember(tx, id, actor.account);
      final foreign = await _foreignDevices(tx, actor.account, devices);
      if (foreign.length != devices.toSet().length) {
        throw const ApiError(
          ErrorCode.invalidField,
          message: 'a device id is already in use',
          details: {'field': 'devices'},
        );
      }
      await _store.setRemoteDevices(tx, actor.account, foreign);
    });
    return noContent();
  }

  /// The ids of [devices] that may be [account]'s: well-formed, not a
  /// device of this server, and not reported for another account. Otherwise
  /// a member's server could have another person's copy of each group
  /// message routed to it.
  Future<List<String>> _foreignDevices(
    Tx tx,
    String account,
    Iterable<String> devices,
  ) async => [
    for (final d in devices.toSet())
      if (Uuid.isValid(d) &&
          await identity.device(tx, d) == null &&
          !await _store.remoteDeviceTaken(tx, d, account: account))
        d,
  ];

  Future<Group?> _viewFor(String domain, String groupId) async {
    final home = _home;
    if (home == null || !Uuid.isValid(groupId)) return null;
    final row = await _store.group(context.db, groupId);
    if (row == null) return null;
    final members = await _store.members(context.db, groupId);
    if (!members.any((m) => Frame.domainOf(m.account) == domain)) return null;
    return _view(context.db, row, Frame.of(home, domain));
  }

  // ---------------------------------------------------- member's server

  Future<S2SGroupSyncResponse> _receiveSync(
    String domain,
    String groupId,
    S2SGroupSync sync,
  ) async {
    if (!Uuid.isValid(groupId) ||
        await _store.group(context.db, groupId) != null) {
      throw const ApiError(
        ErrorCode.forbidden,
        message: 'a different group has this id here',
      );
    }
    return context.db.tx((tx) async {
      final cached = await _store.remoteGroup(tx, groupId);
      if (cached != null && cached.home != domain) {
        throw const ApiError(
          ErrorCode.forbidden,
          message: 'the group belongs to another server',
        );
      }
      final group = sync.group;
      final event = sync.event;
      final rejected = <String>[];
      final previous = cached == null
          ? <String>{}
          : await _store.remoteMembers(tx, groupId);
      var keep = <String>{};
      if (group == null) {
        await _store.deleteRemoteGroup(tx, groupId);
      } else if (cached != null && sync.rosterVersion <= cached.version) {
        // An older or repeated snapshot: keep what is cached.
        keep = previous;
      } else {
        // Someone new here, whatever the event says, must exist and have
        // either asked to join through this server, or been added (or the
        // group created) by a member of the snapshot who may add people and
        // whom their group-add privacy and blocks allow.
        final adder = event?.actor;
        GroupRole? adderRole;
        for (final m in group.members) {
          if (m.account == adder) adderRole = m.role;
        }
        final byAdder =
            adder != null &&
            adderRole != null &&
            (event!.change == RosterChangeKind.added ||
                event.change == RosterChangeKind.created) &&
            _allowed(group.settings.addMembers, adderRole);
        final expired = context.clock.now().subtract(
          GroupsModule._joinMarkerLifetime,
        );
        for (final member in group.members) {
          final account = member.account;
          if (account.contains('@') || !Uuid.isValid(account)) continue;
          if (!previous.contains(account)) {
            final allowed =
                await identity.account(tx, account) != null &&
                (await _store.takeRemoteJoin(
                      tx,
                      groupId,
                      account,
                      expired: expired,
                    ) ||
                    (byAdder &&
                        adder != account &&
                        await people.mayAddToGroup(
                          tx,
                          adder: adder,
                          target: account,
                        )));
            if (!allowed) {
              rejected.add(account);
              continue;
            }
          }
          keep.add(account);
        }
        if (keep.isEmpty) {
          await _store.deleteRemoteGroup(tx, groupId);
        } else {
          await _store.saveRemoteGroup(
            tx,
            groupId: groupId,
            home: domain,
            version: sync.rosterVersion,
            snapshot: group.toJson(),
            members: keep,
          );
        }
      }
      if (event != null) {
        // Only people who are, or just were, members here hear about it.
        final targets = {
          for (final a in sync.notify)
            if (keep.contains(a) || previous.contains(a)) a,
        };
        final devices = await identity.activeDevicesOf(tx, targets);
        await messaging.deliver(
          tx,
          {
            for (final list in devices.values)
              for (final d in list) d.id: null,
          },
          Delivery(
            kind: EnvelopeKind.rosterChange,
            groupId: groupId,
            data: event.toJson(),
          ),
        );
      }
      final devices = await identity.activeDevicesOf(tx, keep);
      return S2SGroupSyncResponse(
        devices: {
          for (final a in keep)
            a: [for (final d in devices[a] ?? const <DeviceRecord>[]) d.id],
        },
        rejected: rejected,
      );
    });
  }

  Future<void> _receiveMessage(
    String domain,
    String groupId,
    S2SGroupMessage message,
  ) async {
    final cached = Uuid.isValid(groupId)
        ? await _store.remoteGroup(context.db, groupId)
        : null;
    if (cached == null || cached.home != domain) _notFound();
    final sender = AccountAddress.tryParse(message.sender);
    if (sender == null ||
        !Uuid.isValid(message.senderDevice) ||
        !Uuid.isValid(message.id)) {
      throw const ApiError(ErrorCode.invalidField);
    }
    // People here send through this server, which delivers to its own
    // members itself (`_deliverOwnSend`): the home never speaks for them.
    // Anyone else must be in the group as the home last described it.
    if (sender.domain == null || sender.domain == _home) {
      throw const ApiError(
        ErrorCode.forbidden,
        message: 'the sender cannot be on this server',
      );
    }
    final snapshot = Group.fromJson(JsonReader.of(cached.snapshot));
    if (!snapshot.members.any(
      (m) => AccountAddress.tryParse(m.account) == sender,
    )) {
      throw const ApiError(
        ErrorCode.forbidden,
        message: 'the sender is not a member of the group',
      );
    }
    if (message.payload.isEmpty ||
        message.payload.length > SendMessageRequest.maxPayloadBytes) {
      throw const ApiError(ErrorCode.payloadTooLarge);
    }
    final members = await _store.remoteMembers(context.db, groupId);
    final active = {
      for (final list in (await identity.activeDevicesOf(
        context.db,
        members,
      )).values)
        for (final d in list) d.id,
    };
    // Devices revoked meanwhile are skipped, not refused.
    final targets = message.devices.where(active.contains).toSet();
    final distributions = <String, Uint8List?>{
      for (final d in message.distributions)
        if (targets.contains(d.device) &&
            d.payload.length <= SendMessageRequest.maxPayloadBytes)
          d.device: d.payload,
    };
    await _deliverGroupMessage(
      groupId,
      id: message.id,
      from: EnvelopeSender(
        account: sender.toString(),
        device: message.senderDevice,
      ),
      payload: message.payload,
      targets: targets,
      distributions: distributions,
      urgent: message.urgent,
      ephemeral: message.ephemeral,
    );
  }

  /// A local member's message to a remote group that its home accepted:
  /// this server delivers it to the group's local member devices.
  Future<void> _deliverOwnSend(
    String groupId,
    _Actor actor,
    JsonReader? body,
  ) async {
    final device = actor.device;
    if (device == null) return;
    final req = GroupMessageRequest.fromJson(body!);
    final members = await _store.remoteMembers(context.db, groupId);
    final targets = {
      for (final list in (await identity.activeDevicesOf(
        context.db,
        members,
      )).values)
        for (final d in list)
          if (d.id != device) d.id,
    };
    await _deliverGroupMessage(
      groupId,
      id: req.id,
      from: EnvelopeSender(account: actor.account, device: device),
      payload: req.payload,
      targets: targets,
      distributions: {
        for (final r in req.distributions)
          for (final d in r.devices)
            if (targets.contains(d.device) &&
                d.payload.length <= SendMessageRequest.maxPayloadBytes)
              d.device: d.payload,
      },
      urgent: req.urgent,
      ephemeral: req.ephemeral,
    );
  }

  /// Distributions (pairwise, from [from]) first, then the group message.
  Future<void> _deliverGroupMessage(
    String groupId, {
    required String id,
    required EnvelopeSender from,
    required Uint8List payload,
    required Set<String> targets,
    required Map<String, Uint8List?> distributions,
    required bool urgent,
    required bool ephemeral,
  }) async {
    final fanOut = {for (final d in targets) d: payload};
    final delivery = Delivery(
      kind: EnvelopeKind.groupMessage,
      id: id,
      from: from,
      groupId: groupId,
      urgent: urgent,
    );
    if (ephemeral) {
      await messaging.deliverEphemeral(fanOut, delivery);
      return;
    }
    await context.db.tx((tx) async {
      await messaging.deliver(
        tx,
        distributions,
        Delivery(kind: EnvelopeKind.message, from: from),
      );
      await messaging.deliver(tx, fanOut, delivery);
    });
  }

  /// A local account's devices changed: tell the home server of every
  /// remote group it is in.
  Future<void> _deviceListChanged(
    Tx tx,
    String accountId, {
    String? exceptDevice,
  }) async {
    if (_relay == null) return;
    for (final g in await _store.remoteGroupsOf(tx, accountId)) {
      await context.outbox.enqueue(
        tx,
        _devicesJob,
        {'group_id': g.groupId, 'home': g.home, 'account': accountId},
        maxAttempts: 12,
        dedupeKey: 'gdev:${g.groupId}:$accountId',
      );
    }
  }

  /// A deleted local account leaves every remote group.
  Future<void> _leaveRemoteGroups(Tx tx, String accountId) async {
    if (_relay != null) {
      for (final g in await _store.remoteGroupsOf(tx, accountId)) {
        await context.outbox.enqueue(tx, _leaveJob, {
          'group_id': g.groupId,
          'home': g.home,
          'account': accountId,
        }, maxAttempts: 12);
      }
    }
    await _store.removeRemoteMember(tx, accountId);
  }

  Future<void> _runDevices(Map<String, Object?> payload) async {
    final relay = _relay;
    if (relay == null) return;
    final account = payload['account']! as String;
    final devices = await identity.activeDevices(context.db, account);
    await _runAction(
      relay,
      payload,
      S2SGroupAction(
        actor: '$account@${relay.localDomain}',
        action: 'devices',
        body: {
          'devices': [for (final d in devices) d.id],
        },
      ),
    );
  }

  Future<void> _runLeave(Map<String, Object?> payload) async {
    final relay = _relay;
    if (relay == null) return;
    final account = payload['account']! as String;
    await _runAction(
      relay,
      payload,
      S2SGroupAction(
        actor: '$account@${relay.localDomain}',
        action: 'remove_member',
        params: {'account': account},
      ),
    );
  }

  /// Runs a queued action; RelayUnavailable propagates so the job retries.
  Future<void> _runAction(
    GroupRelay relay,
    Map<String, Object?> payload,
    S2SGroupAction action,
  ) async {
    final home = payload['home']! as String;
    final result = await relay.action(
      home,
      payload['group_id']! as String,
      action,
    );
    if (result.status >= 400) {
      log.warn('group_action_refused', {
        'peer': home,
        'action': action.action,
        'status': result.status,
      });
    }
  }
}
