import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/transfers/media_settings.dart';
import 'package:helix_remote_engine/src/transfers/transfer_config.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show JsonReader, MediaBody, MediaPointer;

/// What happens to the attachments of a message that has just arrived: the
/// rows exist (`transfer: remote`, written by the content applier from the
/// pointers), and this decides what is fetched.
///
/// - Within the auto-download policy ([MediaSettings]) the **file** is
///   queued; its thumbnail comes with it.
/// - Otherwise only the **thumbnail** (a few KiB) is queued, and the file is
///   fetched when the user asks (`MediaService.downloadNow`).
/// - A view-once message gets no thumbnail: a preview of it would defeat the
///   point.
///
/// Called by the content applier inside the transaction that stores the
/// message, so the jobs exist if and only if the message does. Nothing here
/// touches the network.
final class InboundMedia {
  InboundMedia(this._ctx, this._config);

  final EngineContext _ctx;
  final TransferConfig _config;

  /// False when the engine has no [BlobStore]: attachments stay `remote` and
  /// nothing is queued.
  bool enabled = false;

  Future<void> onMessageStored(MessageRow message) async {
    if (!enabled || message.kind != MediaBody.typeName) return;
    final db = _ctx.db;
    final now = _ctx.now();
    for (final a in await db.messagesDao.attachmentsFor([message.localRowid])) {
      final limit = await db.settingsDao.get(MediaSettings.forKind(a.kind));
      final automatic =
          a.mediaId.isNotEmpty &&
          a.size > 0 &&
          a.size <= _config.maxDownloadBytes &&
          MediaSettings.allows(limit, a.size);
      if (automatic) {
        await db.transfersDao.enqueueDownload(
          attachmentRowid: a.id,
          mediaId: a.mediaId,
          mediaKey: a.mediaKey,
          size: a.size,
          now: now,
        );
        await db.messagesDao.updateAttachment(
          a.id,
          transfer: AttachmentTransfer.downloading,
        );
        continue;
      }
      final thumbnail = _thumbnail(a.thumbnail);
      if (thumbnail != null &&
          message.viewOnceState == null &&
          thumbnail.size > 0 &&
          thumbnail.size <= _config.maxThumbnailBytes) {
        await db.transfersDao.enqueueThumbnail(
          attachmentRowid: a.id,
          mediaId: thumbnail.id,
          mediaKey: thumbnail.key,
          size: thumbnail.size,
          now: now,
        );
      }
    }
  }

  static MediaPointer? _thumbnail(String? json) {
    if (json == null) return null;
    try {
      return MediaPointer.fromJson(
        JsonReader.decode(json),
        allowThumbnail: false,
      );
    } on Object {
      return null;
    }
  }
}
