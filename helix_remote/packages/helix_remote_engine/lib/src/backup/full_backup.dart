import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart' show ApiException;
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_engine/src/backup/archive.dart';
import 'package:helix_remote_engine/src/backup/errors.dart';
import 'package:helix_remote_engine/src/backup/models.dart';
import 'package:helix_remote_engine/src/backup/options.dart';
import 'package:helix_remote_engine/src/backup/snapshot.dart';
import 'package:helix_remote_engine/src/backup/state.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode, FullBackup, JsonMap, JsonReader, Uuid;

/// The manual, user-secret backup (CRYPTO_V2.md §13, F2): envelope v3, a
/// random backup key wrapped by the user's recovery secret and, when the
/// platform has one, by a platform credential key.
///
/// It is the only place the account identity key (and this account's profile
/// key) may be written besides the encrypted local database, and it is
/// sealed, never plain: the archive is the AEAD plaintext. The server
/// refuses any envelope that carries `backup_key`, `passphrase` or
/// `recovery_phrase` at any depth, and this job refuses to send one too, and
/// refuses one that contains the recovery secret's text, before the request
/// leaves.
///
/// The envelope's `backup_id` and `version` are bound into every AEAD (the
/// associated data), so the server cannot present an old backup under a newer
/// version; on restore the id and version in the envelope must also equal the
/// ones the server reports.
///
/// Session and prekey private state, device keys and tokens are never part of
/// it; after a restore peers' first messages fail to decrypt and trigger
/// CRYPTO_V2.md §13a.
final class FullBackupJob {
  FullBackupJob(
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

  Future<FullBackupState> state() async => FullBackupState.decode(
    await _ctx.db.settingsDao.get(BackupSettings.full),
  );

  Future<void> _save(FullBackupState state) => _ctx.db.settingsDao.set(
    BackupSettings.full,
    state.encode(),
    now: _ctx.now(),
  );

  /// Whether [value] carries a field the server forbids, at any depth.
  static bool carriesForbiddenField(Object? value) => switch (value) {
    final Map<Object?, Object?> m => m.entries.any(
      (e) =>
          FullBackup.forbiddenFields.contains(e.key) ||
          carriesForbiddenField(e.value),
    ),
    final List<Object?> l => l.any(carriesForbiddenField),
    _ => false,
  };

  // ------------------------------------------------------------- create

  /// Seals the history and the account secrets under a new backup key and
  /// uploads the envelope. [mediaIds] are the backup-kind media objects the
  /// backup refers to (the server restarts their 90-day retention).
  Future<BackupResult> create({
    required String recoverySecret,
    List<int>? platformKey,
    List<String> mediaIds = const [],
  }) async {
    if (!BackupCrypto.isValidRecoverySecret(recoverySecret)) {
      throw const BackupException(BackupFailure.weakSecret);
    }
    if (platformKey != null && platformKey.length != 32) {
      throw ArgumentError.value(platformKey.length, 'platformKey.length');
    }
    final identity = _ctx.identity;
    _onBackup(const BackupProgress(BackupPhase.preparing, full: true));
    try {
      final account = await _ctx.db.accountDao.current();
      final stats = ExportStats();
      final frames = <ArchiveFrame>[];
      await for (final frame in _exporter.export(
        kind: ArchiveKind.full,
        stats: stats,
        maxBytes: _options.maxFullBytes,
        secrets: ArchiveSecrets(
          identityKeySeed: identity.accountKey.seed,
          identityKey: identity.accountKey.publicKey,
          profileKey: account?.profileKey,
        ),
      )) {
        frames.add(frame);
        _onBackup(
          BackupProgress(
            BackupPhase.preparing,
            messages: stats.messages,
            bytes: stats.bytes,
            full: true,
          ),
        );
      }
      final archive = joinFrames(frames);
      var version = (await state()).version + 1;
      for (var attempt = 0; attempt < 3; attempt++) {
        final backupId = _ctx.ids.next();
        final envelope = await BackupCrypto.seal(
          plaintext: archive,
          backupId: backupId,
          backupVersion: version,
          recoverySecret: recoverySecret,
          createdAt: _ctx.now(),
          random: _ctx.random,
          platformKey: platformKey,
        );
        final json = envelope.toJson();
        _refuseSecrets(json, recoverySecret);
        final size = utf8.encode(jsonEncode(json)).length;
        if (size > FullBackup.maxEnvelopeBytes) {
          throw const BackupException(BackupFailure.tooLarge);
        }
        _onBackup(
          BackupProgress(
            BackupPhase.uploading,
            messages: stats.messages,
            bytes: size,
            version: version,
            full: true,
          ),
        );
        try {
          await _remote.putFull(
            FullBackup(
              backupId: backupId,
              version: version,
              envelope: json,
              mediaIds: mediaIds,
            ),
          );
        } on ApiException catch (e) {
          if (e.code != ErrorCode.versionConflict) rethrow;
          final remote = await _remote.full();
          version = (remote?.version ?? version) + 1;
          continue;
        }
        await _save(FullBackupState(version: version, at: _ctx.now()));
        _onBackup(
          BackupProgress(
            BackupPhase.done,
            messages: stats.messages,
            bytes: size,
            version: version,
            full: true,
          ),
        );
        return BackupResult(
          version: version,
          messages: stats.messages,
          bytes: size,
          truncated: stats.truncated,
        );
      }
      throw const BackupException(BackupFailure.conflict);
    } on Object catch (error) {
      final failure = BackupException.translate(error);
      if (failure is BackupException) {
        _onBackup(
          BackupProgress(
            BackupPhase.failed,
            failure: failure.failure,
            full: true,
          ),
        );
        throw failure;
      }
      rethrow;
    }
  }

  void _refuseSecrets(JsonMap envelope, String recoverySecret) {
    if (carriesForbiddenField(envelope)) {
      throw StateError('a backup envelope must not carry a forbidden field');
    }
    if (jsonEncode(envelope).contains(recoverySecret)) {
      throw StateError('a backup envelope must not contain the secret');
    }
  }

  // ------------------------------------------------------------ restore

  /// Opens the server's full backup with [recoverySecret] (or [platformKey])
  /// and merges its history into this device; the result carries the
  /// identity secrets for the account flow. Needs a signed-in device (the
  /// download is authenticated and account-owned).
  Future<FullBackupRestore> restore({
    String? recoverySecret,
    List<int>? platformKey,
  }) async {
    final identity = _ctx.identity;
    _onRestore(const RestoreProgress(RestorePhase.downloading, full: true));
    try {
      final remote = await _remote.full();
      if (remote == null) throw const BackupException(BackupFailure.noBackup);
      if (remote.version < (await state()).version) {
        throw const BackupException(BackupFailure.rolledBack);
      }
      final envelope = _parse(remote);
      _onRestore(const RestoreProgress(RestorePhase.decrypting, full: true));
      final Uint8List plaintext;
      try {
        plaintext = await BackupCrypto.open(
          envelope,
          recoverySecret: recoverySecret,
          platformKey: platformKey,
        );
      } on DecryptionFailedException {
        throw const BackupException(BackupFailure.wrongKey);
      }
      final session = _importer.begin(kind: ArchiveKind.full);
      for (final frame in ArchiveReader.frames(
        plaintext,
        gzip: _options.gzip,
      )) {
        await session.addFrame(frame);
        _onRestore(
          RestoreProgress(
            RestorePhase.importing,
            added: session.report.messagesAdded,
            existing: session.report.messagesExisting,
            full: true,
          ),
        );
      }
      session.finish();
      final saved = await state();
      if (remote.version > saved.version) {
        await _save(FullBackupState(version: remote.version, at: saved.at));
      }
      final secrets = session.secrets;
      final result = RestoreResult(
        version: remote.version,
        added: session.report.messagesAdded,
        existing: session.report.messagesExisting,
        invalid: session.report.invalidRecords,
      );
      _onRestore(
        RestoreProgress(
          RestorePhase.done,
          added: result.added,
          existing: result.existing,
          full: true,
        ),
      );
      return FullBackupRestore(
        result: result,
        secrets: secrets,
        identityMatches:
            secrets != null &&
            bytesEqual(secrets.identityKey, identity.accountKey.publicKey),
      );
    } on Object catch (error) {
      final failure = BackupException.translate(error);
      if (failure is BackupException) {
        _onRestore(
          RestoreProgress(
            RestorePhase.failed,
            failure: failure.failure,
            full: true,
          ),
        );
        throw failure;
      }
      rethrow;
    }
  }

  BackupEnvelope _parse(FullBackup remote) {
    final version = remote.envelope['v'];
    if (version is int && version > BackupEnvelope.envelopeVersion) {
      throw const BackupException(BackupFailure.newerFormat, 'envelope');
    }
    final BackupEnvelope envelope;
    try {
      envelope = BackupEnvelope.fromJson(JsonReader.of(remote.envelope));
    } on FormatException {
      throw const BackupException(BackupFailure.corrupt, 'envelope');
    } on CryptoV2Exception {
      throw const BackupException(BackupFailure.corrupt, 'envelope');
    }
    // The server's metadata must agree with what the AEADs authenticate.
    if (envelope.backupId != remote.backupId ||
        envelope.backupVersion != remote.version ||
        !Uuid.isValid(envelope.backupId)) {
      throw const BackupException(BackupFailure.corrupt, 'envelope identity');
    }
    return envelope;
  }

  // ------------------------------------------------------------- delete

  Future<void> deleteRemote() async {
    try {
      await _remote.deleteFull();
    } on Object catch (error) {
      final failure = BackupException.translate(error);
      if (failure is BackupException) throw failure;
      rethrow;
    }
    await _save(const FullBackupState());
  }

  Future<void> forgetState() => _save(const FullBackupState());
}
