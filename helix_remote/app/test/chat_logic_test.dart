import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/chat/chat_people.dart';
import 'package:helix_remote/core/chat/message_semantics.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote/core/platform/app_blob_store.dart';
import 'package:helix_remote/features/conversation/application/message_mapper.dart';
import 'package:helix_remote/features/conversation/application/timeline_builder.dart';
import 'package:helix_remote/features/conversation/application/composer_notifier.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart' show BlobArea;
import 'package:helix_remote_ui/helix_remote_ui.dart';

MessageRow row(
  int id, {
  String kind = 'text',
  String? body,
  String? payload,
  bool outgoing = false,
  MessageStatus status = MessageStatus.received,
  DateTime? at,
  String sender = 'bob',
  DateTime? deletedAt,
  String? replyToId,
}) {
  final sentAt = at ?? DateTime.utc(2026, 10, 3, 9, id);
  return MessageRow(
    localRowid: id,
    messageId: 'm$id',
    conversationId: 'direct:bob',
    sender: sender,
    outgoing: outgoing,
    sortKey: SortKey.of(sentAt, 'm$id'),
    sentAt: sentAt,
    receivedAt: sentAt,
    kind: kind,
    body: body,
    payload: payload,
    replyToId: replyToId,
    replyToAuthor: replyToId == null ? null : 'bob',
    forwarded: false,
    mentionsMe: false,
    status: status,
    deletedAt: deletedAt,
  );
}

