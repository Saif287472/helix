import 'dart:typed_data';

import 'package:helix_remote_protocol/src/content/media_pointer.dart';
import 'package:helix_remote_protocol/src/json.dart';

/// Limits receivers enforce; content past them is treated as unreadable.
abstract final class ContentLimits {
  static const maxTextLength = 65536;
  static const maxCaptionLength = 4096;
  static const maxMediaItems = 30;
  static const minPollOptions = 2;
  static const maxPollOptions = 12;
  static const maxEmojiLength = 16;
  static const maxIdsPerReceipt = 500;
  static const editWindow = Duration(minutes: 15);
  static const deleteWindow = Duration(days: 2);
}

/// A message being acted on (reaction, edit, delete, vote, RSVP, reply).
final class MessageRef {
  const MessageRef({required this.id, required this.author});

  final String id;
  final String author;

  JsonMap toJson() => {'id': id, 'author': author};

  factory MessageRef.fromJson(JsonReader json) =>
      MessageRef(id: json.nonEmpty('id'), author: json.nonEmpty('author'));

  @override
  bool operator ==(Object other) =>
      other is MessageRef && other.id == id && other.author == author;

  @override
  int get hashCode => Object.hash(id, author);
}

/// The `body` of a content message, by `type`.
sealed class ContentBody {
  const ContentBody();

  String get type;

  /// Shown as its own bubble in the chat (as opposed to acting on another
  /// message or being control traffic).
  bool get isVisible;

  JsonMap toJson();

  static ContentBody decode(String type, JsonReader body) => switch (type) {
    TextBody.typeName => TextBody.fromJson(body),
    MediaBody.typeName => MediaBody.fromJson(body),
    StickerBody.typeName => StickerBody.fromJson(body),
    LocationBody.typeName => LocationBody.fromJson(body),
    LiveLocationBody.typeName => LiveLocationBody.fromJson(body),
    ContactBody.typeName => ContactBody.fromJson(body),
    PollBody.typeName => PollBody.fromJson(body),
    EventBody.typeName => EventBody.fromJson(body),
    SystemBody.typeName => SystemBody.fromJson(body),
    CallLogBody.typeName => CallLogBody.fromJson(body),
    ReactionBody.typeName => ReactionBody.fromJson(body),
    EditBody.typeName => EditBody.fromJson(body),
    DeleteBody.typeName => DeleteBody.fromJson(body),
    PollVoteBody.typeName => PollVoteBody.fromJson(body),
    RsvpBody.typeName => RsvpBody.fromJson(body),
    ReceiptBody.typeName => ReceiptBody.fromJson(body),
    TypingBody.typeName => TypingBody.fromJson(body),
    SenderKeyDistributionBody.typeName => SenderKeyDistributionBody.fromJson(
      body,
    ),
    GroupKeyBody.typeName => GroupKeyBody.fromJson(body),
    ProfileKeyUpdateBody.typeName => ProfileKeyUpdateBody.fromJson(body),
    DecryptionErrorBody.typeName => DecryptionErrorBody.fromJson(body),
    ResendRequestBody.typeName => ResendRequestBody.fromJson(body),
    ContactSyncBody.typeName => ContactSyncBody.fromJson(body),
    _ => UnknownBody(type: type, raw: body.json),
  };
}

String _limited(JsonReader json, String key, int max) {
  final value = json.string(key);
  if (value.length > max) {
    throw ProtocolFormatException('too long', path: '${json.path}.$key');
  }
  return value;
}

String? _optLimited(JsonReader json, String key, int max) =>
    json.has(key) ? _limited(json, key, max) : null;

// -------------------------------------------------------- visible messages

final class Mention {
  const Mention({
    required this.account,
    required this.start,
    required this.length,
  });

  final String account;
  final int start;
  final int length;

  JsonMap toJson() => {'account': account, 'start': start, 'length': length};

  factory Mention.fromJson(JsonReader json) => Mention(
    account: json.nonEmpty('account'),
    start: json.integer('start'),
    length: json.integer('length'),
  );
}

final class LinkPreview {
  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.image,
  });

  final String url;
  final String? title;
  final String? description;
  final MediaPointer? image;

  JsonMap toJson() => compact({
    'url': url,
    'title': title,
    'description': description,
    'image': image?.toJson(),
  });

  factory LinkPreview.fromJson(JsonReader json) => LinkPreview(
    url: json.nonEmpty('url'),
    title: json.optString('title'),
    description: json.optString('description'),
    image: json.has('image')
        ? MediaPointer.fromJson(json.object('image'))
        : null,
  );
}

