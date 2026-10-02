import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_crypto/v2.dart' show AttachmentCrypto;
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/events.dart';
import 'package:helix_remote_engine/src/messaging/content_codec.dart';
import 'package:helix_remote_engine/src/messaging/outbox.dart';
import 'package:helix_remote_engine/src/transfers/blob_store.dart';
import 'package:helix_remote_engine/src/transfers/media_processor.dart';
import 'package:helix_remote_engine/src/transfers/transfer_config.dart';
import 'package:helix_remote_engine/src/transfers/transfer_failure.dart';
import 'package:helix_remote_engine/src/transfers/transfer_files.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// One file to send, from a path or from bytes.
final class MediaInput {
  /// A file on disk (or wherever the [BlobStore] can read it). The engine
  /// copies it and never changes or deletes the original.
  const MediaInput.file({
    required String this.path,
    required this.kind,
    required this.mime,
    this.name,
    this.caption,
    this.durationMs,
    this.waveform,
    this.width,
    this.height,
  }) : bytes = null;

  const MediaInput.bytes({
    required Uint8List this.bytes,
    required this.kind,
    required this.mime,
    this.name,
    this.caption,
    this.durationMs,
    this.waveform,
    this.width,
    this.height,
  }) : path = null;

  final MediaItemKind kind;
  final String mime;
  final String? path;
  final Uint8List? bytes;

  /// The file name shown for documents.
  final String? name;

  /// A caption for this item (the message has its own as well).
  final String? caption;

  /// What the app already knows. Whatever is missing is taken from the
  /// [MediaProcessor].
  final int? durationMs;

  /// Voice notes: one byte (0-255) per sample.
  final Uint8List? waveform;
  final int? width;
  final int? height;
}

/// The placeholder payload of an outbox op whose message is still
/// uploading. It is not a sendable message on purpose: should it ever be
/// claimed, decoding fails and the op ends as failed instead of sending
/// something half-made.
abstract final class HeldMediaPayload {
  static const text = '{"held":"media"}';

  static bool matches(String payload) => payload == text;
}

/// An attachment of an outgoing message, worked out before the row exists.
final class _Prepared {
  _Prepared({
    required this.kind,
    required this.mime,
    required this.size,
    this.name,
    this.caption,
    this.durationMs,
    this.waveform,
    this.width,
    this.height,
    this.blurhash,
    this.localPath,
    this.thumbnailPath,
    this.pointer,
    this.key,
  });

  final MediaItemKind kind;
  final String mime;
  final int size;
  final String? name;
  final String? caption;
  final int? durationMs;
  final Uint8List? waveform;
  final int? width;
  final int? height;
  final String? blurhash;
  final String? localPath;
  final String? thumbnailPath;

  /// Set for an item that needs no upload (a forward that reuses the
  /// object).
  final MediaPointer? pointer;

  /// The key of an item to upload.
  final Uint8List? key;
}

/// Sending attachments (CONTENT_V2.md §2 `media`): the optimistic message,
/// the uploads and the release of the message into the outbox when its last
/// upload completes.
///
/// A send is **one transaction**: the message row (status `pending`), one
/// `attachments` row per item (`uploading`, with its key and local copy), one
/// upload job per item, and one **held** outbox op that keeps the message's
/// place in the chat's order. The upload worker releases the op, with the
/// real pointers, in the transaction that completes the last upload; until
/// then nothing later in the chat is sent. A failed upload fails the op and
/// the message; retry and cancel are here too.
///
/// Direct chats only until the group send path lands (see [_peerOf]).
final class OutboundMedia {
  OutboundMedia(
    this._ctx,
    this._outbox,
    this._blobs,
    this._processor,
    this._config, {
    required this.onExpiryChanged,
  });

  final EngineContext _ctx;
  final OutboxService _outbox;
  final BlobStore _blobs;
  final MediaProcessor _processor;
  final TransferConfig _config;

  /// A message with a disappearing timer was written.
  final void Function() onExpiryChanged;

  /// Stops the running attempt of a job at once (set by the worker's owner).
  void Function(int jobId)? cancelJob;

  HelixDb get _db => _ctx.db;

