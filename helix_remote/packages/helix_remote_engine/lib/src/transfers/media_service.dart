import 'dart:async';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/messaging/outbox.dart';
import 'package:helix_remote_engine/src/transfers/blob_store.dart';
import 'package:helix_remote_engine/src/transfers/media_janitor.dart';
import 'package:helix_remote_engine/src/transfers/outbound_media.dart';
import 'package:helix_remote_engine/src/transfers/transfer_config.dart';
import 'package:helix_remote_engine/src/transfers/transfer_files.dart';
import 'package:helix_remote_engine/src/transfers/transfer_views.dart';
import 'package:helix_remote_engine/src/transfers/transfer_worker.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show MessageRef;

/// Attachments as the app sees them: send media, watch each attachment's
/// progress and state, retry, cancel, download on demand, open the local
/// file. Everything is a database transaction or a watch query; the bytes
/// move in the [TransferWorker], which this service never waits for.
///
/// ```dart
/// final row = await engine.media.sendMedia(chatId, [
///   MediaInput.file(path: photo, kind: MediaItemKind.image, mime: 'image/jpeg'),
/// ], caption: 'Holiday');
/// engine.media.watchMessage(row.localRowid).listen((views) { … });
/// ```
///
/// Without a [BlobStore] the engine has no file access: sending throws a
/// [StateError], and incoming attachments stay `remote`.
final class MediaService {
  MediaService(
    this._ctx,
    this._blobs,
    this._config,
    this._outbound,
    this._outbox,
    this._janitor,
    this._cancelRunning,
  );

  final EngineContext _ctx;
  final BlobStore? _blobs;
  final TransferConfig _config;
  final OutboundMedia _outbound;
  final OutboxService _outbox;
  final MediaJanitor? _janitor;
  final void Function(int jobId) _cancelRunning;

  HelixDb get _db => _ctx.db;

  /// Whether this engine can move attachments (it was given a [BlobStore]).
  bool get isAvailable => _blobs != null;

  BlobStore get _store =>
      _blobs ?? (throw StateError('this engine has no BlobStore'));

  /// Throws when the engine cannot move files.
  void _requireStore() {
    if (_blobs == null) throw StateError('this engine has no BlobStore');
  }

  // ------------------------------------------------------------- sending

  /// Sends [items] (1 to 30; an album when several) to [conversationId].
  /// Returns the new message at once, status `pending`; its attachments are
  /// `uploading` and the message leaves when the last upload completes.
  /// [viewOnce] messages are shown once and then deleted (CONTENT_V2.md §5).
  Future<MessageRow> sendMedia(
    String conversationId,
    List<MediaInput> items, {
    String? caption,
    MessageRef? replyTo,
    bool viewOnce = false,
  }) {
    _requireStore();
    return _outbound.send(
      conversationId,
      items,
      caption: caption,
      replyTo: replyTo,
      viewOnce: viewOnce,
    );
  }

  /// Sends the media message [messageRowid] on to [toConversationId],
  /// reusing the uploaded object (no upload) while it is fresh.
  Future<MessageRow> forward(int messageRowid, String toConversationId) {
    _requireStore();
    return _outbound.forward(messageRowid, toConversationId);
  }

  // ------------------------------------------------------- retry, cancel

  /// Retries a media message that shows as failed: failed uploads start
  /// again (from the beginning of what the server lacks), or, when they were
  /// done, the send itself; failed downloads of an incoming message start
  /// again.
  Future<void> retry(int messageRowid) async {
    _requireStore();
    if (await _outbound.retry(messageRowid)) return;
    var queued = false;
    for (final op in await _db.outboxDao.forMessage(messageRowid)) {
      if (op.state == OutboxState.failed) {
        await _outbox.retry(op.id);
        queued = true;
      }
    }
    if (queued) return;
    for (final a in await _db.messagesDao.attachmentsFor([messageRowid])) {
      if (a.transfer == AttachmentTransfer.failed) await downloadNow(a.id);
    }
  }

  /// What `ChatsService.retrySend` delegates to: true when [messageRowid] is
  /// a media message (and was retried).
  Future<bool> retryIfMedia(int messageRowid) async {
    if (_blobs == null) return false;
    final message = await _db.messagesDao.byRowid(messageRowid);
    if (message == null || message.kind != 'media') return false;
    await retry(messageRowid);
    return true;
  }

  /// Retries one attachment (a failed download, or the upload it belongs to).
  Future<void> retryAttachment(int attachmentId) async {
    final a = await _db.messagesDao.attachmentById(attachmentId);
    if (a == null) return;
    if (a.mediaId.isEmpty) {
      await _outbound.retry(a.messageRowid);
    } else {
      await downloadNow(attachmentId);
    }
  }