final class TextBody extends ContentBody {
  const TextBody({
    required this.text,
    this.mentions = const [],
    this.linkPreview,
  });

  static const typeName = 'text';

  final String text;
  final List<Mention> mentions;
  final LinkPreview? linkPreview;

  @override
  String get type => typeName;

  @override
  bool get isVisible => true;

  @override
  JsonMap toJson() => compact({
    'text': text,
    'mentions': mentions.isEmpty
        ? null
        : [for (final m in mentions) m.toJson()],
    'link_preview': linkPreview?.toJson(),
  });

  factory TextBody.fromJson(JsonReader json) => TextBody(
    text: _limited(json, 'text', ContentLimits.maxTextLength),
    mentions: json.optObjects('mentions', Mention.fromJson),
    linkPreview: json.has('link_preview')
        ? LinkPreview.fromJson(json.object('link_preview'))
        : null,
  );
}

final class MediaBody extends ContentBody {
  const MediaBody({required this.items, this.caption});

  static const typeName = 'media';

  final List<MediaItem> items;
  final String? caption;

  @override
  String get type => typeName;

  @override
  bool get isVisible => true;

  @override
  JsonMap toJson() => compact({
    'items': [for (final i in items) i.toJson()],
    'caption': caption,
  });

  factory MediaBody.fromJson(JsonReader json) {
    final items = json.objects('items', MediaItem.fromJson);
    if (items.isEmpty || items.length > ContentLimits.maxMediaItems) {
      throw ProtocolFormatException(
        'bad item count',
        path: '${json.path}.items',
      );
    }
    return MediaBody(
      items: items,
      caption: _optLimited(json, 'caption', ContentLimits.maxCaptionLength),
    );
  }
}

final class StickerBody extends ContentBody {
  const StickerBody({
    required this.packId,
    required this.stickerId,
    required this.media,
    this.emoji,
  });

  static const typeName = 'sticker';

  final String packId;
  final String stickerId;
  final MediaPointer media;
  final String? emoji;

  @override
  String get type => typeName;

  @override
  bool get isVisible => true;

  @override
  JsonMap toJson() => compact({
    'pack_id': packId,
    'sticker_id': stickerId,
    'media': media.toJson(),
    'emoji': emoji,
  });

  factory StickerBody.fromJson(JsonReader json) => StickerBody(
    packId: json.nonEmpty('pack_id'),
    stickerId: json.nonEmpty('sticker_id'),
    media: MediaPointer.fromJson(json.object('media')),
    emoji: _optLimited(json, 'emoji', ContentLimits.maxEmojiLength),
  );
}

final class LocationBody extends ContentBody {
  const LocationBody({
    required this.latE7,
    required this.lngE7,
    required this.accuracyM,
    this.label,
    this.address,
  });

  static const typeName = 'location';

  /// Degrees × 10^7.
  final int latE7;
  final int lngE7;
  final int accuracyM;
  final String? label;
  final String? address;

  @override
  String get type => typeName;

  @override
  bool get isVisible => true;

  @override
  JsonMap toJson() => compact({
    'lat_e7': latE7,
    'lng_e7': lngE7,
    'accuracy_m': accuracyM,
    'label': label,
    'address': address,
  });

  factory LocationBody.fromJson(JsonReader json) => LocationBody(
    latE7: json.integer('lat_e7'),
    lngE7: json.integer('lng_e7'),
    accuracyM: json.integer('accuracy_m'),
    label: json.optString('label'),
    address: json.optString('address'),
  );
}

enum LiveLocationState implements WireEnum {
  start('start'),
  update('update'),
  stop('stop');

  const LiveLocationState(this.wire);

  @override
  final String wire;
}

/// One session: one `start` (shown as a bubble), many `update`, one `stop`.
final class LiveLocationBody extends ContentBody {
  const LiveLocationBody({
    required this.sessionId,
    required this.state,
    required this.latE7,
    required this.lngE7,
    required this.accuracyM,
    required this.expiresAt,
  });

  static const typeName = 'live_location';

  final String sessionId;
  final LiveLocationState state;
  final int latE7;
  final int lngE7;
  final int accuracyM;
  final DateTime expiresAt;

  @override
  String get type => typeName;

  @override
  bool get isVisible => state == LiveLocationState.start;

  @override
  JsonMap toJson() => {
    'session_id': sessionId,
    'state': state.wire,
    'lat_e7': latE7,
    'lng_e7': lngE7,
    'accuracy_m': accuracyM,
    'expires_at': toWireTime(expiresAt),
  };