  // ------------------------------------------------------------- sending

  Future<MessageRow> send(
    String conversationId,
    List<MediaInput> inputs, {
    String? caption,
    MessageRef? replyTo,
    bool viewOnce = false,
  }) async {
    if (inputs.isEmpty || inputs.length > ContentLimits.maxMediaItems) {
      throw ArgumentError.value(inputs.length, 'inputs', 'is 1 to 30 items');
    }
    _checkCaption(caption);
    final peer = _peerOf(conversationId);
    final prepared = <_Prepared>[];
    try {
      for (final input in inputs) {
        _checkCaption(input.caption);
        prepared.add(await _ingest(input, viewOnce: viewOnce));
      }
      return await _write(
        conversationId,
        peer,
        prepared,
        caption: caption,
        reply: replyTo,
        viewOnce: viewOnce,
        forwarded: false,
      );
    } on Object {
      for (final item in prepared) {
        await _discard(item);
      }
      rethrow;
    }
  }

  /// Sends the media message [messageRowid] to [toConversationId] again.
  ///
  /// While the original is younger than `forwardReuseWindow` the new message
  /// points at the **same server object with the same key** (no upload; the
  /// server lets any device fetch an object by its random id). An older one
  /// (the server keeps objects 30 days) is uploaded again from the local
  /// copy under a new key. View-once messages cannot be forwarded.
  Future<MessageRow> forward(int messageRowid, String toConversationId) async {
    final peer = _peerOf(toConversationId);
    final source = await _db.messagesDao.byRowid(messageRowid);
    if (source == null ||
        source.kind != MediaBody.typeName ||
        source.deletedAt != null ||
        source.viewOnceState != null) {
      throw StateError('this message cannot be forwarded');
    }
    final rows = await _db.messagesDao.attachmentsFor([messageRowid]);
    if (rows.isEmpty || rows.any((a) => a.mediaId.isEmpty)) {
      throw StateError('this message has not finished uploading');
    }
    final reuse =
        _ctx.now().difference(source.sentAt) <= _config.forwardReuseWindow;
    final prepared = <_Prepared>[];
    try {
      for (final row in rows) {
        prepared.add(await _forwardItem(row, reuse: reuse));
      }
      return await _write(
        toConversationId,
        peer,
        prepared,
        caption: source.body,
        reply: null,
        viewOnce: false,
        forwarded: true,
      );
    } on Object {
      for (final item in prepared) {
        await _discard(item);
      }
      rethrow;
    }
  }

  Future<_Prepared> _forwardItem(
    AttachmentRow row, {
    required bool reuse,
  }) async {
    final kind = _kindOf(row.kind);
    final local = row.localPath;
    final haveLocal = local != null && await _blobs.length(local) != null;
    String? copy;
    String? thumbCopy;
    try {
      if (haveLocal) {
        copy = await _blobs.newPath(
          BlobArea.media,
          extension: TransferFiles.extension(name: row.name, mime: row.mime),
        );
        await _blobs.copy(local, copy);
      }
      final thumb = row.thumbnailPath;
      if (thumb != null && await _blobs.length(thumb) != null) {
        thumbCopy = await _blobs.newPath(BlobArea.media);
        await _blobs.copy(thumb, thumbCopy);
      }
      if (reuse) {
        return _Prepared(
          kind: kind,
          mime: row.mime,
          size: row.size,
          name: row.name,
          caption: row.caption,
          durationMs: row.durationMs,
          waveform: row.waveform,
          width: row.width,
          height: row.height,
          blurhash: row.blurhash,
          localPath: copy,
          thumbnailPath: thumbCopy,
          pointer: MediaPointer(
            id: row.mediaId,
            key: row.mediaKey,
            digest: row.digest,
            size: row.size,
            mime: row.mime,
            name: row.name,
            blurhash: row.blurhash,
            thumbnail: _thumbnailPointer(row.thumbnail),
          ),
        );
      }
      if (copy == null) {
        throw StateError('the original has expired and no copy is kept');
      }
      return _Prepared(
        kind: kind,
        mime: row.mime,
        size: row.size,
        name: row.name,
        caption: row.caption,
        durationMs: row.durationMs,
        waveform: row.waveform,
        width: row.width,
        height: row.height,
        blurhash: row.blurhash,
        localPath: copy,
        thumbnailPath: thumbCopy,
        key: AttachmentCrypto.newKey(_ctx.random),
      );
    } on Object {
      if (copy != null) await _blobs.delete(copy);
      if (thumbCopy != null) await _blobs.delete(thumbCopy);
      rethrow;
    }
  }

