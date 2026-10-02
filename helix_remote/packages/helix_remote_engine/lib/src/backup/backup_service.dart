import 'dart:async';

import 'package:helix_remote_engine/src/account/device_service.dart';
import 'package:helix_remote_engine/src/backup/device_transfer.dart';
import 'package:helix_remote_engine/src/backup/errors.dart';
import 'package:helix_remote_engine/src/backup/full_backup.dart';
import 'package:helix_remote_engine/src/backup/history_backup.dart';
import 'package:helix_remote_engine/src/backup/models.dart';
import 'package:helix_remote_engine/src/backup/options.dart';
import 'package:helix_remote_engine/src/backup/snapshot.dart';
import 'package:helix_remote_engine/src/backup/state.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/events.dart';
import 'package:helix_remote_engine/src/messaging/outbox.dart';

/// History backup, restore and device-to-device transfer: the engine's
/// `backup` feature (plan §6.3, CRYPTO_V2.md §13, F2). The app's backup pages
/// are this service's streams and futures; it holds no UI state.
///
/// | What | Calls |
/// |---|---|
/// | Automatic history backup (keyed from the account identity key, merged across devices, 16 MiB) | [backUpNow], [restoreHistory], [watchStatus], [setAutoBackup], [deleteHistoryBackup], [runMaintenance] |
/// | Full backup (user recovery secret, the only place the identity key is written) | [createFullBackup], [restoreFullBackup], [deleteFullBackup] |
/// | Device-to-device transfer over the media relay | [sendHistory], [watchOffers], [acceptOffer], [declineOffer], [cancelSend] |
///
/// What a backup holds and does not hold is [SnapshotExporter]'s doc; the
/// transfer protocol is [DeviceTransferJob]'s.
///
/// Errors are [BackupException]s with a [BackupFailure] the UI can word.
/// Progress goes to [backupProgress], [restoreProgress] and
/// [transferProgress] (broadcast; they carry no content and no keys).
final class BackupService {
  BackupService(
    this._ctx,
    OutboxService outbox,
    DeviceService devices, {
    BackupOptions options = const BackupOptions(),
  }) : _options = options {
    final remote = options.remote ?? ApiBackupRemote(_ctx.api.backup);
    final relay = options.relay ?? ApiRelayStore(_ctx.api.media);
    final exporter = SnapshotExporter(_ctx, options);
    final importer = SnapshotImporter(_ctx, options);
    _history = HistoryBackupJob(
      _ctx,
      options,
      remote,
      exporter,
      importer,
      onBackup: _backupEvents.add,
      onRestore: _restoreEvents.add,
    );
    _full = FullBackupJob(
      _ctx,
      options,
      remote,
      exporter,
      importer,
      onBackup: _backupEvents.add,
      onRestore: _restoreEvents.add,
    );
    _transfer = DeviceTransferJob(
      _ctx,
      options,
      relay,
      exporter,
      importer,
      outbox,
      devices,
      onProgress: _transferEvents.add,
    );
  }

  final EngineContext _ctx;
  final BackupOptions _options;
  late final HistoryBackupJob _history;
  late final FullBackupJob _full;
  late final DeviceTransferJob _transfer;

  final StreamController<BackupProgress> _backupEvents =
      StreamController.broadcast();
  final StreamController<RestoreProgress> _restoreEvents =
      StreamController.broadcast();
  final StreamController<TransferProgress> _transferEvents =
      StreamController.broadcast();

  final List<StreamSubscription<Object?>> _subscriptions = [];
  bool _started = false;

  TransferLedger get _ledger => TransferLedger(_ctx.db);

  // ----------------------------------------------------------- progress

  /// Progress of the history backup and of the full backup (`full`).
  Stream<BackupProgress> get backupProgress => _backupEvents.stream;

  /// Progress of a restore from either backup.
  Stream<RestoreProgress> get restoreProgress => _restoreEvents.stream;

  /// Progress of device-to-device transfers, sending and receiving.
  Stream<TransferProgress> get transferProgress => _transferEvents.stream;

  // ------------------------------------------------------------- status

  Future<BackupStatus> status() async {
    final h = HistoryBackupState.decode(
      await _ctx.db.settingsDao.get(BackupSettings.history),
    );
    final f = FullBackupState.decode(
      await _ctx.db.settingsDao.get(BackupSettings.full),
    );
    final auto = await _ctx.db.settingsDao.get(BackupSettings.autoBackup);
    return BackupStatus(
      autoBackup: auto ?? _options.autoBackup,
      lastBackupAt: h.at,
      version: h.version == 0 ? null : h.version,
      messages: h.messages,
      bytes: h.bytes,
      truncated: h.truncated,
      lastAttemptAt: h.attemptAt,
      lastFailure: h.failure,
      lastFullBackupAt: f.at,
      fullVersion: f.version == 0 ? null : f.version,
    );
  }

