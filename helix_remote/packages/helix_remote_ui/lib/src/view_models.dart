part of '../helix_remote_ui.dart';

// Plain value objects the components are driven by.
//
// The components never read an engine, a database row or a network model:
// the app maps whatever it has into these and passes callbacks back out. All
// strings that depend on the clock or the locale (time labels, "Yesterday",
// durations) arrive already formatted, so no component formats dates or does
// work in `build`.

/// Value equality by [props], so a list item can be skipped when the app
/// rebuilds with an equal model.
@immutable
abstract class HelixValue {
  const HelixValue();

  /// The fields that define equality. Spread list fields (`...items`) so
  /// their elements, not their identity, are compared.
  List<Object?> get props;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HelixValue &&
          other.runtimeType == runtimeType &&
          listEquals(props, other.props));

  @override
  int get hashCode => Object.hash(runtimeType, Object.hashAll(props));
}

/// Delivery state of one outgoing message.
enum HelixDeliveryStatus {
  /// Queued on this device, not accepted by the server yet.
  pending,

  /// Accepted by the server.
  sent,

  /// On the recipient's device.
  delivered,

  /// Seen by the recipient.
  read,

  /// Gave up; the sender can retry.
  failed,
}

/// What a message is, in a chat-list preview line.
enum HelixPreviewKind {
  text,
  image,
  video,
  gif,
  voiceNote,
  document,
  sticker,
  location,
  contact,
  poll,
  call,
  deleted,
  undecryptable,
  unsupported,
}

/// Where a media transfer is.
enum HelixTransferState {
  /// Fully available on this device.
  done,

  /// On the server only; tap to download.
  notDownloaded,
  downloading,
  uploading,
  failed,
}

/// A half-open character range into a string (for mentions and search hits).
class HelixTextRange extends HelixValue {
  const HelixTextRange(this.start, this.length);
  final int start;
  final int length;
  int get end => start + length;
  @override
  List<Object?> get props => [start, length];
}

/// Text plus the ranges to emphasise (a search result snippet).
class HelixHighlightedText extends HelixValue {
  const HelixHighlightedText(this.text, [this.ranges = const []]);
  final String text;
  final List<HelixTextRange> ranges;
  @override
  List<Object?> get props => [text, ranges.length, ...ranges];
}

// ---------------------------------------------------------------- people

/// Who someone is, for an avatar.
class HelixAvatarModel extends HelixValue {
  const HelixAvatarModel({
    required this.name,
    this.image,
    this.colorIndex = 0,
    this.isGroup = false,
  });

  /// The display name; initials are taken from it.
  final String name;

  /// The picture, when there is one. Initials show until it loads.
  final ImageProvider? image;

  /// Index into [HelixColorTokens.avatarPalette] (wrapped). Use
  /// [colorIndexFor] so the same person keeps the same colour everywhere.
  final int colorIndex;

  /// Groups get a group glyph instead of initials when they have no picture.
  final bool isGroup;

  /// A stable palette index for [seed] (an account id or name).
  static int colorIndexFor(String seed) {
    var hash = 0x811C9DC5;
    for (final unit in seed.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7FFFFFFF;
    }
    return hash % HelixColorTokens.avatarPalette.length;
  }

  /// One or two letters: the first of the first and last words.
  String get initials => helixInitials(name);

  @override
  List<Object?> get props => [name, image, colorIndex, isGroup];
}

/// The first letters of the first and last word of [name], upper-cased.
/// A number or an empty name gives `#`.
String helixInitials(String name) {
  final words = name
      .replaceAll('~', '')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);
  if (words.isEmpty) return '#';
  String first(String word) => String.fromCharCode(word.runes.first);
  final a = first(words.first);
  // A number (or an emoji-only name) has no letters to show.
  if (!RegExp(r'\p{L}', unicode: true).hasMatch(a)) return '#';
  if (words.length == 1) return a.toUpperCase();
  return (a + first(words.last)).toUpperCase();
}

