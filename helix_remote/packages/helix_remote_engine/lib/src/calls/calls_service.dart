import 'dart:async';

import 'package:helix_remote_api/v2.dart' show ApiException;
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/calls/call_config.dart';
import 'package:helix_remote_engine/src/calls/call_media.dart';
import 'package:helix_remote_engine/src/calls/call_models.dart';
import 'package:helix_remote_engine/src/calls/call_signaling.dart';
import 'package:helix_remote_engine/src/calls/group_calls_service.dart';
import 'package:helix_remote_engine/src/errors.dart';
import 'package:helix_remote_engine/src/events.dart';
import 'package:helix_remote_engine/src/messaging/kinds.dart';
import 'package:helix_remote_engine/src/settings_keys.dart';
import 'package:helix_remote_engine/src/util/ids.dart';
import 'package:helix_remote_engine/src/util/keyed_lock.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// 1:1 calls: the signalling state machine (plan §6.3, C4-K).
///
/// The engine owns only the call's STATE; the media (the WebRTC peer
/// connection) is a [CallMediaSession] the host provides through
/// [mediaFactory], so this class is pure Dart and the same code runs in the
/// app, the CLI and tests.
///
/// **One call at a time.** An offer that arrives while this device is in a
/// call is answered with `busy` and logged as missed.
///
/// **Flow.** The caller creates the offer, seals it for every active device
/// of the callee and posts it. Online devices ring at once (and answer
/// `ringing`); offline devices have a pending offer on the server and a push,
/// and ring when [fetchPending] reads it. A callee device that accepts sends
/// its `answer` to the caller's device and tells the server (`answered`), which
/// stops the account's other devices ringing; the caller then sends its ICE
/// candidates to that device alone. A second answer from another device is
/// refused with `answered_elsewhere`. Either side hangs up with an `end`
/// signal to the device it talks to; a caller that cancels before an answer
/// ends every callee device.
///
/// **Glare** (both call each other at once): the call with the smaller id
/// survives on both ends; the loser ends with `glare` and its row is
/// forgotten.
///
/// **Privacy.** Signals are sealed per device; SDP and ICE live only in
/// memory for the length of a call and are never written down or logged.
/// `call_log` keeps the fact and the timings. The server drops a call from a
/// caller that the callee blocked without telling it: the caller's call just
/// rings until it times out, exactly as for an unanswered one. A call to
/// someone this user blocked is refused locally; a blocked caller's offer is
/// dropped without a row or a ring. With `silenceUnknownCallers` on, an offer
/// from someone unknown is logged as missed and does not ring.
///
/// Every state change runs on one queue, so signals and user actions never
/// interleave. User actions return when their own effect is done; signals
/// from the network are queued and acted on in order.
final class CallsService implements CallSignalSink {
  CallsService({
    required this._db,
    required this._signaling,
    required this._clock,
    required this._ids,
    required this._selfAccount,
    required this._postLog,
    required this._emit,
    this._config = const CallConfig(),
    this.mediaFactory,
  });

  final HelixDb _db;
  final CallSignaling _signaling;
  final Clock _clock;
  final IdFactory _ids;
  final String Function() _selfAccount;
  final Future<void> Function(String peer, CallLogBody body) _postLog;
  final void Function(EngineEvent event) _emit;
  final CallConfig _config;

  /// Makes the media session of a call. Without one calls cannot be placed
  /// or answered (incoming ones still ring, and can be declined).
  CallMediaFactory? mediaFactory;

  /// Group calls (ADR-034): offers that name a room and every signal of a
  /// room's links are handed to it, and each of the two answers `busy` while
  /// the other holds the device. Set by the engine.
  GroupCallsService? groups;

  final KeyedLock<String> _queue = KeyedLock();
  static const _queueKey = 'calls';
  final StreamController<CallSnapshot?> _snapshots =
      StreamController<CallSnapshot?>.broadcast();
  final Set<String> _unreadable = {};
  _Call? _call;

  // ---------------------------------------------------------------- reading

  /// The call in progress (ringing, connecting or live), or null.
  CallSnapshot? get current => _call?.snapshot;

  /// The current call and every change to it: first the call as it is now
  /// (or null), then a snapshot per change. A finished call is delivered as
  /// a snapshot with [CallPhase.ended] and then as null.
  Stream<CallSnapshot?> watchCurrent() {
    late final StreamController<CallSnapshot?> out;
    StreamSubscription<CallSnapshot?>? sub;
    out = StreamController<CallSnapshot?>(
      onListen: () {
        out.add(current);
        sub = _snapshots.stream.listen(out.add);
      },
      onCancel: () => sub?.cancel(),
    );
    return out.stream;
  }

  /// The call log, newest first (live).
  Stream<List<CallLogRow>> watchLog({int limit = 50}) =>
      _db.callsDao.watchRecent(limit: limit);

  /// The call log with one person, newest first (live).
  Stream<List<CallLogRow>> watchLogWith(String peer, {int limit = 50}) =>
      _db.callsDao.watchWithPeer(peer, limit: limit);

  Future<List<CallLogRow>> log({int limit = 50}) =>
      _db.callsDao.recent(limit: limit);

  /// Removes one entry from the log.
  Future<void> forget(String callId) => _db.callsDao.forget(callId);

  // ---------------------------------------------------------------- actions

  /// Calls [peer]. Returns when the offer has gone out; follow the call
  /// through [watchCurrent]. Throws [CallFailedException] (`busy`, `blocked`,
  /// `noMedia`, `rateLimited`, `unavailable`).
  Future<CallSnapshot> startCall(String peer, {bool video = false}) =>
      _run(() => _startCall(peer, video));

  /// Answers the ringing call. Throws [CallFailedException] (`noCall`,
  /// `noMedia`, `unavailable`); on a failure to connect the call ends as
  /// failed.
  Future<void> accept() => _run(_accept);

  /// Declines the ringing call; everywhere else it stops ringing too.
  Future<void> decline() => _run(() async {
    final call = _call;
    if (call == null || !call.isIncoming || call.answeringHere) return;
    await _decline(call);
  });

  /// Ends the call, whatever its state: cancels an outgoing call nobody
  /// answered, declines a ringing one, hangs up a live one. Does nothing
  /// when there is no call.
  Future<void> hangUp() => _run(() async {
    final call = _call;
    if (call != null) await _hangUp(call);
  });

  /// Mutes or unmutes the microphone of the live call.
  Future<void> setMuted({required bool muted}) => _run(() async {
    final call = _call;
    if (call == null || call.media == null) return;
    await call.media!.setMuted(muted: muted);
    call.muted = muted;
    _publish(call);
  });

  /// Turns the camera of the live call on or off.
  Future<void> setCameraEnabled({required bool enabled}) => _run(() async {
    final call = _call;
    // The camera is not what the call sends while the screen is.
    if (call == null ||
        call.media == null ||
        !call.video ||
        call.screenSharing) {
      return;
    }
    await call.media!.setVideoEnabled(enabled: enabled);
    call.cameraOn = enabled;
    _publish(call);
  });

