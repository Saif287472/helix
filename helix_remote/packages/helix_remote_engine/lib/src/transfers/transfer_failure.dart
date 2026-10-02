import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart' show CryptoV2Exception;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ErrorCode;

/// Why a transfer failed for good. Stored in the job as its error code
/// (never content) and shown by the UI; a retry from the UI starts it again.
enum TransferFailure {
  /// The account has used up its media storage on the server.
  quotaExceeded('quota_exceeded'),

  /// The file is larger than the server accepts (or than this device will
  /// fetch).
  tooLarge('too_large'),

  /// The local file is gone or changed size: it cannot be uploaded.
  fileMissing('file_missing'),

  /// The downloaded bytes are not the ones the sender described.
  digestMismatch('digest_mismatch'),

  /// The bytes did not decrypt (damaged or tampered with).
  decryptFailed('decrypt_failed'),

  /// The object's size is not what the pointer says.
  sizeMismatch('size_mismatch'),

  /// The server no longer has the object (30 days after the upload, or it
  /// was deleted).
  expired('expired'),

  /// The server refused (not allowed, blocked, suspended, bad request).
  rejected('rejected'),

  /// The transfer kept failing on the network until it ran out of time.
  gaveUp('gave_up'),

  /// Anything else.
  unknown('unknown');

  const TransferFailure(this.wire);

  /// The code stored in `transfer_jobs.last_error`.
  final String wire;

  static TransferFailure? fromWire(String? code) {
    if (code == null) return null;
    for (final failure in values) {
      if (failure.wire == code) return failure;
    }
    return null;
  }
}

/// A transfer step that cannot succeed by retrying.
final class TransferException implements Exception {
  const TransferException(this.failure);

  final TransferFailure failure;

  @override
  String toString() => 'TransferException(${failure.wire})';
}

/// What the worker does after an attempt threw.
sealed class TransferOutcome {
  const TransferOutcome();
}

/// Try again later; the job keeps its progress.
final class RetryTransfer extends TransferOutcome {
  const RetryTransfer(this.code, {this.atLeast});

  final String code;
  final Duration? atLeast;
}

/// Give up; the UI offers a retry.
final class FailTransfer extends TransferOutcome {
  const FailTransfer(this.failure);

  final TransferFailure failure;
}

/// The session ended: wait for the next sign-in.
final class TransferSessionEnded extends TransferOutcome {
  const TransferSessionEnded();
}

/// The server says this device is revoked.
final class TransferDeviceRevoked extends TransferOutcome {
  const TransferDeviceRevoked();
}

/// The job was cancelled or the worker is stopping: nothing to record.
final class TransferInterrupted extends TransferOutcome {
  const TransferInterrupted();
}

/// Sorts an error from a transfer step into what to do next.
TransferOutcome classifyTransferError(Object error) {
  switch (error) {
    case TransferException():
      return FailTransfer(error.failure);
    case RequestCancelledException():
      return const TransferInterrupted();
    case NetworkException():
      return const RetryTransfer('network');
    case SignedOutException():
      return const TransferSessionEnded();
    case MalformedResponseException():
      return const RetryTransfer('bad_response');
    case ApiException():
      switch (error.code) {
        case ErrorCode.deviceRevoked:
          return const TransferDeviceRevoked();
        case ErrorCode.quotaExceeded:
          return const FailTransfer(TransferFailure.quotaExceeded);
        case ErrorCode.payloadTooLarge:
          return const FailTransfer(TransferFailure.tooLarge);
        case ErrorCode.notFound || ErrorCode.expired:
          return const FailTransfer(TransferFailure.expired);
        default:
      }
      if (error.isRetryable || error.isUnauthenticated) {
        return RetryTransfer(error.code.wire, atLeast: error.retryAfter);
      }
      if (error.status >= 500) return RetryTransfer(error.code.wire);
      return const FailTransfer(TransferFailure.rejected);
    case CryptoV2Exception():
      return const FailTransfer(TransferFailure.decryptFailed);
    default:
      return const RetryTransfer('internal');
  }
}
