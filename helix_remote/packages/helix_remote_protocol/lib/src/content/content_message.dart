import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_protocol/src/content/bodies.dart';
import 'package:helix_remote_protocol/src/json.dart';

/// Which chat a content message belongs to.
sealed class ConversationRef {
  const ConversationRef();

  JsonMap toJson();

  factory ConversationRef.fromJson(JsonReader json) =>
      switch (json.string('kind')) {
        'direct' => DirectConversation(to: json.nonEmpty('to')),
        'group' => GroupConversation(group: json.nonEmpty('group')),
        _ => throw ProtocolFormatException(
          'unknown conversation kind',
          path: json.path,
        ),
      };
}

/// A one-to-one chat. [to] is the recipient's account, so the sender's own
/// devices can file the message; receivers resolve the chat as "the sender,
/// unless the sender is me, then [to]" ([chatPeer]).
final class DirectConversation extends ConversationRef {
  const DirectConversation({required this.to});

  final String to;

  /// The other person in this chat, seen from [selfAccount].
  String chatPeer({required String sender, required String selfAccount}) =>
      sender == selfAccount ? to : sender;

  @override
  JsonMap toJson() => {'kind': 'direct', 'to': to};

  @override
  bool operator ==(Object other) =>
      other is DirectConversation && other.to == to;

  @override
  int get hashCode => to.hashCode;
}

final class GroupConversation extends ConversationRef {
  const GroupConversation({required this.group});

  final String group;

  @override
  JsonMap toJson() => {'kind': 'group', 'group': group};

  @override
  bool operator ==(Object other) =>
      other is GroupConversation && other.group == group;

  @override
  int get hashCode => group.hashCode;
}

/// The plaintext of every encrypted message (CONTENT_V2.md §1).
final class ContentMessage {
  const ContentMessage({
    required this.id,
    required this.sentAt,
    required this.conversation,
    required this.body,
    this.reply,
    this.expireSeconds,
    this.profileKey,
    this.viewOnce = false,
    this.version = currentVersion,
  });

  /// The newest content version this code writes and fully understands.
  static const currentVersion = 1;

  final int version;

  /// Message id (UUIDv7) chosen by the author. Other content refers to this
  /// message by `(id, author)`.
  final String id;

  /// Author's clock; display order only.
  final DateTime sentAt;
  final ConversationRef conversation;
  final ContentBody body;
  final MessageRef? reply;

  /// Disappearing timer, counted from first display on each device.
  final int? expireSeconds;

  /// The author's profile key (CRYPTO_V2.md §9), sent so recipients can read
  /// the author's profile.
  final Uint8List? profileKey;
  final bool viewOnce;

  /// Written by a newer client; render as "needs a newer version".
  bool get isFromNewerVersion => version > currentVersion;

  JsonMap toJson() => compact({
    'v': version,
    'id': id,
    'ts': toWireTime(sentAt),
    'conv': conversation.toJson(),
    'type': body.type,
    'body': body.toJson(),
    'reply': reply?.toJson(),
    'exp': expireSeconds,
    'profile_key': profileKey == null ? null : encodeBytes(profileKey!),
    'flags': viewOnce ? {'view_once': true} : null,
  });

  factory ContentMessage.fromJson(JsonReader json) {
    final version = json.integer('v');
    final type = json.nonEmpty('type');
    final bodyJson = json.object('body');
    final ContentBody body = version > currentVersion
        ? UnknownBody(type: type, raw: bodyJson.json)
        : ContentBody.decode(type, bodyJson);
    final flags = json.optObject('flags');
    return ContentMessage(
      version: version,
      id: json.nonEmpty('id'),
      sentAt: json.time('ts'),
      conversation: ConversationRef.fromJson(json.object('conv')),
      body: body,
      reply: json.has('reply')
          ? MessageRef.fromJson(json.object('reply'))
          : null,
      expireSeconds: json.optInt('exp'),
      profileKey: json.optBytes('profile_key'),
      viewOnce: flags?.flag('view_once') ?? false,
    );
  }

  /// UTF-8 JSON, before padding and encryption.
  Uint8List encode() => utf8.encode(jsonEncode(toJson()));

  static ContentMessage decode(List<int> bytes) {
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw ProtocolFormatException('content is not UTF-8');
    }
    return ContentMessage.fromJson(JsonReader.decode(text));
  }
}

/// Padding applied before encryption (CRYPTO_V2.md §6): `0x80` then zeros up
/// to the next multiple of [padBlock].
const padBlock = 160;

Uint8List padPlaintext(List<int> plaintext) {
  final total = ((plaintext.length + 1 + padBlock - 1) ~/ padBlock) * padBlock;
  final out = Uint8List(total)..setRange(0, plaintext.length, plaintext);
  out[plaintext.length] = 0x80;
  return out;
}

Uint8List unpadPlaintext(List<int> padded) {
  for (var i = padded.length - 1; i >= 0; i--) {
    if (padded[i] == 0x80) return Uint8List.fromList(padded.sublist(0, i));
    if (padded[i] != 0) break;
  }
  throw ProtocolFormatException('bad padding');
}
