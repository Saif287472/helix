import 'package:helix_remote_engine/src/backup/errors.dart';
import 'package:helix_remote_engine/src/backup/snapshot.dart'
    show ArchiveSecrets;
import 'package:meta/meta.dart';

// ------------------------------------------------------------ backing up

enum BackupPhase { idle, preparing, uploading, done, failed }

/// Progress of a history or full backup (`BackupService.backupProgress`).
@immutable
final class BackupProgress {
  const BackupProgress(
    this.phase, {
    this.messages = 0,
    this.bytes = 0,
    this.version,
    this.failure,
    this.full = false,
  });

  static const idle = BackupProgress(BackupPhase.idle);

  final BackupPhase phase;

  /// Messages written so far (final once [phase] is `uploading` or later).
  final int messages;
  final int bytes;
  final int? version;
  final BackupFailure? failure;

  /// The manual full backup rather than the automatic history backup.
  final bool full;
}

/// What a finished backup did.
@immutable
final class BackupResult {
  const BackupResult({
    required this.version,
    required this.messages,
    required this.bytes,
    required this.truncated,
    this.skipped = false,
  });

  /// Nothing was uploaded: there was no history to back up.
  const BackupResult.skipped()
    : version = 0,
      messages = 0,
      bytes = 0,
      truncated = false,
      skipped = true;

  final int version;
  final int messages;
  final int bytes;

  /// The oldest messages were left out to fit the size limit.
  final bool truncated;
  final bool skipped;
}

/// The state of the automatic history backup and the last full backup, for
/// the settings page (`BackupService.watchStatus`).
@immutable
final class BackupStatus {
  const BackupStatus({
    this.autoBackup = true,
    this.lastBackupAt,
    this.version,
    this.messages = 0,
    this.bytes = 0,
    this.truncated = false,
    this.lastAttemptAt,
    this.lastFailure,
    this.lastFullBackupAt,
    this.fullVersion,
  });

  final bool autoBackup;

  /// When a history backup last reached the server.
  final DateTime? lastBackupAt;
  final int? version;
  final int messages;
  final int bytes;
  final bool truncated;
  final DateTime? lastAttemptAt;

  /// Why the last attempt failed (cleared by the next success).
  final BackupFailure? lastFailure;
  final DateTime? lastFullBackupAt;
  final int? fullVersion;

  @override
  bool operator ==(Object other) =>
      other is BackupStatus &&
      other.autoBackup == autoBackup &&
      other.lastBackupAt == lastBackupAt &&
      other.version == version &&
      other.messages == messages &&
      other.bytes == bytes &&
      other.truncated == truncated &&
      other.lastAttemptAt == lastAttemptAt &&
      other.lastFailure == lastFailure &&
      other.lastFullBackupAt == lastFullBackupAt &&
      other.fullVersion == fullVersion;

  @override
  int get hashCode => Object.hash(
    autoBackup,
    lastBackupAt,
    version,
    messages,
    bytes,
    truncated,
    lastAttemptAt,
    lastFailure,
    lastFullBackupAt,
    fullVersion,
  );
}

// ------------------------------------------------------------- restoring

enum RestorePhase { idle, downloading, decrypting, importing, done, failed }

/// Progress of a restore (`BackupService.restoreProgress`).
@immutable
final class RestoreProgress {
  const RestoreProgress(
    this.phase, {
    this.added = 0,
    this.existing = 0,
    this.failure,
    this.full = false,
  });

  static const idle = RestoreProgress(RestorePhase.idle);

  final RestorePhase phase;

  /// Messages new to this device so far, and ones it already had.
  final int added;
  final int existing;
  final BackupFailure? failure;
  final bool full;
}

@immutable
final class RestoreResult {
  const RestoreResult({
    required this.version,
    required this.added,
    required this.existing,
    required this.invalid,
  });

  /// The server's backup version that was restored.
  final int version;
  final int added;
  final int existing;

  /// Records skipped because they failed a check.
  final int invalid;
}

/// A restored full backup. The identity secrets are for the account flow
/// (recovering an account whose identity key this is); [identityMatches] says
/// whether they are the signed-in account's own key.
@immutable
final class FullBackupRestore {
  const FullBackupRestore({
    required this.result,
    required this.identityMatches,
    this.secrets,
  });

  final RestoreResult result;
  final bool identityMatches;

  /// Null when the archive carried none. Redacted in `toString`.
  final ArchiveSecrets? secrets;
}

// ------------------------------------------------------------- transfers

enum TransferRole { sending, receiving }

enum TransferPhase {
  /// Sender: reading the history and uploading segments.
  preparing,

  /// Sender: the offer is out; waiting for the other device(s).
  offered,

  /// Receiver: an offer is here and has not been accepted.
  waiting,

  /// Receiver: fetching segments.
  downloading,

  /// Receiver: all segments are in; applying them.
  importing,
  done,
  declined,
  cancelled,
  failed;

  bool get isFinished =>
      this == done || this == declined || this == cancelled || this == failed;
}

/// Progress of one device-to-device transfer (`BackupService.transferProgress`
/// and `watchTransfers`).
@immutable
final class TransferProgress {
  const TransferProgress({
    required this.transferId,
    required this.role,
    required this.phase,
    this.done = 0,
    this.total = 0,
    this.failure,
  });

  final String transferId;
  final TransferRole role;
  final TransferPhase phase;

  /// Segments uploaded, fetched or imported so far, of [total] (0 while
  /// unknown).
  final int done;
  final int total;
  final BackupFailure? failure;
}

/// An offer of history from another of this account's devices, for the UI
/// (`BackupService.watchOffers`). No keys in here.
@immutable
final class TransferOffer {
  const TransferOffer({
    required this.transferId,
    required this.fromDevice,
    required this.receivedAt,
    required this.phase,
    required this.done,
    required this.total,
    this.failure,
  });

  final String transferId;

  /// The offering device's id (look it up in the device list for its name).
  final String fromDevice;
  final DateTime receivedAt;

  /// `waiting` until accepted, then `downloading`, `importing`, `done` (or
  /// `declined`, `cancelled`, `failed`).
  final TransferPhase phase;

  /// Segments fetched (while downloading) or applied (while importing).
  final int done;
  final int total;
  final BackupFailure? failure;

  @override
  bool operator ==(Object other) =>
      other is TransferOffer &&
      other.transferId == transferId &&
      other.phase == phase &&
      other.done == done &&
      other.total == total &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(transferId, phase, done, total, failure);
}