  factory LiveLocationBody.fromJson(JsonReader json) => LiveLocationBody(
    sessionId: json.nonEmpty('session_id'),
    state: json.enumValue('state', LiveLocationState.values),
    latE7: json.integer('lat_e7'),
    lngE7: json.integer('lng_e7'),
    accuracyM: json.integer('accuracy_m'),
    expiresAt: json.time('expires_at'),
  );
}

final class ContactBody extends ContentBody {
  const ContactBody({
    required this.name,
    this.numbers = const [],
    this.account,
  });

  static const typeName = 'contact';

  final String name;
  final List<String> numbers;
  final String? account;

  @override
  String get type => typeName;

  @override
  bool get isVisible => true;

  @override
  JsonMap toJson() => compact({
    'name': name,
    'numbers': numbers.isEmpty ? null : numbers,
    'account': account,
  });

  factory ContactBody.fromJson(JsonReader json) => ContactBody(
    name: json.string('name'),
    numbers: json.optStrings('numbers'),
    account: json.optString('account'),
  );
}

final class PollOption {
  const PollOption({required this.id, required this.text});

  final String id;
  final String text;

  JsonMap toJson() => {'id': id, 'text': text};

  factory PollOption.fromJson(JsonReader json) =>
      PollOption(id: json.nonEmpty('id'), text: json.string('text'));
}

final class PollBody extends ContentBody {
  const PollBody({
    required this.question,
    required this.options,
    this.multiple = false,
    this.closesAt,
  });

  static const typeName = 'poll';

  final String question;
  final List<PollOption> options;
  final bool multiple;
  final DateTime? closesAt;

  @override
  String get type => typeName;

  @override
  bool get isVisible => true;

  @override
  JsonMap toJson() => compact({
    'question': question,
    'options': [for (final o in options) o.toJson()],
    'multiple': multiple,
    'closes_at': closesAt == null ? null : toWireTime(closesAt!),
  });

  factory PollBody.fromJson(JsonReader json) {
    final options = json.objects('options', PollOption.fromJson);
    if (options.length < ContentLimits.minPollOptions ||
        options.length > ContentLimits.maxPollOptions) {
      throw ProtocolFormatException(
        'bad option count',
        path: '${json.path}.options',
      );
    }
    return PollBody(
      question: json.string('question'),
      options: options,
      multiple: json.flag('multiple'),
      closesAt: json.optTime('closes_at'),
    );
  }
}

final class EventBody extends ContentBody {
  const EventBody({
    required this.title,
    required this.startsAt,
    required this.timeZone,
    this.endsAt,
    this.locationText,
    this.plusOneAllowed = false,
  });

  static const typeName = 'event';

  final String title;
  final DateTime startsAt;
  final DateTime? endsAt;

  /// IANA zone, e.g. `Asia/Dhaka`.
  final String timeZone;
  final String? locationText;
  final bool plusOneAllowed;

  @override
  String get type => typeName;

  @override
  bool get isVisible => true;

  @override
  JsonMap toJson() => compact({
    'title': title,
    'starts_at': toWireTime(startsAt),
    'ends_at': endsAt == null ? null : toWireTime(endsAt!),
    'time_zone': timeZone,
    'location_text': locationText,
    'plus_one_allowed': plusOneAllowed,
  });

  factory EventBody.fromJson(JsonReader json) => EventBody(
    title: json.string('title'),
    startsAt: json.time('starts_at'),
    endsAt: json.optTime('ends_at'),
    timeZone: json.nonEmpty('time_zone'),
    locationText: json.optString('location_text'),
    plusOneAllowed: json.flag('plus_one_allowed'),
  );
}

/// A chat or group change the sender announces for local rendering
/// ("Alice changed the timer to 1 day"). The server-side truth for groups is
/// the roster; this is only the human-readable notice.
final class SystemBody extends ContentBody {
  const SystemBody({required this.kind, this.fields = const {}});

  static const typeName = 'system';

  /// e.g. `timer_changed`, `group_created`, `member_added`, `member_removed`,
  /// `member_left`, `group_renamed`, `group_picture_changed`.
  final String kind;
  final JsonMap fields;

  @override
  String get type => typeName;

  @override
  bool get isVisible => true;

  @override
  JsonMap toJson() => {'kind': kind, ...fields};

  factory SystemBody.fromJson(JsonReader json) => SystemBody(
    kind: json.nonEmpty('kind'),
    fields: {
      for (final e in json.json.entries)
        if (e.key != 'kind') e.key: e.value,
    },
  );
}

enum CallMedia implements WireEnum {
  audio('audio'),
  video('video');

  const CallMedia(this.wire);

  @override
  final String wire;
}

enum CallOutcome implements WireEnum {
  answered('answered'),
  missed('missed'),
  declined('declined'),
  failed('failed'),
  unknown('unknown');

