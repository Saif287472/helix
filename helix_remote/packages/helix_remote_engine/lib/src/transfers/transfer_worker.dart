import 'dart:async';

import 'package:helix_remote_api/v2.dart'
    show CancellationToken, RequestCancelledException;
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/transfers/download_runner.dart';
import 'package:helix_remote_engine/src/transfers/outbound_media.dart';
import 'package:helix_remote_engine/src/transfers/transfer_config.dart';
import 'package:helix_remote_engine/src/transfers/transfer_failure.dart';
import 'package:helix_remote_engine/src/transfers/upload_runner.dart';

/// What a running job uses to report progress and notice that it was
/// cancelled.
abstract interface class JobControl {
  /// Passed to every request, so cancelling aborts the one in flight.
  CancellationToken get token;

  /// Throws [RequestCancelledException] when the job was cancelled or the
  /// worker is stopping.
  void throwIfCancelled();

  /// Records [offset] (and the server object, once it exists), renews the
  /// lease and notices a job that was removed meanwhile.
  Future<void> progress(int offset, {String? mediaId});
}

/// Runs a transfer that is not an attachment (a group avatar, a backup
/// blob: `transfer_jobs.purpose`). Registered per purpose; the worker marks
/// the job done when [run] returns and handles failures like its own.
abstract interface class StandaloneTransferHandler {
  Future<void> run(TransferRow job, JobControl control);

  /// A terminal failure, so the owner can show it. Never throws.
  Future<void> failed(TransferRow job, TransferFailure failure);
}

/// The transfer queue worker (plan §6.3): claims due jobs from
/// `transfer_jobs` under a lease, runs uploads and downloads with limits per
/// direction, and records progress after every chunk so an interrupted
/// transfer resumes from where it stopped.
///
/// - **Wake-up:** the queue's own change stream (every enqueue, retry,
///   reschedule and completion, from any code path) and a timer for the next
///   retry or lease expiry.
/// - **Restart-safe:** a job's state lives in the database. A worker that
///   died leaves a lease that runs out; the next worker claims the job again
///   and resumes at its stored offset (uploads ask the server how far it got).
/// - **Failures:** a failure that may pass (no network, a busy server) backs
///   off exponentially and keeps the progress; one that cannot (quota, too
///   large, expired, digest mismatch) ends the job as failed with a typed
///   code, and the UI offers a retry.
/// - **Cancelling** a job removes its row; the running attempt notices at its
///   next checkpoint (or at once, through its cancellation token).
final class TransferWorker {
  TransferWorker(
    this._ctx,
    this._config,
    this._uploads,
    this._downloads,
    this._outbound, {
    required this.onDeviceRevoked,
    required this.onSessionEnded,
  });

  final EngineContext _ctx;
  final TransferConfig _config;
  final UploadRunner _uploads;
  final DownloadRunner _downloads;
  final OutboundMedia _outbound;

  /// The server said this device is revoked.
  final Future<void> Function() onDeviceRevoked;

  /// The device session is gone and could not be renewed.
  final void Function() onSessionEnded;

  final Map<String, StandaloneTransferHandler> _handlers = {};
  final Map<int, _Running> _running = {};

  StreamSubscription<String>? _subscription;
  Timer? _timer;
  bool _active = false;
  bool _draining = false;
  bool _stopping = false;
  bool _pumping = false;
  bool _again = false;

  HelixDb get _db => _ctx.db;

  /// Registers who runs standalone jobs with [purpose]. Jobs of a purpose
  /// nobody handles are left alone (looked at again in an hour).
  void register(String purpose, StandaloneTransferHandler handler) {
    _handlers[purpose] = handler;
  }

  bool get isRunning => _active;

  /// How many jobs are running now.
  int get runningCount => _running.length;

  /// Starts listening; the first pass happens at once.
  void start() {
    if (_active) return;
    _active = true;
    _stopping = false;
    _subscription = _db.transfersDao
        .watchPending()
        .map(
          (rows) => [
            for (final r in rows)
              '${r.id}:${r.state.name}:${r.nextAttemptAt.millisecondsSinceEpoch}'
                  ':${r.attempts}:${r.kind}',
          ].join(','),
        )
        .distinct()
        .listen((_) => _poke());
  }

