import 'package:flutter/foundation.dart' show immutable;

/// Why a backup, restore or transfer did not work, in the terms a person can
/// act on. The engine's `BackupFailure` is mapped to this in the gateway so
/// nothing above it names an engine type.
enum BackupProblem {
  noBackup,
  wrongKey,
  corrupt,
  newerFormat,
  rolledBack,
  accountMismatch,
  tooLarge,
  cancelled,
  offline,
  conflict,
  weakSecret,
  noOtherDevices,
  incomplete,
  expired,
  notAllowed,
  unknown,
}

/// A backup operation failed for a reason in [problem].
final class BackupProblemException implements Exception {
  const BackupProblemException(this.problem);

  final BackupProblem problem;

  @override
  String toString() => 'BackupProblemException(${problem.name})';
}

/// The state of the automatic history backup and the last recovery backup.
@immutable
final class BackupSummary {
  const BackupSummary({
    this.autoBackup = true,
    this.lastBackupAt,
    this.messages = 0,
    this.bytes = 0,
    this.truncated = false,
    this.lastAttemptAt,
    this.lastProblem,
    this.lastRecoveryBackupAt,
  });

  final bool autoBackup;
  final DateTime? lastBackupAt;
  final int messages;
  final int bytes;

  /// The oldest messages were left out to fit the size limit.
  final bool truncated;
  final DateTime? lastAttemptAt;
  final BackupProblem? lastProblem;
  final DateTime? lastRecoveryBackupAt;

  @override
  bool operator ==(Object other) =>
      other is BackupSummary &&
      other.autoBackup == autoBackup &&
      other.lastBackupAt == lastBackupAt &&
      other.messages == messages &&
      other.bytes == bytes &&
      other.truncated == truncated &&
      other.lastAttemptAt == lastAttemptAt &&
      other.lastProblem == lastProblem &&
      other.lastRecoveryBackupAt == lastRecoveryBackupAt;

  @override
  int get hashCode => Object.hash(
    autoBackup,
    lastBackupAt,
    messages,
    bytes,
    truncated,
    lastAttemptAt,
    lastProblem,
    lastRecoveryBackupAt,
  );
}

/// What a finished backup did.
@immutable
final class BackupOutcome {
  const BackupOutcome({
    required this.messages,
    required this.truncated,
    this.skipped = false,
  });

  final int messages;
  final bool truncated;

  /// There was no history to back up.
  final bool skipped;
}

/// What a finished restore or import did.
@immutable
final class RestoreOutcome {
  const RestoreOutcome({
    required this.added,
    required this.existing,
    this.invalid = 0,
  });

  final int added;
  final int existing;
  final int invalid;
}

/// Where a running backup is.
enum RunPhase { preparing, uploading, done, failed }

@immutable
final class BackupRunProgress {
  const BackupRunProgress(this.phase, {this.messages = 0, this.problem});

  final RunPhase phase;
  final int messages;
  final BackupProblem? problem;
}

/// Where a running restore is.
enum RestorePhase { downloading, decrypting, importing, done, failed }

@immutable
final class RestoreRunProgress {
  const RestoreRunProgress(
    this.phase, {
    this.added = 0,
    this.existing = 0,
    this.problem,
  });

  final RestorePhase phase;
  final int added;
  final int existing;
  final BackupProblem? problem;
}

enum TransferDirection { sending, receiving }

enum TransferStage {
  preparing,
  offered,
  waiting,
  downloading,
  importing,
  done,
  declined,
  cancelled,
  failed,
}

/// One device-to-device transfer, from either side.
@immutable
final class TransferView {
  const TransferView({
    required this.id,
    required this.direction,
    required this.stage,
    this.done = 0,
    this.total = 0,
    this.problem,
    this.deviceName,
  });

  final String id;
  final TransferDirection direction;
  final TransferStage stage;
  final int done;
  final int total;
  final BackupProblem? problem;

  /// The other device's name, when known.
  final String? deviceName;

  bool get isFinished =>
      stage == TransferStage.done ||
      stage == TransferStage.declined ||
      stage == TransferStage.cancelled ||
      stage == TransferStage.failed;

  /// 0..1, or null while the size is not known.
  double? get fraction => total <= 0 ? null : (done / total).clamp(0.0, 1.0);

  TransferView copyWith({
    TransferStage? stage,
    int? done,
    int? total,
    BackupProblem? problem,
    String? deviceName,
  }) => TransferView(
    id: id,
    direction: direction,
    stage: stage ?? this.stage,
    done: done ?? this.done,
    total: total ?? this.total,
    problem: problem ?? this.problem,
    deviceName: deviceName ?? this.deviceName,
  );

  @override
  bool operator ==(Object other) =>
      other is TransferView &&
      other.id == id &&
      other.direction == direction &&
      other.stage == stage &&
      other.done == done &&
      other.total == total &&
      other.problem == problem &&
      other.deviceName == deviceName;

  @override
  int get hashCode =>
      Object.hash(id, direction, stage, done, total, problem, deviceName);
}
