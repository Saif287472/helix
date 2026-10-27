import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/chat/message_semantics.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:orbit_ui/models.dart';

/// What the mapper needs to know about the conversation a row is in.
class MapperContext {
  const MapperContext({
    required this.isGroup,
    required this.selfId,
    required this.people,
    required this.now,
  });

  final bool isGroup;
  final String? selfId;
  final PeopleDirectory people;

  /// The injected clock: a label such as "Today" depends on it.
  final DateTime now;
}

/// The content shown for a media message until its attachments have loaded
/// (a blank tile, with the caption). The conversation then replaces it per
/// message, from the attachment rows and their transfer state (see
/// `media_content.dart`).
HelixMediaContent mediaPlaceholderContent([String caption = '']) =>
    HelixMediaContent(const [HelixMediaItem()], caption: caption);

/// One bubble from a database row.
///
/// [reply] is the quote (looked up by the caller, because the quoted message
/// may be outside the window being drawn); [reactions] are the row's
/// reactions; [failedAction] is the label of a failed action on the message
/// (AUD-12i-1).
HelixMessage mapMessage(
  MessageRow row,
  MapperContext ctx, {
  HelixReplyQuote? reply,
  List<ReactionRow> reactions = const [],
  bool highlighted = false,
  String? failedAction,
}) {
  final outgoing = row.outgoing;
  final showAuthor = ctx.isGroup && !outgoing;
  return HelixMessage(
    id: row.localRowid.toString(),
    outgoing: outgoing,
    content: contentOf(row, selfId: ctx.selfId, now: ctx.now),
    timeLabel: formatClock(row.sentAt),
    authorId: row.sender,
    authorName: showAuthor ? ctx.people.displayOf(row.sender) : null,
    authorColorIndex: ctx.people.colorIndexOf(row.sender),
    // The picture beside the last bubble of a run in a group.
    authorAvatar: showAuthor ? ctx.people.avatarOf(row.sender) : null,
    sentAtMs: row.sentAt.millisecondsSinceEpoch,
    status: deliveryStatusOf(row) ?? HelixDeliveryStatus.sent,
    reply: row.replyToId == null ? null : reply,
    forwarded: row.forwarded,
    edited: row.editedAt != null && row.deletedAt == null,
    starred: row.starredAt != null && row.deletedAt == null,
    pinned: row.pinnedAt != null && row.deletedAt == null,
    reactions: row.deletedAt == null
        ? aggregateReactions(reactions, ctx.selfId)
        : const [],
    expiresLabel: row.expireSeconds == null
        ? null
        : formatDisappearing(row.expireSeconds!),
    highlighted: highlighted,
    failedAction: failedAction,
  );
}

/// What goes in the bubble.
HelixMessageContent contentOf(MessageRow row, {String? selfId, DateTime? now}) {
  if (row.deletedAt != null) {
    return const HelixPlaceholderContent(HelixPlaceholderKind.deleted);
  }
  final payload = payloadOf(row);
  switch (row.kind) {
    case 'text':
      return HelixTextContent(
        row.body ?? '',
        mentions: _mentionRanges(payload['mentions'], row.body ?? ''),
        linkPreview: _linkPreview(payload['link_preview']),
      );
    case 'media':
      if (row.viewOnceState != null) {
        final outgoingSeen =
            row.outgoing &&
            (row.status == MessageStatus.viewed ||
                row.status == MessageStatus.read);
        return HelixViewOnceContent(
          isVideo: const {'video', 'video_note'}.contains(mediaKindOf(row)),
          opened: row.viewOnceState == ViewOnceState.opened || outgoingSeen,
        );
      }
      return mediaPlaceholderContent(row.body ?? '');
    case 'location':
      final label = (payload['label'] as String?)?.trim() ?? '';
      return HelixLocationContent(
        label: label.isEmpty ? 'Location' : label,
        address: (payload['address'] as String?) ?? '',
      );
    case 'live_location':
      return const HelixLocationContent(label: 'Live location');
    case 'contact':
      final numbers = [
        for (final n in (payload['numbers'] as List? ?? const []))
          if (n is String) n,
      ];
      return HelixContactContent(
        name: (payload['name'] as String?) ?? 'Contact',
        detail: numbers.isEmpty
            ? ''
            : numbers.length == 1
            ? numbers.first
            : '${numbers.length} numbers',
        onHelix: payload['account'] is String,
      );
    case 'poll':
      return _poll(payload, selfId, now);
    case 'event':
      return _event(payload, selfId, now);
    case 'undecryptable':
      return const HelixPlaceholderContent(HelixPlaceholderKind.undecryptable);
    default:
      // A sticker, or a type from a newer Helix: never raw JSON.
      return const HelixPlaceholderContent(HelixPlaceholderKind.unsupported);
  }
}

