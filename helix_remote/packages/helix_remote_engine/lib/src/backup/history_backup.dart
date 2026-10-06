import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart' show ApiException;
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/backup/archive.dart';
import 'package:helix_remote_engine/src/backup/errors.dart';
import 'package:helix_remote_engine/src/backup/models.dart';
import 'package:helix_remote_engine/src/backup/options.dart';
import 'package:helix_remote_engine/src/backup/snapshot.dart';
import 'package:helix_remote_engine/src/backup/state.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode, HistoryBackup;

/// The automatic history backup (CRYPTO_V2.md §13, BACKUP_RECOVERY.md).
///
/// One blob per account on the server, keyed from the account identity key
/// (`HistoryBackupCrypto`), so every device of the account can write and read
/// it and nobody else can. The server keeps only the newest and refuses a
/// version that does not exceed the stored one.
///
/// **Versions and merging.** [backUp] uploads `version + 1` of the highest
/// version this device wrote or merged. If another device got further the
/// server answers `version_conflict`; the job then downloads that backup,
/// merges it into the local history (restore is a merge) and uploads again on
/// top of it. So a device that knows less never overwrites a backup that holds
/// more, and any device may write it. A device whose history is empty uploads
/// nothing.
///
/// **Size.** The archive is built a page at a time and stops before the frame
/// that would pass the server's 16 MiB (so the oldest messages drop out, and
/// the status says so); the whole backup is therefore never more than the
/// limit in memory. When the server still says 413 the budget is halved
/// (from the size that was refused).
final class HistoryBackupJob {
  HistoryBackupJob(
    this._ctx,
    this._options,
    this._remote,
    this._exporter,
    this._importer, {
    required this._onBackup,
    required this._onRestore,
  });

  final EngineContext _ctx;
  final BackupOptions _options;
  final BackupRemote _remote;
  final SnapshotExporter _exporter;
  final SnapshotImporter _importer;
  final void Function(BackupProgress) _onBackup;
  final void Function(RestoreProgress) _onRestore;

  /// Version byte + nonce + tag around the archive.
  static const sealOverhead = 1 + Aead.nonceLength + Aead.tagLength;

  Future<BackupResult>? _backingUp;
  Future<RestoreResult>? _restoring;

  HelixDb get _db => _ctx.db;

  Future<HistoryBackupState> state() async => HistoryBackupState.decode(
    await _db.settingsDao.get(BackupSettings.history),
  );

  Future<void> _save(HistoryBackupState state) => _db.settingsDao.set(
    BackupSettings.history,
    state.encode(),
    now: _ctx.now(),
  );

  // ------------------------------------------------------------ back up

  /// Builds and uploads the backup. Concurrent calls share one run.
  Future<BackupResult> backUp() =>
      _backingUp ??= _backUp().whenComplete(() => _backingUp = null);

  Future<BackupResult> _backUp() async {
    final identity = _ctx.identity;
    if (await HistoryStore(_db).messageCount() == 0) {
      return const BackupResult.skipped();
    }
    await _save((await state()).copyWith(attemptAt: _ctx.now()));
    _onBackup(const BackupProgress(BackupPhase.preparing));
    try {
      final result = await _upload(
        identity.accountId,
        identity.accountKey.seed,
      );
      final saved = (await state()).copyWith(
        version: result.version,
        at: _ctx.now(),
        messages: result.messages,
        bytes: result.bytes,
        truncated: result.truncated,
        clearFailure: true,
      );
      await _save(saved);
      _onBackup(
        BackupProgress(
          BackupPhase.done,
          messages: result.messages,
          bytes: result.bytes,
          version: result.version,
        ),
      );
      return result;
    } on Object catch (error) {
      final failure = BackupException.translate(error);
      if (failure is BackupException) {
        await _save((await state()).copyWith(failure: failure.failure));
        _onBackup(BackupProgress(BackupPhase.failed, failure: failure.failure));
        throw failure;
      }
      _onBackup(const BackupProgress(BackupPhase.failed));
      rethrow;
    }
  }

  Future<BackupResult> _upload(String accountId, Uint8List seed) async {
    var budget = _options.maxHistoryBytes - sealOverhead;
    var current = await state();
    for (var attempt = 0; attempt < 8; attempt++) {
      final version = current.version + 1;
      final stats = ExportStats();
      final frames = <ArchiveFrame>[];
      await for (final frame in _exporter.export(
        kind: ArchiveKind.history,
        stats: stats,
        maxBytes: budget,
      )) {
        frames.add(frame);
        _onBackup(
          BackupProgress(
            BackupPhase.preparing,
            messages: stats.messages,
            bytes: stats.bytes,
          ),
        );
      }
      final data = await HistoryBackupCrypto.seal(
        identityKeySeed: seed,
        accountId: accountId,
        version: version,
        plaintext: joinFrames(frames),
        random: _ctx.random,
      );
      _onBackup(
        BackupProgress(
          BackupPhase.uploading,
          messages: stats.messages,
          bytes: data.length,
          version: version,
        ),
      );
      try {
        await _remote.putHistory(HistoryBackup(version: version, data: data));
        return BackupResult(
          version: version,
          messages: stats.messages,
          bytes: data.length,
          truncated: stats.truncated,
        );
      } on ApiException catch (e) {
        if (e.code == ErrorCode.versionConflict) {
          // Another device got further: take what it has, then go on top.
          current = await _catchUp(current, accountId, seed);
          continue;
        }
        if (e.code == ErrorCode.payloadTooLarge) {
          // Aim well under what was just refused, and under the old budget.
          budget = (data.length < budget ? data.length : budget) ~/ 2;
          if (budget < 4096) {
            throw const BackupException(BackupFailure.tooLarge);
          }
          continue;
        }
        rethrow;
      }
    }
    throw const BackupException(BackupFailure.conflict, 'kept losing the race');
  }

