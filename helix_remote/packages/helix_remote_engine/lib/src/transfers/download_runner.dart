import 'dart:math' as math;
import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/transfers/blob_store.dart';
import 'package:helix_remote_engine/src/transfers/transfer_config.dart';
import 'package:helix_remote_engine/src/transfers/transfer_failure.dart';
import 'package:helix_remote_engine/src/transfers/transfer_files.dart';
import 'package:helix_remote_engine/src/transfers/transfer_worker.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show JsonReader, MediaPointer;

/// One attachment download (CRYPTO_V2.md §12):
///
/// 1. the thumbnail, when there is one and it is not here yet (best effort);
/// 2. **ranged `GET`s** of the ciphertext into a staging file, from the
///    stored offset (the job's `offset`, bounded by what the file really
///    holds), so an interruption costs at most one chunk;
/// 3. the **digest** of the whole ciphertext is checked against the pointer's
///    before anything is decrypted;
/// 4. the file is **decrypted as a stream** (every chunk authenticated; a
///    truncated or reordered file fails) into a plaintext staging file whose
///    length must equal the pointer's `size`;
/// 5. it moves to its permanent name, and the attachment row points at it
///    in the same transaction that completes the job.
///
/// The ciphertext's length is known from the pointer's `size` and the file
/// header's chunk size, so nothing the server sends can make the download
/// longer than the sender described.
final class DownloadRunner {
  DownloadRunner(this._ctx, this._blobs, this._config);

  final EngineContext _ctx;
  final BlobStore _blobs;
  final TransferConfig _config;

  HelixDb get _db => _ctx.db;
  MediaClient get _media => _ctx.api.media;

  Future<void> run(TransferRow job, JobControl control) async {
    final attachment = await _db.messagesDao.attachmentById(
      job.attachmentRowid!,
    );
    if (attachment == null) {
      await _forget(job);
      return;
    }
    final existing = attachment.localPath;
    if (attachment.transfer == AttachmentTransfer.ready &&
        existing != null &&
        await _blobs.length(existing) != null) {
      await _db.transfersDao.markDone(job.id);
      return;
    }
    if (attachment.size > _config.maxDownloadBytes) {
      throw const TransferException(TransferFailure.tooLarge);
    }
    if (attachment.mediaId.isEmpty) {
      throw const TransferException(TransferFailure.expired);
    }
    if (attachment.transfer != AttachmentTransfer.downloading) {
      await _db.messagesDao.updateAttachment(
        attachment.id,
        transfer: AttachmentTransfer.downloading,
      );
    }
    try {
      await _fetchThumbnail(attachment, control);
    } on RequestCancelledException {
      rethrow;
    } on Object {
      // The preview is a courtesy; the file matters.
    }
    control.throwIfCancelled();

    final mediaId = job.mediaId ?? attachment.mediaId;
    final key = job.mediaKey ?? attachment.mediaKey;
    final staging = await TransferFiles.downloading(_blobs, job.id);
    await _fetch(mediaId, staging, job, attachment, control);

    // The digest first: nothing is decrypted from bytes the sender did not
    // describe.
    final actual = await _blobs.sha256Of(staging);
    if (!bytesEqual(actual, attachment.digest)) {
      await _blobs.delete(staging);
      throw const TransferException(TransferFailure.digestMismatch);
    }
    final plain = await TransferFiles.assembling(_blobs, job.id);
    await _decrypt(staging, plain, key, attachment.size, control);

    final dest = await _blobs.newPath(
      BlobArea.media,
      extension: TransferFiles.extension(
        name: attachment.name,
        mime: attachment.mime,
      ),
    );
    await _blobs.move(plain, dest);
    var kept = false;
    await _db.transaction(() async {
      if (await _db.transfersDao.byId(job.id) == null) return; // cancelled
      if (await _db.messagesDao.attachmentById(attachment.id) == null) return;
      await _db.messagesDao.updateAttachment(
        attachment.id,
        transfer: AttachmentTransfer.ready,
        localPath: dest,
      );
      await _db.transfersDao.markDone(job.id);
      kept = true;
    });
    if (!kept) await _blobs.delete(dest); // its message went meanwhile
    await _blobs.delete(staging);
  }

  /// Downloads the ciphertext of [mediaId] into [staging], resuming.
  Future<void> _fetch(
    String mediaId,
    String staging,
    TransferRow job,
    AttachmentRow attachment,
    JobControl control,
  ) async {
    var have = math.min(job.offset, await _blobs.length(staging) ?? 0);
    int? total = have >= AttachmentCrypto.headerLength
        ? await _totalLength(staging, attachment.size)
        : null;
    var stalls = 0;
    while (total == null || have < total) {
      control.throwIfCancelled();
      final stop = total == null
          ? have + _config.chunkBytes
          : math.min(have + _config.chunkBytes, total);
      final part = await _media.download(
        mediaId,
        start: have,
        end: stop - 1,
        cancel: control.token,
      );
      // A server that ignored the range sent the whole object.
      final at = part.partial ? have : 0;
      final bytes = part.bytes;
      if (bytes.isEmpty) {
        if (++stalls > 3) {
          throw const MalformedResponseException(path: 'body');
        }
        continue;
      }
      stalls = 0;
      if (total != null && at + bytes.length > total) {
        throw const TransferException(TransferFailure.sizeMismatch);
      }
      final sink = await _blobs.openWrite(staging, keep: at);
      try {
        await sink.add(bytes);
        await sink.close();
      } on Object {
        await sink.abort();
        rethrow;
      }
      have = at + bytes.length;
      await control.progress(have);
      if (total == null && have >= AttachmentCrypto.headerLength) {
        total = await _totalLength(staging, attachment.size);
      }
      if (total != null && part.size != null && part.size != total) {
        throw const TransferException(TransferFailure.sizeMismatch);
      }
    }
    if (have != total) {
      throw const TransferException(TransferFailure.sizeMismatch);
    }
  }