/// A poll with the votes the engine has recorded in its payload
/// (`votes`: account to the answers they chose).
HelixPollContent _poll(
  Map<String, Object?> payload,
  String? me,
  DateTime? now,
) {
  final rawVotes = payload['votes'];
  final rawOptions = payload['options'];
  final votes = <String, Set<String>>{
    for (final e in (rawVotes is Map ? rawVotes : const {}).entries)
      if (e.key is String && e.value is List)
        e.key as String: {
          for (final id in e.value as List)
            if (id is String) id,
        },
  };
  final options = [
    for (final o in (rawOptions is List ? rawOptions : const []))
      if (o is Map && o['id'] is String && o['text'] is String)
        HelixPollOption(
          id: o['id'] as String,
          text: o['text'] as String,
          votes: votes.values.where((v) => v.contains(o['id'])).length,
          mine: me != null && (votes[me]?.contains(o['id']) ?? false),
        ),
  ];
  final closes = _time(payload['closes_at']);
  return HelixPollContent(
    question: (payload['question'] as String?) ?? '',
    options: options,
    multiple: payload['multiple'] == true,
    voters: votes.values.where((v) => v.isNotEmpty).length,
    closed: closes != null && now != null && !closes.isAfter(now),
  );
}

/// An event with the answers recorded in its payload (`rsvps`: account to
/// `{state, plus_one}`).
HelixEventContent _event(
  Map<String, Object?> payload,
  String? me,
  DateTime? now,
) {
  final counts = {for (final s in HelixRsvp.values) s: 0};
  HelixRsvp? mine;
  final rawRsvps = payload['rsvps'];
  for (final e in (rawRsvps is Map ? rawRsvps : const {}).entries) {
    final answer = e.value is Map ? (e.value as Map)['state'] : null;
    final state = switch (answer) {
      'going' => HelixRsvp.going,
      'maybe' => HelixRsvp.maybe,
      'declined' => HelixRsvp.declined,
      _ => null,
    };
    if (state == null) continue;
    counts[state] = counts[state]! + 1;
    if (e.key == me) mine = state;
  }
  final starts = _time(payload['starts_at']);
  return HelixEventContent(
    title: (payload['title'] as String?) ?? '',
    whenLabel: starts == null ? '' : formatWhen(starts, now ?? starts),
    place: ((payload['location_text'] as String?) ?? '').trim(),
    going: counts[HelixRsvp.going]!,
    maybe: counts[HelixRsvp.maybe]!,
    declined: counts[HelixRsvp.declined]!,
    mine: mine,
  );
}

/// A wire time (epoch milliseconds) from a payload, or null.
DateTime? _time(Object? raw) =>
    raw is num ? DateTime.fromMillisecondsSinceEpoch(raw.toInt()) : null;

List<HelixTextRange> _mentionRanges(Object? raw, String text) {
  if (raw is! List) return const [];
  final out = <HelixTextRange>[];
  for (final m in raw) {
    if (m is! Map) continue;
    final start = (m['start'] as num?)?.toInt();
    final length = (m['length'] as num?)?.toInt();
    if (start == null || length == null || start < 0 || length <= 0) continue;
    if (start + length > text.length) continue;
    out.add(HelixTextRange(start, length));
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

HelixLinkPreview? _linkPreview(Object? raw) {
  if (raw is! Map) return null;
  final url = raw['url'];
  if (url is! String || url.isEmpty) return null;
  return HelixLinkPreview(
    url: url,
    title: raw['title'] as String?,
    description: raw['description'] as String?,
  );
}

/// One chip per emoji, most used first (earliest first among equals); yours
/// is marked.
List<HelixReaction> aggregateReactions(List<ReactionRow> rows, String? selfId) {
  if (rows.isEmpty) return const [];
  final counts = <String, int>{};
  final mine = <String>{};
  for (final row in rows) {
    counts.update(row.emoji, (n) => n + 1, ifAbsent: () => 1);
    if (row.reactor == selfId) mine.add(row.emoji);
  }
  final order = counts.keys.toList();
  order.sort((a, b) {
    final byCount = counts[b]!.compareTo(counts[a]!);
    return byCount != 0
        ? byCount
        : order.indexOf(a).compareTo(order.indexOf(b));
  });
  return [
    for (final emoji in order)
      HelixReaction(
        emoji: emoji,
        count: counts[emoji]!,
        mine: mine.contains(emoji),
      ),
  ];
}

/// The quote shown above a reply: who said it and what, from the quoted row
/// (null when that message is not on this device any more).
HelixReplyQuote quoteOf(
  String authorAccount,
  MessageRow? quoted,
  MapperContext ctx,
) {
  final author = authorAccount == ctx.selfId
      ? 'You'
      : ctx.people.displayOf(authorAccount);
  final color = ctx.people.colorIndexOf(authorAccount);
  if (quoted == null || quoted.deletedAt != null) {
    return HelixReplyQuote(
      authorName: author,
      authorColorIndex: color,
      missing: true,
    );
  }
  return HelixReplyQuote(
    authorName: author,
    authorColorIndex: color,
    text: previewTextOf(quoted),
    kind: previewKindOf(quoted),
  );
}