  /// Merges the server's backup into the local history and returns the state
  /// at its version. An unreadable newer backup is overwritten (nobody can
  /// use it); one from a newer format is not (the other device is ahead of
  /// this app).
  Future<HistoryBackupState> _catchUp(
    HistoryBackupState state,
    String accountId,
    Uint8List seed,
  ) async {
    final remote = await _remote.history();
    if (remote == null) return state;
    try {
      await _merge(remote, accountId, seed);
    } on BackupException catch (e) {
      if (e.failure == BackupFailure.newerFormat ||
          e.failure == BackupFailure.accountMismatch ||
          e.failure == BackupFailure.compressionUnavailable) {
        rethrow;
      }
    }
    final next = state.copyWith(
      version: remote.version > state.version ? remote.version : null,
    );
    await _save(next);
    return next;
  }

  // ------------------------------------------------------------ restore

  /// Downloads the backup, opens it with the account key, and merges it into
  /// the local history. Concurrent calls share one run.
  ///
  /// Throws [BackupException]: `noBackup`, `wrongKey` (not made under this
  /// account's key), `corrupt`, `newerFormat`, `rolledBack` (the server's
  /// version is older than one this device already knew) or `offline`.
  Future<RestoreResult> restore() =>
      _restoring ??= _restore().whenComplete(() => _restoring = null);

  Future<RestoreResult> _restore() async {
    final identity = _ctx.identity;
    _onRestore(const RestoreProgress(RestorePhase.downloading));
    try {
      final remote = await _remote.history();
      if (remote == null) throw const BackupException(BackupFailure.noBackup);
      final known = (await state()).version;
      if (remote.version < known) {
        throw const BackupException(BackupFailure.rolledBack);
      }
      final result = await _merge(
        remote,
        identity.accountId,
        identity.accountKey.seed,
      );
      final saved = await state();
      if (remote.version > saved.version) {
        await _save(saved.copyWith(version: remote.version));
      }
      _onRestore(
        RestoreProgress(
          RestorePhase.done,
          added: result.added,
          existing: result.existing,
        ),
      );
      return result;
    } on Object catch (error) {
      final failure = BackupException.translate(error);
      if (failure is BackupException) {
        _onRestore(
          RestoreProgress(RestorePhase.failed, failure: failure.failure),
        );
        throw failure;
      }
      _onRestore(const RestoreProgress(RestorePhase.failed));
      rethrow;
    }
  }

  Future<RestoreResult> _merge(
    HistoryBackup remote,
    String accountId,
    Uint8List seed,
  ) async {
    _onRestore(const RestoreProgress(RestorePhase.decrypting));
    final data = remote.data;
    if (data.isNotEmpty && data[0] > HistoryBackupCrypto.formatVersion) {
      throw const BackupException(BackupFailure.newerFormat, 'history format');
    }
    final Uint8List plaintext;
    try {
      plaintext = await HistoryBackupCrypto.open(
        identityKeySeed: seed,
        accountId: accountId,
        version: remote.version,
        data: data,
      );
    } on DecryptionFailedException {
      throw const BackupException(BackupFailure.wrongKey);
    } on MalformedCryptoInputException {
      throw const BackupException(BackupFailure.corrupt, 'history header');
    }
    final session = _importer.begin(kind: ArchiveKind.history);
    for (final frame in ArchiveReader.frames(plaintext, gzip: _options.gzip)) {
      await session.addFrame(frame);
      _onRestore(
        RestoreProgress(
          RestorePhase.importing,
          added: session.report.messagesAdded,
          existing: session.report.messagesExisting,
        ),
      );
    }
    session.finish();
    return RestoreResult(
      version: remote.version,
      added: session.report.messagesAdded,
      existing: session.report.messagesExisting,
      invalid: session.report.invalidRecords,
    );
  }

  // ------------------------------------------------------------- delete

  /// Removes the backup from the server and forgets the local bookkeeping.
  /// (The server also deletes it by itself when the account identity key
  /// changes, because nobody can open it any more: see
  /// `BackupService.forgetBackupState`.)
  Future<void> deleteRemote() async {
    try {
      await _remote.deleteHistory();
    } on Object catch (error) {
      final failure = BackupException.translate(error);
      if (failure is BackupException) throw failure;
      rethrow;
    }
    await _save(const HistoryBackupState());
  }

  Future<void> forgetState() => _save(const HistoryBackupState());
}
