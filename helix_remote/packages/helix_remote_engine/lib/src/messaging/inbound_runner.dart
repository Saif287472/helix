import 'dart:async';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_engine/src/calls/call_models.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/errors.dart';
import 'package:helix_remote_engine/src/events.dart';
import 'package:helix_remote_engine/src/messaging/inbound.dart';
import 'package:helix_remote_engine/src/util/keyed_lock.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// What one [InboundRunner.fetchOnce] run did.
final class SyncSummary {
  const SyncSummary({
    required this.processed,
    required this.notices,
    required this.complete,
    this.pendingCalls = const [],
  });

  /// Envelopes processed (replays not counted).
  final int processed;

  /// The new messages a notification may show, oldest first.
  final List<IncomingNotice> notices;

  /// False if the run stopped early: no network while looking up a sender's
  /// keys, or the page limit was reached. The mailbox keeps the rest.
  final bool complete;

  /// Calls that ring this device but that the headless run could not open
  /// (`Engine.syncOnce` fills it): show an incoming-call notification for
  /// each; the running app rings them with `CallsService.fetchPending`.
  final List<PendingCallNotice> pendingCalls;

  SyncSummary withPendingCalls(List<PendingCallNotice> calls) => SyncSummary(
    processed: processed,
    notices: notices,
    complete: complete,
    pendingCalls: calls,
  );
}

/// Feeds envelopes to the [InboundProcessor] in order and acks them.
///
/// Two sources, one queue: the WebSocket ([startRealtime], used by the
/// running app) and the REST mailbox ([fetchOnce], used by the FCM
/// background isolate, the CLI and as a safety net when the socket reports a
/// full window). Both go through one serial queue and `processed_envelopes`
/// de-duplicates, so they may overlap.
///
/// **Ack after durable processing** (REALTIME_V2.md): an envelope is acked
/// only once its transaction committed (or it was quarantined); acks are
/// cumulative, so a transient failure holds back the whole stream: the
/// runner retries that envelope with backoff while the realtime window
/// stops further delivery.
final class InboundRunner {
  InboundRunner(
    this._ctx,
    this._processor, {
    required this.onDeviceRevoked,
    required this.onSessionEnded,
  });

  final EngineContext _ctx;
  final InboundProcessor _processor;

  /// The socket closed with 4003 or a 403: this device was revoked.
  final Future<void> Function() onDeviceRevoked;

  /// The session could not be renewed.
  final void Function() onSessionEnded;

  final KeyedLock<String> _serial = KeyedLock();
  static const _queue = 'inbound';

  StreamSubscription<Envelope>? _envelopes;
  StreamSubscription<RealtimeState>? _states;
  StreamSubscription<void>? _wakes;
  bool _running = false;
  bool _fetching = false;

  /// Starts the realtime socket and processes what it delivers.
  Future<void> startRealtime() async {
    if (_running) return;
    _running = true;
    final realtime = _ctx.api.realtime;
    _envelopes = realtime.envelopes.listen(
      (envelope) => unawaited(_fromSocket(envelope)),
    );
    _states = realtime.states.listen(_onState);
    _wakes = realtime.wakes.listen((_) => unawaited(_safetyNet()));
    final cursor = await _ctx.db.inboxDao.cursor();
    realtime.start(after: cursor?.lastProcessedSeq ?? 0);
  }

  Future<void> stopRealtime() async {
    _running = false;
    await _envelopes?.cancel();
    await _states?.cancel();
    await _wakes?.cancel();
    _envelopes = _states = null;
    _wakes = null;
    await _ctx.api.realtime.stop();
    // Let the envelope being processed finish before the caller closes the
    // database.
    await _serial.run(_queue, () async {});
  }

  /// Takes the socket back after the app resumed or after a supersede.
  void reconnect() => _ctx.api.realtime.reconnect();

  Future<void> _fromSocket(Envelope envelope) => _serial.run(_queue, () async {
    try {
      final result = await _processRetrying(envelope);
      if (result == null) return;
      final seq = envelope.seq;
      if (seq != null) await _ack(seq);
    } on Object {
      // The database went away under us (sign-out, wipe, shutdown): the
      // envelope stays unacked and comes back after the next sign-in.
    }
  });