/// Everything known about how to name one person. The display name follows
/// the product rule: phone-book name, then nickname, then number, then
/// `~Helix name`.
class HelixPersonNames extends HelixValue {
  const HelixPersonNames({
    this.phoneBookName,
    this.nickname,
    this.number,
    this.helixName,
  });

  final String? phoneBookName;
  final String? nickname;
  final String? number;
  final String? helixName;

  static bool _has(String? value) => value != null && value.isNotEmpty;

  /// The name to show for this person (never empty).
  String get display {
    if (_has(phoneBookName)) return phoneBookName!;
    if (_has(nickname)) return nickname!;
    if (_has(number)) return number!;
    if (_has(helixName)) return '~$helixName';
    return 'Helix user';
  }

  /// Which rung of the naming order [display] came from.
  HelixNameSource get source {
    if (_has(phoneBookName)) return HelixNameSource.phoneBook;
    if (_has(nickname)) return HelixNameSource.nickname;
    if (_has(number)) return HelixNameSource.number;
    if (_has(helixName)) return HelixNameSource.helixName;
    return HelixNameSource.unknown;
  }

  /// The line under the name: the number when the name is not the number,
  /// otherwise the `~Helix name`. Null when there is nothing more to say.
  String? get secondary {
    switch (source) {
      case HelixNameSource.phoneBook:
      case HelixNameSource.nickname:
        if (_has(number)) return number;
        return _has(helixName) ? '~$helixName' : null;
      case HelixNameSource.number:
        return _has(helixName) ? '~$helixName' : null;
      case HelixNameSource.helixName:
      case HelixNameSource.unknown:
        return null;
    }
  }

  @override
  List<Object?> get props => [phoneBookName, nickname, number, helixName];
}

/// Which rung of the people-naming order produced a display name.
enum HelixNameSource { phoneBook, nickname, number, helixName, unknown }

/// A person in a people list or a people search result.
class HelixPersonItem extends HelixValue {
  const HelixPersonItem({
    required this.id,
    required this.names,
    this.image,
    this.about,
    this.online = false,
    this.blocked = false,
  });

  final String id;
  final HelixPersonNames names;
  final ImageProvider? image;
  final String? about;
  final bool online;
  final bool blocked;

  HelixAvatarModel get avatar => HelixAvatarModel(
    name: names.display,
    image: image,
    colorIndex: HelixAvatarModel.colorIndexFor(id),
  );

  @override
  List<Object?> get props => [id, names, image, about, online, blocked];
}

// ------------------------------------------------------------ chat list

/// The last-message line of a chat-list row.
class HelixChatPreview extends HelixValue {
  const HelixChatPreview({
    required this.text,
    this.kind = HelixPreviewKind.text,
    this.senderPrefix,
    this.status,
    this.isDraft = false,
  });

  /// The text (or a caption / file name); a media kind with an empty text
  /// shows its own label ("Photo", "Voice message", ...).
  final String text;
  final HelixPreviewKind kind;

  /// "You" or a first name, shown before the text in groups and for your own
  /// messages.
  final String? senderPrefix;

  /// The tick shown before an outgoing message's preview; null for incoming.
  final HelixDeliveryStatus? status;

  /// An unsent draft: shown as "Draft: ..." in an accent colour.
  final bool isDraft;

  @override
  List<Object?> get props => [text, kind, senderPrefix, status, isDraft];
}

/// One row of the chat list.
class HelixChatListItem extends HelixValue {
  const HelixChatListItem({
    required this.id,
    required this.title,
    required this.avatar,
    this.preview,
    this.timeLabel = '',
    this.unreadCount = 0,
    this.hasMention = false,
    this.markedUnread = false,
    this.pinned = false,
    this.muted = false,
    this.archived = false,
    this.typingLabel,
    this.online = false,
    this.verified = false,
  });

  final String id;
  final String title;
  final HelixAvatarModel avatar;
  final HelixChatPreview? preview;

  /// "14:05", "Yesterday", "Mon", "12/09/26" - already formatted.
  final String timeLabel;
  final int unreadCount;

  /// Someone @-mentioned you in the unread messages.
  final bool hasMention;