  /// Stops: running jobs are cancelled and handed back (pending, progress
  /// kept, no attempt counted) for the next start.
  Future<void> stop() async {
    _active = false;
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
    _stopping = true;
    for (final job in _running.values) {
      job.token.cancel();
    }
    await Future.wait([for (final job in _running.values) job.done]);
    _stopping = false;
  }

  /// Cancels the running attempt of [jobId], if any, at once. The caller
  /// removes the row.
  void cancelRunning(int jobId) => _running[jobId]?.token.cancel();

  void _poke() {
    if (!_active) return;
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_pumping) {
      _again = true;
      return;
    }
    _pumping = true;
    try {
      do {
        _again = false;
        await _fill();
      } while (_again && _active);
    } on Object {
      // The database closed under us (sign-out, wipe): nothing to run.
    } finally {
      _pumping = false;
    }
    if (_active) await _arm();
  }

  bool _isUpload(String kind) => kind == 'upload';

  int _count({required bool uploads}) =>
      _running.values.where((r) => _isUpload(r.kind) == uploads).length;

  Future<void> _fill() async {
    while (_active || _draining) {
      final kinds = <String>{
        if (_count(uploads: true) < _config.maxUploads) 'upload',
        if (_count(uploads: false) < _config.maxDownloads) ...[
          'download',
          'thumbnail',
        ],
      };
      if (kinds.isEmpty) return;
      final job = await _db.transfersDao.claim(
        _ctx.now(),
        lease: _config.lease,
        kinds: kinds,
      );
      if (job == null) return;
      _start(job);
    }
  }

  void _start(TransferRow job) {
    final running = _Running(job.id, job.kind);
    _running[job.id] = running;
    running.done = _execute(job, running).whenComplete(() {
      _running.remove(job.id);
      _poke();
    });
  }

  Future<void> _arm() async {
    _timer?.cancel();
    final DateTime? next;
    try {
      next = await _nextWake();
    } on Object {
      return;
    }
    if (!_active) return;
    if (next == null) {
      _timer = Timer(_config.idlePoll, _poke);
      return;
    }
    var wait = next.difference(_ctx.now());
    if (wait < Duration.zero) wait = Duration.zero;
    if (wait > const Duration(minutes: 5)) wait = const Duration(minutes: 5);
    _timer = Timer(wait + const Duration(milliseconds: 20), _poke);
  }

  /// The earliest time a queued job becomes claimable, among those whose
  /// direction has a free slot (a full direction wakes the pass when a job
  /// ends).
  Future<DateTime?> _nextWake() async {
    DateTime? next;
    final uploadsFree = _count(uploads: true) < _config.maxUploads;
    final downloadsFree = _count(uploads: false) < _config.maxDownloads;
    for (final row in await _db.transfersDao.pending()) {
      if (_running.containsKey(row.id)) continue;
      if (_isUpload(row.kind) ? !uploadsFree : !downloadsFree) continue;
      final at = row.state == TransferState.inFlight
          ? row.leaseUntil
          : row.nextAttemptAt;
      if (at != null && (next == null || at.isBefore(next))) next = at;
    }
    return next;
  }

  /// Runs until nothing is due and nothing is running (jobs backing off stay
  /// queued). For headless hosts and tests.
  Future<void> drain() async {
    _draining = true;
    try {
      while (true) {
        await _fill();
        if (_running.isEmpty) return;
        await Future.wait([for (final job in _running.values) job.done]);
      }
    } finally {
      _draining = false;
    }
  }

  // ----------------------------------------------------------------- jobs

  Future<void> _execute(TransferRow job, _Running running) async {
    final control = _Control(this, job.id, running);
    final heartbeat = Timer.periodic(_config.lease ~/ 3, (_) async {
      try {
        final held = await _db.transfersDao.renewLease(
          job.id,
          until: _ctx.now().add(_config.lease),
        );
        if (!held) running.token.cancel();
      } on Object {
        // The database is closing.
      }
    });
    try {
      final ran = await _run(job, control);
      if (ran && job.attachmentRowid == null) {
        await _db.transfersDao.markDone(job.id);
      }
    } on Object catch (error) {
      await _failed(job, running, classifyTransferError(error));
    } finally {
      heartbeat.cancel();
    }
  }

  /// Runs the job; false when nobody here handles it (it was handed back).
  Future<bool> _run(TransferRow job, JobControl control) async {
    final purpose = job.purpose;
    if (job.attachmentRowid == null) {
      final handler = purpose == null ? null : _handlers[purpose];
      if (handler == null) {
        // Nobody here runs this one: leave it, look again later.
        await _db.transfersDao.release(
          job.id,
          at: _ctx.now().add(const Duration(hours: 1)),
        );
        return false;
      }
      await handler.run(job, control);
      return true;
    }
    switch (job.kind) {
      case 'upload':
        await _uploads.run(job, control);
      case 'download':
        await _downloads.run(job, control);
      case 'thumbnail':
        await _downloads.runThumbnail(job, control);
      default:
        throw const TransferException(TransferFailure.unknown);
    }
    return true;
  }

  Future<void> _failed(
    TransferRow job,
    _Running running,
    TransferOutcome outcome,
  ) async {
    try {
      switch (outcome) {
        case TransferInterrupted():
          // Cancelled (the row is gone) or the worker is stopping: hand a
          // stopped job back with its progress; a cancelled one has no row.
          if (_stopping) {
            await _db.transfersDao.release(job.id, at: _ctx.now());
          }
        case RetryTransfer():
          if (_ctx.now().difference(job.createdAt) > _config.maxAge) {
            await _giveUp(job, TransferFailure.gaveUp);
            return;
          }
          var delay = _config.backoff.delay(
            job.attempts + 1,
            _ctx.ids.jitter(),
          );
          final atLeast = outcome.atLeast;
          if (atLeast != null && atLeast > delay) delay = atLeast;
          await _db.transfersDao.reschedule(
            job.id,
            nextAttemptAt: _ctx.now().add(delay),
            code: outcome.code,
          );
        case FailTransfer():
          await _giveUp(job, outcome.failure);
        case TransferSessionEnded():
          await _db.transfersDao.release(
            job.id,
            at: _ctx.now().add(const Duration(seconds: 30)),
          );
          onSessionEnded();
        case TransferDeviceRevoked():
          await _db.transfersDao.release(
            job.id,
            at: _ctx.now().add(const Duration(minutes: 5)),
          );
          // Not awaited: revoking stops this worker.
          unawaited(onDeviceRevoked());
      }
    } on Object {
      // The database closed under us (sign-out, wipe).
    }
  }

  Future<void> _giveUp(TransferRow job, TransferFailure failure) async {
    await _db.transfersDao.fail(
      job.id,
      code: failure.wire,
      now: _ctx.now(),
      backoff: Duration.zero,
      maxAttempts: 1,
    );
    final purpose = job.purpose;
    if (job.attachmentRowid == null) {
      await (purpose == null ? null : _handlers[purpose])?.failed(job, failure);
      return;
    }
    if (job.kind == 'upload') {
      await _outbound.uploadFailed(job, failure);
    } else if (job.kind == 'download') {
      await _downloads.downloadFailed(job, failure);
    }
  }
}

final class _Running {
  _Running(this.id, this.kind);

  final int id;
  final String kind;
  final CancellationToken token = CancellationToken();
  Future<void> done = Future.value();
}

final class _Control implements JobControl {
  _Control(this._worker, this._jobId, this._running);

  final TransferWorker _worker;
  final int _jobId;
  final _Running _running;

  @override
  CancellationToken get token => _running.token;

  @override
  void throwIfCancelled() {
    if (_running.token.isCancelled) throw const RequestCancelledException();
  }

  @override
  Future<void> progress(int offset, {String? mediaId}) async {
    throwIfCancelled();
    final db = _worker._db;
    await db.transfersDao.setProgress(_jobId, offset: offset, mediaId: mediaId);
    final held = await db.transfersDao.renewLease(
      _jobId,
      until: _worker._ctx.now().add(_worker._config.lease),
    );
    if (!held) {
      _running.token.cancel();
      throw const RequestCancelledException();
    }
  }
}