  /// Stops the transfer of one attachment. A download goes back to "not
  /// downloaded" (what was fetched so far is dropped); cancelling an upload
  /// cancels the whole send (see [cancelSend]).
  Future<void> cancel(int attachmentId) async {
    final blobs = _store;
    final a = await _db.messagesDao.attachmentById(attachmentId);
    final job = a == null ? null : await _db.transfersDao.byAttachment(a.id);
    if (a == null || job == null) return;
    if (job.kind == 'upload') {
      await cancelSend(a.messageRowid);
      return;
    }
    await _db.transaction(() async {
      await _db.transfersDao.remove(job.id);
      if (a.transfer == AttachmentTransfer.downloading ||
          a.transfer == AttachmentTransfer.failed) {
        await _db.messagesDao.updateAttachment(
          a.id,
          transfer: AttachmentTransfer.remote,
        );
      }
    });
    _cancelRunning(job.id);
    for (final path in await TransferFiles.allFor(blobs, job.id)) {
      await blobs.delete(path);
    }
  }

  /// Gives up on sending an outgoing media message that has not left yet
  /// (still uploading, or failed): the uploads stop, the message and its
  /// local copies are removed, and objects already on the server are
  /// deleted.
  Future<void> cancelSend(int messageRowid) {
    _requireStore();
    return _outbound.cancelSend(messageRowid);
  }

  // ------------------------------------------------------------ receiving

  /// Fetches an incoming attachment now, whatever the auto-download policy
  /// says (the "download" button, or a retry).
  Future<void> downloadNow(int attachmentId) async {
    final blobs = _store;
    await _db.transaction(() async {
      final a = await _db.messagesDao.attachmentById(attachmentId);
      if (a == null) return;
      if (a.mediaId.isEmpty) {
        throw StateError('this attachment is not uploaded yet');
      }
      final local = a.localPath;
      if (a.transfer == AttachmentTransfer.ready &&
          local != null &&
          await blobs.length(local) != null) {
        return;
      }
      await _db.transfersDao.enqueueDownload(
        attachmentRowid: a.id,
        mediaId: a.mediaId,
        mediaKey: a.mediaKey,
        size: a.size,
        now: _ctx.now(),
      );
      await _db.messagesDao.updateAttachment(
        a.id,
        transfer: AttachmentTransfer.downloading,
      );
    });
  }

  /// The local file of an attachment, or null when it is not on this device
  /// (not downloaded yet, or the file was removed). The path is the
  /// [BlobStore]'s: for a file-backed store, a path the OS can open.
  Future<String?> openLocalPath(int attachmentId) async {
    final blobs = _blobs;
    final a = await _db.messagesDao.attachmentById(attachmentId);
    final path = a?.localPath;
    if (blobs == null || a == null || path == null) return null;
    return await blobs.length(path) == null ? null : path;
  }

  /// The local thumbnail of an attachment, or null.
  Future<String?> thumbnailPath(int attachmentId) async {
    final blobs = _blobs;
    final a = await _db.messagesDao.attachmentById(attachmentId);
    final path = a?.thumbnailPath;
    if (blobs == null || a == null || path == null) return null;
    return await blobs.length(path) == null ? null : path;
  }

  /// The user has finished looking at a view-once message (call it when the
  /// viewer closes, after `ChatsService.openViewOnce`): the files, their
  /// keys and the pointers in the message are deleted, so the media cannot be
  /// opened or fetched again. The bubble stays, as "opened". On the sender's
  /// side this runs by itself once the recipient has viewed the message.
  Future<void> consumeViewOnce(int messageRowid) async {
    final blobs = _store;
    final paths = <String>[];
    final jobs = <TransferRow>[];
    await _db.transaction(() async {
      final message = await _db.messagesDao.byRowid(messageRowid);
      // Incoming: after the user opened it. Outgoing: after the recipient
      // viewed it.
      final consumable =
          message != null &&
          (message.outgoing
              ? message.viewOnceState != null &&
                    message.status == MessageStatus.viewed
              : message.viewOnceState == ViewOnceState.opened);
      if (!consumable) {
        throw StateError('this message was not opened as view-once');
      }
      for (final a in await _db.messagesDao.attachmentsFor([messageRowid])) {
        final job = await _db.transfersDao.byAttachment(a.id);
        if (job != null) jobs.add(job);
        paths.addAll([?a.localPath, ?a.thumbnailPath]);
      }
      await _db.messagesDao.removeAttachments(messageRowid);
      await _db.messagesDao.updatePayload(messageRowid, null);
    });
    for (final job in jobs) {
      _cancelRunning(job.id);
      for (final path in await TransferFiles.allFor(blobs, job.id)) {
        await blobs.delete(path);
      }
    }
    for (final path in paths) {
      await blobs.delete(path);
    }
  }