  /// Starts or stops sharing this device's screen in the live video call, in
  /// place of the camera. The other side is told (a `media` signal) so it can
  /// fit the screen in its window. False, and nothing changes, when there is
  /// no live video call or the phone or the person refused the capture. A
  /// share the system ends by itself (its own Stop control) is stopped and
  /// announced the same way.
  Future<bool> setScreenSharing({required bool enabled}) => _run(() async {
    final call = _call;
    if (call == null ||
        call.finished ||
        call.media == null ||
        !call.video ||
        call.phase != CallPhase.active) {
      return false;
    }
    if (call.screenSharing == enabled) return true;
    final bool done;
    try {
      done = await call.media!.setScreenSharing(enabled: enabled);
    } on Object {
      return false;
    }
    if (!done) return false;
    if (enabled) {
      call.screenEnded = call.media!.screenSharingEnded.listen(
        (_) => unawaited(_screenEndedBySystem(call)),
      );
    } else {
      await call.screenEnded?.cancel();
      call.screenEnded = null;
    }
    await _announceScreen(call, enabled);
    return true;
  });

  /// Asks to change the live call to video ([video] true) or back to voice
  /// (ADR-036). The other person is asked first for video; going back to voice
  /// needs no yes. The caller's call time pays for the new kind, so a Free
  /// caller with none left in that pool is told (`lastSwitch`) and the call
  /// goes on as it was. Follow it through [watchCurrent]
  /// (`CallSnapshot.switchStage`). Does nothing unless a one-to-one call is
  /// live and no switch is under way.
  Future<void> switchMedia({required bool video}) => _run(() async {
    final call = _call;
    if (call == null ||
        call.finished ||
        call.phase != CallPhase.active ||
        call.media == null ||
        call.peerDevice == null ||
        call.pending != null ||
        call.video == video ||
        mediaFactory == null) {
      return;
    }
    call.lastSwitch = null;
    final s = _Switch(video: video, stage: _SwitchStage.asking);
    call.pending = s;
    _armSwitch(call, s);
    _publish(call);
    await _send(
      call.callId,
      CallSignalPayload(
        type: CallSignalType.switchAsk,
        callId: call.callId,
        media: video ? CallMedia.video : CallMedia.audio,
      ),
      account: call.peer,
      devices: {call.peerDevice!},
    );
  });

  /// Answers the other side's ask to switch ([CallSwitchStage.asked]).
  Future<void> answerSwitch({required bool accept}) => _run(() async {
    final call = _call;
    final s = call?.pending;
    if (call == null || s == null || s.stage != _SwitchStage.asked) return;
    await _answerAsk(call, s, accept);
  });

  void _armSwitch(_Call call, _Switch s) {
    s.timer?.cancel();
    s.timer = Timer(
      _config.connectTimeout,
      () => unawaited(
        _run(() async {
          if (call.finished || !identical(call.pending, s)) return;
          await _abortSwitch(
            call,
            s,
            s.stage == _SwitchStage.working
                ? CallSwitchOutcome.failed
                : CallSwitchOutcome.declined,
          );
        }),
      ),
    );
  }

  bool _switchPeer(_Call call, String device) =>
      call.phase == CallPhase.active &&
      !call.finished &&
      call.peerDevice == device;

  Future<void> _answerAsk(_Call call, _Switch s, bool accept) async {
    final device = call.peerDevice!;
    if (!accept) {
      call.pending = null;
      s.timer?.cancel();
      _publish(call);
      await _send(
        call.callId,
        CallSignalPayload(
          type: CallSignalType.switchDecline,
          callId: call.callId,
        ),
        account: call.peer,
        devices: {device},
      );
      return;
    }
    if (!call.isIncoming) {
      // The caller pays, so the caller makes the new connection.
      await _beginSwitch(call, s);
      return;
    }
    s.stage = _SwitchStage.accepted;
    _armSwitch(call, s);
    _publish(call);
    await _send(
      call.callId,
      CallSignalPayload(type: CallSignalType.switchAccept, callId: call.callId),
      account: call.peer,
      devices: {device},
    );
  }

  Future<void> _onSwitchAsk(
    _Call call,
    String device,
    CallSignalPayload p,
  ) async {
    if (!_switchPeer(call, device) || p.media == null) return;
    final video = p.media == CallMedia.video;
    if (video == call.video) return;
    final mine = call.pending;
    if (mine != null) {
      if (mine.stage != _SwitchStage.asking) return;
      if (!call.isIncoming && mine.video == video) {
        // Both asked for the same thing at once: the caller goes ahead.
        mine.stage = _SwitchStage.accepted;
        await _beginSwitch(call, mine);
        return;
      }
      mine.timer?.cancel(); // The other side's ask wins.
    }
    final s = _Switch(video: video, stage: _SwitchStage.asked);
    call.pending = s;
    call.lastSwitch = null;
    _armSwitch(call, s);
    _publish(call);
    // Going back to voice costs less and needs no yes.
    if (!video) await _answerAsk(call, s, true);
  }

  Future<void> _onSwitchAccept(_Call call, String device) async {
    final s = call.pending;
    if (s == null ||
        call.isIncoming ||
        s.stage != _SwitchStage.asking ||
        !_switchPeer(call, device)) {
      return;
    }
    await _beginSwitch(call, s);
  }

  void _onSwitchDecline(_Call call, String device) {
    final s = call.pending;
    if (s == null || !_switchPeer(call, device)) return;
    unawaited(_abortSwitch(call, s, CallSwitchOutcome.declined, notify: false));
  }

  /// Caller: asks the server for the new kind of media (the call time moves to
  /// the other pool), makes the new connection and offers it.
  Future<void> _beginSwitch(_Call call, _Switch s) async {
    final factory = mediaFactory;
    final device = call.peerDevice;
    if (factory == null || device == null) {
      await _abortSwitch(call, s, CallSwitchOutcome.failed);
      return;
    }
    s
      ..stage = _SwitchStage.working
      ..segment = call.segment + 1;
    _armSwitch(call, s);
    _publish(call);
    final List<IceServer> servers;
    try {
      servers = await _relay(call, CallRole.caller, video: s.video);
    } on CallFailedException {
      await _abortSwitch(call, s, CallSwitchOutcome.noCallTime);
      return;
    }
    try {
      final media = await factory.create(
        CallMediaConfig(video: s.video, iceServers: servers),
      );
      s.media = media;
      _wireSwitch(call, s);
      final sdp = await media.createOffer();
      await _send(
        call.callId,
        CallSignalPayload(
          type: CallSignalType.switchOffer,
          callId: call.callId,
          media: s.video ? CallMedia.video : CallMedia.audio,
          sdp: sdp,
          segment: s.segment,
        ),
        account: call.peer,
        devices: {device},
      );
    } on Object {
      await _abortSwitch(call, s, CallSwitchOutcome.failed, restore: true);
    }
  }

