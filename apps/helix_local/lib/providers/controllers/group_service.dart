import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';
import 'package:helix_local_domain/core/constants.dart';
import 'package:helix_local_domain/domain/models.dart';
import 'package:helix_local_protocol/protocol/protocol_messages.dart';
import 'package:helix_local_transport/services/transport/secure_channel.dart';

import 'package:helix_local_domain/application/contracts/repositories.dart';
import 'package:helix_local_protocol/application/contracts/use_cases.dart';
import 'package:helix_local_groups/helix_groups.dart';

import 'package:helix_local_storage/infrastructure/storage/in_memory_group_repository.dart';

export 'package:helix_local_domain/domain/models.dart'
    show
        GroupVisibility,
        GroupJoinDecision,
        GroupMember,
        GroupSnapshot,
        GroupInvite,
        GroupMessageReceipt;

class GroupCommands {
  static const hostAnnounce = 'host-announce';
  static const handover = 'handover';
  static const joinRequest = 'join-request';
  static const join = 'join';
  static const hostQuery = 'host-query';
  static const approve = 'approve';
  static const deny = 'deny';
  static const kick = 'kick';
  static const block = 'block';
}

class GroupService {
  GroupService({
    GroupRepository? repository,
    CreateGroupUseCase? createGroupUseCase,
    GroupElectionEngineImpl? electionEngine,
    GroupMessageRouterImpl? messageRouter,
  }) {
    _repository = repository ?? InMemoryGroupRepository();
    final gateway = GroupSignalingGatewayAdapter(
      (peerFingerprint) => getChannel(peerFingerprint),
    );

    _createGroupUseCase =
        createGroupUseCase ??
        CreateGroupUseCaseImpl(
          repository: _repository,
          localFingerprint: () => localFingerprint,
          localDisplayName: () => localDisplayName,
          localDeviceSuffix: () => localDeviceSuffix,
          localEndpoint: () => localEndpoint,
          onNotify: () => notify(),
        );

    _electionEngine =
        electionEngine ??
        GroupElectionEngineImpl(
          repository: _repository,
          onNotify: () => notify(),
        );

    _messageRouter =
        messageRouter ??
        GroupMessageRouterImpl(
          repository: _repository,
          gateway: gateway,
          localFingerprint: () => localFingerprint,
          onReceipt: (receipt) => emitMessageReceipt(receipt),
        );
  }

  late final GroupRepository _repository;
  late final CreateGroupUseCase _createGroupUseCase;
  late final GroupElectionEngineImpl _electionEngine;
  late final GroupMessageRouterImpl _messageRouter;

  final _channels = <String, SecureChannel>{};
  final _updates = StreamController<List<GroupSnapshot>>.broadcast();
  final _messages = StreamController<GroupMessageReceipt>.broadcast();

  final _seenEventIds = <String>{};
  final _seenMessageIds = <String>{};

  Future<SecureChannel?> Function(String fingerprint, String endpoint)?
  connectChannelCallback;
  ({String displayName, String deviceSuffix, String endpoint}) Function(
    String fingerprint,
  )?
  resolvePeerDetails;
  List<String> Function()? getActivePeerFingerprints;
  Timer? _announceTimer;
  bool _announcementInFlight = false;

  bool get isInitialized => _localFingerprint.isNotEmpty;

  static const _uuid = Uuid();
  static const publicLobbyId = 'public-lobby';

  String _localFingerprint = '';
  String _localDisplayName = '';
  String _localDeviceSuffix = '';
  String _localEndpoint = '';

  String get localFingerprint => _localFingerprint;
  String get localDisplayName => _localDisplayName;
  String get localDeviceSuffix => _localDeviceSuffix;
  String get localEndpoint => _localEndpoint;

  List<GroupSnapshot> get groups => _snapshotAll();
  Stream<List<GroupSnapshot>> get groupUpdates => _updates.stream;
  Stream<GroupMessageReceipt> get messageReceipts => _messages.stream;

  SecureChannel? getChannel(String peerFingerprint) =>
      _channels[peerFingerprint];

  void notify() {
    _notify();
  }

  void emitMessageReceipt(GroupMessageReceipt receipt) {
    if (!_messages.isClosed) {
      _messages.add(receipt);
    }
  }