  /// Process [envelope], retrying until it works or the runner stops.
  /// Returns null when stopped first.
  ///
  /// A [TransientEngineException] (no network) retries forever with
  /// backoff. Any other failure is a bug or a full disk; it retries a few
  /// times and then quarantines the envelope, because nothing may block
  /// the stream for good and an unacked envelope behind later acks would
  /// be lost anyway.
  Future<InboundResult?> _processRetrying(Envelope envelope) async {
    var transient = 0;
    var unexpected = 0;
    while (_running) {
      try {
        return await _processor.process(envelope);
      } on TransientEngineException {
        transient++;
        await Future<void>.delayed(
          _ctx.config.inboundRetry.delay(transient, _ctx.ids.jitter()),
        );
      } on Object {
        if (++unexpected >= 3) {
          return _processor.quarantineUnprocessable(envelope);
        }
        await Future<void>.delayed(
          _ctx.config.inboundRetry.delay(unexpected, _ctx.ids.jitter()),
        );
      }
    }
    return null;
  }

  /// One attempt at [envelope] for a headless run: a failure that is not
  /// [TransientEngineException] is retried twice and then quarantined, so a
  /// run cannot be stuck on one envelope forever (see [_processRetrying]).
  Future<InboundResult> _processGuarded(Envelope envelope) async {
    var unexpected = 0;
    while (true) {
      try {
        return await _processor.process(envelope);
      } on TransientEngineException {
        rethrow;
      } on Object {
        if (++unexpected >= 3) {
          return _processor.quarantineUnprocessable(envelope);
        }
      }
    }
  }

  Future<void> _safetyNet() async {
    try {
      await fetchOnce();
    } on Object {
      // The next wake, reconnect or push retries.
    }
  }

  void _onState(RealtimeState state) {
    switch (state.phase) {
      case RealtimePhase.revoked:
        unawaited(onDeviceRevoked());
      case RealtimePhase.signedOut:
        onSessionEnded();
      case RealtimePhase.suspended:
        _ctx.emit(const SuspensionChanged(suspended: true));
      default:
    }
  }

  /// Acks through [seq]: on the socket when it is connected (which returns
  /// window credit), otherwise by REST. A failed ack is not an error: the
  /// server replays and `processed_envelopes` swallows the duplicates.
  Future<void> _ack(int seq) async {
    final realtime = _ctx.api.realtime;
    try {
      if (_running && realtime.state.phase == RealtimePhase.connected) {
        realtime.ack(seq);
      } else {
        await _ctx.api.messaging.ack(seq);
      }
    } on HelixApiException {
      return;
    }
    await _ctx.db.inboxDao.advanceCursor(
      processedSeq: seq,
      ackedSeq: seq,
      now: _ctx.now(),
    );
  }

  /// Reads the REST mailbox from the cursor, processes and acks everything
  /// (at most `EngineConfig.maxFetchPages` pages). No socket needed.
  /// Throws API errors for the mailbox read itself (offline, signed out).
  Future<SyncSummary> fetchOnce() async {
    if (_fetching) {
      // One at a time; the running fetch will see what arrived.
      return const SyncSummary(processed: 0, notices: [], complete: true);
    }
    _fetching = true;
    try {
      var processed = 0;
      final notices = <IncomingNotice>[];
      for (var page = 0; page < _ctx.config.maxFetchPages; page++) {
        final cursor = (await _ctx.db.inboxDao.cursor())?.lastProcessedSeq ?? 0;
        final MailboxPage batch;
        try {
          batch = await _ctx.api.messaging.mailbox(after: cursor);
        } on ApiException catch (e) {
          if (e.code == ErrorCode.deviceRevoked) unawaited(onDeviceRevoked());
          rethrow;
        }
        var last = 0;
        for (final envelope in batch.envelopes) {
          final InboundResult result;
          try {
            result = await _serial.run(_queue, () => _processGuarded(envelope));
          } on TransientEngineException {
            if (last > 0) await _ack(last);
            return SyncSummary(
              processed: processed,
              notices: notices,
              complete: false,
            );
          }
          if (!result.duplicate) processed++;
          final notice = result.notice;
          if (notice != null) notices.add(notice);
          final seq = envelope.seq;
          if (seq != null && seq > last) last = seq;
        }
        if (last > 0) await _ack(last);
        if (!batch.more || batch.envelopes.isEmpty) {
          return SyncSummary(
            processed: processed,
            notices: notices,
            complete: true,
          );
        }
      }
      return SyncSummary(
        processed: processed,
        notices: notices,
        complete: false,
      );
    } finally {
      _fetching = false;
    }
  }
}
