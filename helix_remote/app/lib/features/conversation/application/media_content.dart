import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote/core/util/streams.dart';
import 'package:helix_remote/features/conversation/application/audio_playback.dart';
import 'package:helix_remote/features/conversation/application/message_mapper.dart';
import 'package:helix_remote_db/helix_remote_db.dart'
    show AttachmentRow, AttachmentTransfer;
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show AttachmentTransferView, TransferDirection, TransferPhase;
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// One attachment of a message and where its transfer stands.
@immutable
class MediaPart {
  const MediaPart(this.row, this.view);

  final AttachmentRow row;

  /// Null until the transfer queue has been read.
  final AttachmentTransferView? view;

  int get id => row.id;
  bool get isVisual =>
      const {'image', 'video', 'video_note', 'gif'}.contains(row.kind);

  /// The file is on this device.
  bool get ready =>
      view?.phase == TransferPhase.ready ||
      (view == null && row.transfer == AttachmentTransfer.ready);

  @override
  bool operator ==(Object other) =>
      other is MediaPart && other.row == row && other.view == view;

  @override
  int get hashCode => Object.hash(row, view);
}

/// A message's attachments, live: their rows (sizes, names, thumbnails) and
/// their transfers (progress, failures). Watched only by the rows that are on
/// screen, since a media bubble cannot be drawn without it.
final messageMediaProvider = StreamProvider.autoDispose
    .family<List<MediaPart>, int>((ref, rowid) async* {
      final gateway = await ref.watch(chatGatewayProvider.future);
      yield* combineLatest2<
        List<AttachmentRow>,
        List<AttachmentTransferView>,
        List<MediaPart>
      >(gateway.watchAttachments(rowid), gateway.watchTransfers(rowid), (
        rows,
        views,
      ) {
        final byId = {for (final v in views) v.attachmentId: v};
        return [for (final row in rows) MediaPart(row, byId[row.id])];
      });
    });

/// The bubble content for a media message, from its attachments.
///
/// Visual items (photos, videos, GIFs) become a grid with the caption; a voice
/// note or an audio file becomes the audio bubble (with [playback] state when
/// it is the one playing); anything else is a document tile.
HelixMessageContent mediaContentOf({
  required int rowid,
  required String caption,
  required List<MediaPart> parts,
  PlaybackState? playback,
}) {
  if (parts.isEmpty) return mediaPlaceholderContent(caption);
  final first = parts.first;
  if (parts.every((p) => p.isVisual)) {
    return HelixMediaContent([
      for (final p in parts) _gridItem(p),
    ], caption: caption);
  }
  if (first.row.kind == 'voice_note' || first.row.mime.startsWith('audio/')) {
    final isVoice = first.row.kind == 'voice_note';
    final active = playback != null && playback.messageRowid == rowid;
    final (transfer, progress) = _transferOf(first);
    return HelixAudioContent(
      durationLabel: formatDurationMs(first.row.durationMs),
      waveform: first.row.waveform,
      progress: active ? playback.fraction : 0,
      positionLabel: active && playback.position > Duration.zero
          ? formatDurationMs(playback.position.inMilliseconds)
          : null,
      playing: active && playback.playing,
      speed: playback?.speed ?? 1,
      played: playback?.played.contains(rowid) ?? false,
      isVoiceNote: isVoice,
      transfer: transfer,
      transferProgress: progress,
      title: isVoice ? null : first.row.name,
    );
  }
  final (transfer, progress) = _transferOf(first);
  final name = first.row.name ?? 'File';
  final dot = name.lastIndexOf('.');
  return HelixDocumentContent(
    name: name,
    sizeLabel: formatFileSize(first.row.size),
    typeLabel: dot < 0 || dot == name.length - 1
        ? ''
        : name.substring(dot + 1).toUpperCase(),
    transfer: transfer,
    progress: progress,
    caption: caption,
  );
}

HelixMediaItem _gridItem(MediaPart part) {
  final row = part.row;
  final (transfer, progress) = _transferOf(part);
  final isVideo = row.kind == 'video' || row.kind == 'video_note';
  return HelixMediaItem(
    thumbnail: mediaThumbnailOf(part),
    width: row.width ?? 4,
    height: row.height ?? 3,
    isVideo: isVideo,
    isGif: row.kind == 'gif',
    durationLabel: isVideo ? formatDurationMs(row.durationMs) : null,
    transfer: transfer,
    progress: progress,
    semanticLabel: isVideo ? 'Video' : 'Photo',
  );
}

(HelixTransferState, double?) _transferOf(MediaPart part) {
  final view = part.view;
  if (view == null) {
    return switch (part.row.transfer) {
      AttachmentTransfer.ready => (HelixTransferState.done, null),
      AttachmentTransfer.remote => (HelixTransferState.notDownloaded, null),
      AttachmentTransfer.downloading => (HelixTransferState.downloading, null),
      AttachmentTransfer.uploading => (HelixTransferState.uploading, null),
      AttachmentTransfer.failed => (HelixTransferState.failed, null),
    };
  }
  switch (view.phase) {
    case TransferPhase.ready:
      return (HelixTransferState.done, null);
    case TransferPhase.notDownloaded:
      return (HelixTransferState.notDownloaded, null);
    case TransferPhase.failed:
      return (HelixTransferState.failed, null);
    case TransferPhase.queued:
    case TransferPhase.active:
      final uploading = view.direction == TransferDirection.upload;
      return (
        uploading
            ? HelixTransferState.uploading
            : HelixTransferState.downloading,
        view.phase == TransferPhase.active ? view.fraction : null,
      );
  }
}

/// A small picture of the item: its thumbnail, or, for a finished photo, the
/// photo itself scaled down.
ImageProvider? mediaThumbnailOf(MediaPart part) {
  final thumb = part.view?.thumbnailPath ?? part.row.thumbnailPath;
  if (thumb != null) return _fileImage(thumb);
  final full = part.view?.localPath ?? part.row.localPath;
  if (full != null && part.ready && part.row.kind != 'video') {
    return _fileImage(full);
  }
  return null;
}

/// A file picture decoded no larger than a chat bubble needs. `FileImage` and
/// `ResizeImage` are equal when their file and size are, so an unchanged
/// thumbnail is not decoded again when its message rebuilds.
ImageProvider _fileImage(String path) =>
    ResizeImage(FileImage(File(path)), width: 720, allowUpscaling: false);