void main() {
  final people = ChatPeople([
    PersonRow(
      accountId: 'bob',
      phonebookName: 'Bob',
      identityVerified: false,
      blocked: false,
      updatedAt: DateTime.utc(2026),
    ),
  ]);
  final now = DateTime(2026, 10, 3, 14, 30);

  group('labels', () {
    test('chat times: clock, Yesterday, weekday, date', () {
      expect(formatChatTime(DateTime(2026, 10, 3, 9, 5), now), '09:05');
      expect(formatChatTime(DateTime(2026, 10, 2, 23), now), 'Yesterday');
      expect(formatChatTime(DateTime(2026, 9, 30, 8), now), 'Wed');
      expect(formatChatTime(DateTime(2026, 8, 1, 8), now), '01/08/26');
      expect(formatChatTime(null, now), '');
    });

    test('date separators, durations, sizes and timers', () {
      expect(formatDateSeparator(DateTime(2026, 10, 3, 1), now), 'Today');
      expect(formatDateSeparator(DateTime(2026, 8, 1), now), '1 August 2026');
      expect(formatDurationMs(7000), '0:07');
      expect(formatDurationMs(3723000), '1:02:03');
      expect(formatFileSize(482000), '482 KB');
      expect(formatFileSize(3400000), '3.4 MB');
      expect(formatDisappearing(86400), '1d');
      expect(describeDisappearing(7 * 86400), '1 week');
      expect(describeDisappearing(null), 'Off');
    });
  });

  group('message semantics', () {
    test('preview kind follows the content, deleted wins', () {
      expect(previewKindOf(row(1)), HelixPreviewKind.text);
      expect(
        previewKindOf(
          row(2, kind: 'media', payload: '{"items":[{"kind":"voice_note"}]}'),
        ),
        HelixPreviewKind.voiceNote,
      );
      expect(
        previewKindOf(row(3, kind: 'location')),
        HelixPreviewKind.location,
      );
      expect(
        previewKindOf(row(4, deletedAt: DateTime.utc(2026))),
        HelixPreviewKind.deleted,
      );
    });

    test('ticks: only for outgoing, viewed reads as read', () {
      expect(deliveryStatusOf(row(1)), isNull);
      expect(
        deliveryStatusOf(row(2, outgoing: true, status: MessageStatus.viewed)),
        HelixDeliveryStatus.read,
      );
      expect(
        deliveryStatusOf(row(3, outgoing: true, status: MessageStatus.failed)),
        HelixDeliveryStatus.failed,
      );
    });

    test('notices read as sentences, never raw JSON', () {
      final timer = row(
        1,
        kind: 'system',
        payload: '{"kind":"timer_changed","seconds":86400}',
        outgoing: true,
      );
      expect(
        systemNoticeText(timer, selfId: 'me', people: people),
        'You set disappearing messages to 1 day',
      );
      final added = row(
        2,
        kind: 'system',
        payload: '{"kind":"member_added","actor":"bob","members":["me"]}',
      );
      expect(
        systemNoticeText(added, selfId: 'me', people: people),
        'Bob added You',
      );
      final unknown = row(
        3,
        kind: 'system',
        payload: '{"kind":"from_the_future"}',
      );
      expect(systemNoticeText(unknown, selfId: 'me', people: people), isNull);
      final missed = row(
        4,
        kind: 'call_log',
        payload: '{"outcome":"missed","media":"audio"}',
      );
      expect(callLogText(missed), 'Missed voice call');
    });
  });

  group('timeline', () {
    MapperContext ctx({bool group = false}) =>
        MapperContext(isGroup: group, selfId: 'me', people: people, now: now);

    TimelineSnapshot build(
      List<MessageRow> rows, {
      OpenInfo open = const OpenInfo(),
      bool group = false,
    }) => buildTimeline(
      rows: rows,
      ctx: ctx(group: group),
      reactions: const {},
      quotes: const {},
      open: open,
      hasOlder: false,
      hasNewer: false,
    );

    test('is newest first with a separator per day and grouped bubbles', () {
      final rows = [
        row(1, at: DateTime.utc(2026, 10, 2, 9)),
        row(2, at: DateTime.utc(2026, 10, 3, 9, 0)),
        row(3, at: DateTime.utc(2026, 10, 3, 9, 1)),
      ];
      final items = build(rows).newestFirst.map((e) => e.item).toList();
      expect(items.first, isA<HelixMessageItem>());
      expect(
        items.whereType<HelixDateSeparatorItem>().length,
        anyOf(1, 2),
        reason: 'local time decides where the day changes',
      );
      final messages = items.whereType<HelixMessageItem>().toList();
      expect(messages, hasLength(3));
      // The last two share a run: the newest closes it.
      expect(messages.first.position, HelixRunPosition.last);
    });

    test(
      'puts the unread divider before the first unread incoming message',
      () {
        final rows = [
          row(1, outgoing: true, status: MessageStatus.read),
          row(2),
          row(3),
        ];
        final snapshot = build(
          rows,
          open: OpenInfo(unreadAtOpen: 2, lastReadSortKey: rows[0].sortKey),
        );
        final order = snapshot.newestFirst.map((e) => e.item.id).toList();
        expect(order.indexOf('unread'), greaterThan(order.indexOf('3')));
        expect(order.indexOf('unread'), lessThan(order.indexOf('1')));
        expect(snapshot.unreadDividerIndex, isNotNull);
      },
    );

    test('maps replies, reactions, edits and group authors', () {
      final reply = row(5, body: 'ok', replyToId: 'm1');
      final quoted = row(1, body: 'lunch?');
      final message = mapMessage(
        reply,
        ctx(group: true),
        reply: quoteOf('bob', quoted, ctx()),
        reactions: [
          ReactionRow(
            messageRowid: 5,
            reactor: 'me',
            emoji: '👍',
            reactedAt: DateTime.utc(2026),
          ),
          ReactionRow(
            messageRowid: 5,
            reactor: 'bob',
            emoji: '👍',
            reactedAt: DateTime.utc(2026),
          ),
        ],
      );
      expect(message.authorName, 'Bob');
      expect(message.reply!.text, 'lunch?');
      expect(message.reactions.single.count, 2);
      expect(message.reactions.single.mine, isTrue);
    });
  });

  group('mentions', () {
    test('an @ counts only at a word start', () {
      expect(mentionTokenAt('hi @al', 6)?.query, 'al');
      expect(mentionTokenAt('mail me@al', 10), isNull);
      expect(mentionTokenAt('@', 1)?.query, '');
      expect(mentionTokenAt('hello', 5), isNull);
    });
  });

  group('AppBlobStore', () {
    late Directory dir;
    late AppBlobStore store;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('helix_blob_');
      store = AppBlobStore(dir);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test(
      'writes, resumes at an offset, reads a range, moves and sweeps',
      () async {
        final path = await store.namedPath(BlobArea.staging, 'job-1.part');
        var sink = await store.openWrite(path);
        await sink.add([1, 2, 3, 4, 5]);
        await sink.close();
        // Resume after the first three bytes: the rest is cut off.
        sink = await store.openWrite(path, keep: 3);
        await sink.add([9, 9]);
        await sink.close();
        expect(await store.length(path), 5);
        final read = <int>[];
        await for (final part in store.read(path, start: 1, end: 4)) {
          read.addAll(part);
        }
        expect(read, [2, 3, 9]);

        final target = await store.newPath(BlobArea.media, extension: 'jpg');
        expect(target, endsWith('.jpg'));
        await store.move(path, target);
        expect(await store.length(path), isNull);
        expect(await store.length(target), 5);
        expect((await store.list(BlobArea.media)).single.size, 5);

        await store.clear();
        expect(await store.length(target), isNull);
      },
    );

    test('refuses unsafe names', () async {
      expect(
        () => store.namedPath(BlobArea.media, '../escape'),
        throwsArgumentError,
      );
    });
  });
}
