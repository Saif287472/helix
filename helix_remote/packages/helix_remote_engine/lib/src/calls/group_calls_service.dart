import 'dart:async';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/calls/call_config.dart';
import 'package:helix_remote_engine/src/calls/call_media.dart';
import 'package:helix_remote_engine/src/calls/call_signaling.dart';
import 'package:helix_remote_engine/src/calls/group_call_models.dart';
import 'package:helix_remote_engine/src/errors.dart';
import 'package:helix_remote_engine/src/events.dart';
import 'package:helix_remote_engine/src/groups/group_ids.dart';
import 'package:helix_remote_engine/src/util/ids.dart';
import 'package:helix_remote_engine/src/util/keyed_lock.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Group calls: a room of pairwise calls, at most [CallRoom.maxParticipants]
/// people (ADR-034).
///
/// Every pair in the room has one ordinary call of its own, signalled and
/// encrypted like a 1:1 call; the server sees only pairs of accounts and call
/// ids, never a room. The room travels in the sealed offer (`CallRoom`). The
/// starter offers to the people it invites. Between two invited people who
/// are not the starter, the one with the smaller account id offers, so no
/// pair ever offers both ways. A person who joins answers every offer that
/// reached them while they were ringing, then makes the offers they owe.
///
/// **One call at a time:** a room refuses (`busy`) while a 1:1 call or another
/// room is live, and `CallsService` answers `busy` while this holds a room.
///
/// Everything runs on one queue.
final class GroupCallsService {
  GroupCallsService({
    required this._db,
    required this._signaling,
    required this._clock,
    required this._ids,
    required this._selfAccount,
    required this._emit,
    required this._postLog,
    required this._oneToOneBusy,
    required this._mediaFactory,
    this._config = const CallConfig(),
  });

  final HelixDb _db;
  final CallSignaling _signaling;
  final Clock _clock;
  final IdFactory _ids;
  final String Function() _selfAccount;
  final void Function(EngineEvent event) _emit;

  /// Posts the room's `call_log` entry to its group chat.
  final Future<void> Function(String conversation, CallLogBody body) _postLog;
  final bool Function() _oneToOneBusy;
  final CallConfig _config;

  /// Makes the media session of a link (the host's, the same one 1:1 calls
  /// use). Without one rooms cannot be started or joined (invitations still
  /// ring and can be declined).
  final CallMediaFactory? Function() _mediaFactory;

  final KeyedLock<String> _queue = KeyedLock();
  static const _queueKey = 'group-calls';
  final StreamController<GroupCallSnapshot?> _snapshots =
      StreamController<GroupCallSnapshot?>.broadcast();

  _Room? _room;

  /// Rooms this device left or declined: an offer for one is refused, so a
  /// late offer from another member cannot bring the call back.
  final Set<String> _closed = {};

  // ---------------------------------------------------------------- reading

  /// The room this device is in or is invited to, or null.
  GroupCallSnapshot? get current => _room?.snapshot(_selfAccount());

  /// Whether a room holds this device (a 1:1 call must answer `busy`).
  bool get isBusy => _room != null && !_room!.finished;