  Future<_Prepared> _ingest(MediaInput input, {required bool viewOnce}) async {
    if (input.mime.isEmpty) throw ArgumentError.value(input.mime, 'mime');
    final local = await _blobs.newPath(
      BlobArea.media,
      extension: TransferFiles.extension(name: input.name, mime: input.mime),
    );
    String? thumbPath;
    try {
      final bytes = input.bytes;
      if (bytes != null) {
        await _blobs.writeBytes(local, bytes);
      } else {
        await _blobs.copy(input.path!, local);
      }
      final size = await _blobs.length(local);
      if (size == null || size == 0) {
        throw ArgumentError.value(input.path, 'input', 'is empty');
      }
      var processed = ProcessedMedia.none;
      try {
        processed = await _processor.process(
          path: local,
          kind: input.kind,
          mime: input.mime,
        );
      } on Object {
        // Sent without previews.
      }
      final thumbnail = processed.thumbnail;
      if (!viewOnce &&
          thumbnail != null &&
          thumbnail.isNotEmpty &&
          thumbnail.length <= _config.maxThumbnailBytes) {
        thumbPath = await _blobs.newPath(BlobArea.media);
        await _blobs.writeBytes(thumbPath, thumbnail);
      }
      return _Prepared(
        kind: input.kind,
        mime: input.mime,
        size: size,
        name: input.name,
        caption: input.caption,
        durationMs: input.durationMs ?? processed.durationMs,
        waveform: input.waveform ?? processed.waveform,
        width: input.width ?? processed.width,
        height: input.height ?? processed.height,
        // A blurred preview of a view-once picture would defeat the point.
        blurhash: viewOnce ? null : processed.blurhash,
        localPath: local,
        thumbnailPath: thumbPath,
        key: AttachmentCrypto.newKey(_ctx.random),
      );
    } on Object {
      await _blobs.delete(local);
      if (thumbPath != null) await _blobs.delete(thumbPath);
      rethrow;
    }
  }

  Future<void> _discard(_Prepared item) async {
    final local = item.localPath;
    if (local != null) await _blobs.delete(local);
    final thumb = item.thumbnailPath;
    if (thumb != null) await _blobs.delete(thumb);
  }