  // -------------------------------------------------------------- watching

  /// The attachments of one message with their transfer state and progress,
  /// live: every chunk, retry and completion emits.
  Stream<List<AttachmentTransferView>> watchMessage(int messageRowid) {
    return _combine<
          List<AttachmentRow>,
          List<TransferRow>,
          List<AttachmentTransferView>
        >(
          _db.messagesDao.watchAttachmentsFor([messageRowid]),
          _db.transfersDao.watchLive(),
          (attachments, jobs) => _views(attachments, jobs),
        )
        .distinct(_sameViews);
  }

  /// One attachment's state and progress, live; null once it is gone.
  Stream<AttachmentTransferView?> watchAttachment(int attachmentId) async* {
    final a = await _db.messagesDao.attachmentById(attachmentId);
    if (a == null) {
      yield null;
      return;
    }
    yield* watchMessage(a.messageRowid).map(
      (views) => views.where((v) => v.attachmentId == attachmentId).firstOrNull,
    );
  }

  /// Like [watchMessage], once.
  Future<List<AttachmentTransferView>> viewsOf(int messageRowid) async =>
      _views(
        await _db.messagesDao.attachmentsFor([messageRowid]),
        await _db.transfersDao.live(),
      );

  List<AttachmentTransferView> _views(
    List<AttachmentRow> attachments,
    List<TransferRow> jobs,
  ) {
    final byAttachment = {
      for (final job in jobs)
        if (job.attachmentRowid != null) job.attachmentRowid!: job,
    };
    return [
      for (final a in attachments)
        AttachmentTransferView.of(
          a,
          byAttachment[a.id],
          encryptionChunkBytes: _config.encryptionChunkBytes,
        ),
    ];
  }

  static bool _sameViews(
    List<AttachmentTransferView> a,
    List<AttachmentTransferView> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ------------------------------------------------------------ upkeep

  /// Deletes files nothing points at any more (the file store follows the
  /// messages). Runs by itself; call it to be sure (tests, headless hosts).
  Future<int> sweep() async => await _janitor?.sweep() ?? 0;

  /// Deletes every file the engine holds (sign-out, revocation).
  Future<void> wipeFiles() async {
    try {
      await _blobs?.clear();
    } on Object {
      // Nothing more can be done about a store that will not clear.
    }
  }

  /// Housekeeping that follows from what happened to messages: view-once
  /// media the recipient has seen is deleted from the sender's device too,
  /// and a queued send whose message was deleted before it left is dropped
  /// (it would hold up the chat for good). Runs with the file sweep.
  Future<void> upkeep() async {
    if (_blobs == null) return;
    try {
      await _outbound.reapHeld();
      await _consumeViewed(includeIncoming: false);
    } on Object {
      // The database closed under us.
    }
  }

  /// Start-up: also deletes the media of incoming view-once messages that
  /// were opened but not consumed (the app died while the viewer was open;
  /// nobody can be looking now).
  Future<void> consumeOpenedViewOnce() async {
    if (_blobs == null) return;
    await _consumeViewed(includeIncoming: true);
  }

  Future<void> _consumeViewed({required bool includeIncoming}) async {
    for (final item in await _db.messagesDao.viewOnceWithMediaToConsume()) {
      if (!item.outgoing && !includeIncoming) continue;
      try {
        await consumeViewOnce(item.rowid);
      } on Object {
        // Gone meanwhile.
      }
    }
  }
}

/// The latest value of two streams, combined.
Stream<R> _combine<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A a, B b) combine,
) {
  late final StreamController<R> controller;
  StreamSubscription<A>? subscriptionA;
  StreamSubscription<B>? subscriptionB;
  A? latestA;
  B? latestB;
  var hasA = false;
  var hasB = false;
  void emit() {
    if (hasA && hasB && !controller.isClosed) {
      controller.add(combine(latestA as A, latestB as B));
    }
  }

  controller = StreamController<R>(
    onListen: () {
      subscriptionA = a.listen((value) {
        latestA = value;
        hasA = true;
        emit();
      }, onError: controller.addError);
      subscriptionB = b.listen((value) {
        latestB = value;
        hasB = true;
        emit();
      }, onError: controller.addError);
    },
    onCancel: () async {
      await subscriptionA?.cancel();
      await subscriptionB?.cancel();
    },
  );
  return controller.stream;
}