  void configureLocalIdentity({
    required String fingerprint,
    required String displayName,
    required String deviceSuffix,
    required String endpoint,
  }) {
    _localFingerprint = fingerprint;
    _localDisplayName = displayName;
    _localDeviceSuffix = deviceSuffix;
    _localEndpoint = endpoint;

    final groupsList = _repository.listGroups();
    for (final group in groupsList) {
      final hasLocal = group.members.any((m) => m.fingerprint == fingerprint);
      if (hasLocal) {
        final updatedMembers = group.members.map((m) {
          if (m.fingerprint == fingerprint) {
            return m.copyWith(
              displayName: displayName,
              deviceSuffix: deviceSuffix,
              endpoint: endpoint,
            );
          }
          return m;
        }).toList();

        var hostEndpoint = group.hostEndpoint;
        if (group.hostFingerprint == fingerprint) {
          hostEndpoint = endpoint;
        }

        final updatedGroup = GroupSnapshot(
          groupId: group.groupId,
          name: group.name,
          visibility: group.visibility,
          hostFingerprint: group.hostFingerprint,
          hostEndpoint: hostEndpoint,
          epoch: group.epoch,
          membershipVersion: group.membershipVersion,
          members: updatedMembers,
          pending: group.pending,
          banned: group.banned,
        );
        _repository.saveGroup(updatedGroup);
      }
    }
    _notify();
  }

  Future<GroupSnapshot> createPublicLobby() async {
    final group = await _createGroupUseCase.createPublicLobby();
    if (group.hostFingerprint == _localFingerprint) {
      startPeriodicAnnouncements();
    }
    return group;
  }

