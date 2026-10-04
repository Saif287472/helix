import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote/features/backup/application/backup_models.dart';
import 'package:helix_remote_api/v2.dart' show NetworkException;
import 'package:helix_remote_engine/helix_remote_engine.dart' as engine;

/// Everything the backup pages need from the engine, as plain values.
///
/// An interface so the notifiers and the pages are tested against a fake: no
/// database, no network, and no key ever in a test. [EngineBackupGateway] is
/// the only implementation that touches the engine.
///
/// Every method that can fail throws [BackupProblemException].
abstract interface class BackupGateway {
  Stream<BackupSummary> watchSummary();

  /// Progress of a history or recovery backup, from the engine's broadcast
  /// stream (it carries no content and no keys).
  Stream<BackupRunProgress> get backupProgress;

  Stream<RestoreRunProgress> get restoreProgress;

  Stream<TransferView> get transferProgress;

  /// Offers of history from this account's other devices, live.
  Stream<List<TransferView>> watchOffers();

  Future<BackupOutcome> backUpNow();

  Future<void> setAutoBackup(bool enabled);

  Future<void> deleteServerBackup();

  Future<RestoreOutcome> restoreHistory();

  /// Seals the history and the account's secrets under [recoverySecret]. The
  /// secret is used and dropped: it is never stored or sent.
  Future<BackupOutcome> createRecoveryBackup(String recoverySecret);

  Future<RestoreOutcome> restoreRecoveryBackup(String recoverySecret);

  Future<void> deleteRecoveryBackup();

  /// Sends this device's history to the account's other devices; returns the
  /// transfer id.
  Future<String> sendHistory();

  Future<void> cancelSend(String transferId);

  Future<RestoreOutcome> acceptOffer(String transferId);

  Future<void> declineOffer(String transferId);

  void pauseOffer(String transferId);
}

final backupGatewayProvider = Provider<BackupGateway>(EngineBackupGateway.new);

final class EngineBackupGateway implements BackupGateway {
  EngineBackupGateway(this._ref);

  final Ref _ref;

  Future<engine.Engine> get _engine async =>
      (await _ref.read(runtimeProvider.future)).engine;

  Future<engine.BackupService> get _backup async => (await _engine).backup;

  // ----------------------------------------------------------- streams

  @override
  Stream<BackupSummary> watchSummary() async* {
    final backup = await _backup;
    yield* backup.watchStatus().map(
      (s) => BackupSummary(
        autoBackup: s.autoBackup,
        lastBackupAt: s.lastBackupAt,
        messages: s.messages,
        bytes: s.bytes,
        truncated: s.truncated,
        lastAttemptAt: s.lastAttemptAt,
        lastProblem: s.lastFailure == null ? null : _problem(s.lastFailure!),
        lastRecoveryBackupAt: s.lastFullBackupAt,
      ),
    );
  }

  @override
  Stream<BackupRunProgress> get backupProgress async* {
    final backup = await _backup;
    yield* backup.backupProgress
        .where((p) => p.phase != engine.BackupPhase.idle)
        .map(
          (p) => BackupRunProgress(
            switch (p.phase) {
              engine.BackupPhase.idle ||
              engine.BackupPhase.preparing => RunPhase.preparing,
              engine.BackupPhase.uploading => RunPhase.uploading,
              engine.BackupPhase.done => RunPhase.done,
              engine.BackupPhase.failed => RunPhase.failed,
            },
            messages: p.messages,
            problem: _maybe(p.failure),
          ),
        );
  }

  @override
  Stream<RestoreRunProgress> get restoreProgress async* {
    final backup = await _backup;
    yield* backup.restoreProgress
        .where((p) => p.phase != engine.RestorePhase.idle)
        .map(
          (p) => RestoreRunProgress(
            switch (p.phase) {
              engine.RestorePhase.idle ||
              engine.RestorePhase.downloading => RestorePhase.downloading,
              engine.RestorePhase.decrypting => RestorePhase.decrypting,
              engine.RestorePhase.importing => RestorePhase.importing,
              engine.RestorePhase.done => RestorePhase.done,
              engine.RestorePhase.failed => RestorePhase.failed,
            },
            added: p.added,
            existing: p.existing,
            problem: _maybe(p.failure),
          ),
        );
  }

  @override
  Stream<TransferView> get transferProgress async* {
    final backup = await _backup;
    yield* backup.transferProgress.map(
      (p) => TransferView(
        id: p.transferId,
        direction: p.role == engine.TransferRole.sending
            ? TransferDirection.sending
            : TransferDirection.receiving,
        stage: _stage(p.phase),
        done: p.done,
        total: p.total,
        problem: _maybe(p.failure),
      ),
    );
  }

  @override
  Stream<List<TransferView>> watchOffers() async* {
    final eng = await _engine;
    yield* eng.backup.watchOffers().asyncMap((offers) async {
      final names = <String, String?>{
        for (final d in await eng.devices.list()) d.deviceId: d.name,
      };
      return [
        for (final o in offers)
          TransferView(
            id: o.transferId,
            direction: TransferDirection.receiving,
            stage: _stage(o.phase),
            done: o.done,
            total: o.total,
            problem: _maybe(o.failure),
            deviceName: names[o.fromDevice],
          ),
      ];
    });
  }

  // ----------------------------------------------------------- actions

