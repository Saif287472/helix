import 'dart:async';

import 'package:helix_remote_api/v2.dart' show ApiException;
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/calls/call_config.dart';
import 'package:helix_remote_engine/src/calls/call_media.dart';
import 'package:helix_remote_engine/src/calls/call_models.dart';
import 'package:helix_remote_engine/src/calls/call_signaling.dart';
import 'package:helix_remote_engine/src/errors.dart';
import 'package:helix_remote_engine/src/events.dart';
import 'package:helix_remote_engine/src/messaging/kinds.dart';
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
/// dropped without a row or a ring.
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
    if (call == null || call.media == null || !call.video) return;
    await call.media!.setVideoEnabled(enabled: enabled);
    call.cameraOn = enabled;
    _publish(call);
  });

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
  ) => _run(() => _handleSignal(account, device, payload));

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

  Future<bool> _isKnown(String callId) async =>
      _call?.callId == callId || await _db.callsDao.byId(callId) != null;

  // ----------------------------------------------------------- outgoing

  Future<CallSnapshot> _startCall(String peer, bool video) async {
    final self = _selfAccount();
    if (peer == self) throw ArgumentError.value(peer, 'peer', 'is this user');
    if (_call != null) throw const CallFailedException(CallFailure.busy);
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
    final String sdp;
    try {
      final media = await factory.create(
        CallMediaConfig(video: video, iceServers: await _iceServers()),
      );
      call.media = media;
      call.cameraOn = video;
      _wireMedia(call);
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
      throw CallFailedException(_classify(e));
    }
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
    final now = _now();
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
    final String answer;
    try {
      final media = await factory.create(
        CallMediaConfig(video: call.video, iceServers: await _iceServers()),
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
        await _onCandidates(call, device, p.candidates);
      case CallSignalType.end:
        await _onEnd(call, device, p.reason ?? CallEndReason.unknown);
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
    await call.candidates?.cancel();
    await call.mediaStates?.cancel();
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

  Future<void> _emitMissed(_Call call) =>
      _emitMissedNotice(call.callId, call.peer, video: call.video);

  Future<void> _emitMissedNotice(
    String callId,
    String peer, {
    required bool video,
  }) async {
    final now = _now();
    final chat = directConversationId(peer);
    final muted = (await _db.conversationsDao.byId(chat))?.mutedUntil;
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

  Future<List<IceServer>> _iceServers() async {
    try {
      final turn = await _signaling.turnCredentials();
      if (turn == null) return const [];
      return [
        IceServer(
          urls: turn.urls,
          username: turn.username,
          credential: turn.credential,
        ),
      ];
    } on Object {
      return const []; // A direct connection may still work.
    }
  }

  CallFailure _classify(Object error) => switch (error) {
    ApiException(code: ErrorCode.rateLimited) => CallFailure.rateLimited,
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
  final bool video;
  final DateTime startedAt;

  CallPhase phase;
  DateTime? answeredAt;
  DateTime? endedAt;
  CallEnd? end;
  bool finished = false;
  bool muted = false;
  bool cameraOn = false;

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
  );

  /// The `call_log` direction and state for how this call ended.
  (String, String) logFacts() {
    final base = isIncoming ? 'incoming' : 'outgoing';
    return switch (end!) {
      CallEnd.hungUp || CallEnd.remoteHungUp => (base, 'ended'),
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