  const CallOutcome(this.wire);

  @override
  final String wire;
}

final class CallLogBody extends ContentBody {
  const CallLogBody({
    required this.callId,
    required this.media,
    required this.outcome,
    this.durationS,
  });

  static const typeName = 'call_log';

  final String callId;
  final CallMedia media;
  final CallOutcome outcome;
  final int? durationS;

  @override
  String get type => typeName;

  @override
  bool get isVisible => true;

  @override
  JsonMap toJson() => compact({
    'call_id': callId,
    'media': media.wire,
    'outcome': outcome.wire,
    'duration_s': durationS,
  });

  factory CallLogBody.fromJson(JsonReader json) => CallLogBody(
    callId: json.nonEmpty('call_id'),
    media: json.enumValue('media', CallMedia.values),
    outcome: json.enumValue(
      'outcome',
      CallOutcome.values,
      orElse: CallOutcome.unknown,
    ),
    durationS: json.optInt('duration_s'),
  );
}

// ------------------------------------------------- actions on other messages

final class ReactionBody extends ContentBody {
  const ReactionBody({
    required this.target,
    required this.emoji,
    this.remove = false,
  });

  static const typeName = 'reaction';

  final MessageRef target;
  final String emoji;
  final bool remove;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {
    'target': target.toJson(),
    'emoji': emoji,
    if (remove) 'remove': true,
  };

  factory ReactionBody.fromJson(JsonReader json) => ReactionBody(
    target: MessageRef.fromJson(json.object('target')),
    emoji: _limited(json, 'emoji', ContentLimits.maxEmojiLength),
    remove: json.flag('remove'),
  );
}

final class EditBody extends ContentBody {
  const EditBody({required this.target, this.text, this.caption});

  static const typeName = 'edit';

  final MessageRef target;

  /// New text of a `text` message.
  final String? text;

  /// New caption of a `media` message.
  final String? caption;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() =>
      compact({'target': target.toJson(), 'text': text, 'caption': caption});

  factory EditBody.fromJson(JsonReader json) {
    final edit = EditBody(
      target: MessageRef.fromJson(json.object('target')),
      text: _optLimited(json, 'text', ContentLimits.maxTextLength),
      caption: _optLimited(json, 'caption', ContentLimits.maxCaptionLength),
    );
    if ((edit.text == null) == (edit.caption == null)) {
      throw ProtocolFormatException(
        'edit needs text or caption',
        path: json.path,
      );
    }
    return edit;
  }
}

final class DeleteBody extends ContentBody {
  const DeleteBody({required this.target});

  static const typeName = 'delete';

  final MessageRef target;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {'target': target.toJson()};

  factory DeleteBody.fromJson(JsonReader json) =>
      DeleteBody(target: MessageRef.fromJson(json.object('target')));
}

final class PollVoteBody extends ContentBody {
  const PollVoteBody({required this.target, required this.optionIds});

  static const typeName = 'poll_vote';

  final MessageRef target;

  /// Empty withdraws the vote.
  final List<String> optionIds;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {'target': target.toJson(), 'option_ids': optionIds};

  factory PollVoteBody.fromJson(JsonReader json) => PollVoteBody(
    target: MessageRef.fromJson(json.object('target')),
    optionIds: json.strings('option_ids'),
  );
}

enum RsvpState implements WireEnum {
  going('going'),
  maybe('maybe'),
  declined('declined');

  const RsvpState(this.wire);

  @override
  final String wire;
}

final class RsvpBody extends ContentBody {
  const RsvpBody({
    required this.target,
    required this.state,
    this.plusOne = false,
  });

  static const typeName = 'rsvp';

  final MessageRef target;
  final RsvpState state;
  final bool plusOne;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {
    'target': target.toJson(),
    'state': state.wire,
    'plus_one': plusOne,
  };

  factory RsvpBody.fromJson(JsonReader json) => RsvpBody(
    target: MessageRef.fromJson(json.object('target')),
    state: json.enumValue('state', RsvpState.values),
    plusOne: json.flag('plus_one'),
  );
}

enum ReceiptKind implements WireEnum {
  delivered('delivered'),
  read('read'),
  viewed('viewed');

  const ReceiptKind(this.wire);

  @override
  final String wire;
}

final class ReceiptBody extends ContentBody {
  const ReceiptBody({required this.kind, required this.ids});

  static const typeName = 'receipt';

  final ReceiptKind kind;
  final List<String> ids;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {'kind': kind.wire, 'ids': ids};