  /// Callee: the caller's offer for the new connection.
  Future<void> _onSwitchOffer(
    _Call call,
    String device,
    CallSignalPayload p,
  ) async {
    final s = call.pending;
    final factory = mediaFactory;
    if (s == null ||
        factory == null ||
        !call.isIncoming ||
        !_switchPeer(call, device) ||
        (s.stage != _SwitchStage.asking && s.stage != _SwitchStage.accepted) ||
        p.sdp == null ||
        p.segment != call.segment + 1 ||
        (p.media == CallMedia.video) != s.video) {
      return;
    }
    s
      ..stage = _SwitchStage.working
      ..segment = p.segment!;
    _armSwitch(call, s);
    _publish(call);
    try {
      final servers = await _relay(call, CallRole.callee, video: s.video);
      final media = await factory.create(
        CallMediaConfig(video: s.video, iceServers: servers),
      );
      s.media = media;
      _wireSwitch(call, s);
      final answer = await media.acceptOffer(p.sdp!);
      s.remoteReady = true;
      await _send(
        call.callId,
        CallSignalPayload(
          type: CallSignalType.switchAnswer,
          callId: call.callId,
          sdp: answer,
          segment: s.segment,
        ),
        account: call.peer,
        devices: {device},
      );
      await _drainSwitch(call);
      await _flushSwitch(call, s);
    } on Object {
      await _abortSwitch(call, s, CallSwitchOutcome.failed);
    }
  }

  /// Caller: the callee's answer for the new connection.
  Future<void> _onSwitchAnswer(
    _Call call,
    String device,
    CallSignalPayload p,
  ) async {
    final s = call.pending;
    final media = s?.media;
    if (s == null ||
        media == null ||
        call.isIncoming ||
        s.stage != _SwitchStage.working ||
        !_switchPeer(call, device) ||
        p.segment != s.segment ||
        p.sdp == null) {
      return;
    }
    try {
      await media.acceptAnswer(p.sdp!);
      s.remoteReady = true;
      await _drainSwitch(call);
      await _flushSwitch(call, s);
    } on Object {
      await _abortSwitch(call, s, CallSwitchOutcome.failed, restore: true);
    }
  }

  void _wireSwitch(_Call call, _Switch s) {
    final media = s.media!;
    s.candidates = media.localCandidates.listen((c) {
      if (call.finished) return;
      if (!identical(call.pending, s)) {
        _onLocalCandidate(call, c); // The switch is done: this is the call's.
        return;
      }
      s.outgoing.add(c);
      if (!s.remoteReady) return;
      s.iceTimer ??= Timer(_config.iceBatchDelay, () {
        s.iceTimer = null;
        unawaited(_run(() => _flushSwitch(call, s)));
      });
    });
    s.states = media.states.listen(
      (st) => unawaited(
        _run(() async {
          if (call.finished) return;
          if (!identical(call.pending, s)) {
            await _onMediaState(call, st);
            return;
          }
          if (st == CallMediaState.connected) {
            await _completeSwitch(call, s);
          } else if (st == CallMediaState.failed) {
            await _abortSwitch(
              call,
              s,
              CallSwitchOutcome.failed,
              restore: !call.isIncoming,
            );
          }
        }),
      ),
    );
  }

  Future<void> _flushSwitch(_Call call, _Switch s) async {
    final device = call.peerDevice;
    if (call.finished || device == null || !s.remoteReady) return;
    while (s.outgoing.isNotEmpty) {
      final batch = s.outgoing.take(CallSignalPayload.maxCandidates).toList();
      s.outgoing.removeRange(0, batch.length);
      await _send(
        call.callId,
        CallSignalPayload(
          type: CallSignalType.ice,
          callId: call.callId,
          candidates: batch,
          segment: s.segment,
        ),
        account: call.peer,
        devices: {device},
      );
      if (call.finished) return;
    }
  }

  void _onSwitchCandidates(
    _Call call,
    String device,
    int segment,
    List<IceCandidatePayload> candidates,
  ) {
    final s = call.pending;
    if (s == null || segment != s.segment || !_switchPeer(call, device)) {
      return;
    }
    for (final c in candidates) {
      if (s.queuedRemote.length >= _config.maxQueuedCandidates) return;
      s.queuedRemote.add(c);
    }
  }

  Future<void> _drainSwitch(_Call call) async {
    final s = call.pending;
    final media = s?.media;
    if (s == null || media == null || !s.remoteReady) return;
    final queued = List.of(s.queuedRemote);
    s.queuedRemote.clear();
    for (final c in queued) {
      if (call.finished) return;
      try {
        await media.addRemoteCandidate(c);
      } on Object {
        // A candidate the agent refuses is skipped; the others may connect.
      }
    }
  }

  /// The new connection is up: it becomes the call's, the old one is closed.
  Future<void> _completeSwitch(_Call call, _Switch s) async {
    final media = s.media;
    if (media == null) return;
    s.timer?.cancel();
    s.iceTimer?.cancel();
    await call.candidates?.cancel();
    await call.mediaStates?.cancel();
    await call.screenEnded?.cancel();
    call.screenEnded = null;
    final old = call.media;
    call
      ..media = media
      ..candidates = s.candidates
      ..mediaStates = s.states
      ..segment = s.segment
      ..video = s.video
      ..cameraOn = s.video
      ..screenSharing = false
      ..peerScreenSharing = false
      ..remoteReady = true
      ..pending = null
      ..lastSwitch = null;
    call.outgoingCandidates
      ..clear()
      ..addAll(s.outgoing);
    call.queuedRemote.clear();
    call.queuedTotal = 0;
    if (call.muted) {
      try {
        await media.setMuted(muted: true);
      } on Object {
        // Stays unmuted at worst; the button shows it.
        call.muted = false;
      }
    }
    _publish(call);
    try {
      await old?.close();
    } on Object {
      // The old platform session is gone either way.
    }
    await _flush(call);
  }

  /// Drops a switch that did not happen: the new connection is closed and the
  /// call goes on as it was. [restore]: this side had already moved the call
  /// time to the new pool, so it asks for the old kind again (the failed
  /// attempt costs the started minute).
  Future<void> _abortSwitch(
    _Call call,
    _Switch s,
    CallSwitchOutcome outcome, {
    bool notify = true,
    bool restore = false,
  }) async {
    if (!identical(call.pending, s)) return;
    await _closeSwitch(s);
    call.pending = null;
    call.lastSwitch = outcome;
    final device = call.peerDevice;
    if (notify && device != null && !call.finished) {
      await _send(
        call.callId,
        CallSignalPayload(
          type: CallSignalType.switchDecline,
          callId: call.callId,
        ),
        account: call.peer,
        devices: {device},
      );
    }
    if (restore && !call.finished) {
      try {
        await _relay(call, CallRole.caller);
      } on Object {
        // The call goes on under the credentials it has.
      }
    }
    _publish(call);
  }

  Future<void> _closeSwitch(_Switch s) async {
    s.timer?.cancel();
    s.iceTimer?.cancel();
    await s.candidates?.cancel();
    await s.states?.cancel();
    try {
      await s.media?.close();
    } on Object {
      // The platform session is gone either way.
    }
    s.media = null;
  }

  Future<void> _dropSwitch(_Call call) async {
    final s = call.pending;
    if (s == null) return;
    call.pending = null;
    await _closeSwitch(s);
  }