  Future<MessageRow> _write(
    String conversationId,
    String peer,
    List<_Prepared> prepared, {
    required String? caption,
    required MessageRef? reply,
    required bool viewOnce,
    required bool forwarded,
  }) async {
    final row = await _db.transaction(() async {
      final chat = await _db.conversationsDao.byId(conversationId);
      if (chat == null) throw StateError('no such chat');
      final now = _ctx.now();
      final self = _ctx.identity;
      final expire = chat.disappearingSeconds;
      final profileKey = (await _db.accountDao.current())?.profileKey;
      final needsUpload = prepared.any((p) => p.pointer == null);
      final body = MediaBody(
        items: [for (final p in prepared) _itemOf(p)],
        caption: caption,
      );
      final content = ContentMessage(
        id: _ctx.ids.next(),
        sentAt: now,
        conversation: DirectConversation(to: peer),
        body: body,
        reply: reply,
        expireSeconds: expire,
        profileKey: profileKey == null ? null : Uint8List.fromList(profileKey),
        viewOnce: viewOnce,
      );
      final stored = ContentCodec.split(body);
      final row = await _db.messagesDao.insertMessage(
        MessagesCompanion.insert(
          messageId: content.id,
          conversationId: conversationId,
          sender: self.accountId,
          senderDevice: Value(self.deviceId),
          outgoing: true,
          sortKey: SortKey.of(now, content.id),
          sentAt: now,
          receivedAt: now,
          kind: MediaBody.typeName,
          body: Value(stored.text),
          payload: Value(stored.payload),
          replyToId: Value(reply?.id),
          replyToAuthor: Value(reply?.author),
          forwarded: Value(forwarded),
          status: MessageStatus.pending,
          expireSeconds: Value(expire),
          expiresAt: Value(
            expire == null ? null : now.add(Duration(seconds: expire)),
          ),
          viewOnceState: viewOnce
              ? const Value(ViewOnceState.unopened)
              : const Value.absent(),
        ),
        media: [for (final p in prepared) _companionOf(p)],
      );
      final rows = await _db.messagesDao.attachmentsFor([row.localRowid]);
      for (final (index, p) in prepared.indexed) {
        if (p.pointer != null) continue;
        await _db.transfersDao.enqueueUpload(
          attachmentRowid: rows[index].id,
          localPath: p.localPath!,
          size: p.size,
          mediaKey: p.key!,
          now: now,
        );
      }
      await _db.conversationsDao.setDraft(conversationId, null);
      if (needsUpload) {
        await _db.outboxDao.enqueueHeld(
          kind: OutboxKinds.sendContent,
          idempotencyKey: content.id,
          payload: HeldMediaPayload.text,
          conversationId: conversationId,
          messageRowid: row.localRowid,
          now: now,
        );
      } else {
        await _outbox.enqueueContent(
          content: content,
          audience: [peer, self.accountId],
          conversationId: conversationId,
          messageRowid: row.localRowid,
        );
      }
      return row;
    });
    if (row.expiresAt != null) onExpiryChanged();
    return row;
  }

  MediaItem _itemOf(_Prepared p) => MediaItem(
    kind: p.kind,
    media:
        p.pointer ??
        MediaPointer(
          // Replaced by the real object when the upload completes.
          id: 'pending',
          key: p.key!,
          digest: Uint8List(32),
          size: p.size,
          mime: p.mime,
          name: p.name,
          blurhash: p.blurhash,
        ),
    caption: p.caption,
    durationMs: p.durationMs,
    waveform: p.waveform,
    width: p.width,
    height: p.height,
  );

  AttachmentsCompanion _companionOf(_Prepared p) {
    final pointer = p.pointer;
    return AttachmentsCompanion.insert(
      messageRowid: 0,
      position: 0,
      kind: p.kind.wire,
      mediaId: pointer?.id ?? '',
      mediaKey: pointer?.key ?? p.key!,
      digest: pointer?.digest ?? Uint8List(32),
      mime: p.mime,
      size: p.size,
      name: Value(p.name),
      width: Value(p.width),
      height: Value(p.height),
      durationMs: Value(p.durationMs),
      waveform: Value(p.waveform),
      blurhash: Value(p.blurhash),
      caption: Value(p.caption),
      thumbnail: Value(
        pointer?.thumbnail == null
            ? null
            : jsonEncode(pointer!.thumbnail!.toJson()),
      ),
      thumbnailPath: Value(p.thumbnailPath),
      localPath: Value(p.localPath),
      transfer: pointer == null
          ? AttachmentTransfer.uploading
          : (p.localPath != null
                ? AttachmentTransfer.ready
                : AttachmentTransfer.remote),
    );
  }

  // ----------------------------------------------------------- uploading

  /// An upload finished: the attachment gets its pointer, the job is done
  /// and, when this was the message's last upload, the message is released
  /// to the outbox with the real pointers. One transaction.
  Future<void> completeUpload({
    required TransferRow job,
    required AttachmentRow attachment,
    required String mediaId,
    required Uint8List digest,
  }) => _db.transaction(() async {
    if (await _db.transfersDao.byId(job.id) == null) return; // cancelled
    final fresh = await _db.messagesDao.attachmentById(attachment.id);
    if (fresh == null) return;
    await _db.messagesDao.setAttachmentPointer(
      attachment.id,
      mediaId: mediaId,
      digest: digest,
    );
    await _db.messagesDao.updateAttachment(
      attachment.id,
      transfer: AttachmentTransfer.ready,
    );
    await _db.transfersDao.markDone(job.id);
    await _release(attachment.messageRowid);
  });

