import 'dart:typed_data';

import 'package:helix_remote_protocol/src/content/media_pointer.dart';
import 'package:helix_remote_protocol/src/json.dart';

part 'bodies/actions.dart';
part 'bodies/bounded.dart';
part 'bodies/control.dart';
part 'bodies/transfer.dart';
part 'bodies/visible.dart';

/// Limits receivers enforce; content past them is treated as unreadable.
///
/// A body does not name one of these itself: it reads a sized field through
/// [Bounded] (`bodies/bounded.dart`), which binds the field's role to the
/// limit the contract knows for it. Anything a role does not name falls back
/// to the reader's own backstop in `json.dart`.
abstract final class ContentLimits {
  static const maxTextLength = 65536;
  static const maxCaptionLength = 4096;

  /// A name, title, label or address: one line a peer writes about something.
  static const maxNameLength = 512;

  /// An identifier on the wire (a message id, an account address, a group or
  /// device id). Account addresses are `uuid@host`, so this covers the widest
  /// legal one.
  static const maxIdLength = 512;

  /// A URL in a link preview.
  static const maxUrlLength = 4096;

  /// A phone number in a contact card, as the sender typed it.
  static const maxNumberLength = 32;

  /// The length of a key or digest the crypto fixes: X25519 and Ed25519
  /// public keys, chain keys, group and profile keys, SHA-256.
  static const keyBytes = 32;

  static const maxMediaItems = 30;

  /// Mentions in one text message: at most one per member of the largest
  /// group (Group.maxMembers).
  static const maxMentions = 1024;

  static const minPollOptions = 2;
  static const maxPollOptions = 12;
  static const maxEmojiLength = 16;

  /// Ids in one receipt — and in one resend request, which is the same shape.
  static const maxIdsPerReceipt = 500;

  /// Contacts in one `contact_sync` message (own devices only).
  static const maxContactEntries = 4096;

  /// Numbers in one contact card.
  static const maxContactNumbers = 32;

  /// Keys in one `system` body's field map.
  static const maxSystemFields = 32;

  /// Devices named in one message (a history transfer). No account comes
  /// near this; the list is the sender's own device id list.
  static const maxDevices = 256;

  static const editWindow = Duration(minutes: 15);
  static const deleteWindow = Duration(days: 2);

  /// Sanity bounds on numbers read from peers: nothing beyond them is real,
  /// and everything within them is safe to add, multiply and `Duration`.
  static const maxLatE7 = 900000000;
  static const maxLngE7 = 1800000000;
  static const maxAccuracyM = 100000000;
  static const maxCallSeconds = 31536000;
  static const maxExpireSeconds = 315360000;

  /// Counters (iterations, epochs, versions) are 32-bit on the wire.
  static const maxCounter = 4294967295;

  /// A media dimension or duration (pixels, milliseconds).
  static const maxMediaDimension = 1000000;
  static const maxMediaDurationMs = 86400000;
  static const maxWaveformSamples = 1024;
}

/// A message being acted on (reaction, edit, delete, vote, RSVP, reply).
final class MessageRef {
  const MessageRef({required this.id, required this.author});

  final String id;
  final String author;

  JsonMap toJson() => {'id': id, 'author': author};

  factory MessageRef.fromJson(JsonReader json) =>
      MessageRef(id: json.id('id'), author: json.id('author'));

  @override
  bool operator ==(Object other) =>
      other is MessageRef && other.id == id && other.author == author;

  @override
  int get hashCode => Object.hash(id, author);
}

/// The `body` of a content message, by `type`.
sealed class ContentBody {
  const ContentBody();

  /// Every body this build can read, keyed by its `type` string in the order
  /// the families below declare them. It is the only decode table: a type
  /// name missing here cannot be produced by this build's encoder, so the
  /// [UnknownBody] fallback means exactly what the contract says it means —
  /// a peer from a newer version. An unregistered class is a test failure
  /// (`test/content_test.dart`), not a silent fallback.
  static const Map<String, ContentBody Function(JsonReader)> _registry = {
    TextBody.typeName: TextBody.fromJson,
    MediaBody.typeName: MediaBody.fromJson,
    StickerBody.typeName: StickerBody.fromJson,
    LocationBody.typeName: LocationBody.fromJson,
    LiveLocationBody.typeName: LiveLocationBody.fromJson,
    ContactBody.typeName: ContactBody.fromJson,
    PollBody.typeName: PollBody.fromJson,
    EventBody.typeName: EventBody.fromJson,
    SystemBody.typeName: SystemBody.fromJson,
    CallLogBody.typeName: CallLogBody.fromJson,
    ReactionBody.typeName: ReactionBody.fromJson,
    EditBody.typeName: EditBody.fromJson,
    DeleteBody.typeName: DeleteBody.fromJson,
    PinBody.typeName: PinBody.fromJson,
    PollVoteBody.typeName: PollVoteBody.fromJson,
    RsvpBody.typeName: RsvpBody.fromJson,
    ReceiptBody.typeName: ReceiptBody.fromJson,
    TypingBody.typeName: TypingBody.fromJson,
    SenderKeyDistributionBody.typeName: SenderKeyDistributionBody.fromJson,
    GroupKeyBody.typeName: GroupKeyBody.fromJson,
    ProfileKeyUpdateBody.typeName: ProfileKeyUpdateBody.fromJson,
    DecryptionErrorBody.typeName: DecryptionErrorBody.fromJson,
    ResendRequestBody.typeName: ResendRequestBody.fromJson,
    ContactSyncBody.typeName: ContactSyncBody.fromJson,
    DeviceTransferOfferBody.typeName: DeviceTransferOfferBody.fromJson,
  };

  /// Every content type string [decode] understands, in [_registry]'s order.
  /// Tests enumerate it so a new type cannot ship without a golden fixture
  /// (`contracts/v2/fixtures/`).
  static List<String> get knownTypes => _registry.keys.toList();

  String get type;

  /// Shown as its own bubble in the chat (as opposed to acting on another
  /// message or being control traffic).
  bool get isVisible;

  JsonMap toJson();

  static ContentBody decode(String type, JsonReader body) {
    final decodeBody = _registry[type];
    if (decodeBody == null) return UnknownBody(type: type, raw: body.json);
    return decodeBody(body);
  }
}

/// A type this client does not know. Shown as "This message needs a newer
/// version of Helix" (CONTENT_V2.md §1), never as raw JSON.
final class UnknownBody extends ContentBody {
  const UnknownBody({required this.type, required this.raw});

  @override
  final String type;
  final JsonMap raw;

  @override
  bool get isVisible => true;

  @override
  JsonMap toJson() => raw;
}