  Future<void> _screenEndedBySystem(_Call call) => _run(() async {
    if (call.finished || !call.screenSharing) return;
    await call.screenEnded?.cancel();
    call.screenEnded = null;
    await _announceScreen(call, false);
  });

  Future<void> _announceScreen(_Call call, bool sharing) async {
    call.screenSharing = sharing;
    _publish(call);
    await _send(
      call.callId,
      CallSignalPayload(
        type: CallSignalType.media,
        callId: call.callId,
        screen: sharing,
      ),
      account: call.peer,
      devices: call.peerDevice == null ? null : {call.peerDevice!},
    );
  }

  // --------------------------------------------------- pending (woken) calls

  /// The offers waiting for this device on the server, seen without opening
  /// them: for a headless host (the FCM isolate) to show an incoming-call
  /// notification. Changes nothing, so the running app can still ring the
  /// call by [fetchPending]. Expired offers, blocked callers and calls
  /// already known here are left out.
  Future<List<PendingCallNotice>> peekPending() async {
    final now = _now();
    final notices = <PendingCallNotice>[];
    for (final p in await _signaling.pending()) {
      if (!p.expiresAt.isAfter(now)) continue;
      if (await _isKnown(p.callId)) continue;
      if (await _isBlocked(p.from.account)) continue;
      // A silenced call must not ring a phone the app is not running on.
      if (await _isSilenced(p.from.account)) continue;
      notices.add(
        PendingCallNotice(
          callId: p.callId,
          caller: p.from.account,
          expiresAt: p.expiresAt,
        ),
      );
    }
    return notices;
  }

  /// Opens the offers that arrived while this device was offline and rings
  /// the newest unexpired one (the rest are answered as busy). Run by the
  /// running app after a call push woke it and whenever the socket
  /// reconnects. Returns how many calls rang. Throws what the API throws
  /// when offline.
  Future<int> fetchPending() async {
    final now = _now();
    final fresh = [
      for (final p in await _signaling.pending())
        if (p.expiresAt.isAfter(now)) p,
    ];
    var rang = 0;
    for (final p in fresh) {
      if (_unreadable.contains(p.callId) || await _isKnown(p.callId)) continue;
      if (await _isBlocked(p.from.account)) continue;
      final CallSignalPayload? opened;
      try {
        opened = await _signaling.open(p);
      } on TransientEngineException {
        continue; // Try again at the next fetch.
      }
      if (opened == null ||
          opened.type != CallSignalType.offer ||
          opened.callId != p.callId) {
        _unreadable.add(p.callId);
        continue;
      }
      final offer = opened;
      if (offer.room != null && groups != null) {
        await groups!.onPendingOffer(p.from.account, p.from.device, offer);
        continue;
      }
      await _run(() => _onOffer(p.from.account, p.from.device, offer, p));
      if (_call?.callId == p.callId) rang++;
    }
    return rang;
  }

  // ------------------------------------------------------------ network in

  @override
  Future<void> onSignal(
    String account,
    String device,
    CallSignalPayload payload,
  ) {
    final rooms = groups;
    if (rooms != null && rooms.claims(payload)) {
      return rooms.onSignal(account, device, payload);
    }
    return _run(() => _handleSignal(account, device, payload));
  }

  @override
  void onEndedElsewhere(String callId, CallState state) {
    unawaited(
      _run(() async {
        final call = _call;
        if (call == null ||
            call.callId != callId ||
            !call.isIncoming ||
            call.answeringHere ||
            call.phase != CallPhase.ringing) {
          return;
        }
        await _finish(
          call,
          state == CallState.answered
              ? CallEnd.answeredElsewhere
              : CallEnd.declinedElsewhere,
        );
      }),
    );
  }

  // --------------------------------------------------------------- lifecycle

  /// Ends the current call because the engine is stopping: a hang-up is
  /// tried for [CallConfig.signalTimeout], then the call ends locally either
  /// way. Safe to call with no call.
  Future<void> release() async {
    final call = _call;
    if (call == null) return;
    try {
      await hangUp().timeout(_config.signalTimeout);
    } on Object {
      // Fall through to the local end.
    }
    final still = _call;
    if (still != null) await _finish(still, CallEnd.failed, post: false);
  }

  /// Marks calls the log still shows as ringing or live as failed: a crash
  /// or a kill left them behind. Call at start-up, never while another
  /// isolate of this database may be in a call.
  Future<void> recoverUnfinished() async {
    final now = _now();
    for (final row in await _db.callsDao.unfinished()) {
      if (_call?.callId == row.callId) continue;
      await _db.callsDao.end(row.callId, state: 'failed', at: now);
    }
  }

  /// Releases the streams. Call after [release].
  Future<void> close() => _snapshots.close();

  // ===================================================================
  // The state machine. Everything below runs on the queue.
  // ===================================================================

  Future<T> _run<T>(Future<T> Function() action) =>
      _queue.run(_queueKey, action);

  DateTime _now() => _clock().toUtc();

  Future<bool> _isBlocked(String account) async =>
      (await _db.peopleDao.byAccount(account))?.blocked ?? false;

  /// An unknown caller while "silence unknown callers" is on. Someone is
  /// known when they are in the phone's contacts, were renamed here, or were
  /// ever written to from this account; a call from anyone else does not ring.
  Future<bool> _isSilenced(String account) async {
    if (!await _db.settingsDao.get(EngineSettings.silenceUnknownCallers)) {
      return false;
    }
    final person = await _db.peopleDao.byAccount(account);
    if ((person?.phonebookName ?? '').isNotEmpty ||
        (person?.nickname ?? '').isNotEmpty) {
      return false;
    }
    return !await _db.messagesDao.hasOutgoing(directConversationId(account));
  }

  Future<bool> _isKnown(String callId) async =>
      _call?.callId == callId || await _db.callsDao.byId(callId) != null;

  // ----------------------------------------------------------- outgoing

