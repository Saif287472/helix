import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/transfers/blob_store.dart';
import 'package:helix_remote_engine/src/transfers/outbound_media.dart';
import 'package:helix_remote_engine/src/transfers/transfer_config.dart';
import 'package:helix_remote_engine/src/transfers/transfer_failure.dart';
import 'package:helix_remote_engine/src/transfers/transfer_files.dart';
import 'package:helix_remote_engine/src/transfers/transfer_worker.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show CreateUploadRequest, ErrorCode, MediaKind, MediaPointer, UploadTarget;

/// One attachment upload (CRYPTO_V2.md §12, MODULE.md of the server's media
/// module):
///
/// 1. the thumbnail, if there is one and it is not uploaded yet (its own small
///    object with its own key);
/// 2. the file is **encrypted once into a staging file** (STREAM, 64 KiB
///    chunks), so every resume sends the same bytes, and `size` is known for
///    `POST /v1/media`;
/// 3. `POST /v1/media` for the ciphertext's size;
/// 4. the staged bytes go up: chunks with `Upload-Offset` to this server
///    (after an interruption `HEAD` says how far it got), or one presigned
///    `PUT` for S3;
/// 5. the digest (SHA-256 of the ciphertext) and the object id go into the
///    attachment's pointer, and the message is released to the outbox in the
///    same transaction as the job's completion.
///
/// The plaintext file is never modified; the staging file is deleted when the
/// upload is done (or the job is cancelled).
final class UploadRunner {
  UploadRunner(this._ctx, this._blobs, this._config, this._outbound);

  final EngineContext _ctx;
  final BlobStore _blobs;
  final TransferConfig _config;
  final OutboundMedia _outbound;

  HelixDb get _db => _ctx.db;
  MediaClient get _media => _ctx.api.media;

  Future<void> run(TransferRow job, JobControl control) async {
    final attachment = await _db.messagesDao.attachmentById(
      job.attachmentRowid!,
    );
    final key = job.mediaKey;
    if (attachment == null || key == null) {
      await _forget(job);
      return;
    }
    await _uploadThumbnail(attachment, control);
    control.throwIfCancelled();

    final source = job.localPath;
    final size = source == null ? null : await _blobs.length(source);
    if (source == null || size == null || size != job.size) {
      throw const TransferException(TransferFailure.fileMissing);
    }
    final staging = await TransferFiles.encrypted(_blobs, job.id);
    final expected = AttachmentCrypto.ciphertextLength(
      size,
      chunkSize: _config.encryptionChunkBytes,
    );

    var mediaId = job.mediaId;
    var offset = job.offset;
    Uint8List? digest;
    if (await _blobs.length(staging) != expected) {
      // First attempt, or the staged bytes are gone or incomplete: encrypt
      // again. Anything already on the server came from different bytes.
      if (mediaId != null) {
        unawaited(_deleteRemote(mediaId));
        await _db.transfersDao.resetProgress(job.id);
        mediaId = null;
        offset = 0;
      }
      digest = await _encrypt(source, staging, key, expected, control);
    }
    control.throwIfCancelled();

    UploadTarget? target;
    if (mediaId != null && offset > 0) {
      // A local upload that got part of the way: ask how far.
      try {
        offset = math.min(
          (await _media.uploadStatus(mediaId)).offset,
          expected,
        );
      } on ApiException catch (error) {
        if (error.code != ErrorCode.notFound) rethrow;
        // The server dropped the abandoned object: start a new one.
        mediaId = null;
        offset = 0;
      }
    } else if (mediaId != null) {
      // Created, nothing sent (or a presigned target, which cannot resume):
      // a fresh target is as cheap as asking.
      unawaited(_deleteRemote(mediaId));
      mediaId = null;
    }
    if (mediaId == null) {
      target = await _media.createUpload(
        CreateUploadRequest(size: expected, kind: MediaKind.attachment),
      );
      mediaId = target.mediaId;
      offset = 0;
      await control.progress(0, mediaId: mediaId);
    }

    if (target != null && !target.resumable) {
      // Presigned: exactly `size` bytes in one request.
      final bytes = await _blobs.readBytes(staging);
      await _media.upload(target, bytes, cancel: control.token);
      offset = expected;
      await control.progress(offset);
    } else {
      offset = await _sendChunks(mediaId, staging, offset, expected, control);
    }

    digest ??= await _blobs.sha256Of(staging);
    await _outbound.completeUpload(
      job: job,
      attachment: attachment,
      mediaId: mediaId,
      digest: digest,
    );
    await _blobs.delete(staging);
  }