  @override
  Future<BackupOutcome> backUpNow() => _guard(() async {
    final result = await (await _backup).backUpNow();
    return BackupOutcome(
      messages: result.messages,
      truncated: result.truncated,
      skipped: result.skipped,
    );
  });

  @override
  Future<void> setAutoBackup(bool enabled) =>
      _guard(() async => (await _backup).setAutoBackup(enabled));

  @override
  Future<void> deleteServerBackup() =>
      _guard(() async => (await _backup).deleteHistoryBackup());

  @override
  Future<RestoreOutcome> restoreHistory() => _guard(() async {
    final result = await (await _backup).restoreHistory();
    return _outcome(result);
  });

  @override
  Future<BackupOutcome> createRecoveryBackup(String recoverySecret) =>
      _guard(() async {
        final result = await (await _backup).createFullBackup(
          recoverySecret: recoverySecret,
        );
        return BackupOutcome(
          messages: result.messages,
          truncated: result.truncated,
          skipped: result.skipped,
        );
      });

  @override
  Future<RestoreOutcome> restoreRecoveryBackup(String recoverySecret) =>
      _guard(() async {
        final restored = await (await _backup).restoreFullBackup(
          recoverySecret: recoverySecret,
        );
        // The archive also carries this account's identity secrets. They are
        // for recovering an account whose key was lost; a signed-in device
        // already has its key, and nothing here uses or shows them.
        if (restored.secrets != null && !restored.identityMatches) {
          throw const engine.BackupException(
            engine.BackupFailure.accountMismatch,
          );
        }
        return _outcome(restored.result);
      });

  @override
  Future<void> deleteRecoveryBackup() =>
      _guard(() async => (await _backup).deleteFullBackup());

  @override
  Future<String> sendHistory() =>
      _guard(() async => (await _backup).sendHistory());

  @override
  Future<void> cancelSend(String transferId) =>
      _guard(() async => (await _backup).cancelSend(transferId));

  @override
  Future<RestoreOutcome> acceptOffer(String transferId) => _guard(() async {
    final result = await (await _backup).acceptOffer(transferId);
    return _outcome(result);
  });

  @override
  Future<void> declineOffer(String transferId) =>
      _guard(() async => (await _backup).declineOffer(transferId));

  @override
  void pauseOffer(String transferId) {
    unawaited(
      _backup.then((b) => b.pauseTransfer(transferId), onError: (_) {}),
    );
  }

  // ----------------------------------------------------------- mapping

  RestoreOutcome _outcome(engine.RestoreResult r) =>
      RestoreOutcome(added: r.added, existing: r.existing, invalid: r.invalid);

  static BackupProblem? _maybe(engine.BackupFailure? failure) =>
      failure == null ? null : _problem(failure);

  static BackupProblem _problem(engine.BackupFailure failure) =>
      switch (failure) {
        engine.BackupFailure.noBackup => BackupProblem.noBackup,
        engine.BackupFailure.wrongKey => BackupProblem.wrongKey,
        engine.BackupFailure.corrupt => BackupProblem.corrupt,
        engine.BackupFailure.newerFormat => BackupProblem.newerFormat,
        engine.BackupFailure.rolledBack => BackupProblem.rolledBack,
        engine.BackupFailure.accountMismatch => BackupProblem.accountMismatch,
        engine.BackupFailure.tooLarge => BackupProblem.tooLarge,
        engine.BackupFailure.cancelled => BackupProblem.cancelled,
        engine.BackupFailure.offline => BackupProblem.offline,
        engine.BackupFailure.conflict => BackupProblem.conflict,
        engine.BackupFailure.compressionUnavailable => BackupProblem.corrupt,
        engine.BackupFailure.weakSecret => BackupProblem.weakSecret,
        engine.BackupFailure.noOtherDevices => BackupProblem.noOtherDevices,
        engine.BackupFailure.incomplete => BackupProblem.incomplete,
        engine.BackupFailure.expired => BackupProblem.expired,
        engine.BackupFailure.notAllowed => BackupProblem.notAllowed,
      };

  static TransferStage _stage(engine.HistoryTransferPhase phase) =>
      switch (phase) {
        engine.HistoryTransferPhase.preparing => TransferStage.preparing,
        engine.HistoryTransferPhase.offered => TransferStage.offered,
        engine.HistoryTransferPhase.waiting => TransferStage.waiting,
        engine.HistoryTransferPhase.downloading => TransferStage.downloading,
        engine.HistoryTransferPhase.importing => TransferStage.importing,
        engine.HistoryTransferPhase.done => TransferStage.done,
        engine.HistoryTransferPhase.declined => TransferStage.declined,
        engine.HistoryTransferPhase.cancelled => TransferStage.cancelled,
        engine.HistoryTransferPhase.failed => TransferStage.failed,
      };

  /// Runs [body], turning what the engine and API throw into a
  /// [BackupProblemException] and letting nothing else (a closed database, a
  /// bug) be mistaken for a backup problem.
  static Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on BackupProblemException {
      rethrow;
    } on engine.BackupException catch (e) {
      throw BackupProblemException(_problem(e.failure));
    } on NetworkException {
      throw const BackupProblemException(BackupProblem.offline);
    } on NoServerChosen {
      throw const BackupProblemException(BackupProblem.notAllowed);
    } on engine.EngineException {
      throw const BackupProblemException(BackupProblem.notAllowed);
    } on Object {
      throw const BackupProblemException(BackupProblem.unknown);
    }
  }
}