  /// Manually marked unread (a dot, no count).
  final bool markedUnread;
  final bool pinned;
  final bool muted;
  final bool archived;

  /// "typing..." or "Sam is typing..."; replaces the preview while set.
  final String? typingLabel;
  final bool online;

  /// The safety number was verified.
  final bool verified;

  bool get hasUnread => unreadCount > 0 || markedUnread;

  @override
  List<Object?> get props => [
    id,
    title,
    avatar,
    preview,
    timeLabel,
    unreadCount,
    hasMention,
    markedUnread,
    pinned,
    muted,
    archived,
    typingLabel,
    online,
    verified,
  ];
}

// --------------------------------------------------------- conversation

/// Where a message sits in a run of messages from one sender.
enum HelixRunPosition { single, first, middle, last }

/// The quoted message shown at the top of a reply.
class HelixReplyQuote extends HelixValue {
  const HelixReplyQuote({
    required this.authorName,
    this.text = '',
    this.kind = HelixPreviewKind.text,
    this.thumbnail,
    this.authorColorIndex = 0,
    this.missing = false,
  });

  final String authorName;
  final String text;
  final HelixPreviewKind kind;
  final ImageProvider? thumbnail;
  final int authorColorIndex;

  /// The original is not on this device (deleted, or not synced yet).
  final bool missing;

  @override
  List<Object?> get props => [
    authorName,
    text,
    kind,
    thumbnail,
    authorColorIndex,
    missing,
  ];
}

/// One emoji on a message and how many people used it.
class HelixReaction extends HelixValue {
  const HelixReaction({
    required this.emoji,
    required this.count,
    this.mine = false,
  });
  final String emoji;
  final int count;

  /// You reacted with it (tap again to take it back).
  final bool mine;
  @override
  List<Object?> get props => [emoji, count, mine];
}

/// A link preview card under a text message.
class HelixLinkPreview extends HelixValue {
  const HelixLinkPreview({
    required this.url,
    this.title,
    this.description,
    this.image,
  });
  final String url;
  final String? title;
  final String? description;
  final ImageProvider? image;
  @override
  List<Object?> get props => [url, title, description, image];
}

/// What a bubble contains.
sealed class HelixMessageContent extends HelixValue {
  const HelixMessageContent();
}

/// Text, with optional mention ranges (shown bold) and a link preview.
class HelixTextContent extends HelixMessageContent {
  const HelixTextContent(
    this.text, {
    this.mentions = const [],
    this.linkPreview,
  });
  final String text;
  final List<HelixTextRange> mentions;
  final HelixLinkPreview? linkPreview;
  @override
  List<Object?> get props => [text, mentions.length, ...mentions, linkPreview];
}

/// One image, video or GIF inside a media bubble.
class HelixMediaItem extends HelixValue {
  const HelixMediaItem({
    this.thumbnail,
    this.width = 4,
    this.height = 3,
    this.isVideo = false,
    this.isGif = false,
    this.durationLabel,
    this.transfer = HelixTransferState.done,
    this.progress,
    this.semanticLabel,
  });

  /// A small decoded preview; the placeholder shows while it is null.
  final ImageProvider? thumbnail;

  /// Only the ratio matters (sizes from the content message).
  final int width;
  final int height;
  final bool isVideo;
  final bool isGif;

  /// "0:12"; shown on videos.
  final String? durationLabel;
  final HelixTransferState transfer;

  /// 0..1 while [transfer] is downloading/uploading; null if unknown.
  final double? progress;
  final String? semanticLabel;

  double get aspectRatio => height <= 0 ? 1 : width / height;

  @override
  List<Object?> get props => [
    thumbnail,
    width,
    height,
    isVideo,
    isGif,
    durationLabel,
    transfer,
    progress,
    semanticLabel,
  ];
}

/// Images and videos (an album is several items) and an optional caption.
class HelixMediaContent extends HelixMessageContent {
  const HelixMediaContent(this.items, {this.caption = ''});
  final List<HelixMediaItem> items;
  final String caption;
  @override
  List<Object?> get props => [caption, items.length, ...items];
}