  /// The ciphertext length the pointer's `size` and the file's own chunk
  /// size imply.
  Future<int> _totalLength(String staging, int plainSize) async {
    final header = await _blobs.readBytes(
      staging,
      end: AttachmentCrypto.headerLength,
    );
    if (header.length < AttachmentCrypto.headerLength ||
        String.fromCharCodes(header.sublist(0, 4)) != AttachmentCrypto.magic ||
        header[4] != AttachmentCrypto.version) {
      throw const TransferException(TransferFailure.decryptFailed);
    }
    final chunkSize = ByteData.sublistView(header).getUint32(5);
    if (chunkSize < AttachmentCrypto.minChunkSize ||
        chunkSize > AttachmentCrypto.maxChunkSize) {
      throw const TransferException(TransferFailure.decryptFailed);
    }
    return AttachmentCrypto.ciphertextLength(plainSize, chunkSize: chunkSize);
  }

  Future<void> _decrypt(
    String staging,
    String plain,
    Uint8List key,
    int expectedSize,
    JobControl control,
  ) async {
    final sink = await _blobs.openWrite(plain);
    var written = 0;
    try {
      await for (final part in AttachmentCrypto.decrypt(
        _blobs.read(staging),
        key,
      )) {
        control.throwIfCancelled();
        written += part.length;
        if (written > expectedSize) {
          throw const TransferException(TransferFailure.sizeMismatch);
        }
        await sink.add(part);
      }
      await sink.close();
    } on Object catch (error) {
      await sink.abort();
      await _blobs.delete(plain);
      // The staged bytes will not get better: a retry fetches them again.
      if (error is CryptoV2Exception || error is TransferException) {
        await _blobs.delete(staging);
      }
      rethrow;
    }
    if (written != expectedSize) {
      await _blobs.delete(plain);
      await _blobs.delete(staging);
      throw const TransferException(TransferFailure.sizeMismatch);
    }
  }

  // ------------------------------------------------------------ thumbnails

  /// A thumbnail job: the small preview of an attachment that is not
  /// downloaded (on-demand policy).
  Future<void> runThumbnail(TransferRow job, JobControl control) async {
    final attachment = await _db.messagesDao.attachmentById(
      job.attachmentRowid!,
    );
    if (attachment != null) await _fetchThumbnail(attachment, control);
    await _db.transfersDao.markDone(job.id);
  }

  Future<void> _fetchThumbnail(
    AttachmentRow attachment,
    JobControl control,
  ) async {
    if (attachment.thumbnailPath != null || attachment.thumbnail == null) {
      return;
    }
    final MediaPointer pointer;
    try {
      pointer = MediaPointer.fromJson(
        JsonReader.decode(attachment.thumbnail!),
        allowThumbnail: false,
      );
    } on Object {
      return;
    }
    if (pointer.size <= 0 || pointer.size > _config.maxThumbnailBytes) return;
    final download = await _media.download(pointer.id, cancel: control.token);
    // Whatever the server sends is bounded by what the pointer says.
    final limit = AttachmentCrypto.ciphertextLength(
      pointer.size,
      chunkSize: AttachmentCrypto.maxChunkSize,
    );
    if (download.bytes.length > limit) {
      throw const TransferException(TransferFailure.sizeMismatch);
    }
    final bytes = await AttachmentCrypto.decryptBytes(
      download.bytes,
      pointer.key,
      digest: pointer.digest,
    );
    if (bytes.length != pointer.size) {
      throw const TransferException(TransferFailure.sizeMismatch);
    }
    final path = await _blobs.newPath(
      BlobArea.media,
      extension: TransferFiles.extension(mime: pointer.mime),
    );
    await _blobs.writeBytes(path, bytes);
    await _db.transaction(() async {
      if (await _db.messagesDao.attachmentById(attachment.id) == null) {
        await _blobs.delete(path);
        return;
      }
      await _db.messagesDao.updateAttachment(
        attachment.id,
        thumbnailPath: path,
      );
    });
  }

  // ------------------------------------------------------------- endings

  /// A download ended for good: the attachment shows as failed.
  Future<void> downloadFailed(TransferRow job, TransferFailure failure) async {
    final attachmentId = job.attachmentRowid;
    if (attachmentId == null) return;
    if (await _db.messagesDao.attachmentById(attachmentId) != null) {
      await _db.messagesDao.updateAttachment(
        attachmentId,
        transfer: AttachmentTransfer.failed,
      );
    }
    // Bytes that cannot be used are not kept for a resume.
    if (failure != TransferFailure.gaveUp &&
        failure != TransferFailure.quotaExceeded) {
      for (final path in await TransferFiles.allFor(_blobs, job.id)) {
        await _blobs.delete(path);
      }
      await _db.transfersDao.setProgress(job.id, offset: 0);
    }
  }

  Future<void> _forget(TransferRow job) async {
    for (final path in await TransferFiles.allFor(_blobs, job.id)) {
      await _blobs.delete(path);
    }
    await _db.transfersDao.remove(job.id);
  }
}