  factory ReceiptBody.fromJson(JsonReader json) {
    final ids = json.strings('ids');
    if (ids.isEmpty || ids.length > ContentLimits.maxIdsPerReceipt) {
      throw ProtocolFormatException('bad id count', path: '${json.path}.ids');
    }
    return ReceiptBody(
      kind: json.enumValue('kind', ReceiptKind.values),
      ids: ids,
    );
  }
}

// ----------------------------------------------------------------- control

enum TypingState implements WireEnum {
  started('started'),
  stopped('stopped');

  const TypingState(this.wire);

  @override
  final String wire;
}

final class TypingBody extends ContentBody {
  const TypingBody({required this.state});

  static const typeName = 'typing';

  final TypingState state;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {'state': state.wire};

  factory TypingBody.fromJson(JsonReader json) =>
      TypingBody(state: json.enumValue('state', TypingState.values));
}

final class SenderKeyDistributionBody extends ContentBody {
  const SenderKeyDistributionBody({
    required this.groupId,
    required this.distributionId,
    required this.iteration,
    required this.chainKey,
    required this.signingKey,
  });

  static const typeName = 'sender_key_distribution';

  final String groupId;
  final String distributionId;
  final int iteration;
  final Uint8List chainKey;

  /// Ed25519 public key.
  final Uint8List signingKey;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {
    'group_id': groupId,
    'dist_id': distributionId,
    'iteration': iteration,
    'chain_key': encodeBytes(chainKey),
    'signing_key': encodeBytes(signingKey),
  };

  factory SenderKeyDistributionBody.fromJson(JsonReader json) =>
      SenderKeyDistributionBody(
        groupId: json.nonEmpty('group_id'),
        distributionId: json.nonEmpty('dist_id'),
        iteration: json.integer('iteration'),
        chainKey: json.bytes('chain_key'),
        signingKey: json.bytes('signing_key'),
      );
}

final class GroupKeyBody extends ContentBody {
  const GroupKeyBody({
    required this.groupId,
    required this.epoch,
    required this.key,
  });

  static const typeName = 'group_key';

  final String groupId;
  final int epoch;
  final Uint8List key;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {
    'group_id': groupId,
    'epoch': epoch,
    'key': encodeBytes(key),
  };

  factory GroupKeyBody.fromJson(JsonReader json) => GroupKeyBody(
    groupId: json.nonEmpty('group_id'),
    epoch: json.integer('epoch'),
    key: json.bytes('key'),
  );
}

final class ProfileKeyUpdateBody extends ContentBody {
  const ProfileKeyUpdateBody({required this.key, required this.version});

  static const typeName = 'profile_key_update';

  final Uint8List key;
  final int version;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {'key': encodeBytes(key), 'version': version};

  factory ProfileKeyUpdateBody.fromJson(JsonReader json) =>
      ProfileKeyUpdateBody(
        key: json.bytes('key'),
        version: json.integer('version'),
      );
}

final class DecryptionErrorBody extends ContentBody {
  const DecryptionErrorBody({
    required this.messageId,
    required this.senderDevice,
  });

  static const typeName = 'decryption_error';

  /// Envelope delivery id of the message that failed.
  final String messageId;
  final String senderDevice;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {'message_id': messageId, 'sender_device': senderDevice};

  factory DecryptionErrorBody.fromJson(JsonReader json) => DecryptionErrorBody(
    messageId: json.nonEmpty('message_id'),
    senderDevice: json.nonEmpty('sender_device'),
  );
}

final class ResendRequestBody extends ContentBody {
  const ResendRequestBody({required this.ids});

  static const typeName = 'resend_request';

  final List<String> ids;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {'ids': ids};

  factory ResendRequestBody.fromJson(JsonReader json) =>
      ResendRequestBody(ids: json.strings('ids'));
}

final class ContactSyncEntry {
  const ContactSyncEntry({required this.account, this.nickname});

  final String account;
  final String? nickname;

  JsonMap toJson() => compact({'account': account, 'nickname': nickname});

  factory ContactSyncEntry.fromJson(JsonReader json) => ContactSyncEntry(
    account: json.nonEmpty('account'),
    nickname: json.optString('nickname'),
  );
}

/// Own devices only: renames made on another device.
final class ContactSyncBody extends ContentBody {
  const ContactSyncBody({required this.entries});

  static const typeName = 'contact_sync';

  final List<ContactSyncEntry> entries;

  @override
  String get type => typeName;

  @override
  bool get isVisible => false;

  @override
  JsonMap toJson() => {
    'entries': [for (final e in entries) e.toJson()],
  };

  factory ContactSyncBody.fromJson(JsonReader json) => ContactSyncBody(
    entries: json.objects('entries', ContactSyncEntry.fromJson),
  );
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