  Future<CallSnapshot> _startCall(String peer, bool video) async {
    final self = _selfAccount();
    if (peer == self) throw ArgumentError.value(peer, 'peer', 'is this user');
    if (_call != null || (groups?.isBusy ?? false)) {
      throw const CallFailedException(CallFailure.busy);
    }
    if (await _isBlocked(peer)) {
      throw const CallFailedException(CallFailure.blocked);
    }
    final factory = mediaFactory;
    if (factory == null) {
      throw const CallFailedException(CallFailure.noMedia);
    }
    final now = _now();
    final call = _Call(
      callId: _ids.next(),
      peer: peer,
      direction: CallDirection.outgoing,
      video: video,
      startedAt: now,
    );
    _call = call;
    await _db.peopleDao.upsertPerson(
      PeopleCompanion.insert(accountId: peer, updatedAt: now),
    );
    await _writeLog(call, 'outgoing', 'ringing');
    _publish(call);
    final List<IceServer> iceServers;
    try {
      iceServers = await _relay(call, CallRole.caller);
    } on CallFailedException {
      await _finish(call, CallEnd.failed, post: false);
      rethrow;
    }
    final String sdp;
    try {
      final media = await factory.create(
        CallMediaConfig(video: video, iceServers: iceServers),
      );
      call.media = media;
      call.cameraOn = video;
      _wireMedia(call);
      // The camera is on while it rings: the screen shows the preview now,
      // not only once the other side answers.
      _publish(call);
      sdp = await media.createOffer();
    } on Object {
      await _finish(call, CallEnd.failed, post: false);
      throw const CallFailedException(CallFailure.noMedia);
    }
    try {
      await _signaling.send(
        call.callId,
        CallSignalPayload(
          type: CallSignalType.offer,
          callId: call.callId,
          media: video ? CallMedia.video : CallMedia.audio,
          sdp: sdp,
        ),
        account: peer,
        ttl: _config.ringTimeout,
      );
    } on Object catch (e) {
      await _finish(call, CallEnd.failed, post: false);
      final reason = _classify(e);
      if (reason == CallFailure.blockedByPeer) {
        await PersonState.markBlocksMe(_db, peer, blocked: true, now: _now());
      }
      throw CallFailedException(reason);
    }
    // The offer went out, so they have not blocked this account (or no
    // longer have).
    await PersonState.markBlocksMe(_db, peer, blocked: false, now: _now());
    call.ringTimer = Timer(
      _config.ringTimeout,
      () => unawaited(_run(() => _ringTimedOut(call))),
    );
    return call.snapshot;
  }

  Future<void> _ringTimedOut(_Call call) async {
    if (call.finished || !call.isRinging) return;
    if (call.isIncoming) {
      await _finish(call, CallEnd.unanswered);
      return;
    }
    await _signalEnd(call, CallEndReason.cancelled);
    await _finish(call, CallEnd.unanswered);
  }

  // ----------------------------------------------------------- incoming

  Future<void> _onOffer(
    String account,
    String device,
    CallSignalPayload offer, [
    PendingCall? pending,
  ]) async {
    final self = _selfAccount();
    if (account == self || offer.sdp == null || offer.media == null) return;
    if (await _isKnown(offer.callId)) return;
    if (await _isBlocked(account)) return;
    if (await _isSilenced(account)) {
      await _logSilenced(
        offer.callId,
        account,
        video: offer.media == CallMedia.video,
      );
      return;
    }
    final now = _now();
    if (groups?.isBusy ?? false) {
      await _send(
        offer.callId,
        CallSignalPayload(
          type: CallSignalType.end,
          callId: offer.callId,
          reason: CallEndReason.busy,
        ),
        account: account,
        devices: {device},
      );
      await _logMissed(
        offer.callId,
        account,
        video: offer.media == CallMedia.video,
      );
      return;
    }
    final existing = _call;
    if (existing != null) {
      final glare =
          existing.direction == CallDirection.outgoing &&
          existing.peer == account &&
          existing.isRinging;
      if (glare && offer.callId.compareTo(existing.callId) < 0) {
        // The incoming call wins: the own one is withdrawn, then this rings.
        await _signalEnd(existing, CallEndReason.glare);
        await _finish(existing, CallEnd.glare);
      } else if (glare) {
        await _send(
          offer.callId,
          CallSignalPayload(
            type: CallSignalType.end,
            callId: offer.callId,
            reason: CallEndReason.glare,
          ),
          account: account,
          devices: {device},
        );
        return;
      } else {
        await _send(
          offer.callId,
          CallSignalPayload(
            type: CallSignalType.end,
            callId: offer.callId,
            reason: CallEndReason.busy,
          ),
          account: account,
          devices: {device},
        );
        await _logMissed(
          offer.callId,
          account,
          video: offer.media == CallMedia.video,
        );
        return;
      }
    }
    final call =
        _Call(
            callId: offer.callId,
            peer: account,
            direction: CallDirection.incoming,
            video: offer.media == CallMedia.video,
            startedAt: now,
          )
          ..peerDevice = device
          ..offerSdp = offer.sdp;
    _call = call;
    await _db.peopleDao.upsertPerson(
      PeopleCompanion.insert(accountId: account, updatedAt: now),
    );
    await _writeLog(call, 'incoming', 'ringing');
    call.phase = CallPhase.ringing;
    final wait = pending == null
        ? _config.ringTimeout + _config.signalTimeout
        : pending.expiresAt.difference(now);
    call.ringTimer = Timer(
      wait.isNegative ? Duration.zero : wait,
      () => unawaited(_run(() => _ringTimedOut(call))),
    );
    _publish(call);
    _emit(IncomingCallEvent(call.snapshot));
    // Tell the caller this device is ringing (best effort, live only).
    unawaited(
      _send(
        call.callId,
        CallSignalPayload(type: CallSignalType.ringing, callId: call.callId),
        account: account,
        devices: {device},
      ),
    );
  }

  Future<void> _accept() async {
    final call = _call;
    if (call == null ||
        !call.isIncoming ||
        call.phase != CallPhase.ringing ||
        call.answeringHere) {
      throw const CallFailedException(CallFailure.noCall);
    }
    final factory = mediaFactory;
    if (factory == null) {
      throw const CallFailedException(CallFailure.noMedia);
    }
    call.answeringHere = true;
    final device = call.peerDevice!;
    final List<IceServer> iceServers;
    try {
      iceServers = await _relay(call, CallRole.callee);
    } on CallFailedException {
      await _signalEnd(call, CallEndReason.failed);
      await _finish(call, CallEnd.failed);
      rethrow;
    }
    final String answer;
    try {
      final media = await factory.create(
        CallMediaConfig(video: call.video, iceServers: iceServers),
      );
      call.media = media;
      call.cameraOn = call.video;
      _wireMedia(call);
      answer = await media.acceptOffer(call.offerSdp!);
      call.offerSdp = null;
      call.remoteReady = true;
    } on Object {
      await _signalEnd(call, CallEndReason.failed);
      await _finish(call, CallEnd.failed);
      throw const CallFailedException(CallFailure.noMedia);
    }
    try {
      await _signaling.send(
        call.callId,
        CallSignalPayload(
          type: CallSignalType.answer,
          callId: call.callId,
          sdp: answer,
        ),
        account: call.peer,
        devices: {device},
      );
    } on Object catch (e) {
      await _finish(call, CallEnd.failed);
      throw CallFailedException(_classify(e));
    }
    call.ringTimer?.cancel();
    call.phase = CallPhase.connecting;
    call.connectTimer = Timer(
      _config.connectTimeout,
      () => unawaited(_run(() => _connectTimedOut(call))),
    );
    _publish(call);
    // The account's other devices stop ringing.
    await _best(() => _signaling.setState(call.callId, CallState.answered));
    await _drainRemote(call, device);
    await _flush(call);
  }

  Future<void> _decline(_Call call) async {
    await _signalEnd(call, CallEndReason.declined);
    await _best(() => _signaling.setState(call.callId, CallState.declined));
    await _finish(call, CallEnd.declinedByMe);
  }