  /// The last-backup status, live: emits now and whenever a backup or the
  /// switch changes.
  Stream<BackupStatus> watchStatus() {
    final controller = StreamController<BackupStatus>();
    final subs = <StreamSubscription<Object?>>[];
    Future<void> emit() async {
      try {
        if (!controller.isClosed) controller.add(await status());
      } on Object {
        // The database closed under us.
      }
    }

    controller
      ..onListen = () {
        for (final setting in [
          BackupSettings.history,
          BackupSettings.full,
          BackupSettings.autoBackup,
        ]) {
          subs.add(_ctx.db.settingsDao.watch(setting).listen((_) => emit()));
        }
      }
      ..onCancel = () async {
        for (final s in subs) {
          await s.cancel();
        }
      };
    return controller.stream.distinct();
  }

  /// Turns the automatic daily backup on or off.
  Future<void> setAutoBackup(bool enabled) => _ctx.db.settingsDao.set(
    BackupSettings.autoBackup,
    enabled,
    now: _ctx.now(),
  );

  // ----------------------------------------------------- history backup

  /// Builds the history backup and uploads it (merging in a newer backup
  /// from another device first when the server has one). Returns a
  /// `skipped` result when there is no history. Throws [BackupException].
  Future<BackupResult> backUpNow() => _history.backUp();

  /// Downloads the history backup and merges it into this device's history:
  /// what is already here stays (local wins), messages that are not are added,
  /// the chat list and search follow. Run it after signing in on a new
  /// device. Safe to run again. Throws [BackupException] (`noBackup`,
  /// `wrongKey`, `corrupt`, `newerFormat`, `rolledBack`, `offline`).
  Future<RestoreResult> restoreHistory() => _history.restore();

  /// Deletes the server's history backup.
  Future<void> deleteHistoryBackup() => _history.deleteRemote();

  /// The account identity key changed (recovery, SMS takeover): the server
  /// has already deleted the history backup because nobody can open it any
  /// more. Forgets this device's bookkeeping for it (versions, last result) so
  /// the next backup starts over under the new key, and deletes any copy that
  /// is still there (best effort).
  Future<void> forgetBackupState() async {
    await _history.forgetState();
    try {
      await _history.deleteRemote();
    } on Object {
      // Already gone, or offline: the server deletes it on a key change.
    }
  }

  // -------------------------------------------------------- full backup

  /// Creates the manual backup under [recoverySecret] (16 characters or 6
  /// words) and, if given, a 32-byte [platformKey] from the platform's
  /// credential store. [mediaIds] lists the backup-kind media objects the
  /// backup refers to. Throws [BackupException] (`weakSecret`, `tooLarge`,
  /// ...). The secret is used and dropped; it is never stored or sent.
  Future<BackupResult> createFullBackup({
    required String recoverySecret,
    List<int>? platformKey,
    List<String> mediaIds = const [],
  }) => _full.create(
    recoverySecret: recoverySecret,
    platformKey: platformKey,
    mediaIds: mediaIds,
  );

  /// Opens the server's full backup with [recoverySecret] or [platformKey] and
  /// merges its history. The result carries the identity secrets for the
  /// account flow. Throws [BackupException] (`noBackup`, `wrongKey`, ...).
  Future<FullBackupRestore> restoreFullBackup({
    String? recoverySecret,
    List<int>? platformKey,
  }) => _full.restore(recoverySecret: recoverySecret, platformKey: platformKey);

  Future<void> deleteFullBackup() => _full.deleteRemote();

  // ------------------------------------------------ device-to-device

  /// Sends this device's history to [devices] (default: all other devices of
  /// the account) through the media relay. Returns the transfer id once the
  /// offer is queued; follow it on [transferProgress]. Throws
  /// [BackupException] (`noOtherDevices`, `cancelled`, `offline`, ...).
  Future<String> sendHistory({List<String>? devices}) =>
      _transfer.send(to: devices);

  /// Withdraws an offer this device made (or stops it while it is uploading).
  Future<void> cancelSend(String transferId) =>
      _transfer.cancelSend(transferId);

  /// Offers from this account's other devices, newest first (live).
  Stream<List<TransferOffer>> watchOffers() => _ledger
      .watchIncoming()
      .map(
        (offers) => [
          for (final o in offers.values)
            TransferOffer(
              transferId: o.transferId,
              fromDevice: o.fromDevice,
              receivedAt: o.receivedAt,
              phase: o.phase,
              done: o.phase == TransferPhase.importing ? o.imported : 0,
              total: o.total,
              failure: BackupFailure.values.asNameMap()[o.error],
            ),
        ]..sort((a, b) => b.receivedAt.compareTo(a.receivedAt)),
      )
      .distinct(_sameOffers);