/// A voice note or an audio file.
class HelixAudioContent extends HelixMessageContent {
  const HelixAudioContent({
    required this.durationLabel,
    this.waveform,
    this.progress = 0,
    this.positionLabel,
    this.playing = false,
    this.speed = 1,
    this.played = false,
    this.isVoiceNote = true,
    this.transfer = HelixTransferState.done,
    this.transferProgress,
    this.title,
  });

  /// Total length, "0:23".
  final String durationLabel;

  /// Samples 0..255, any length; resampled when drawn. Null draws a flat
  /// placeholder.
  final Uint8List? waveform;

  /// Playback position 0..1.
  final double progress;

  /// Current position while playing, "0:07"; the duration is shown when null.
  final String? positionLabel;
  final bool playing;

  /// 1, 1.5 or 2.
  final double speed;

  /// The recipient has listened (blue dot for incoming).
  final bool played;
  final bool isVoiceNote;
  final HelixTransferState transfer;
  final double? transferProgress;

  /// File name for audio files that are not voice notes.
  final String? title;

  @override
  List<Object?> get props => [
    durationLabel,
    waveform,
    progress,
    positionLabel,
    playing,
    speed,
    played,
    isVoiceNote,
    transfer,
    transferProgress,
    title,
  ];
}

/// A file.
class HelixDocumentContent extends HelixMessageContent {
  const HelixDocumentContent({
    required this.name,
    this.sizeLabel = '',
    this.typeLabel = '',
    this.transfer = HelixTransferState.done,
    this.progress,
    this.caption = '',
  });
  final String name;

  /// "482 KB".
  final String sizeLabel;

  /// "PDF" - the extension or kind, upper-cased.
  final String typeLabel;
  final HelixTransferState transfer;
  final double? progress;
  final String caption;
  @override
  List<Object?> get props => [
    name,
    sizeLabel,
    typeLabel,
    transfer,
    progress,
    caption,
  ];
}

/// A static location (placeholder map tile; the app supplies no map).
class HelixLocationContent extends HelixMessageContent {
  const HelixLocationContent({this.label = '', this.address = ''});
  final String label;
  final String address;
  @override
  List<Object?> get props => [label, address];
}

/// A shared contact card.
class HelixContactContent extends HelixMessageContent {
  const HelixContactContent({
    required this.name,
    this.detail = '',
    this.onHelix = false,
  });
  final String name;

  /// First number, or "3 numbers".
  final String detail;

  /// The contact has a Helix account (shows "Message").
  final bool onHelix;
  @override
  List<Object?> get props => [name, detail, onHelix];
}

/// Why a bubble shows a notice instead of content.
enum HelixPlaceholderKind {
  /// Deleted for everyone.
  deleted,

  /// The message could not be decrypted (a ratchet or key problem).
  undecryptable,

  /// A content type or version this client does not know.
  unsupported,

  /// A disappearing message whose time is up but which is still on screen.
  expired,
}

/// A bubble with no content: deleted, undecryptable, unsupported.
class HelixPlaceholderContent extends HelixMessageContent {
  const HelixPlaceholderContent(this.kind);
  final HelixPlaceholderKind kind;
  @override
  List<Object?> get props => [kind];
}

/// View-once media, before or after it was opened.
class HelixViewOnceContent extends HelixMessageContent {
  const HelixViewOnceContent({this.isVideo = false, this.opened = false});
  final bool isVideo;

  /// Already opened (incoming) or already viewed by the recipient (outgoing).
  final bool opened;
  @override
  List<Object?> get props => [isVideo, opened];
}

/// One message bubble.
class HelixMessage extends HelixValue {
  const HelixMessage({
    required this.id,
    required this.outgoing,
    required this.content,
    required this.timeLabel,
    this.authorId,
    this.authorName,
    this.authorColorIndex = 0,
    this.sentAtMs = 0,
    this.status = HelixDeliveryStatus.sent,
    this.reply,
    this.forwarded = false,
    this.edited = false,
    this.reactions = const [],
    this.expiresLabel,
    this.starred = false,
    this.highlighted = false,
  });