  Future<void> _hangUp(_Call call) async {
    if (call.isIncoming && !call.answeringHere && call.isRinging) {
      await _decline(call);
    } else if (!call.isIncoming && call.isRinging) {
      await _signalEnd(call, CallEndReason.cancelled);
      await _finish(call, CallEnd.cancelledByMe);
    } else {
      await _signalEnd(call, CallEndReason.hangup);
      await _finish(call, CallEnd.hungUp);
    }
  }

  // ------------------------------------------------------------- signals

  Future<void> _handleSignal(
    String account,
    String device,
    CallSignalPayload p,
  ) async {
    if (p.type == CallSignalType.offer) {
      return _onOffer(account, device, p);
    }
    final call = _call;
    if (call == null || call.callId != p.callId || call.peer != account) {
      return; // Not a call this device is in: dropped.
    }
    switch (p.type) {
      case CallSignalType.ringing:
        if (!call.isIncoming &&
            call.phase == CallPhase.calling &&
            call.peerDevice == null) {
          call.phase = CallPhase.ringing;
          _publish(call);
        }
      case CallSignalType.answer:
        await _onAnswer(call, device, p);
      case CallSignalType.ice:
        final segment = p.segment ?? 0;
        if (segment == call.segment) {
          await _onCandidates(call, device, p.candidates);
        } else {
          _onSwitchCandidates(call, device, segment, p.candidates);
          await _drainSwitch(call);
        }
      case CallSignalType.switchAsk:
        await _onSwitchAsk(call, device, p);
      case CallSignalType.switchAccept:
        await _onSwitchAccept(call, device);
      case CallSignalType.switchDecline:
        _onSwitchDecline(call, device);
      case CallSignalType.switchOffer:
        await _onSwitchOffer(call, device, p);
      case CallSignalType.switchAnswer:
        await _onSwitchAnswer(call, device, p);
      case CallSignalType.end:
        await _onEnd(call, device, p.reason ?? CallEndReason.unknown);
      case CallSignalType.media:
        // Only the device this call talks to, and only while it is live.
        if (call.peerDevice == device && call.phase == CallPhase.active) {
          final sharing = p.screen ?? false;
          if (call.peerScreenSharing != sharing) {
            call.peerScreenSharing = sharing;
            _publish(call);
          }
        }
      case CallSignalType.offer || CallSignalType.unknown:
    }
  }

  Future<void> _onAnswer(_Call call, String device, CallSignalPayload p) async {
    if (call.isIncoming || p.sdp == null || call.media == null) return;
    final bound = call.peerDevice;
    if (bound != null) {
      if (bound != device) {
        // A second device took the call too: it is told so.
        await _send(
          call.callId,
          CallSignalPayload(
            type: CallSignalType.end,
            callId: call.callId,
            reason: CallEndReason.answeredElsewhere,
          ),
          account: call.peer,
          devices: {device},
        );
      }
      return;
    }
    if (!call.isRinging) return;
    call.peerDevice = device;
    call.ringTimer?.cancel();
    try {
      await call.media!.acceptAnswer(p.sdp!);
    } on Object {
      await _signalEnd(call, CallEndReason.failed);
      await _finish(call, CallEnd.failed);
      return;
    }
    call.remoteReady = true;
    call.phase = CallPhase.connecting;
    call.connectTimer = Timer(
      _config.connectTimeout,
      () => unawaited(_run(() => _connectTimedOut(call))),
    );
    _publish(call);
    await _drainRemote(call, device);
    await _flush(call);
  }

  Future<void> _onEnd(_Call call, String device, CallEndReason reason) async {
    final bound = call.peerDevice;
    if (bound != null && bound != device) return;
    final talking =
        call.phase == CallPhase.connecting || call.phase == CallPhase.active;
    if (call.isIncoming) {
      await _finish(call, switch (reason) {
        CallEndReason.glare => CallEnd.glare,
        CallEndReason.failed => CallEnd.failed,
        CallEndReason.answeredElsewhere => CallEnd.answeredElsewhere,
        _ =>
          talking || call.answeringHere
              ? CallEnd.remoteHungUp
              : CallEnd.cancelledByPeer,
      });
      return;
    }
    if (reason == CallEndReason.answeredElsewhere && bound == null) {
      return; // A sibling of the answering device: its answer follows.
    }
    await _finish(call, switch (reason) {
      CallEndReason.declined => CallEnd.declinedByPeer,
      CallEndReason.busy => CallEnd.busy,
      CallEndReason.glare => CallEnd.glare,
      CallEndReason.failed => CallEnd.failed,
      _ => talking ? CallEnd.remoteHungUp : CallEnd.declinedByPeer,
    });
  }

  // --------------------------------------------------------------- media

  void _wireMedia(_Call call) {
    final media = call.media!;
    call.candidates = media.localCandidates.listen(
      (c) => _onLocalCandidate(call, c),
    );
    call.mediaStates = media.states.listen(
      (s) => unawaited(_run(() => _onMediaState(call, s))),
    );
  }

  Future<void> _onMediaState(_Call call, CallMediaState state) async {
    if (call.finished) return;
    switch (state) {
      case CallMediaState.connected:
        if (call.phase != CallPhase.connecting) return;
        call.connectTimer?.cancel();
        call.phase = CallPhase.active;
        call.answeredAt = _now();
        await _db.callsDao.answered(call.callId, at: call.answeredAt!);
        _publish(call);
      case CallMediaState.failed:
        await _signalEnd(call, CallEndReason.failed);
        await _finish(call, CallEnd.failed);
      case CallMediaState.connecting ||
          CallMediaState.disconnected ||
          CallMediaState.closed:
    }
  }

  Future<void> _connectTimedOut(_Call call) async {
    if (call.finished || call.phase != CallPhase.connecting) return;
    await _signalEnd(call, CallEndReason.failed);
    await _finish(call, CallEnd.failed);
  }

  void _onLocalCandidate(_Call call, IceCandidatePayload candidate) {
    if (call.finished) return;
    call.outgoingCandidates.add(candidate);
    if (call.peerDevice == null || !call.remoteReady) return; // Held.
    call.iceTimer ??= Timer(_config.iceBatchDelay, () {
      call.iceTimer = null;
      unawaited(_run(() => _flush(call)));
    });
  }

  /// Sends the candidates gathered so far to the device this call talks to,
  /// in signals of at most [CallSignalPayload.maxCandidates].
  Future<void> _flush(_Call call) async {
    final device = call.peerDevice;
    if (call.finished || device == null || !call.remoteReady) return;
    while (call.outgoingCandidates.isNotEmpty) {
      final batch = call.outgoingCandidates
          .take(CallSignalPayload.maxCandidates)
          .toList();
      call.outgoingCandidates.removeRange(0, batch.length);
      await _send(
        call.callId,
        CallSignalPayload(
          type: CallSignalType.ice,
          callId: call.callId,
          candidates: batch,
          segment: call.segment == 0 ? null : call.segment,
        ),
        account: call.peer,
        devices: {device},
      );
      if (call.finished) return;
    }
  }