  /// Releases the message's held op once every attachment has its pointer.
  Future<void> _release(int messageRowid) async {
    final rows = await _db.messagesDao.attachmentsFor([messageRowid]);
    if (rows.isEmpty || rows.any((a) => a.mediaId.isEmpty)) return;
    final message = await _db.messagesDao.byRowid(messageRowid);
    if (message == null) return;
    final ops = [
      for (final op in await _db.outboxDao.forMessage(messageRowid))
        if (op.kind == OutboxKinds.sendContent && OutboxDao.isHeld(op)) op,
    ];
    if (ops.isEmpty) return;
    final body = MediaBody(
      items: [for (final a in rows) _itemOfRow(a)],
      caption: message.body,
    );
    await _db.messagesDao.updatePayload(
      messageRowid,
      ContentCodec.split(body).payload,
    );
    final updated = (await _db.messagesDao.byRowid(messageRowid))!;
    final peer = _peerOf(updated.conversationId);
    final profileKey = (await _db.accountDao.current())?.profileKey;
    final content = ContentCodec.rebuild(
      updated,
      to: peer,
      profileKey: profileKey == null ? null : Uint8List.fromList(profileKey),
    );
    await _db.outboxDao.release(
      ops.first.id,
      payload: SendContentPayload(
        content: content,
        audience: {peer, _ctx.identity.accountId}.toList()..sort(),
      ).encode(),
      now: _ctx.now(),
    );
  }

  MediaItem _itemOfRow(AttachmentRow a) => MediaItem(
    kind: _kindOf(a.kind),
    media: MediaPointer(
      id: a.mediaId,
      key: a.mediaKey,
      digest: a.digest,
      size: a.size,
      mime: a.mime,
      name: a.name,
      blurhash: a.blurhash,
      thumbnail: _thumbnailPointer(a.thumbnail),
    ),
    caption: a.caption,
    durationMs: a.durationMs,
    waveform: a.waveform,
    width: a.width,
    height: a.height,
  );

  /// An upload ended for good: the attachment, the message and its held op
  /// fail, and the UI hears about it. [retry] starts it again.
  Future<void> uploadFailed(TransferRow job, TransferFailure failure) async {
    final attachmentId = job.attachmentRowid;
    if (attachmentId == null) return;
    int? failedMessage;
    await _db.transaction(() async {
      final attachment = await _db.messagesDao.attachmentById(attachmentId);
      if (attachment == null) return;
      await _db.messagesDao.updateAttachment(
        attachmentId,
        transfer: AttachmentTransfer.failed,
      );
      final message = await _db.messagesDao.byRowid(attachment.messageRowid);
      if (message == null || message.status != MessageStatus.pending) return;
      for (final op in await _db.outboxDao.forMessage(message.localRowid)) {
        if (op.kind == OutboxKinds.sendContent && OutboxDao.isHeld(op)) {
          await _db.outboxDao.fail(op.id, errorCode: failure.wire);
        }
      }
      await _db.messagesDao.advanceStatus(
        message.localRowid,
        MessageStatus.failed,
      );
      failedMessage = message.localRowid;
    });
    final rowid = failedMessage;
    if (rowid != null) {
      _ctx.emit(SendFailedEvent(messageRowid: rowid, errorCode: failure.wire));
    }
  }

  // ------------------------------------------------------ retry and cancel

  /// Starts the failed uploads of [messageRowid] again and puts the message
  /// back in the queue. False when every attachment is already uploaded (the
  /// caller then retries the outbox op itself).
  Future<bool> retry(int messageRowid) => _db.transaction(() async {
    final rows = await _db.messagesDao.attachmentsFor([messageRowid]);
    final todo = [
      for (final a in rows)
        if (a.mediaId.isEmpty) a,
    ];
    if (todo.isEmpty) return false;
    final now = _ctx.now();
    for (final a in todo) {
      final job = await _db.transfersDao.byAttachment(a.id);
      if (job != null && job.state != TransferState.failed) continue;
      final path = a.localPath;
      if (path == null) continue;
      await _db.transfersDao.enqueueUpload(
        attachmentRowid: a.id,
        localPath: path,
        size: a.size,
        mediaKey: a.mediaKey,
        now: now,
      );
      await _db.messagesDao.updateAttachment(
        a.id,
        transfer: AttachmentTransfer.uploading,
      );
    }
    for (final op in await _db.outboxDao.forMessage(messageRowid)) {
      if (op.kind == OutboxKinds.sendContent &&
          (op.state == OutboxState.failed || OutboxDao.isHeld(op))) {
        await _db.outboxDao.hold(op.id, payload: HeldMediaPayload.text);
      }
    }
    await _db.messagesDao.advanceStatus(messageRowid, MessageStatus.pending);
    return true;
  });