  final String id;
  final bool outgoing;
  final HelixMessageContent content;

  /// "14:05".
  final String timeLabel;

  /// Used to group runs; null groups nothing.
  final String? authorId;

  /// Shown above the first incoming bubble of a run in a group chat; leave
  /// null in a direct chat.
  final String? authorName;
  final int authorColorIndex;

  /// Sender time (epoch ms), used only to split runs.
  final int sentAtMs;

  /// Only meaningful for outgoing messages.
  final HelixDeliveryStatus status;
  final HelixReplyQuote? reply;
  final bool forwarded;
  final bool edited;
  final List<HelixReaction> reactions;

  /// The disappearing timer marker, "1d" / "1h"; null when off.
  final String? expiresLabel;
  final bool starred;

  /// Briefly highlighted after jumping to it from a quote or search.
  final bool highlighted;

  @override
  List<Object?> get props => [
    id,
    outgoing,
    content,
    timeLabel,
    authorId,
    authorName,
    authorColorIndex,
    sentAtMs,
    status,
    reply,
    forwarded,
    edited,
    reactions.length,
    ...reactions,
    expiresLabel,
    starred,
    highlighted,
  ];
}

/// Splits [messages] (oldest first) into runs of one sender within
/// [HelixChatMetrics.runGapMs]. Call it when the list changes, not in `build`.
List<HelixRunPosition> helixRunPositions(
  List<HelixMessage> messages, {
  int maxGapMs = HelixChatMetrics.runGapMs,
}) {
  bool sameRun(HelixMessage a, HelixMessage b) =>
      a.outgoing == b.outgoing &&
      a.authorId == b.authorId &&
      (b.sentAtMs - a.sentAtMs).abs() <= maxGapMs;
  final out = List<HelixRunPosition>.filled(
    messages.length,
    HelixRunPosition.single,
  );
  for (var i = 0; i < messages.length; i++) {
    final joinsPrev = i > 0 && sameRun(messages[i - 1], messages[i]);
    final joinsNext =
        i + 1 < messages.length && sameRun(messages[i], messages[i + 1]);
    out[i] = switch ((joinsPrev, joinsNext)) {
      (false, false) => HelixRunPosition.single,
      (false, true) => HelixRunPosition.first,
      (true, true) => HelixRunPosition.middle,
      (true, false) => HelixRunPosition.last,
    };
  }
  return out;
}

/// One row of a conversation, in display order.
sealed class HelixTimelineItem extends HelixValue {
  const HelixTimelineItem();

  /// Stable across rebuilds; use for `ValueKey` and `findChildIndexCallback`.
  String get id;
}

/// A message bubble row.
class HelixMessageItem extends HelixTimelineItem {
  const HelixMessageItem(
    this.message, {
    this.position = HelixRunPosition.single,
    this.selected = false,
  });

  final HelixMessage message;
  final HelixRunPosition position;
  final bool selected;

  @override
  String get id => message.id;

  @override
  List<Object?> get props => [message, position, selected];
}

/// "Today", "Yesterday", "12 September 2026".
class HelixDateSeparatorItem extends HelixTimelineItem {
  const HelixDateSeparatorItem(this.label);
  final String label;
  @override
  String get id => 'date:$label';
  @override
  List<Object?> get props => [label];
}

/// "3 unread messages".
class HelixUnreadDividerItem extends HelixTimelineItem {
  const HelixUnreadDividerItem(this.count);
  final int count;
  @override
  String get id => 'unread';
  @override
  List<Object?> get props => [count];
}

/// A centred notice: group changes, timer changes, call log entries,
/// "Messages are end-to-end encrypted".
class HelixSystemNoticeItem extends HelixTimelineItem {
  const HelixSystemNoticeItem(this.noticeId, this.text, {this.icon});
  final String noticeId;
  final String text;
  final IconData? icon;
  @override
  String get id => 'notice:$noticeId';
  @override
  List<Object?> get props => [noticeId, text, icon];
}

// -------------------------------------------------------------- composer

