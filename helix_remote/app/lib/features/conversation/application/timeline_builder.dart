import 'package:flutter/foundation.dart';
import 'package:helix_remote/core/chat/message_semantics.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote/features/conversation/application/message_mapper.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// What was true when the conversation was opened: how many messages were
/// unread and where reading had got to. The unread divider is drawn from this
/// and stays put while the person reads past it.
@immutable
class OpenInfo {
  const OpenInfo({this.unreadAtOpen = 0, this.lastReadSortKey});

  final int unreadAtOpen;
  final String? lastReadSortKey;
}

/// One row of the timeline: what to draw, and which message it is.
@immutable
class TimelineEntry {
  const TimelineEntry(
    this.item, {
    this.messageRowid,
    this.messageId,
    this.hasMedia = false,
    this.replyToId,
  });

  final HelixTimelineItem item;

  /// The database id of a message row; null for separators and notices.
  final int? messageRowid;

  /// The message's content id (what a quote or a search hit names).
  final String? messageId;

  /// The bubble's content comes from its attachments (a media message that is
  /// not view-once), so the row watches them.
  final bool hasMedia;

  /// The content id of the message this one quotes, so a tap on the quote can
  /// jump to it.
  final String? replyToId;

  @override
  bool operator ==(Object other) =>
      other is TimelineEntry &&
      other.item == item &&
      other.messageRowid == messageRowid &&
      other.hasMedia == hasMedia &&
      other.replyToId == replyToId;

  @override
  int get hashCode => Object.hash(item, messageRowid, hasMedia, replyToId);
}

/// The window the screen draws, newest first (the list is built `reverse`).
@immutable
class TimelineSnapshot {
  const TimelineSnapshot({
    required this.newestFirst,
    required this.indexOfId,
    required this.hasOlder,
    required this.hasNewer,
    this.oldestSortKey,
  });

  static const empty = TimelineSnapshot(
    newestFirst: [],
    indexOfId: {},
    hasOlder: false,
    hasNewer: false,
  );

  final List<TimelineEntry> newestFirst;

  /// Item id to index, for `findChildIndexCallback` and for jumps.
  final Map<String, int> indexOfId;

  /// There are messages older than the window.
  final bool hasOlder;

  /// The window stops before the newest message (the person jumped back in
  /// time).
  final bool hasNewer;

  /// The sort key of the oldest row in the window.
  final String? oldestSortKey;

  /// The index of the message with content id [messageId], or null.
  int? indexOfMessage(String messageId) {
    for (var i = 0; i < newestFirst.length; i++) {
      if (newestFirst[i].messageId == messageId) return i;
    }
    return null;
  }

  int? get unreadDividerIndex => indexOfId['unread'];
}

/// Rows (oldest first) into timeline entries: date separators, the unread
/// divider, notices and grouped bubbles, newest first.
///
/// Pure and cheap (linear in the window): it runs on every change to the
/// window and nothing here touches the database or the clock - [ctx] carries
/// the injected "now".
TimelineSnapshot buildTimeline({
  required List<MessageRow> rows,
  required MapperContext ctx,
  required Map<int, List<ReactionRow>> reactions,
  required Map<String, HelixReplyQuote> quotes,
  required OpenInfo open,
  required bool hasOlder,
  required bool hasNewer,
  String? highlightMessageId,
}) {
  final entries = <TimelineEntry>[];
  // Message entries of the run being built, to give them their positions.
  var segment = <int>[];

  void closeSegment() {
    if (segment.isEmpty) return;
    final messages = [
      for (final i in segment) (entries[i].item as HelixMessageItem).message,
    ];
    final positions = helixRunPositions(messages);
    for (var k = 0; k < segment.length; k++) {
      final old = entries[segment[k]];
      entries[segment[k]] = TimelineEntry(
        HelixMessageItem(messages[k], position: positions[k]),
        messageRowid: old.messageRowid,
        messageId: old.messageId,
        hasMedia: old.hasMedia,
        replyToId: old.replyToId,
      );
    }
    segment = [];
  }

  DateTime? lastDay;
  var dividerPlaced = false;
  final lastRead = open.lastReadSortKey;
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final local = row.sentAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    if (lastDay != day) {
      closeSegment();
      entries.add(
        TimelineEntry(
          HelixDateSeparatorItem(formatDateSeparator(row.sentAt, ctx.now)),
        ),
      );
      lastDay = day;
    }
    if (!dividerPlaced &&
        open.unreadAtOpen > 0 &&
        !row.outgoing &&
        !isNoticeKind(row.kind) &&
        (lastRead == null || row.sortKey.compareTo(lastRead) > 0) &&
        // The boundary is further back than the window when the very first
        // row is already past it and older rows exist.
        !(i == 0 && hasOlder && lastRead != null)) {
      closeSegment();
      entries.add(TimelineEntry(HelixUnreadDividerItem(open.unreadAtOpen)));
      dividerPlaced = true;
    }
    if (isNoticeKind(row.kind)) {
      closeSegment();
      final text = systemNoticeText(
        row,
        selfId: ctx.selfId,
        people: ctx.people,
      );
      if (text != null) {
        entries.add(
          TimelineEntry(
            HelixSystemNoticeItem(
              row.localRowid.toString(),
              text,
              icon: row.kind == 'call_log' ? callLogIcon(row) : null,
            ),
            messageRowid: row.localRowid,
            messageId: row.messageId,
          ),
        );
      }
      continue;
    }
    final quote = row.replyToId == null
        ? null
        : quotes[row.replyToId] ?? quoteOf(row.replyToAuthor ?? '', null, ctx);
    final message = mapMessage(
      row,
      ctx,
      reply: quote,
      reactions: reactions[row.localRowid] ?? const [],
      highlighted: row.messageId == highlightMessageId,
    );
    segment.add(entries.length);
    entries.add(
      TimelineEntry(
        HelixMessageItem(message),
        messageRowid: row.localRowid,
        messageId: row.messageId,
        replyToId: row.replyToId,
        hasMedia:
            row.kind == 'media' &&
            row.viewOnceState == null &&
            row.deletedAt == null,
      ),
    );
  }
  closeSegment();

  final newestFirst = entries.reversed.toList(growable: false);
  return TimelineSnapshot(
    newestFirst: newestFirst,
    indexOfId: {
      for (var i = 0; i < newestFirst.length; i++) newestFirst[i].item.id: i,
    },
    hasOlder: hasOlder,
    hasNewer: hasNewer,
    oldestSortKey: rows.isEmpty ? null : rows.first.sortKey,
  );
}