  static bool _sameOffers(List<TransferOffer> a, List<TransferOffer> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((e) => e);

  Future<List<TransferOffer>> offers() => watchOffers().first;

  /// Fetches and imports an offer. Resumes after a failure or a restart
  /// (fetched chunks are kept; gaps are asked for again). Completes with what
  /// was imported. Throws [BackupException] (`expired`, `corrupt`, ...).
  Future<RestoreResult> acceptOffer(String transferId) =>
      _transfer.accept(transferId);

  /// Declines an offer: nothing is fetched, the sender is told.
  Future<void> declineOffer(String transferId) => _transfer.decline(transferId);

  /// Stops fetching or importing an offer; it can be accepted again.
  void pauseTransfer(String transferId) => _transfer.pause(transferId);

  // -------------------------------------------------------- lifecycle

  /// Starts reacting to the account: a new device joining (offer it history
  /// from the longest-linked device) and offers arriving (accept them, when
  /// [BackupOptions.autoAcceptTransfers] is on). Called by the engine with its
  /// workers.
  void start() {
    if (_started) return;
    _started = true;
    _subscriptions
      ..add(
        _ctx.events.listen((event) {
          if (event is OwnDevicesChanged) unawaited(_offerToNewDevices());
        }),
      )
      ..add(_ledger.watchIncoming().listen((_) => unawaited(_resumeOffers())));
  }

  Future<void> stop() async {
    _started = false;
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
  }

  Future<void> close() async {
    await stop();
    await _backupEvents.close();
    await _restoreEvents.close();
    await _transferEvents.close();
  }

  /// One housekeeping pass: remove relay objects and stale offers, retry
  /// offers that were waiting for the network, and run the automatic backup
  /// when it is due. Failures are recorded in the status, not thrown.
  Future<void> runMaintenance() async {
    if (!_ctx.isSignedIn) return;
    try {
      await _transfer.cleanUp();
      await _resumeOffers(retryFailed: true);
      final status = await this.status();
      if (!status.autoBackup) return;
      final now = _ctx.now();
      final at = status.lastBackupAt;
      final attempt = status.lastAttemptAt;
      final due = at == null || now.difference(at) >= _options.backupInterval;
      final cooled =
          attempt == null ||
          status.lastFailure == null ||
          now.difference(attempt) >= _options.retryInterval;
      if (due && cooled) await _history.backUp();
    } on Object {
      // Offline, signed out, or the database closed: next pass.
    }
  }

  // -------------------------------------------------------------- hooks

  /// Starts every offer that is waiting. With [retryFailed] also those that
  /// stopped on a network error.
  Future<void> _resumeOffers({bool retryFailed = false}) async {
    if (!_options.autoAcceptTransfers || !_ctx.isSignedIn) return;
    try {
      for (final offer in (await _ledger.incoming()).values) {
        final fresh =
            offer.phase == TransferPhase.waiting && offer.error == null;
        final retry =
            retryFailed &&
            offer.phase == TransferPhase.waiting &&
            offer.error == BackupFailure.offline.name;
        if (fresh || retry) {
          unawaited(
            _transfer
                .accept(offer.transferId)
                .then<void>((_) {}, onError: (Object _) {}),
          );
        }
      }
    } on Object {
      // The database closed.
    }
  }

  /// A device joined: the longest-linked device that was here before it
  /// offers it the history. Which devices are new is read from their link
  /// times against a cursor (`BackupSettings.offerCursor`, initially this
  /// device's own link time), so every device reaches the same answer.
  Future<void> _offerToNewDevices() async {
    if (!_options.autoTransferToNewDevices || !_ctx.isSignedIn) return;
    try {
      final rows = await _transfer.senderOrder();
      final self = rows.where((r) => r.isThisDevice).firstOrNull;
      final selfLinked = self?.linkedAt;
      if (self == null || selfLinked == null) return;
      final stored = await _ctx.db.settingsDao.get(BackupSettings.offerCursor);
      final cursor = stored ?? selfLinked.millisecondsSinceEpoch;
      final fresh = [
        for (final r in rows)
          if (!r.isThisDevice &&
              (r.linkedAt?.millisecondsSinceEpoch ?? 0) > cursor)
            r,
      ];
      if (fresh.isEmpty) return;
      final newest = fresh
          .map((r) => r.linkedAt!.millisecondsSinceEpoch)
          .reduce((a, b) => a > b ? a : b);
      await _ctx.db.settingsDao.set(
        BackupSettings.offerCursor,
        newest,
        now: _ctx.now(),
      );
      final freshIds = {for (final r in fresh) r.deviceId};
      final senders = rows.where((r) => !freshIds.contains(r.deviceId));
      if (senders.isEmpty || !senders.first.isThisDevice) return;
      await _transfer.send(to: freshIds.toList());
    } on Object {
      // No network, nothing to send, or no other device: the user can still
      // send history by hand.
    }
  }
}
