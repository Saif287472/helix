import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode;

/// Why a backup, restore or transfer did not work, in terms the app can act
/// on. Never carries message content, keys, secrets or codes.
enum BackupFailure {
  /// The server holds no backup of that kind (or the offer is unknown).
  noBackup,

  /// The key does not open it: a wrong recovery secret, or (history backup,
  /// transfer) data that was not made under this account's key.
  wrongKey,

  /// The bytes are damaged or are not a Helix backup (a bad frame, a failed
  /// digest, a header that does not match what was asked for).
  corrupt,

  /// Made by a newer Helix than this one reads. Update the app.
  newerFormat,

  /// The server returned an older backup than this device already knows
  /// (a rollback), so it was not used.
  rolledBack,

  /// The backup belongs to another account.
  accountMismatch,

  /// The history does not fit the server's size limit even after trimming.
  tooLarge,

  /// The caller cancelled.
  cancelled,

  /// The network or the server is unavailable; try again later.
  offline,

  /// A newer backup is on the server and could not be merged.
  conflict,

  /// The backup is compressed and this engine was given no gzip codec.
  compressionUnavailable,

  /// The recovery secret does not meet the policy (at least 20 characters).
  weakSecret,

  /// This is the only device; there is nobody to send history to.
  noOtherDevices,

  /// The transfer is incomplete: segments are missing or the offer vanished.
  incomplete,

  /// The relay (media) object is gone or expired.
  expired,

  /// The signed-in session does not allow it (signed out, suspended).
  notAllowed,
}

/// Thrown by `BackupService` operations. [failure] is what to show;
/// [detail] is a short technical note for logs (no content).
final class BackupException implements Exception {
  const BackupException(this.failure, [this.detail]);

  final BackupFailure failure;
  final String? detail;

  @override
  String toString() =>
      'BackupException(${failure.name}${detail == null ? '' : ': $detail'})';

  /// The [BackupException] for anything an operation can throw: network and
  /// server errors, crypto failures, cancellation. Unexpected errors (bugs,
  /// a closed database) are returned as they are.
  static Object translate(Object error) {
    switch (error) {
      case BackupException():
        return error;
      case RequestCancelledException():
        return const BackupException(BackupFailure.cancelled);
      case NetworkException():
        return const BackupException(BackupFailure.offline, 'network');
      case SignedOutException():
        return const BackupException(BackupFailure.notAllowed, 'signed out');
      case ApiException(:final code):
        return BackupException(switch (code) {
          ErrorCode.versionConflict => BackupFailure.conflict,
          ErrorCode.payloadTooLarge ||
          ErrorCode.quotaExceeded => BackupFailure.tooLarge,
          ErrorCode.notFound => BackupFailure.noBackup,
          ErrorCode.expired => BackupFailure.expired,
          _ when code.isRetryable => BackupFailure.offline,
          _ => BackupFailure.notAllowed,
        }, code.wire);
      case DecryptionFailedException():
        return const BackupException(BackupFailure.wrongKey);
      case CryptoV2Exception():
        return const BackupException(BackupFailure.corrupt, 'crypto');
      default:
        return error;
    }
  }
}
