import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/features/conversation/application/media_content.dart';
import 'package:helix_remote/features/conversation/application/media_viewer.dart';
import 'package:helix_remote_db/helix_remote_db.dart' show SharedAttachment;

/// One photo or video in the shared-media grid.
@immutable
class SharedMediaTile {
  const SharedMediaTile({
    required this.part,
    required this.messageRowid,
    required this.index,
    required this.label,
    this.thumbnail,
    this.isVideo = false,
    this.durationLabel,
  });

  final MediaPart part;

  /// The message it came in, and its place in that message's album.
  final int messageRowid;
  final int index;
  final ImageProvider? thumbnail;
  final bool isVideo;
  final String? durationLabel;

  /// For a screen reader: "Photo, Yesterday" or "Video, 3 Oct".
  final String label;

  @override
  bool operator ==(Object other) =>
      other is SharedMediaTile &&
      other.part == part &&
      other.messageRowid == messageRowid &&
      other.index == index &&
      other.thumbnail == thumbnail;

  @override
  int get hashCode => Object.hash(part, messageRowid, index, thumbnail);
}

/// One file in the documents list.
@immutable
class SharedDocument {
  const SharedDocument({
    required this.part,
    required this.messageRowid,
    required this.name,
    required this.detail,
  });

  final MediaPart part;
  final int messageRowid;
  final String name;

  /// "482 KB, PDF, Yesterday".
  final String detail;

  @override
  bool operator ==(Object other) =>
      other is SharedDocument &&
      other.part == part &&
      other.messageRowid == messageRowid &&
      other.name == name &&
      other.detail == detail;

  @override
  int get hashCode => Object.hash(part, messageRowid, name, detail);
}

/// One web link found in a message's text.
@immutable
class SharedLink {
  const SharedLink({
    required this.url,
    required this.host,
    required this.messageId,
    required this.whenLabel,
  });

  final String url;

  /// The site, without `www.`: the line a person scans for.
  final String host;

  /// The message's content id, which "show in chat" opens at.
  final String messageId;
  final String whenLabel;

  @override
  bool operator ==(Object other) =>
      other is SharedLink &&
      other.url == url &&
      other.messageId == messageId &&
      other.whenLabel == whenLabel;

  @override
  int get hashCode => Object.hash(url, messageId, whenLabel);
}

/// The media and documents of a conversation.
@immutable
class SharedFiles {
  const SharedFiles({this.media = const [], this.documents = const []});

  final List<SharedMediaTile> media;
  final List<SharedDocument> documents;
}

const _visualKinds = {'image', 'video', 'video_note', 'gif'};

/// Photos and videos in a grid, everything else (files, audio) as documents,
/// newest first, live. The engine's query bounds it (500 attachments).
final sharedFilesProvider = StreamProvider.autoDispose
    .family<SharedFiles, String>((ref, conversationId) async* {
      final gateway = await ref.watch(chatGatewayProvider.future);
      final now = ref.read(clockProvider)();
      yield* gateway
          .watchSharedAttachments(conversationId)
          .map((rows) => sharedFilesOf(rows, now));
    });

/// The grid and the list for [rows] (newest message first), as seen at [now].
SharedFiles sharedFilesOf(List<SharedAttachment> rows, DateTime now) {
  final media = <SharedMediaTile>[];
  final documents = <SharedDocument>[];
  for (final shared in rows) {
    final row = shared.attachment;
    final part = MediaPart(row, null);
    final when = formatChatTime(shared.sentAt, now);
    if (_visualKinds.contains(row.kind)) {
      final isVideo = row.kind == 'video' || row.kind == 'video_note';
      media.add(
        SharedMediaTile(
          part: part,
          messageRowid: row.messageRowid,
          index: row.position,
          thumbnail: mediaThumbnailOf(part),
          isVideo: isVideo,
          durationLabel: isVideo ? formatDurationMs(row.durationMs) : null,
          label: isVideo ? 'Video, $when' : 'Photo, $when',
        ),
      );
    } else {
      final name = row.name ?? 'File';
      final dot = name.lastIndexOf('.');
      final type = dot < 0 || dot == name.length - 1
          ? null
          : name.substring(dot + 1).toUpperCase();
      documents.add(
        SharedDocument(
          part: part,
          messageRowid: row.messageRowid,
          name: name,
          detail: [formatFileSize(row.size), ?type, when].join(', '),
        ),
      );
    }
  }
  return SharedFiles(media: media, documents: documents);
}

final _linkPattern = RegExp(r'https?://[^\s<>"]+', caseSensitive: false);

/// The web links in a conversation's messages, newest first, live. A message
/// with two links gives two rows.
final sharedLinksProvider = StreamProvider.autoDispose
    .family<List<SharedLink>, String>((ref, conversationId) async* {
      final gateway = await ref.watch(chatGatewayProvider.future);
      final now = ref.read(clockProvider)();
      yield* gateway.watchMessagesWithLinks(conversationId).map((rows) {
        return [
          for (final row in rows)
            for (final match in _linkPattern.allMatches(row.body ?? ''))
              SharedLink(
                url: _cleaned(match.group(0)!),
                host: _hostOf(_cleaned(match.group(0)!)),
                messageId: row.messageId,
                whenLabel: formatChatTime(row.sentAt, now),
              ),
        ];
      });
    });

/// Trailing punctuation belongs to the sentence, not to the link.
String _cleaned(String url) {
  const trailing = '.,;:!?)]}\'"';
  var end = url.length;
  while (end > 0 && trailing.contains(url[end - 1])) {
    end--;
  }
  return url.substring(0, end);
}

String _hostOf(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  if (host.isEmpty) return url;
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// What tapping a file in the shared-media view did.
enum SharedOpenResult {
  /// A photo or video: open the viewer.
  viewer,

  /// A document: it was handed to the system (share sheet) to open.
  handedOver,

  /// It is not on this phone yet: a download was started.
  fetching,

  /// A transfer that was running was cancelled.
  cancelled,

  /// The file is gone.
  missing,
}

/// Opens [part] of the message [messageRowid].
typedef SharedOpen =
    Future<SharedOpenResult> Function(MediaPart part, int messageRowid);

/// Taps in the shared-media view: the same rules as a media bubble (open it
/// when it is here, download it when it is not).
final sharedOpenProvider = Provider<SharedOpen>((ref) {
  return (part, messageRowid) async {
    final actions = ref.read(mediaActionsProvider);
    final tap = await actions.tap(part, messageRowid: messageRowid);
    switch (tap) {
      case MediaTap.fetching:
        return SharedOpenResult.fetching;
      case MediaTap.cancelled:
        return SharedOpenResult.cancelled;
      case MediaTap.open:
        if (part.isVisual) return SharedOpenResult.viewer;
        return await actions.share(part)
            ? SharedOpenResult.handedOver
            : SharedOpenResult.missing;
    }
  };
});