  /// The room and every change to it: first as it is now (or null), then a
  /// snapshot per change, then the ended snapshot and null.
  Stream<GroupCallSnapshot?> watchCurrent() {
    late final StreamController<GroupCallSnapshot?> out;
    StreamSubscription<GroupCallSnapshot?>? sub;
    out = StreamController<GroupCallSnapshot?>(
      onListen: () {
        out.add(current);
        sub = _snapshots.stream.listen(out.add);
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  // ---------------------------------------------------------------- actions

  /// Starts a room in [group] (`group:<id>`) and invites [invite] (one to
  /// [CallRoom.maxParticipants] - 1 other members). Throws
  /// [CallFailedException] (`busy`, `blocked`, `noMedia`, `unavailable`) and
  /// [ArgumentError] for a list that is empty, too long, names this user or
  /// someone who is not in the group.
  Future<GroupCallSnapshot> start(
    String group, {
    required Iterable<String> invite,
    bool video = false,
  }) => _run(() => _start(group, invite.toSet().toList(), video));

  /// Joins the room that rings. Throws [CallFailedException] (`noCall`,
  /// `noMedia`).
  Future<void> accept() => _run(_accept);

  /// Declines the invitation: everyone who offered is told.
  Future<void> decline() => _run(() async {
    final room = _room;
    if (room == null || room.phase != GroupCallPhase.ringing) return;
    await _decline(room);
  });

  /// Leaves the room, or declines an invitation that still rings.
  Future<void> hangUp() => _run(() async {
    final room = _room;
    if (room == null || room.finished) return;
    if (room.phase == GroupCallPhase.ringing) {
      await _decline(room);
    } else {
      await _leave(room);
    }
  });

  Future<void> setMuted({required bool muted}) => _run(() async {
    final room = _room;
    if (room == null || room.phase != GroupCallPhase.active) return;
    room.muted = muted;
    for (final link in room.links.values) {
      await link.media?.setMuted(muted: muted);
    }
    _publish(room);
  });

  Future<void> setCameraEnabled({required bool enabled}) => _run(() async {
    final room = _room;
    if (room == null || room.phase != GroupCallPhase.active || !room.video) {
      return;
    }
    room.cameraOn = enabled;
    for (final link in room.links.values) {
      await link.media?.setVideoEnabled(enabled: enabled);
    }
    _publish(room);
  });

  /// Ends the room when the engine stops. Does nothing without one.
  Future<void> release() async {
    final room = _room;
    if (room == null || room.finished) return;
    try {
      await hangUp().timeout(_config.signalTimeout);
    } on Object {
      // Fall through to the local end.
    }
    final still = _room;
    if (still != null) await _finish(still, GroupCallEnd.failed);
  }

  Future<void> close() => _snapshots.close();

  // ------------------------------------------------------------ network in

  /// Whether [payload] belongs to a room: an offer that names one, or any
  /// signal on a link this device holds. `CallsService` hands those over.
  bool claims(CallSignalPayload payload) {
    if (payload.type == CallSignalType.offer) return payload.room != null;
    final room = _room;
    return room != null && room.byCall(payload.callId) != null;
  }

  Future<void> onSignal(
    String account,
    String device,
    CallSignalPayload payload,
  ) => _run(() => _handleSignal(account, device, payload));

  /// An offer fetched from the pending list (this device was offline).
  Future<void> onPendingOffer(
    String account,
    String device,
    CallSignalPayload offer,
  ) => _run(() => _onOffer(account, device, offer));

  // ===================================================================
  // The state machine. Everything below runs on the queue.
  // ===================================================================

  Future<T> _run<T>(Future<T> Function() action) =>
      _queue.run(_queueKey, action);

  DateTime _now() => _clock().toUtc();

  Future<bool> _isBlocked(String account) async =>
      (await _db.peopleDao.byAccount(account))?.blocked ?? false;

  Future<bool> _inGroup(String group, String account) async {
    if (!GroupIds.isGroupConversation(group)) return false;
    return await _db.groupsDao.member(GroupIds.groupIdOf(group), account) !=
        null;
  }

  /// Relay credentials for the pairwise call [callId] of [room] as [role]; a
  /// metered one sets the room's warning and cut-off (the earliest wins).
  /// Throws only [CallFailure.noCallTime].
  Future<List<IceServer>> _relay(
    _Room room,
    String callId,
    CallRole role,
  ) async {
    try {
      final turn = await _signaling.turnCredentials(
        callId: callId,
        role: role,
        video: room.video,
        roomId: room.id,
        groupId: GroupIds.groupIdOf(room.group),
      );
      if (turn == null) return const [];
      if (turn.metered) _meter(room, turn.expiresAt);
      return [
        IceServer(
          urls: turn.urls,
          username: turn.username,
          credential: turn.credential,
        ),
      ];
    } on CallFailedException {
      rethrow;
    } on Object {
      return const [];
    }
  }

  void _meter(_Room room, DateTime endsAt) {
    final current = room.endsAt;
    if (current != null && !endsAt.isBefore(current)) return;
    room.warnTimer?.cancel();
    room.endTimer?.cancel();
    room.endsAt = endsAt;
    final left = endsAt.difference(_now());
    final warnIn = left - _config.callTimeWarning;
    if (warnIn <= Duration.zero) {
      room.endingSoon = true;
    } else {
      room.warnTimer = Timer(
        warnIn,
        () => unawaited(
          _run(() async {
            if (room.finished) return;
            room.endingSoon = true;
            _publish(room);
          }),
        ),
      );
    }
    room.endTimer = Timer(
      left > Duration.zero ? left : Duration.zero,
      () => unawaited(_run(() => _callTimeOver(room))),
    );
  }

  Future<void> _callTimeOver(_Room room) async {
    if (room.finished) return;
    for (final link in room.links.values) {
      await _signalEnd(link, CallEndReason.hangup);
    }
    await _finish(room, GroupCallEnd.callTimeOver);
  }

  // ----------------------------------------------------------- outgoing

  Future<GroupCallSnapshot> _start(
    String group,
    List<String> invite,
    bool video,
  ) async {
    final self = _selfAccount();
    if (invite.isEmpty ||
        invite.length > CallRoom.maxParticipants - 1 ||
        invite.contains(self)) {
      throw ArgumentError.value(invite, 'invite', 'is not 1 to 3 other people');
    }
    if (_room != null || _oneToOneBusy()) {
      throw const CallFailedException(CallFailure.busy);
    }
    final factory = _mediaFactory();
    if (factory == null) throw const CallFailedException(CallFailure.noMedia);
    if (!await _inGroup(group, self)) {
      throw ArgumentError.value(group, 'group', 'is not a group of this user');
    }
    for (final account in invite) {
      if (!await _inGroup(group, account)) {
        throw ArgumentError.value(account, 'invite', 'is not in the group');
      }
      if (await _isBlocked(account)) {
        throw const CallFailedException(CallFailure.blocked);
      }
    }
    final room = _Room(
      id: _ids.next(),
      group: group,
      starter: self,
      incoming: false,
      video: video,
      startedAt: _now(),
      invited: [self, ...invite],
    )..phase = GroupCallPhase.active;
    _room = room;
    room.cameraOn = video;
    _publish(room);
    var sent = 0;
    for (final account in invite) {
      try {
        if (await _offerTo(room, account, factory)) sent++;
      } on CallFailedException {
        // No call time left: the room never starts.
        await _finish(room, GroupCallEnd.failed);
        rethrow;
      }
    }
    if (sent == 0) {
      await _finish(room, GroupCallEnd.failed);
      throw const CallFailedException(CallFailure.unavailable);
    }
    room.ringTimer = Timer(
      _config.ringTimeout,
      () => unawaited(_run(() => _ringTimedOut(room))),
    );
    return room.snapshot(self);
  }

  /// Makes the link to [account] and sends its offer. False when it could not
  /// be made (the person is marked failed; the room goes on).
  Future<bool> _offerTo(
    _Room room,
    String account,
    CallMediaFactory factory,
  ) async {
    if (room.links.containsKey(account)) return true;
    final link = _Link(account: account, callId: _ids.next());
    room.links[account] = link;
    link.state = GroupParticipantState.invited;
    try {
      final media = await factory.create(
        CallMediaConfig(
          video: room.video,
          iceServers: await _relay(room, link.callId, CallRole.caller),
          room: room.id,
          peer: account,
        ),
      );
      link.media = media;
      _wire(room, link);
      final sdp = await media.createOffer();
      await _signaling.send(
        link.callId,
        CallSignalPayload(
          type: CallSignalType.offer,
          callId: link.callId,
          media: room.video ? CallMedia.video : CallMedia.audio,
          sdp: sdp,
          room: CallRoom(
            id: room.id,
            group: room.group,
            participants: room.invited,
          ),
        ),
        account: account,
        ttl: _config.ringTimeout,
      );
      _publish(room);
      return true;
    } on CallFailedException catch (e) {
      await _dropLink(room, link, GroupParticipantState.failed);
      if (e.reason == CallFailure.noCallTime) rethrow;
      return false;
    } on Object {
      await _dropLink(room, link, GroupParticipantState.failed);
      return false;
    }
  }

  Future<void> _ringTimedOut(_Room room) async {
    if (room.finished) return;
    if (room.phase == GroupCallPhase.ringing) {
      // Nobody picked up here: the invitation lapses.
      await _finish(room, GroupCallEnd.unanswered);
      return;
    }
    // Links still ringing are given up on.
    for (final link in room.links.values.toList()) {
      if (link.state == GroupParticipantState.invited && !link.answering) {
        await _signalEnd(link, CallEndReason.cancelled);
        await _dropLink(room, link, GroupParticipantState.failed);
      }
    }
    await _checkAlone(room);
  }

  // ----------------------------------------------------------- incoming

  Future<void> _onOffer(
    String account,
    String device,
    CallSignalPayload offer,
  ) async {
    final self = _selfAccount();
    final info = offer.room;
    if (info == null ||
        account == self ||
        offer.sdp == null ||
        offer.media == null) {
      return;
    }
    // Only people the room names, in a room that fits, in a group both are in.
    if (info.participants.length > CallRoom.maxParticipants ||
        !info.participants.contains(account) ||
        !info.participants.contains(self) ||
        !await _inGroup(info.group, account) ||
        !await _inGroup(info.group, self)) {
      return;
    }
    if (await _isBlocked(account)) return;
    if (_closed.contains(info.id)) {
      await _sendTo(account, device, offer.callId, CallEndReason.declined);
      return;
    }
    var room = _room;
    if (room != null && room.id != info.id ||
        (room == null && _oneToOneBusy())) {
      await _sendTo(account, device, offer.callId, CallEndReason.busy);
      return;
    }
    if (room == null) {
      room = _Room(
        id: info.id,
        group: info.group,
        // The first offer of a room comes from its starter.
        starter: account,
        incoming: true,
        video: offer.media == CallMedia.video,
        startedAt: _now(),
        invited: info.participants,
      );
      _room = room;
      room.ringTimer = Timer(
        _config.ringTimeout + _config.signalTimeout,
        () => unawaited(_run(() => _ringTimedOut(room!))),
      );
    }
    final link = room.links.putIfAbsent(
      account,
      () => _Link(account: account, callId: offer.callId),
    );
    if (link.callId != offer.callId || link.media != null) return; // A repeat.
    link
      ..device = device
      ..offerSdp = offer.sdp
      ..state = GroupParticipantState.invited;
    if (room.phase == GroupCallPhase.ringing) {
      _publish(room);
      if (room.links.length == 1) {
        _emit(IncomingGroupCallEvent(room.snapshot(self)));
      }
      return;
    }
    // Already in the room: this person is answered at once.
    await _answerLink(room, link);
  }

  Future<void> _accept() async {
    final room = _room;
    if (room == null || room.phase != GroupCallPhase.ringing) {
      throw const CallFailedException(CallFailure.noCall);
    }
    final factory = _mediaFactory();
    if (factory == null) throw const CallFailedException(CallFailure.noMedia);
    room
      ..phase = GroupCallPhase.active
      ..cameraOn = room.video;
    room.ringTimer?.cancel();
    final waiting = room.links.values.where((l) => l.offerSdp != null).toList();
    var joined = 0;
    for (final link in waiting) {
      if (await _answerLink(room, link)) joined++;
    }
    if (joined == 0 && room.links.values.every((l) => l.media == null)) {
      await _finish(room, GroupCallEnd.failed);
      throw const CallFailedException(CallFailure.noMedia);
    }
    // Offers this person owes: the smaller account id offers, the starter's
    // pairs are already made.
    final self = _selfAccount();
    for (final other in room.invited) {
      if (other == self || other == room.starter) continue;
      if (room.links.containsKey(other)) continue;
      if (self.compareTo(other) < 0) {
        try {
          await _offerTo(room, other, factory);
        } on CallFailedException {
          // This link is dropped; the call goes on with the others.
        }
      }
    }
    _publish(room);
  }

  /// Answers the offer held on [link]: makes its media, sends the answer.
  Future<bool> _answerLink(_Room room, _Link link) async {
    final factory = _mediaFactory();
    final sdp = link.offerSdp;
    final device = link.device;
    if (factory == null || sdp == null || device == null) return false;
    try {
      final media = await factory.create(
        CallMediaConfig(
          video: room.video,
          iceServers: await _relay(room, link.callId, CallRole.callee),
          room: room.id,
          peer: link.account,
        ),
      );
      link.media = media;
      _wire(room, link);
      final answer = await media.acceptOffer(sdp);
      link
        ..offerSdp = null
        ..remoteReady = true
        ..answering = true
        ..state = GroupParticipantState.connecting;
      await _signaling.send(
        link.callId,
        CallSignalPayload(
          type: CallSignalType.answer,
          callId: link.callId,
          sdp: answer,
        ),
        account: link.account,
        devices: {device},
      );
      link.connectTimer = Timer(
        _config.connectTimeout,
        () => unawaited(_run(() => _connectTimedOut(room, link))),
      );
      await _drainRemote(link, device);
      await _flush(link);
      _publish(room);
      return true;
    } on Object {
      await _signalEnd(link, CallEndReason.failed);
      await _dropLink(room, link, GroupParticipantState.failed);
      return false;
    }
  }

  Future<void> _decline(_Room room) async {
    for (final link in room.links.values) {
      await _signalEnd(link, CallEndReason.declined);
    }
    await _finish(room, GroupCallEnd.declinedByMe);
  }

  Future<void> _leave(_Room room) async {
    for (final link in room.links.values) {
      await _signalEnd(
        link,
        link.state == GroupParticipantState.invited && !link.answering
            ? CallEndReason.cancelled
            : CallEndReason.hangup,
      );
    }
    await _finish(room, GroupCallEnd.hungUp);
  }

  // ------------------------------------------------------------- signals

  Future<void> _handleSignal(
    String account,
    String device,
    CallSignalPayload p,
  ) async {
    if (p.type == CallSignalType.offer) return _onOffer(account, device, p);
    final room = _room;
    final link = room?.byCall(p.callId);
    if (room == null || link == null || link.account != account) return;
    switch (p.type) {
      case CallSignalType.answer:
        await _onAnswer(room, link, device, p);
      case CallSignalType.ice:
        await _onCandidates(link, device, p.candidates);
      case CallSignalType.end:
        await _onEnd(room, link, device, p.reason ?? CallEndReason.unknown);
      case CallSignalType.ringing ||
          CallSignalType.media ||
          CallSignalType.offer ||
          CallSignalType.switchAsk ||
          CallSignalType.switchAccept ||
          CallSignalType.switchDecline ||
          CallSignalType.switchOffer ||
          CallSignalType.switchAnswer ||
          CallSignalType.unknown:
    }
  }

  Future<void> _onAnswer(
    _Room room,
    _Link link,
    String device,
    CallSignalPayload p,
  ) async {
    if (p.sdp == null || link.media == null || link.device != null) return;
    // A link this device offered: the first device to answer is the one.
    link.device = device;
    try {
      await link.media!.acceptAnswer(p.sdp!);
    } on Object {
      await _signalEnd(link, CallEndReason.failed);
      await _dropLink(room, link, GroupParticipantState.failed);
      await _checkAlone(room);
      return;
    }
    link
      ..remoteReady = true
      ..state = GroupParticipantState.connecting;
    link.connectTimer = Timer(
      _config.connectTimeout,
      () => unawaited(_run(() => _connectTimedOut(room, link))),
    );
    _publish(room);
    await _drainRemote(link, device);
    await _flush(link);
  }

  Future<void> _onEnd(
    _Room room,
    _Link link,
    String device,
    CallEndReason reason,
  ) async {
    final bound = link.device;
    if (bound != null && bound != device) return;
    // A person with a different device answering a ringing link is not an end.
    if (reason == CallEndReason.answeredElsewhere && bound == null) return;
    await _dropLink(
      room,
      link,
      reason == CallEndReason.failed
          ? GroupParticipantState.failed
          : GroupParticipantState.left,
    );
    if (room.phase == GroupCallPhase.ringing && link.account == room.starter) {
      // The starter withdrew before this device joined.
      await _finish(room, GroupCallEnd.unanswered);
      return;
    }
    await _checkAlone(room);
  }

  // --------------------------------------------------------------- media

  void _wire(_Room room, _Link link) {
    final media = link.media!;
    link.candidates = media.localCandidates.listen((c) {
      if (link.dropped) return;
      link.outgoing.add(c);
      if (link.device == null || !link.remoteReady) return;
      link.iceTimer ??= Timer(_config.iceBatchDelay, () {
        link.iceTimer = null;
        unawaited(_run(() => _flush(link)));
      });
    });
    link.states = media.states.listen(
      (s) => unawaited(_run(() => _onMediaState(room, link, s))),
    );
  }

  Future<void> _onMediaState(
    _Room room,
    _Link link,
    CallMediaState state,
  ) async {
    if (room.finished || link.dropped) return;
    switch (state) {
      case CallMediaState.connected:
        link.connectTimer?.cancel();
        link.state = GroupParticipantState.connected;
        room.answeredAt ??= _now();
        _publish(room);
      case CallMediaState.failed:
        await _signalEnd(link, CallEndReason.failed);
        await _dropLink(room, link, GroupParticipantState.failed);
        await _checkAlone(room);
      case CallMediaState.disconnected:
        // May recover by itself; the connect timer is not restarted.
        if (link.state == GroupParticipantState.connected) {
          link.state = GroupParticipantState.connecting;
          _publish(room);
        }
      case CallMediaState.connecting || CallMediaState.closed:
    }
  }

  Future<void> _connectTimedOut(_Room room, _Link link) async {
    if (room.finished ||
        link.dropped ||
        link.state == GroupParticipantState.connected) {
      return;
    }
    await _signalEnd(link, CallEndReason.failed);
    await _dropLink(room, link, GroupParticipantState.failed);
    await _checkAlone(room);
  }

  Future<void> _flush(_Link link) async {
    final device = link.device;
    if (link.dropped || device == null || !link.remoteReady) return;
    while (link.outgoing.isNotEmpty) {
      final batch = link.outgoing
          .take(CallSignalPayload.maxCandidates)
          .toList();
      link.outgoing.removeRange(0, batch.length);
      await _best(
        () => _signaling.send(
          link.callId,
          CallSignalPayload(
            type: CallSignalType.ice,
            callId: link.callId,
            candidates: batch,
          ),
          account: link.account,
          devices: {device},
        ),
      );
      if (link.dropped) return;
    }
  }

  Future<void> _onCandidates(
    _Link link,
    String device,
    List<IceCandidatePayload> candidates,
  ) async {
    final bound = link.device;
    if (bound != null && bound != device) return;
    if (bound == null) return; // Nothing is known of this peer yet.
    for (final c in candidates) {
      if (link.queued.length >= _config.maxQueuedCandidates) return;
      link.queued.add(c);
    }
    if (link.remoteReady) await _drainRemote(link, bound);
  }

  Future<void> _drainRemote(_Link link, String device) async {
    final media = link.media;
    if (media == null || link.queued.isEmpty) return;
    final queued = [...link.queued];
    link.queued.clear();
    for (final c in queued) {
      if (link.dropped) return;
      try {
        await media.addRemoteCandidate(c);
      } on Object {
        // A candidate the agent refuses is skipped; the others may connect.
      }
    }
  }

  // ---------------------------------------------------------- finishing

  Future<void> _signalEnd(_Link link, CallEndReason reason) => _best(
    () => _signaling.send(
      link.callId,
      CallSignalPayload(
        type: CallSignalType.end,
        callId: link.callId,
        reason: reason,
      ),
      account: link.account,
      devices: link.device == null ? null : {link.device!},
    ),
  );

  Future<void> _sendTo(
    String account,
    String device,
    String callId,
    CallEndReason reason,
  ) => _best(
    () => _signaling.send(
      callId,
      CallSignalPayload(
        type: CallSignalType.end,
        callId: callId,
        reason: reason,
      ),
      account: account,
      devices: {device},
    ),
  );

  Future<void> _best(Future<Object?> Function() action) async {
    try {
      await action().timeout(_config.signalTimeout);
    } on Object {
      // Best effort: the local state moves on.
    }
  }

  /// Takes a link out of play: its media closes, the person gets [state].
  Future<void> _dropLink(
    _Room room,
    _Link link,
    GroupParticipantState state,
  ) async {
    if (link.dropped) return;
    link
      ..dropped = true
      ..state = state;
    link.connectTimer?.cancel();
    link.iceTimer?.cancel();
    await link.candidates?.cancel();
    await link.states?.cancel();
    try {
      await link.media?.close();
    } on Object {
      // The platform session is gone either way.
    }
    link
      ..media = null
      ..offerSdp = null
      ..queued.clear()
      ..outgoing.clear();
    if (!room.finished) _publish(room);
  }

  /// The room has nobody left to talk to: it ends. Others still ringing or
  /// connecting keep it alive.
  Future<void> _checkAlone(_Room room) async {
    if (room.finished || room.phase != GroupCallPhase.active) return;
    final alive = room.links.values.any((l) => !l.dropped);
    // Participants who owe an offer to this device may still arrive.
    final self = _selfAccount();
    final waiting = room.invited.any(
      (a) =>
          a != self &&
          !room.links.containsKey(a) &&
          a != room.starter &&
          a.compareTo(self) < 0,
    );
    if (alive || (waiting && room.answeredAt == null)) return;
    await _finish(
      room,
      room.answeredAt == null
          ? GroupCallEnd.unanswered
          : GroupCallEnd.everyoneLeft,
    );
  }

  Future<void> _finish(_Room room, GroupCallEnd end) async {
    if (room.finished) return;
    room
      ..finished = true
      ..phase = GroupCallPhase.ended
      ..end = end
      ..endedAt = _now();
    room.ringTimer?.cancel();
    room.warnTimer?.cancel();
    room.endTimer?.cancel();
    _closed.add(room.id);
    for (final link in room.links.values) {
      await _dropLink(room, link, link.state);
    }
    final snapshot = room.snapshot(_selfAccount());
    _snapshots.add(snapshot);
    if (identical(_room, room)) _room = null;
    // The starter's phone tells the group chat how the call went, as the
    // caller's phone does for a 1:1 call.
    if (!room.incoming) {
      final answered = room.answeredAt;
      await _best(
        () => _postLog(
          room.group,
          CallLogBody(
            callId: room.id,
            media: room.video ? CallMedia.video : CallMedia.audio,
            outcome: answered == null
                ? (end == GroupCallEnd.failed
                      ? CallOutcome.failed
                      : CallOutcome.missed)
                : CallOutcome.answered,
            durationS: answered == null
                ? null
                : room.endedAt!.difference(answered).inSeconds,
          ),
        ),
      );
    }
    _snapshots.add(null);
  }

  void _publish(_Room room) => _snapshots.add(room.snapshot(_selfAccount()));
}

/// One room's mutable state, touched only on the service's queue.
final class _Room {
  _Room({
    required this.id,
    required this.group,
    required this.starter,
    required this.incoming,
    required this.video,
    required this.startedAt,
    required this.invited,
  }) : phase = incoming ? GroupCallPhase.ringing : GroupCallPhase.active;

  final String id;
  final String group;
  final String starter;
  final bool incoming;
  final bool video;
  final DateTime startedAt;

  /// Everyone the room was made for, this user included.
  final List<String> invited;
  final Map<String, _Link> links = {};
  GroupCallPhase phase;
  DateTime? answeredAt;
  DateTime? endedAt;
  GroupCallEnd? end;
  bool finished = false;
  bool muted = false;
  bool cameraOn = false;
  Timer? ringTimer;

  /// A metered room: when its call time ends, and the timers for it.
  DateTime? endsAt;
  bool endingSoon = false;
  Timer? warnTimer;
  Timer? endTimer;

  _Link? byCall(String callId) {
    for (final link in links.values) {
      if (link.callId == callId) return link;
    }
    return null;
  }

  GroupCallSnapshot snapshot(String self) => GroupCallSnapshot(
    roomId: id,
    group: group,
    starter: starter,
    isIncoming: incoming,
    video: video,
    phase: phase,
    startedAt: startedAt,
    answeredAt: answeredAt,
    endedAt: endedAt,
    end: end,
    muted: muted,
    cameraOn: cameraOn,
    endsAt: endsAt,
    endingSoon: endingSoon,
    participants: [
      for (final account in invited)
        if (account != self)
          GroupCallParticipant(
            account,
            links[account]?.state ?? GroupParticipantState.invited,
          ),
    ],
  );
}

/// One pairwise call of a room.
final class _Link {
  _Link({required this.account, required this.callId});

  final String account;
  final String callId;
  GroupParticipantState state = GroupParticipantState.invited;

  /// The peer device this link talks to, once known.
  String? device;
  CallMediaSession? media;

  /// The offer that rang this device, kept until the room is joined.
  String? offerSdp;
  bool answering = false;
  bool remoteReady = false;
  bool dropped = false;
  final List<IceCandidatePayload> outgoing = [];
  final List<IceCandidatePayload> queued = [];
  StreamSubscription<IceCandidatePayload>? candidates;
  StreamSubscription<CallMediaState>? states;
  Timer? connectTimer;
  Timer? iceTimer;
}
