import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/src/messaging/kinds.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// How a visible content body is split across the `messages` columns
/// (`body` = searchable text or caption, `payload` = the rest as JSON) and
/// put back together, for example to re-send a message (CRYPTO_V2.md §13a).
abstract final class ContentCodec {
  /// The text and payload columns for [body].
  static ({String? text, String? payload}) split(ContentBody body) {
    switch (body) {
      case TextBody():
        final rest = body.toJson()..remove('text');
        return (text: body.text, payload: _json(rest));
      case MediaBody():
        final rest = body.toJson()..remove('caption');
        return (text: body.caption, payload: _json(rest));
      default:
        return (text: null, payload: _json(body.toJson()));
    }
  }

  /// The body stored in [row]; an unreadable payload becomes an
  /// [UnknownBody] instead of failing.
  static ContentBody join(MessageRow row) {
    try {
      final payload = row.payload == null
          ? <String, Object?>{}
          : (jsonDecode(row.payload!) as Map).cast<String, Object?>();
      final map = {...payload};
      if (row.body != null) {
        map[row.kind == MediaBody.typeName ? 'caption' : 'text'] = row.body;
      }
      return ContentBody.decode(row.kind, JsonReader(map));
    } on Object {
      return UnknownBody(type: row.kind, raw: const {});
    }
  }

  /// The content message that carried [row] (an outgoing message), for a
  /// re-send. The edited text, if any, is what is sent again.
  static ContentMessage rebuild(
    MessageRow row, {
    required String to,
    required Uint8List? profileKey,
    ConversationRef? conversation,
  }) => ContentMessage(
    id: row.messageId,
    sentAt: row.sentAt,
    conversation: conversation ?? DirectConversation(to: to),
    body: join(row),
    reply: row.replyToId == null || row.replyToAuthor == null
        ? null
        : MessageRef(id: row.replyToId!, author: row.replyToAuthor!),
    expireSeconds: row.expireSeconds,
    profileKey: profileKey,
    viewOnce: row.viewOnceState != null,
  );

  /// Whether a body is shown as its own bubble and gets a delivered receipt.
  static bool isMessage(ContentBody body) =>
      body.isVisible &&
      !(body is LiveLocationBody && body.state != LiveLocationState.start);

  /// A media body's items as attachment rows (album order is set by the
  /// insert; `messageRowid` and `position` are filled in there).
  static List<AttachmentsCompanion> attachments(MediaBody body) => [
    for (final item in body.items)
      AttachmentsCompanion.insert(
        messageRowid: 0,
        position: 0,
        kind: item.kind.wire,
        mediaId: item.media.id,
        mediaKey: item.media.key,
        digest: item.media.digest,
        mime: item.media.mime,
        size: item.media.size,
        name: Value(item.media.name),
        width: Value(item.width),
        height: Value(item.height),
        durationMs: Value(item.durationMs),
        waveform: Value(item.waveform),
        blurhash: Value(item.media.blurhash),
        caption: Value(item.caption),
        thumbnail: Value(
          item.media.thumbnail == null
              ? null
              : jsonEncode(item.media.thumbnail!.toJson()),
        ),
        transfer: AttachmentTransfer.remote,
      ),
  ];

  /// The kind a content type is stored under: unknown types and content
  /// from newer versions are shown as "needs a newer version". A type a peer
  /// invents that is one of the engine's own row kinds (a forged "couldn't
  /// decrypt" placeholder, say) is stored as unsupported too: those kinds
  /// are written only by the engine.
  static String storedKind(ContentMessage content) {
    final body = content.body;
    if (content.isFromNewerVersion ||
        (body is UnknownBody && MessageKinds.reserved.contains(body.type))) {
      return MessageKinds.unsupported;
    }
    return body.type;
  }

  static String? _json(Map<String, Object?> map) =>
      map.isEmpty ? null : jsonEncode(map);
}