  /// Gives up on sending [messageRowid]: the uploads stop, the queued send is
  /// removed, the message and its local files go, and the partly uploaded
  /// objects are deleted from the server. Only for a message that has not
  /// left yet (uploading, or failed).
  Future<void> cancelSend(int messageRowid) async {
    final jobs = <TransferRow>[];
    final paths = <String>[];
    await _db.transaction(() async {
      final message = await _db.messagesDao.byRowid(messageRowid);
      if (message == null) return;
      final ops = [
        for (final op in await _db.outboxDao.forMessage(messageRowid))
          if (op.kind == OutboxKinds.sendContent) op,
      ];
      final unsent = ops.any(
        (op) => OutboxDao.isHeld(op) || op.state == OutboxState.failed,
      );
      if (!message.outgoing || !unsent) {
        throw StateError('this message has already been sent');
      }
      for (final a in await _db.messagesDao.attachmentsFor([messageRowid])) {
        final job = await _db.transfersDao.byAttachment(a.id);
        if (job != null) jobs.add(job);
        paths.addAll([?a.localPath, ?a.thumbnailPath]);
      }
      for (final op in ops) {
        await _db.outboxDao.complete(op.id);
      }
      // The jobs and attachment rows go with the message.
      await _db.messagesDao.removeMessages([messageRowid]);
    });
    for (final job in jobs) {
      cancelJob?.call(job.id);
      for (final path in await TransferFiles.allFor(_blobs, job.id)) {
        await _blobs.delete(path);
      }
      final mediaId = job.mediaId;
      if (mediaId != null && job.kind == 'upload') {
        try {
          await _ctx.api.media.delete(mediaId);
        } on Object {
          // Offline: the server expires abandoned uploads.
        }
      }
    }
    for (final path in paths) {
      await _blobs.delete(path);
    }
  }

  /// Drops queued sends whose message is gone (deleted for me, for everyone
  /// or with its chat) or has no attachments left: a held op would hold
  /// every later message of that chat back for ever.
  Future<void> reapHeld() async {
    for (final op in await _db.outboxDao.heldOps()) {
      if (op.kind != OutboxKinds.sendContent) continue;
      final rowid = op.messageRowid;
      final message = rowid == null
          ? null
          : await _db.messagesDao.byRowid(rowid);
      final gone =
          message == null ||
          message.deletedAt != null ||
          (await _db.messagesDao.attachmentsFor([message.localRowid])).isEmpty;
      if (gone) await _db.outboxDao.complete(op.id);
    }
  }

  // ------------------------------------------------------------- helpers

  void _checkCaption(String? caption) {
    if (caption != null && caption.length > ContentLimits.maxCaptionLength) {
      throw ArgumentError.value('<${caption.length} chars>', 'caption');
    }
  }

  /// Direct chats only: the group send path (sender keys, `group_message`)
  /// belongs to the groups feature. When it lands, this is the place to
  /// resolve a group conversation to its audience and `conv`.
  String _peerOf(String conversationId) {
    const prefix = 'direct:';
    if (!conversationId.startsWith(prefix)) {
      throw UnsupportedError('media in groups is not available yet');
    }
    return conversationId.substring(prefix.length);
  }

  static MediaItemKind _kindOf(String wire) => MediaItemKind.values.firstWhere(
    (k) => k.wire == wire,
    orElse: () => MediaItemKind.unknown,
  );

  static MediaPointer? _thumbnailPointer(String? json) {
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