  Future<void> _onCandidates(
    _Call call,
    String device,
    List<IceCandidatePayload> candidates,
  ) async {
    final bound = call.peerDevice;
    if (bound != null && bound != device) return;
    if (bound == null && call.isIncoming) return;
    final queue = call.queuedRemote.putIfAbsent(device, () => []);
    for (final c in candidates) {
      if (call.queuedTotal >= _config.maxQueuedCandidates) return;
      queue.add(c);
      call.queuedTotal++;
    }
    if (bound != null && call.remoteReady) await _drainRemote(call, bound);
  }

  Future<void> _drainRemote(_Call call, String device) async {
    final media = call.media;
    final queued = call.queuedRemote.remove(device);
    if (media == null || queued == null) return;
    call.queuedTotal -= queued.length;
    // Everything queued for other devices will never be used.
    call.queuedRemote.clear();
    call.queuedTotal = 0;
    for (final c in queued) {
      if (call.finished) return;
      try {
        await media.addRemoteCandidate(c);
      } on Object {
        // A candidate the agent refuses is skipped; the others may connect.
      }
    }
  }

  // ------------------------------------------------------------- finish

  /// Ends [call] locally (idempotent): timers and media go, the log row gets
  /// its final facts, the UI sees the end, and (for a call this device
  /// placed) the caller's `call_log` message goes to the chat.
  Future<void> _finish(_Call call, CallEnd end, {bool post = true}) async {
    if (call.finished) return;
    call.finished = true;
    call.ringTimer?.cancel();
    call.connectTimer?.cancel();
    call.iceTimer?.cancel();
    call.warnTimer?.cancel();
    call.endTimer?.cancel();
    await _dropSwitch(call);
    await call.candidates?.cancel();
    await call.mediaStates?.cancel();
    await call.screenEnded?.cancel();
    try {
      await call.media?.close();
    } on Object {
      // The platform session is gone either way.
    }
    call.media = null;
    call.offerSdp = null;
    call.queuedRemote.clear();
    call.outgoingCandidates.clear();
    final now = _now();
    call.phase = CallPhase.ended;
    call.end = end;
    call.endedAt = now;
    if (end == CallEnd.glare) {
      await _db.callsDao.forget(call.callId);
    } else {
      final (direction, state) = call.logFacts();
      await _writeLog(call, direction, state);
    }
    final snapshot = call.snapshot;
    if (identical(_call, call)) _call = null;
    // The chat entry and the missed-call notice are in place before the UI
    // hears the call is over.
    if (call.isIncoming &&
        call.answeredAt == null &&
        (end == CallEnd.unanswered || end == CallEnd.cancelledByPeer)) {
      await _emitMissed(call);
    }
    if (!call.isIncoming && post) await _postOutcome(call, end);
    if (!_snapshots.isClosed) {
      _snapshots
        ..add(snapshot)
        ..add(null);
    }
  }

  Future<void> _postOutcome(_Call call, CallEnd end) async {
    final answered = call.answeredAt;
    final CallOutcome outcome;
    if (answered != null) {
      outcome = CallOutcome.answered;
    } else {
      outcome = switch (end) {
        CallEnd.declinedByPeer => CallOutcome.declined,
        CallEnd.failed => CallOutcome.failed,
        CallEnd.glare => CallOutcome.unknown,
        _ => CallOutcome.missed,
      };
    }
    if (outcome == CallOutcome.unknown) return;
    final duration = answered == null
        ? null
        : call.endedAt!.difference(answered).inSeconds;
    try {
      await _postLog(
        call.peer,
        CallLogBody(
          callId: call.callId,
          media: call.video ? CallMedia.video : CallMedia.audio,
          outcome: outcome,
          durationS: duration,
        ),
      );
    } on Object {
      // The chat entry is a courtesy; the call log has the fact.
    }
  }

  Future<void> _logMissed(
    String callId,
    String peer, {
    required bool video,
  }) async {
    final now = _now();
    await _db.peopleDao.upsertPerson(
      PeopleCompanion.insert(accountId: peer, updatedAt: now),
    );
    await _db.callsDao.start(
      CallLogCompanion.insert(
        callId: callId,
        peerAccountId: peer,
        kind: 'direct',
        direction: 'missed',
        video: Value(video),
        state: 'missed',
        startedAt: now,
        endedAt: Value(now),
      ),
    );
    await _emitMissedNotice(callId, peer, video: video);
  }

  /// A silenced call: a missed call in the log, with no notice and no answer,
  /// so the caller's call goes unanswered exactly like any other.
  Future<void> _logSilenced(
    String callId,
    String peer, {
    required bool video,
  }) async {
    final now = _now();
    await _db.peopleDao.upsertPerson(
      PeopleCompanion.insert(accountId: peer, updatedAt: now),
    );
    await _db.callsDao.start(
      CallLogCompanion.insert(
        callId: callId,
        peerAccountId: peer,
        kind: 'direct',
        direction: 'missed',
        video: Value(video),
        state: 'missed',
        startedAt: now,
        endedAt: Value(now),
      ),
    );
  }

  Future<void> _emitMissed(_Call call) =>
      _emitMissedNotice(call.callId, call.peer, video: call.video);

  Future<void> _emitMissedNotice(
    String callId,
    String peer, {
    required bool video,
  }) async {
    final now = _now();
    final chat = directConversationId(peer);
    final conversation = await _db.conversationsDao.byId(chat);
    final muted = conversation?.mutedUntil;
    _emit(
      MissedCallEvent(
        IncomingNotice(
          conversationId: chat,
          messageRowid: 0,
          messageId: callId,
          sender: peer,
          kind: MessageKinds.missedCall,
          preview: video ? 'Missed video call' : 'Missed voice call',
          muted: muted != null && muted.isAfter(now),
          sentAt: now,
          locked: conversation?.lockedAt != null,
        ),
      ),
    );
  }

  Future<void> _writeLog(_Call call, String direction, String state) =>
      _db.callsDao.start(
        CallLogCompanion.insert(
          callId: call.callId,
          peerAccountId: call.peer,
          kind: 'direct',
          direction: direction,
          video: Value(call.video),
          state: state,
          startedAt: call.startedAt,
          answeredAt: Value(call.answeredAt),
          endedAt: Value(call.endedAt),
        ),
      );

  // ------------------------------------------------------------- helpers

  void _publish(_Call call) {
    if (!_snapshots.isClosed) _snapshots.add(call.snapshot);
  }

  /// A signal that tells the other side the call ends: to the device it
  /// talks to, or to every device of the peer while nobody has answered.
  Future<void> _signalEnd(_Call call, CallEndReason reason) => _send(
    call.callId,
    CallSignalPayload(
      type: CallSignalType.end,
      callId: call.callId,
      reason: reason,
    ),
    account: call.peer,
    devices: call.peerDevice == null ? null : {call.peerDevice!},
  );

  /// Best-effort send: a failure or a slow network never blocks the local
  /// state machine for more than [CallConfig.signalTimeout].
  Future<void> _send(
    String callId,
    CallSignalPayload payload, {
    required String account,
    Set<String>? devices,
  }) => _best(
    () => _signaling.send(callId, payload, account: account, devices: devices),
  );