  Future<int> _sendChunks(
    String mediaId,
    String staging,
    int from,
    int expected,
    JobControl control,
  ) async {
    var offset = from;
    var conflicts = 0;
    var stalls = 0;
    while (offset < expected) {
      control.throwIfCancelled();
      final end = math.min(offset + _config.chunkBytes, expected);
      final bytes = await _blobs.readBytes(staging, start: offset, end: end);
      final UploadProgress stored;
      try {
        stored = await _media.uploadContent(
          mediaId,
          bytes,
          offset: offset,
          cancel: control.token,
        );
      } on ApiException catch (error) {
        // A wrong offset names the stored one: continue from there.
        final at = error.details?['upload_offset'];
        if (error.code == ErrorCode.conflict &&
            at is int &&
            at >= 0 &&
            at <= expected &&
            ++conflicts <= 5) {
          offset = at;
          continue;
        }
        rethrow;
      }
      if (stored.offset <= offset) {
        // The server stored nothing: do not loop on it.
        if (++stalls > 3) {
          throw const MalformedResponseException(path: 'upload-offset');
        }
        continue;
      }
      stalls = 0;
      offset = math.min(stored.offset, expected);
      await control.progress(offset);
    }
    return offset;
  }

  /// Encrypts [source] into [staging] and returns the ciphertext's digest.
  Future<Uint8List> _encrypt(
    String source,
    String staging,
    Uint8List key,
    int expected,
    JobControl control,
  ) async {
    final sink = await _blobs.openWrite(staging);
    final digest = Sha256Accumulator();
    var written = 0;
    try {
      await for (final part in AttachmentCrypto.encrypt(
        _blobs.read(source),
        key,
        random: _ctx.random,
        chunkSize: _config.encryptionChunkBytes,
      )) {
        control.throwIfCancelled();
        digest.add(part);
        written += part.length;
        await sink.add(part);
      }
      await sink.close();
    } on Object {
      await sink.abort();
      await _blobs.delete(staging);
      rethrow;
    }
    if (written != expected) {
      // The source changed while it was being read.
      await _blobs.delete(staging);
      throw const TransferException(TransferFailure.fileMissing);
    }
    return digest.close();
  }

  /// The thumbnail is a separate small object; its pointer is stored on the
  /// attachment before the main upload starts, so a resume does not repeat it.
  Future<void> _uploadThumbnail(
    AttachmentRow attachment,
    JobControl control,
  ) async {
    final path = attachment.thumbnailPath;
    if (path == null || attachment.thumbnail != null) return;
    final bytes = await _blobs.length(path) == null
        ? null
        : await _blobs.readBytes(path);
    if (bytes == null || bytes.isEmpty) return;
    final key = AttachmentCrypto.newKey(_ctx.random);
    final sealed = await AttachmentCrypto.encryptBytes(
      bytes,
      key,
      random: _ctx.random,
      chunkSize: _config.encryptionChunkBytes,
    );
    final target = await _media.createUpload(
      CreateUploadRequest(
        size: sealed.ciphertext.length,
        kind: MediaKind.attachment,
      ),
    );
    await _media.upload(
      target,
      sealed.ciphertext,
      chunkSize: _config.chunkBytes,
      cancel: control.token,
    );
    final pointer = MediaPointer(
      id: target.mediaId,
      key: key,
      digest: sealed.digest,
      size: bytes.length,
      mime: TransferFiles.sniffImageMime(bytes),
    );
    await _db.messagesDao.setAttachmentThumbnail(
      attachment.id,
      jsonEncode(pointer.toJson()),
    );
  }

  Future<void> _forget(TransferRow job) async {
    for (final path in await TransferFiles.allFor(_blobs, job.id)) {
      await _blobs.delete(path);
    }
    final mediaId = job.mediaId;
    if (mediaId != null) unawaited(_deleteRemote(mediaId));
    await _db.transfersDao.remove(job.id);
  }

  /// Best effort: the server expires abandoned objects anyway.
  Future<void> _deleteRemote(String mediaId) async {
    try {
      await _media.delete(mediaId);
    } on Object {
      // Offline or already gone.
    }
  }
}