  void startPeriodicAnnouncements() {
    _announceTimer?.cancel();
    _announceTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
      if (_announcementInFlight) return;
      _announcementInFlight = true;
      try {
        final group = _repository.loadGroup(publicLobbyId);
        if (group != null && group.hostFingerprint == _localFingerprint) {
          final announce = buildHostAnnouncement(publicLobbyId);
          await _messageRouter.broadcastControl(group, announce);
        }
      } finally {
        _announcementInFlight = false;
      }
    });
  }

  void stopPeriodicAnnouncements() {
    _announceTimer?.cancel();
    _announceTimer = null;
  }

  Future<void> discoverPublicLobby() async {
    final lf = _localFingerprint;
    if (lf.isEmpty) return;

    final activeFingerprints =
        getActivePeerFingerprints?.call() ?? const <String>[];
    for (final fp in activeFingerprints) {
      try {
        final frame = GroupControlFrame(
          groupId: publicLobbyId,
          eventId: _uuid.v4(),
          command: GroupCommands.hostQuery,
          senderFingerprint: lf,
          epoch: 0,
          membershipVersion: 0,
        );
        final channel = getChannel(fp) ?? await _getOrConnectChannel(fp, '');
        await channel.sendGroupControl(frame);
      } catch (_) {}
    }
  }

  Future<SecureChannel> _getOrConnectChannel(
    String hostFingerprint,
    String hostEndpoint,
  ) async {
    final active = getChannel(hostFingerprint);
    if (active != null) return active;

    final cb = connectChannelCallback;
    if (cb != null) {
      final connected = await cb(hostFingerprint, hostEndpoint);
      if (connected != null) {
        registerPeerChannel(hostFingerprint, connected);
        return connected;
      }
    }
    throw StateError('Could not establish connection to group host');
  }

  Future<void> joinGroup({
    required String groupId,
    required String hostFingerprint,
    required String hostEndpoint,
    int epoch = 0,
  }) async {
    final channel = await _getOrConnectChannel(hostFingerprint, hostEndpoint);
    final frame = GroupControlFrame(
      groupId: groupId,
      eventId: _uuid.v4(),
      command: GroupCommands.join,
      senderFingerprint: _localFingerprint,
      targetFingerprint: _localFingerprint,
      hostFingerprint: hostFingerprint,
      hostEndpoint: hostEndpoint,
      epoch: epoch,
      membershipVersion: 1,
    );
    await channel.sendGroupControl(frame);
  }

  Future<void> connectAndJoin(String inviteCode) async {
    final invite = parseGroupCode(inviteCode);
    if (invite.isExpired) {
      throw StateError('Invite code has expired');
    }
    await joinGroup(
      groupId: invite.groupId,
      hostFingerprint: invite.hostFingerprint,
      hostEndpoint: invite.hostEndpoint,
      epoch: invite.epoch,
    );
  }

  Future<void> executeHandover(
    String groupId,
    String nextHostFingerprint,
  ) async {
    final frame = buildHandover(groupId, nextHostFingerprint);
    final group = _requireGroup(groupId);
    await _messageRouter.broadcastControl(group, frame);
  }

  Future<void> executeKick(String groupId, String targetFingerprint) async {
    final frame = kickMember(groupId, targetFingerprint);
    final group = _requireGroup(groupId);
    await _messageRouter.broadcastControl(group, frame);
  }

  Future<void> executeBlock(String groupId, String targetFingerprint) async {
    final frame = blockMember(groupId, targetFingerprint);
    final group = _requireGroup(groupId);
    await _messageRouter.broadcastControl(group, frame);
  }

  Future<void> executeDecideJoin(
    String groupId,
    String targetFingerprint,
    GroupJoinDecision decision,
  ) async {
    final group = _requireGroup(groupId);
    final isPending = group.pending.any(
      (m) => m.fingerprint == targetFingerprint,
    );
    if (!isPending && decision == GroupJoinDecision.approved) {
      final details = resolvePeerDetails?.call(targetFingerprint);
      final pendingMember = GroupMember(
        fingerprint: targetFingerprint,
        displayName:
            details?.displayName ??
            (targetFingerprint.length >= 8
                ? targetFingerprint.substring(0, 8)
                : targetFingerprint),
        deviceSuffix: details?.deviceSuffix ?? '',
        endpoint: details?.endpoint ?? '',
        joinedAt: DateTime.now(),
      );
      final updatedPending = List<GroupMember>.from(group.pending)
        ..add(pendingMember);
      final updatedGroup = GroupSnapshot(
        groupId: group.groupId,
        name: group.name,
        visibility: group.visibility,
        hostFingerprint: group.hostFingerprint,
        hostEndpoint: group.hostEndpoint,
        epoch: group.epoch,
        membershipVersion: group.membershipVersion,
        members: group.members,
        pending: updatedPending,
        banned: group.banned,
      );
      _repository.saveGroup(updatedGroup);
    }

    final frame = decideJoinRequest(
      groupId: groupId,
      targetFingerprint: targetFingerprint,
      decision: decision,
    );
    final updated = _requireGroup(groupId);
    await _messageRouter.broadcastControl(updated, frame);
    if (decision == GroupJoinDecision.approved) {
      await sendMembershipSync(groupId, targetFingerprint);
    }
  }

  Future<void> sendMembershipSync(
    String groupId,
    String targetFingerprint,
  ) async {
    final group = _requireGroup(groupId);
    final payload = jsonEncode({
      'type': 'sync',
      'members': group.members
          .map(
            (m) => {
              'fingerprint': m.fingerprint,
              'displayName': m.displayName,
              'deviceSuffix': m.deviceSuffix,
              'endpoint': m.endpoint,
              'isAdmin': m.isAdmin,
            },
          )
          .toList(),
    });
    final frame = GroupMessageFrame(
      groupId: groupId,
      messageId: _uuid.v4(),
      senderFingerprint: _localFingerprint,
      epoch: group.epoch,
      membershipVersion: group.membershipVersion,
      sentAt: DateTime.now().millisecondsSinceEpoch,
      encryptedPayload: utf8.encode(payload),
    );
    final channel = getChannel(targetFingerprint);
    if (channel == null) {
      throw StateError('No active channel for group member');
    }
    await channel.sendGroupMessage(frame);
  }

  Future<void> relinquishHosting(
    String winningHost,
    String winningEndpoint,
  ) async {
    final group = _repository.loadGroup(publicLobbyId);
    if (group == null) return;

    final handoverFrame = GroupControlFrame(
      groupId: publicLobbyId,
      eventId: _uuid.v4(),
      command: GroupCommands.handover,
      senderFingerprint: _localFingerprint,
      targetFingerprint: winningHost,
      hostFingerprint: winningHost,
      hostEndpoint: winningEndpoint,
      epoch: group.epoch + 1,
      membershipVersion: group.membershipVersion + 1,
    );
    await _messageRouter.broadcastControl(group, handoverFrame);

    final updated = GroupSnapshot(
      groupId: publicLobbyId,
      name: group.name,
      visibility: group.visibility,
      hostFingerprint: winningHost,
      hostEndpoint: winningEndpoint,
      epoch: group.epoch + 1,
      membershipVersion: group.membershipVersion + 1,
      members: group.members,
      pending: group.pending,
      banned: group.banned,
    );
    _repository.saveGroup(updated);
    stopPeriodicAnnouncements();

    await joinGroup(
      groupId: publicLobbyId,
      hostFingerprint: winningHost,
      hostEndpoint: winningEndpoint,
      epoch: group.epoch + 1,
    );
  }

  Future<void> leaveGroup(String groupId) async {
    final group = _requireGroup(groupId);
    final lf = _localFingerprint;

    if (group.hostFingerprint == lf) {
      final otherMembers = group.members
          .where((m) => m.fingerprint != lf)
          .toList();
      if (otherMembers.isNotEmpty) {
        otherMembers.sort((a, b) => a.fingerprint.compareTo(b.fingerprint));
        final nextHost = otherMembers.first.fingerprint;
        await executeHandover(groupId, nextHost);
      }
    }

    final frame = GroupControlFrame(
      groupId: groupId,
      eventId: _uuid.v4(),
      command: GroupCommands.kick,
      senderFingerprint: lf,
      targetFingerprint: lf,
      hostFingerprint: group.hostFingerprint,
      hostEndpoint: group.hostEndpoint,
      epoch: group.epoch,
      membershipVersion: group.membershipVersion + 1,
    );

    if (group.hostFingerprint == lf) {
      await _messageRouter.broadcastControl(group, frame);
    } else {
      final hostChannel = getChannel(group.hostFingerprint);
      if (hostChannel == null) {
        throw StateError('No active channel for group host');
      }
      await hostChannel.sendGroupControl(frame);
    }

    if (groupId == publicLobbyId) {
      await _repository.removeGroup(groupId);
      await createPublicLobby();
    } else {
      await _repository.removeGroup(groupId);
    }
    stopPeriodicAnnouncements();
    _notify();
  }

  Future<GroupSnapshot> createPrivateGroup({required String name}) =>
      _createGroupUseCase.createPrivateGroup(name);

  String buildGroupCode(
    String groupId, {
    Duration ttl = const Duration(minutes: 30),
  }) {
    final group = _requireGroup(groupId);
    final expiresAt = DateTime.now().add(ttl);
    final payload = jsonEncode({
      'v': 1,
      'gid': group.groupId,
      'host': group.hostEndpoint,
      'hostFp': group.hostFingerprint,
      'epoch': group.epoch,
      'exp': expiresAt.millisecondsSinceEpoch,
    });
    return base64Url.encode(utf8.encode(payload));
  }

  GroupInvite parseGroupCode(String code) {
    final decoded = utf8.decode(base64Url.decode(base64Url.normalize(code)));
    final map = jsonDecode(decoded) as Map<String, dynamic>;
    return GroupInvite(
      groupId: map['gid'] as String,
      hostEndpoint: map['host'] as String,
      hostFingerprint: map['hostFp'] as String,
      epoch: (map['epoch'] as num).toInt(),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (map['exp'] as num).toInt(),
      ),
    );
  }

  GroupControlFrame buildHostAnnouncement(String groupId) {
    final group = _requireGroup(groupId);
    return _control(group, GroupCommands.hostAnnounce);
  }

  GroupControlFrame buildHandover(String groupId, String nextHostFingerprint) {
    final group = _requireGroup(groupId);
    if (!_isLocalAdmin(group)) throw StateError('Only admins can hand over');
    if (!group.members.any((m) => m.fingerprint == nextHostFingerprint)) {
      throw ArgumentError('Next host must be a group member');
    }

    final nextHostMember = group.members.firstWhere(
      (m) => m.fingerprint == nextHostFingerprint,
    );
    final updated = GroupSnapshot(
      groupId: group.groupId,
      name: group.name,
      visibility: group.visibility,
      hostFingerprint: nextHostFingerprint,
      hostEndpoint: nextHostMember.endpoint,
      epoch: group.epoch + 1,
      membershipVersion: group.membershipVersion + 1,
      members: group.members,
      pending: group.pending,
      banned: group.banned,
    );

    _repository.saveGroup(updated);
    _notify();

    return _control(
      updated,
      GroupCommands.handover,
      targetFingerprint: nextHostFingerprint,
      hostFingerprint: nextHostFingerprint,
      hostEndpoint: updated.hostEndpoint,
    );
  }

  GroupSnapshot electHostAfterCrash(
    String groupId, {
    Iterable<String>? activeFingerprints,
  }) {
    return _electionEngine.electHostAfterCrash(
      groupId,
      activeFingerprints: activeFingerprints,
    );
  }

  GroupControlFrame addJoinRequest({
    required String groupId,
    required String fingerprint,
    required String displayName,
    required String deviceSuffix,
    required String endpoint,
  }) {
    final group = _requireGroup(groupId);
    if (group.banned.contains(fingerprint)) {
      return _control(
        group,
        GroupCommands.block,
        targetFingerprint: fingerprint,
      );
    }

    final pendingList = List<GroupMember>.of(group.pending);
    final targetIndex = pendingList.indexWhere(
      (m) => m.fingerprint == fingerprint,
    );
    final newPending = GroupMember(
      fingerprint: fingerprint,
      displayName: displayName,
      deviceSuffix: deviceSuffix,
      endpoint: endpoint,
      joinedAt: DateTime.now(),
    );
    if (targetIndex != -1) {
      pendingList[targetIndex] = newPending;
    } else {
      pendingList.add(newPending);
    }

    final updated = GroupSnapshot(
      groupId: group.groupId,
      name: group.name,
      visibility: group.visibility,
      hostFingerprint: group.hostFingerprint,
      hostEndpoint: group.hostEndpoint,
      epoch: group.epoch,
      membershipVersion: group.membershipVersion + 1,
      members: group.members,
      pending: pendingList,
      banned: group.banned,
    );

    _repository.saveGroup(updated);
    _notify();

    return _control(
      updated,
      GroupCommands.joinRequest,
      targetFingerprint: fingerprint,
    );
  }

  GroupControlFrame decideJoinRequest({
    required String groupId,
    required String targetFingerprint,
    required GroupJoinDecision decision,
  }) {
    final group = _requireGroup(groupId);
    if (!_isLocalAdmin(group)) throw StateError('Only admins can decide joins');

    final pendingList = List<GroupMember>.of(group.pending);
    final targetIndex = pendingList.indexWhere(
      (m) => m.fingerprint == targetFingerprint,
    );
    GroupMember? pending;
    if (targetIndex != -1) {
      pending = pendingList.removeAt(targetIndex);
    }

    final membersList = List<GroupMember>.of(group.members);
    final bannedSet = Set<String>.of(group.banned);

    switch (decision) {
      case GroupJoinDecision.approved:
        if (pending != null) {
          membersList.add(pending);
        } else {
          membersList.add(
            GroupMember(
              fingerprint: targetFingerprint,
              displayName: targetFingerprint,
              deviceSuffix: '',
              endpoint: '',
              joinedAt: DateTime.now(),
            ),
          );
        }
        bannedSet.remove(targetFingerprint);
      case GroupJoinDecision.denied:
        break;
      case GroupJoinDecision.blocked:
        membersList.removeWhere((m) => m.fingerprint == targetFingerprint);
        bannedSet.add(targetFingerprint);
    }

    var updated = GroupSnapshot(
      groupId: group.groupId,
      name: group.name,
      visibility: group.visibility,
      hostFingerprint: group.hostFingerprint,
      hostEndpoint: group.hostEndpoint,
      epoch: group.epoch,
      membershipVersion: group.membershipVersion + 1,
      members: membersList,
      pending: pendingList,
      banned: bannedSet,
    );

    updated = _electHostIfNeeded(updated, bumpEpoch: true);

    _repository.saveGroup(updated);
    _notify();

    return _control(updated, switch (decision) {
      GroupJoinDecision.approved => GroupCommands.approve,
      GroupJoinDecision.denied => GroupCommands.deny,
      GroupJoinDecision.blocked => GroupCommands.block,
    }, targetFingerprint: targetFingerprint);
  }

  GroupControlFrame kickMember(String groupId, String targetFingerprint) {
    final group = _requireGroup(groupId);
    if (!_isLocalAdmin(group)) throw StateError('Only admins can kick');

    final membersList = List<GroupMember>.of(group.members)
      ..removeWhere((m) => m.fingerprint == targetFingerprint);
    final pendingList = List<GroupMember>.of(group.pending)
      ..removeWhere((m) => m.fingerprint == targetFingerprint);

    var updated = GroupSnapshot(
      groupId: group.groupId,
      name: group.name,
      visibility: group.visibility,
      hostFingerprint: group.hostFingerprint,
      hostEndpoint: group.hostEndpoint,
      epoch: group.epoch,
      membershipVersion: group.membershipVersion + 1,
      members: membersList,
      pending: pendingList,
      banned: group.banned,
    );

    updated = _electHostIfNeeded(updated, bumpEpoch: true);

    _repository.saveGroup(updated);
    _notify();

    return _control(
      updated,
      GroupCommands.kick,
      targetFingerprint: targetFingerprint,
    );
  }

  GroupControlFrame blockMember(String groupId, String targetFingerprint) {
    final group = _requireGroup(groupId);
    if (!_isLocalAdmin(group)) throw StateError('Only admins can block');

    final membersList = List<GroupMember>.of(group.members)
      ..removeWhere((m) => m.fingerprint == targetFingerprint);
    final pendingList = List<GroupMember>.of(group.pending)
      ..removeWhere((m) => m.fingerprint == targetFingerprint);
    final bannedSet = Set<String>.of(group.banned)..add(targetFingerprint);

    var updated = GroupSnapshot(
      groupId: group.groupId,
      name: group.name,
      visibility: group.visibility,
      hostFingerprint: group.hostFingerprint,
      hostEndpoint: group.hostEndpoint,
      epoch: group.epoch,
      membershipVersion: group.membershipVersion + 1,
      members: membersList,
      pending: pendingList,
      banned: bannedSet,
    );

    updated = _electHostIfNeeded(updated, bumpEpoch: true);

    _repository.saveGroup(updated);
    _notify();

    return _control(
      updated,
      GroupCommands.block,
      targetFingerprint: targetFingerprint,
    );
  }

  void registerPeerChannel(String peerFingerprint, SecureChannel channel) {
    if (peerFingerprint.isEmpty) return;
    _channels[peerFingerprint] = channel;
  }

  Future<GroupMessageFrame> sendGroupPayload({
    required String groupId,
    required Uint8List encryptedPayload,
  }) async {
    return _messageRouter.sendGroupPayload(
      groupId: groupId,
      encryptedPayload: encryptedPayload,
    );
  }

  Future<void> handleControlFrame({
    required String peerFingerprint,
    required SecureChannel channel,
    required GroupControlFrame frame,
  }) async {
    registerPeerChannel(peerFingerprint, channel);

    if (frame.command == GroupCommands.hostQuery) {
      final group = _repository.loadGroup(frame.groupId);
      if (group != null && group.hostFingerprint == _localFingerprint) {
        final announce = buildHostAnnouncement(frame.groupId);
        try {
          await channel.sendGroupControl(announce);
        } catch (_) {}
      }
      return;
    }

    if (frame.groupId == publicLobbyId &&
        frame.command == GroupCommands.hostAnnounce) {
      final currentGroup = _repository.loadGroup(publicLobbyId);
      final host = frame.hostFingerprint ?? frame.senderFingerprint;
      if (currentGroup != null &&
          currentGroup.hostFingerprint == _localFingerprint &&
          host != _localFingerprint) {
        final localWin = _localFingerprint.compareTo(host) < 0;
        if (!localWin) {
          await relinquishHosting(host, frame.hostEndpoint ?? '');
          return;
        }
      }
    }

    if (frame.command == GroupCommands.handover &&
        frame.groupId == publicLobbyId) {
      final host = frame.hostFingerprint ?? frame.senderFingerprint;
      if (host != _localFingerprint) {
        await joinGroup(
          groupId: publicLobbyId,
          hostFingerprint: host,
          hostEndpoint: frame.hostEndpoint ?? '',
          epoch: frame.epoch,
        );
      }
    }

    if (frame.groupId == publicLobbyId &&
        frame.command == GroupCommands.joinRequest) {
      await executeDecideJoin(
        publicLobbyId,
        frame.senderFingerprint,
        GroupJoinDecision.approved,
      );
      return;
    }

    final accepted = applyControlFrame(frame);
    if (!accepted) return;
    final group = _repository.loadGroup(frame.groupId);
    if (group != null && group.hostFingerprint == _localFingerprint) {
      if (group.groupId == publicLobbyId &&
          frame.command == GroupCommands.join) {
        await executeDecideJoin(
          publicLobbyId,
          frame.senderFingerprint,
          GroupJoinDecision.approved,
        );
        return;
      }
      await _messageRouter.broadcastControl(
        group,
        frame,
        exceptFingerprint: peerFingerprint,
      );
    }
  }

  Future<void> handleMessageFrame({
    required String peerFingerprint,
    required SecureChannel channel,
    required GroupMessageFrame frame,
  }) async {
    registerPeerChannel(peerFingerprint, channel);
    final accepted = applyMessageFrame(frame);
    if (!accepted) return;
    final group = _repository.loadGroup(frame.groupId);
    if (group != null && group.hostFingerprint == _localFingerprint) {
      for (final target in _messageRouter.forwardingTargetsFor(group, frame)) {
        if (target == peerFingerprint) continue;
        try {
          await _channels[target]?.sendGroupMessage(frame);
        } catch (_) {}
      }
    }
  }

  bool applyControlFrame(GroupControlFrame frame) {
    var group = _repository.loadGroup(frame.groupId);
    group ??= GroupSnapshot(
      groupId: frame.groupId,
      name: frame.groupId == publicLobbyId ? 'LAN Lobby' : 'Private group',
      visibility: frame.groupId == publicLobbyId
          ? GroupVisibility.publicLobby
          : GroupVisibility.private,
      hostFingerprint: frame.hostFingerprint ?? frame.senderFingerprint,
      hostEndpoint: frame.hostEndpoint ?? '',
      epoch: 0,
      membershipVersion: 0,
      members: const [],
      pending: const [],
      banned: const {},
    );

    if (_seenEventIds.contains(frame.eventId)) return false;
    if (frame.epoch < group.epoch) return false;
    if (frame.epoch == group.epoch &&
        frame.membershipVersion < group.membershipVersion) {
      return false;
    }

    _seenEventIds.add(frame.eventId);
    if (_seenEventIds.length > kMaxGroupDedupIds) {
      _seenEventIds.remove(_seenEventIds.first);
    }
    var epoch = group.epoch;
    if (frame.epoch > epoch) epoch = frame.epoch;
    var membershipVersion = group.membershipVersion;
    if (frame.membershipVersion > membershipVersion) {
      membershipVersion = frame.membershipVersion;
    }

    var hostFingerprint = group.hostFingerprint;
    var hostEndpoint = group.hostEndpoint;
    final membersList = List<GroupMember>.of(group.members);
    final pendingList = List<GroupMember>.of(group.pending);
    final bannedSet = Set<String>.of(group.banned);

    switch (frame.command) {
      case GroupCommands.hostAnnounce:
      case GroupCommands.handover:
        final host = frame.hostFingerprint ?? frame.senderFingerprint;
        hostFingerprint = host;
        hostEndpoint = frame.hostEndpoint ?? hostEndpoint;

        final hasHost = membersList.any((m) => m.fingerprint == host);
        if (!hasHost) {
          membersList.add(
            GroupMember(
              fingerprint: host,
              displayName: 'Group host',
              deviceSuffix: '',
              endpoint: hostEndpoint,
              joinedAt: DateTime.now(),
              isAdmin: true,
            ),
          );
        }
      case GroupCommands.joinRequest:
        final target = frame.targetFingerprint;
        if (target != null && !bannedSet.contains(target)) {
          final hasPending = pendingList.any((m) => m.fingerprint == target);
          if (!hasPending) {
            pendingList.add(
              GroupMember(
                fingerprint: target,
                displayName: target,
                deviceSuffix: '',
                endpoint: '',
                joinedAt: DateTime.now(),
              ),
            );
          }
        }
      case GroupCommands.approve:
        final target = frame.targetFingerprint;
        if (target != null && !bannedSet.contains(target)) {
          pendingList.removeWhere((m) => m.fingerprint == target);
          final hasMember = membersList.any((m) => m.fingerprint == target);
          if (!hasMember) {
            membersList.add(
              GroupMember(
                fingerprint: target,
                displayName: target,
                deviceSuffix: '',
                endpoint: '',
                joinedAt: DateTime.now(),
              ),
            );
          }
        }
      case GroupCommands.deny:
        final target = frame.targetFingerprint;
        if (target != null) {
          pendingList.removeWhere((m) => m.fingerprint == target);
        }
      case GroupCommands.kick:
        final target = frame.targetFingerprint;
        if (target != null) {
          membersList.removeWhere((m) => m.fingerprint == target);
          pendingList.removeWhere((m) => m.fingerprint == target);
        }
      case GroupCommands.block:
        final target = frame.targetFingerprint;
        if (target != null) {
          membersList.removeWhere((m) => m.fingerprint == target);
          pendingList.removeWhere((m) => m.fingerprint == target);
          bannedSet.add(target);
        }
    }

    var updated = GroupSnapshot(
      groupId: group.groupId,
      name: group.name,
      visibility: group.visibility,
      hostFingerprint: hostFingerprint,
      hostEndpoint: hostEndpoint,
      epoch: epoch,
      membershipVersion: membershipVersion,
      members: membersList,
      pending: pendingList,
      banned: bannedSet,
    );

    updated = _electHostIfNeeded(updated, bumpEpoch: false);
    _repository.saveGroup(updated);
    _notify();
    return true;
  }

  bool applyMessageFrame(GroupMessageFrame frame) {
    final group = _repository.loadGroup(frame.groupId);
    if (group == null) return false;
    if (frame.epoch != group.epoch) return false;
    if (frame.membershipVersion < group.membershipVersion) return false;
    if (group.banned.contains(frame.senderFingerprint)) return false;
    if (!group.members.any((m) => m.fingerprint == frame.senderFingerprint)) {
      return false;
    }
    if (_seenMessageIds.contains(frame.messageId)) return false;

    _seenMessageIds.add(frame.messageId);
    if (_seenMessageIds.length > kMaxGroupDedupIds) {
      _seenMessageIds.remove(_seenMessageIds.first);
    }
    _messages.add(
      GroupMessageReceipt(
        groupId: frame.groupId,
        messageId: frame.messageId,
        senderFingerprint: frame.senderFingerprint,
        encryptedPayload: frame.encryptedPayload,
      ),
    );
    return true;
  }

  List<String> forwardingTargetsFor(GroupMessageFrame frame) {
    final group = _repository.loadGroup(frame.groupId);
    if (group == null || group.hostFingerprint != _localFingerprint) {
      return const [];
    }
    return group.members
        .map((m) => m.fingerprint)
        .where((fp) => fp != _localFingerprint)
        .where((fp) => fp != frame.senderFingerprint)
        .where((fp) => !group.banned.contains(fp))
        .toList()
      ..sort();
  }

  Future<void> dispose() async {
    _announceTimer?.cancel();
    await _updates.close();
    await _messages.close();
  }

  GroupSnapshot _requireGroup(String groupId) {
    final group = _repository.loadGroup(groupId);
    if (group == null) throw ArgumentError('Unknown groupId');
    return group;
  }

  bool _isLocalAdmin(GroupSnapshot group) => group.members.any(
    (m) => m.fingerprint == _localFingerprint && m.isAdmin == true,
  );

  GroupSnapshot _electHostIfNeeded(
    GroupSnapshot group, {
    required bool bumpEpoch,
  }) {
    final hasHost =
        group.members.any((m) => m.fingerprint == group.hostFingerprint) &&
        !group.banned.contains(group.hostFingerprint);
    if (hasHost) return group;

    final eligible =
        group.members
            .where((m) => !group.banned.contains(m.fingerprint))
            .map((m) => m.fingerprint)
            .toList()
          ..sort();
    if (eligible.isEmpty) return group;

    final newHostFp = eligible.first;
    final newHostMember = group.members.firstWhere(
      (m) => m.fingerprint == newHostFp,
    );
    return GroupSnapshot(
      groupId: group.groupId,
      name: group.name,
      visibility: group.visibility,
      hostFingerprint: newHostFp,
      hostEndpoint: newHostMember.endpoint,
      epoch: bumpEpoch ? group.epoch + 1 : group.epoch,
      membershipVersion: group.membershipVersion,
      members: group.members,
      pending: group.pending,
      banned: group.banned,
    );
  }

  GroupControlFrame _control(
    GroupSnapshot group,
    String command, {
    String? targetFingerprint,
    String? hostFingerprint,
    String? hostEndpoint,
  }) {
    final frame = GroupControlFrame(
      groupId: group.groupId,
      eventId: _uuid.v4(),
      command: command,
      senderFingerprint: _localFingerprint,
      targetFingerprint: targetFingerprint,
      hostFingerprint: hostFingerprint ?? group.hostFingerprint,
      hostEndpoint: hostEndpoint ?? group.hostEndpoint,
      epoch: group.epoch,
      membershipVersion: group.membershipVersion,
    );
    _seenEventIds.add(frame.eventId);
    return frame;
  }

  List<GroupSnapshot> _snapshotAll() {
    return _repository.listGroups();
  }

  void _notify() {
    if (!_updates.isClosed) _updates.add(_snapshotAll());
  }
}