  Future<void> _best(Future<Object?> Function() action) async {
    try {
      await action().timeout(_config.signalTimeout);
    } on Object {
      // Intentionally ignored: see above.
    }
  }

  /// Relay credentials for [call] as [role]. A metered call also gets its
  /// warning and cut-off timers: the relay stops carrying it when its call
  /// time ends, so the call ends there too, with a warning first. Only a
  /// caller with no call time left throws ([CallFailure.noCallTime]).
  Future<List<IceServer>> _relay(
    _Call call,
    CallRole role, {
    bool? video,
  }) async {
    try {
      final turn = await _signaling.turnCredentials(
        callId: call.callId,
        role: role,
        video: video ?? call.video,
      );
      if (turn == null) return const [];
      call.warnTimer?.cancel();
      call.endTimer?.cancel();
      call.endsAt = null;
      call.endingSoon = false;
      if (turn.metered) _meter(call, turn.expiresAt);
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
      return const []; // A direct connection may still work.
    }
  }

  void _meter(_Call call, DateTime endsAt) {
    final left = endsAt.difference(_now());
    call.endsAt = endsAt;
    final warnIn = left - _config.callTimeWarning;
    if (warnIn <= Duration.zero) {
      call.endingSoon = true;
    } else {
      call.warnTimer = Timer(
        warnIn,
        () => unawaited(_run(() => _callTimeWarning(call))),
      );
    }
    call.endTimer = Timer(
      left > Duration.zero ? left : Duration.zero,
      () => unawaited(_run(() => _callTimeOver(call))),
    );
  }

  Future<void> _callTimeWarning(_Call call) async {
    if (call.finished) return;
    call.endingSoon = true;
    _publish(call);
  }

  Future<void> _callTimeOver(_Call call) async {
    if (call.finished) return;
    await _signalEnd(call, CallEndReason.hangup);
    await _finish(call, CallEnd.callTimeOver);
  }

  CallFailure _classify(Object error) => switch (error) {
    ApiException(code: ErrorCode.rateLimited) => CallFailure.rateLimited,
    ApiException(code: ErrorCode.blocked) => CallFailure.blockedByPeer,
    _ => CallFailure.unavailable,
  };
}

/// One call's mutable state, owned by [CallsService] and touched only on its
/// queue.
final class _Call {
  _Call({
    required this.callId,
    required this.peer,
    required this.direction,
    required this.video,
    required this.startedAt,
  }) : phase = direction == CallDirection.outgoing
           ? CallPhase.calling
           : CallPhase.ringing;

  final String callId;
  final String peer;
  final CallDirection direction;
  bool video;
  final DateTime startedAt;

  CallPhase phase;
  DateTime? answeredAt;
  DateTime? endedAt;
  CallEnd? end;
  bool finished = false;
  bool muted = false;
  bool cameraOn = false;

  /// This device shares its screen, and the other side does.
  bool screenSharing = false;
  bool peerScreenSharing = false;
  StreamSubscription<void>? screenEnded;

  /// The peer device this call talks to: the caller's device (incoming), or
  /// the callee device that answered (outgoing).
  String? peerDevice;

  /// Incoming: the caller's offer, in memory only until it is answered.
  String? offerSdp;

  /// This device pressed accept (the phase may still read ringing).
  bool answeringHere = false;

  /// The media session holds the remote description: candidates can go in
  /// and out.
  bool remoteReady = false;

  CallMediaSession? media;
  StreamSubscription<IceCandidatePayload>? candidates;
  StreamSubscription<CallMediaState>? mediaStates;
  Timer? ringTimer;
  Timer? connectTimer;
  Timer? iceTimer;

  /// Metered call: when its call time ends, whether the warning has shown,
  /// and the timers for both.
  DateTime? endsAt;
  bool endingSoon = false;
  Timer? warnTimer;
  Timer? endTimer;

  /// The media connection the call is on: 0 at the start, one more for each
  /// voice/video switch. A switch in progress is [pending].
  int segment = 0;
  _Switch? pending;
  CallSwitchOutcome? lastSwitch;

  /// Local candidates not sent yet.
  final List<IceCandidatePayload> outgoingCandidates = [];

  /// Remote candidates that arrived before the media session could take
  /// them, by device.
  final Map<String, List<IceCandidatePayload>> queuedRemote = {};
  int queuedTotal = 0;

  bool get isIncoming => direction == CallDirection.incoming;

  bool get isRinging =>
      phase == CallPhase.calling || phase == CallPhase.ringing;

  CallSnapshot get snapshot => CallSnapshot(
    callId: callId,
    peer: peer,
    direction: direction,
    video: video,
    phase: phase,
    startedAt: startedAt,
    answeredAt: answeredAt,
    endedAt: endedAt,
    end: end,
    muted: muted,
    cameraOn: cameraOn,
    screenSharing: screenSharing,
    peerScreenSharing: peerScreenSharing,
    endsAt: endsAt,
    endingSoon: endingSoon,
    switchStage: switch (pending?.stage) {
      null => CallSwitchStage.none,
      _SwitchStage.asking => CallSwitchStage.asking,
      _SwitchStage.asked => CallSwitchStage.asked,
      _ => CallSwitchStage.working,
    },
    switchToVideo: pending?.video ?? false,
    lastSwitch: lastSwitch,
  );

  /// The `call_log` direction and state for how this call ended.
  (String, String) logFacts() {
    final base = isIncoming ? 'incoming' : 'outgoing';
    return switch (end!) {
      CallEnd.hungUp ||
      CallEnd.remoteHungUp ||
      CallEnd.callTimeOver => (base, 'ended'),
      CallEnd.declinedByMe => ('incoming', 'declined'),
      CallEnd.declinedByPeer => ('outgoing', 'declined'),
      CallEnd.cancelledByMe => ('outgoing', 'cancelled'),
      CallEnd.cancelledByPeer =>
        answeredAt != null ? (base, 'ended') : ('missed', 'missed'),
      CallEnd.unanswered =>
        isIncoming ? ('missed', 'missed') : ('outgoing', 'unanswered'),
      CallEnd.busy => ('outgoing', 'unanswered'),
      CallEnd.answeredElsewhere => ('incoming', 'answered_elsewhere'),
      CallEnd.declinedElsewhere => ('incoming', 'declined'),
      CallEnd.failed => (base, 'failed'),
      CallEnd.glare => (base, 'cancelled'),
    };
  }
}

enum _SwitchStage { asking, asked, accepted, working }

/// A voice/video switch in progress on one call (ADR-036): the new media
/// connection is made beside the old one and replaces it once it connects.
final class _Switch {
  _Switch({required this.video, required this.stage});

  final bool video;
  _SwitchStage stage;
  int segment = 0;
  CallMediaSession? media;
  StreamSubscription<IceCandidatePayload>? candidates;
  StreamSubscription<CallMediaState>? states;
  Timer? timer;
  Timer? iceTimer;
  bool remoteReady = false;
  final List<IceCandidatePayload> outgoing = [];
  final List<IceCandidatePayload> queuedRemote = [];
}
