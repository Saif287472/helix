import 'package:helix_remote_crypto/v2.dart' show AttachmentCrypto;
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/transfers/transfer_failure.dart';
import 'package:meta/meta.dart';

/// Where one attachment's transfer stands, for the UI.
enum TransferPhase {
  /// An incoming attachment that was not fetched (on-demand policy): the UI
  /// offers "download".
  notDownloaded,

  /// Queued, or waiting for the next retry after a failure that may pass
  /// (see [AttachmentTransferView.failure] for the last error code).
  queued,

  /// A worker is moving bytes.
  active,

  /// The file is on this device ([AttachmentTransferView.localPath]).
  ready,

  /// Given up: [AttachmentTransferView.failure] says why; the UI offers a
  /// retry.
  failed,
}

enum TransferDirection { upload, download }

/// One attachment's state and progress. Built from the attachment row and
/// its transfer job; a watch stream of these is what a bubble shows.
@immutable
final class AttachmentTransferView {
  const AttachmentTransferView({
    required this.attachmentId,
    required this.messageRowid,
    required this.kind,
    required this.phase,
    required this.bytesDone,
    required this.bytesTotal,
    this.direction,
    this.failure,
    this.lastError,
    this.localPath,
    this.thumbnailPath,
  });

  final int attachmentId;
  final int messageRowid;

  /// The attachment's kind (`image`, `voice_note`, …).
  final String kind;
  final TransferPhase phase;

  /// Null when nothing is queued or running.
  final TransferDirection? direction;

  /// Encrypted bytes moved so far and in total (what goes over the wire).
  final int bytesDone;
  final int bytesTotal;

  /// Set when [phase] is [TransferPhase.failed].
  final TransferFailure? failure;

  /// The last error code while a retry is pending (`network`, …).
  final String? lastError;
  final String? localPath;
  final String? thumbnailPath;

  /// 0 to 1.
  double get fraction => bytesTotal <= 0
      ? (phase == TransferPhase.ready ? 1 : 0)
      : (bytesDone / bytesTotal).clamp(0, 1).toDouble();

  bool get isBusy =>
      phase == TransferPhase.queued || phase == TransferPhase.active;

  /// Builds the view of [attachment] from its [job] (null when none exists).
  static AttachmentTransferView of(
    AttachmentRow attachment,
    TransferRow? thumbnailOrFileJob, {
    required int encryptionChunkBytes,
  }) {
    // A thumbnail fetch is not the attachment's transfer.
    final job = thumbnailOrFileJob?.kind == 'thumbnail'
        ? null
        : thumbnailOrFileJob;
    final total = AttachmentCrypto.ciphertextLength(
      attachment.size,
      chunkSize: encryptionChunkBytes,
    );
    final liveJob =
        job != null &&
        (job.state == TransferState.pending ||
            job.state == TransferState.inFlight);
    final failedJob = job != null && job.state == TransferState.failed;
    final TransferPhase phase;
    if (attachment.transfer == AttachmentTransfer.ready) {
      phase = TransferPhase.ready;
    } else if (failedJob || attachment.transfer == AttachmentTransfer.failed) {
      phase = TransferPhase.failed;
    } else if (liveJob) {
      phase = job.state == TransferState.inFlight
          ? TransferPhase.active
          : TransferPhase.queued;
    } else if (attachment.transfer == AttachmentTransfer.remote) {
      phase = TransferPhase.notDownloaded;
    } else {
      phase = TransferPhase.queued;
    }
    final direction = job == null
        ? (attachment.transfer == AttachmentTransfer.uploading
              ? TransferDirection.upload
              : null)
        : (job.kind == 'upload'
              ? TransferDirection.upload
              : TransferDirection.download);
    return AttachmentTransferView(
      attachmentId: attachment.id,
      messageRowid: attachment.messageRowid,
      kind: attachment.kind,
      phase: phase,
      bytesDone: phase == TransferPhase.ready
          ? total
          : (liveJob || failedJob ? job.offset.clamp(0, total) : 0),
      bytesTotal: total,
      direction: phase == TransferPhase.ready ? null : direction,
      failure: phase == TransferPhase.failed
          ? (TransferFailure.fromWire(job?.lastError) ??
                TransferFailure.unknown)
          : null,
      lastError: phase == TransferPhase.queued ? job?.lastError : null,
      localPath: attachment.localPath,
      thumbnailPath: attachment.thumbnailPath,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AttachmentTransferView &&
      other.attachmentId == attachmentId &&
      other.phase == phase &&
      other.bytesDone == bytesDone &&
      other.bytesTotal == bytesTotal &&
      other.direction == direction &&
      other.failure == failure &&
      other.lastError == lastError &&
      other.localPath == localPath &&
      other.thumbnailPath == thumbnailPath;

  @override
  int get hashCode => Object.hash(
    attachmentId,
    phase,
    bytesDone,
    bytesTotal,
    direction,
    failure,
    lastError,
    localPath,
    thumbnailPath,
  );

  @override
  String toString() =>
      'AttachmentTransferView(#$attachmentId $phase '
      '$bytesDone/$bytesTotal ${failure?.wire ?? ''})';
}