/// What the composer banner is about.
enum HelixComposerBannerKind { reply, edit }

/// The reply/edit banner above the text field.
class HelixComposerBannerModel extends HelixValue {
  const HelixComposerBannerModel({
    required this.kind,
    required this.title,
    this.text = '',
    this.previewKind = HelixPreviewKind.text,
    this.thumbnail,
  });
  final HelixComposerBannerKind kind;

  /// "Replying to Sam" / "Edit message".
  final String title;
  final String text;
  final HelixPreviewKind previewKind;
  final ImageProvider? thumbnail;
  @override
  List<Object?> get props => [kind, title, text, previewKind, thumbnail];
}

/// A person offered while typing `@`.
class HelixMentionCandidate extends HelixValue {
  const HelixMentionCandidate({
    required this.id,
    required this.name,
    this.detail,
    this.image,
  });
  final String id;
  final String name;
  final String? detail;
  final ImageProvider? image;

  HelixAvatarModel get avatar => HelixAvatarModel(
    name: name,
    image: image,
    colorIndex: HelixAvatarModel.colorIndexFor(id),
  );

  @override
  List<Object?> get props => [id, name, detail, image];
}

/// What the voice-record overlay shows. The gesture that produces it is in
/// [HelixMicButton].
class HelixVoiceRecordState extends HelixValue {
  const HelixVoiceRecordState({
    required this.elapsedLabel,
    this.cancelProgress = 0,
    this.lockProgress = 0,
    this.locked = false,
  });

  /// "0:07".
  final String elapsedLabel;

  /// 0..1 how far the finger slid towards cancel.
  final double cancelProgress;

  /// 0..1 how far the finger slid up towards lock.
  final double lockProgress;

  /// Recording continues without holding.
  final bool locked;

  @override
  List<Object?> get props => [
    elapsedLabel,
    cancelProgress,
    lockProgress,
    locked,
  ];
}

// -------------------------------------------------------------- general

/// A message hit in a search.
class HelixMessageSearchResult extends HelixValue {
  const HelixMessageSearchResult({
    required this.id,
    required this.chatTitle,
    required this.avatar,
    required this.snippet,
    this.timeLabel = '',
    this.senderLabel,
  });
  final String id;
  final String chatTitle;
  final HelixAvatarModel avatar;
  final HelixHighlightedText snippet;
  final String timeLabel;

  /// "You" or a first name.
  final String? senderLabel;
  @override
  List<Object?> get props => [
    id,
    chatTitle,
    avatar,
    snippet,
    timeLabel,
    senderLabel,
  ];
}

/// How a call went, from this device's point of view.
enum HelixCallDirection { incoming, outgoing, missed, declined, failed }

/// One row of the call log.
class HelixCallLogItem extends HelixValue {
  const HelixCallLogItem({
    required this.id,
    required this.title,
    required this.avatar,
    required this.direction,
    required this.timeLabel,
    this.video = false,
    this.count = 1,
    this.isGroup = false,
    this.durationLabel,
  });
  final String id;
  final String title;
  final HelixAvatarModel avatar;
  final HelixCallDirection direction;

  /// "Today, 14:05".
  final String timeLabel;
  final bool video;

  /// Consecutive calls with the same person are folded into one row.
  final int count;
  final bool isGroup;
  final String? durationLabel;

  @override
  List<Object?> get props => [
    id,
    title,
    avatar,
    direction,
    timeLabel,
    video,
    count,
    isGroup,
    durationLabel,
  ];
}

/// Connectivity and update banners.
enum HelixBannerKind { offline, connecting, updateAvailable, info }

/// A square QR module matrix to display (the app encodes the payload; the UI
/// package never does). `modules` is row-major, true = dark.
class HelixQrMatrix extends HelixValue {
  // ignore: prefer_const_constructors_in_immutables
  HelixQrMatrix(this.size, this.modules)
    : assert(modules.length == size * size, 'modules must be size x size');
  final int size;
  final List<bool> modules;
  bool at(int x, int y) => modules[y * size + x];
  @override
  List<Object?> get props => [size, ...modules];
}
