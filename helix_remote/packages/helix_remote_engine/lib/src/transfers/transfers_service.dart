import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/transfers/outbound_media.dart';
import 'package:helix_remote_engine/src/transfers/transfer_worker.dart';

/// The transfer queue as a whole (a "downloads" screen, a badge, headless
/// hosts). Per-attachment progress is `MediaService.watchMessage`.
final class TransfersService {
  TransfersService(this._ctx, this._worker, this._outbound);

  final EngineContext _ctx;
  final TransferWorker? _worker;
  final OutboundMedia _outbound;

  HelixDb get _db => _ctx.db;

  /// Jobs that are queued, running or failed, oldest first, live. Each has
  /// its `kind` (`upload`, `download`, `thumbnail`), `state`, `offset` and
  /// last error code.
  Stream<List<TransferRow>> watchQueue() => _db.transfersDao.watchLive();

  /// How many transfers are queued or running.
  Future<int> pendingCount() async => (await _db.transfersDao.pending()).length;

  /// Queues every failed transfer again. Returns how many.
  Future<int> retryFailed() => _db.transaction(() async {
    var count = 0;
    for (final job in await _db.transfersDao.live()) {
      if (job.state != TransferState.failed) continue;
      final attachmentId = job.attachmentRowid;
      final attachment = attachmentId == null
          ? null
          : await _db.messagesDao.attachmentById(attachmentId);
      if (attachment == null) continue;
      if (job.kind == 'upload') {
        // The message's held send comes back with its uploads.
        if (!await _outbound.retry(attachment.messageRowid)) continue;
      } else if (job.kind == 'download') {
        await _db.transfersDao.enqueueDownload(
          attachmentRowid: attachment.id,
          mediaId: attachment.mediaId,
          mediaKey: attachment.mediaKey,
          size: attachment.size,
          now: _ctx.now(),
        );
        await _db.messagesDao.updateAttachment(
          attachment.id,
          transfer: AttachmentTransfer.downloading,
        );
      } else {
        continue;
      }
      count++;
    }
    return count;
  });

  /// Runs everything that is due and waits until it is done (jobs backing
  /// off stay queued). For headless hosts and tests; a running worker does
  /// this by itself.
  Future<void> drain() async => _worker?.drain();

  /// Registers who runs standalone transfers (not attachments) with
  /// `purpose`: group pictures, backup blobs.
  void registerStandalone(String purpose, StandaloneTransferHandler handler) =>
      _worker?.register(purpose, handler);
}
