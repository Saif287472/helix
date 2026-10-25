part of '../bodies.dart';

/// The bodies a chat shows as its own bubble (CONTENT_V2.md §2).

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
    account: json.id('account'),
    start: json.intIn('start', 0, ContentLimits.maxTextLength),
    length: json.intIn('length', 0, ContentLimits.maxTextLength),
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
    url: json.url('url'),
    title: json.optName('title'),
    description: json.optCaption('description'),
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
    text: json.text('text'),
    mentions: json.optMany(
      'mentions',
      Mention.fromJson,
      maxItems: ContentLimits.maxMentions,
    ),
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
    final items = json.many(
      'items',
      MediaItem.fromJson,
      maxItems: ContentLimits.maxMediaItems,
    );
    if (items.isEmpty) {
      throw ProtocolFormatException(
        'bad item count',
        path: '${json.path}.items',
      );
    }
    return MediaBody(items: items, caption: json.optCaption('caption'));
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
    packId: json.id('pack_id'),
    stickerId: json.id('sticker_id'),
    media: MediaPointer.fromJson(json.object('media')),
    emoji: json.optEmoji('emoji'),
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
    latE7: json.intIn(
      'lat_e7',
      -ContentLimits.maxLatE7,
      ContentLimits.maxLatE7,
    ),
    lngE7: json.intIn(
      'lng_e7',
      -ContentLimits.maxLngE7,
      ContentLimits.maxLngE7,
    ),
    accuracyM: json.intIn('accuracy_m', 0, ContentLimits.maxAccuracyM),
    label: json.optName('label'),
    address: json.optName('address'),
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
    sessionId: json.id('session_id'),
    state: json.enumValue('state', LiveLocationState.values),
    latE7: json.intIn(
      'lat_e7',
      -ContentLimits.maxLatE7,
      ContentLimits.maxLatE7,
    ),
    lngE7: json.intIn(
      'lng_e7',
      -ContentLimits.maxLngE7,
      ContentLimits.maxLngE7,
    ),
    accuracyM: json.intIn('accuracy_m', 0, ContentLimits.maxAccuracyM),
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
    name: json.label('name'),
    numbers: json.optNumbers('numbers'),
    account: json.optId('account'),
  );
}

final class PollOption {
  const PollOption({required this.id, required this.text});

  final String id;
  final String text;

  JsonMap toJson() => {'id': id, 'text': text};

  factory PollOption.fromJson(JsonReader json) =>
      PollOption(id: json.id('id'), text: json.label('text'));
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
    final options = json.many(
      'options',
      PollOption.fromJson,
      maxItems: ContentLimits.maxPollOptions,
    );
    if (options.length < ContentLimits.minPollOptions) {
      throw ProtocolFormatException(
        'bad option count',
        path: '${json.path}.options',
      );
    }
    return PollBody(
      question: json.caption('question'),
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
    title: json.label('title'),
    startsAt: json.time('starts_at'),
    endsAt: json.optTime('ends_at'),
    timeZone: json.name('time_zone'),
    locationText: json.optName('location_text'),
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

  factory SystemBody.fromJson(JsonReader json) {
    final fields = {
      for (final e in json.json.entries)
        if (e.key != 'kind') e.key: e.value,
    };
    if (fields.length > ContentLimits.maxSystemFields) {
      throw ProtocolFormatException('too many fields', path: json.path);
    }
    return SystemBody(kind: json.name('kind'), fields: fields);
  }
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
    callId: json.id('call_id'),
    media: json.enumValue('media', CallMedia.values),
    outcome: json.enumValue(
      'outcome',
      CallOutcome.values,
      orElse: CallOutcome.unknown,
    ),
    durationS: json.optIntIn('duration_s', 0, ContentLimits.maxCallSeconds),
  );
}
