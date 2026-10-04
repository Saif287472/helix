import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/chat/chat_naming.dart';
import 'package:helix_remote/core/chat/chat_people.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/features/conversation/application/message_mapper.dart';
import 'package:helix_remote/features/conversation/application/timeline_builder.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// What opens a conversation: which one, how many messages to start with
/// (enough to cover the unread ones), and optionally a message to open at.
@immutable
class TimelineArgs {
  const TimelineArgs(
    this.conversationId, {
    this.initialLimit = TimelineWindow.pageSize,
    this.anchorMessageId,
  });

  final String conversationId;
  final int initialLimit;
  final String? anchorMessageId;

  @override
  bool operator ==(Object other) =>
      other is TimelineArgs &&
      other.conversationId == conversationId &&
      other.initialLimit == initialLimit &&
      other.anchorMessageId == anchorMessageId;

  @override
  int get hashCode =>
      Object.hash(conversationId, initialLimit, anchorMessageId);
}

/// The slice of the conversation being drawn.
///
/// Normally the newest [limit] messages (the live end). After a jump into the
/// past it is [limit] messages from [anchorKey] onwards. Either way the window
/// grows by paging, and the database query behind it is a keyset query on
/// `(conversation_id, sort_key)`: its cost depends on the window, never on how
/// long the conversation is.
@immutable
class TimelineWindow {
  const TimelineWindow({this.anchorKey, this.limit = pageSize});

  static const pageSize = 50;

  /// Null: the newest messages. Otherwise the sort key the window starts at.
  final String? anchorKey;
  final int limit;

  bool get isLatest => anchorKey == null;

  @override
  bool operator ==(Object other) =>
      other is TimelineWindow &&
      other.anchorKey == anchorKey &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(anchorKey, limit);
}

/// Paging, jumping and returning to the live end.
final class TimelineWindowNotifier extends Notifier<TimelineWindow> {
  TimelineWindowNotifier(this.args);

  final TimelineArgs args;

  @override
  TimelineWindow build() {
    final anchor = args.anchorMessageId;
    if (anchor != null) {
      // Resolve the anchor after the first build, then replace the window.
      Future.microtask(() => jumpTo(anchor));
    }
    return TimelineWindow(limit: args.initialLimit);
  }

  Future<ChatGateway> get _gateway => ref.read(chatGatewayProvider.future);

  /// Loads the page before the window.
  Future<void> loadOlder() async {
    final window = state;
    if (window.isLatest) {
      state = TimelineWindow(limit: window.limit + TimelineWindow.pageSize);
      return;
    }
    final gateway = await _gateway;
    final page = await gateway.pageOlder(
      args.conversationId,
      before: window.anchorKey,
      limit: TimelineWindow.pageSize,
    );
    if (page.messages.isEmpty) return;
    state = TimelineWindow(
      anchorKey: page.messages.first.sortKey,
      limit: window.limit + page.messages.length,
    );
  }

  /// Loads more after the window (only when it is not at the live end).
  void loadNewer() {
    final window = state;
    if (window.isLatest) return;
    state = TimelineWindow(
      anchorKey: window.anchorKey,
      limit: window.limit + TimelineWindow.pageSize,
    );
  }

  /// Opens the window at the message with content id [messageId], with a few
  /// messages of context before it. False when it is not on this device.
  Future<bool> jumpTo(String messageId) async {
    final gateway = await _gateway;
    final row = await gateway.findMessage(args.conversationId, messageId);
    if (row == null) return false;
    // A message inside the live window needs no new window.
    final window = state;
    if (window.isLatest) {
      final newest = await gateway.pageOlder(
        args.conversationId,
        limit: window.limit,
      );
      final first = newest.messages.isEmpty
          ? null
          : newest.messages.first.sortKey;
      if (first != null && row.sortKey.compareTo(first) >= 0) return true;
    }
    final context = await gateway.pageOlder(
      args.conversationId,
      before: row.sortKey,
      limit: 8,
    );
    state = TimelineWindow(
      anchorKey: context.messages.isEmpty
          ? row.sortKey
          : context.messages.first.sortKey,
      limit: 120,
    );
    return true;
  }

  /// Back to the newest messages.
  void jumpToLatest() => state = const TimelineWindow();
}

final timelineWindowProvider = NotifierProvider.autoDispose
    .family<TimelineWindowNotifier, TimelineWindow, TimelineArgs>(
      TimelineWindowNotifier.new,
    );

/// A request to bring one message into view, and to flash it.
@immutable
class TimelineJump {
  const TimelineJump(this.messageId, this.serial);

  final String messageId;

  /// Distinguishes two jumps to the same message.
  final int serial;
}

final class TimelineJumpNotifier extends Notifier<TimelineJump?> {
  TimelineJumpNotifier(this.conversationId);

  final String conversationId;
  int _serial = 0;
  Timer? _clear;

  @override
  TimelineJump? build() {
    ref.onDispose(() => _clear?.cancel());
    return null;
  }

  /// Highlights [messageId] for a moment; the screen scrolls to it.
  void to(String messageId) {
    _clear?.cancel();
    state = TimelineJump(messageId, ++_serial);
    _clear = Timer(const Duration(milliseconds: 2200), () => state = null);
  }
}

final timelineJumpProvider = NotifierProvider.autoDispose
    .family<TimelineJumpNotifier, TimelineJump?, String>(
      TimelineJumpNotifier.new,
    );

/// The conversation as it was when it was opened (unread count, read
/// position). Read once: the unread divider must not move as messages are
/// read.
final conversationOpenProvider = FutureProvider.autoDispose
    .family<OpenInfo, String>((ref, conversationId) async {
      final gateway = await ref.watch(chatGatewayProvider.future);
      final chat = await gateway.chat(conversationId);
      return OpenInfo(
        unreadAtOpen: chat?.unreadCount ?? 0,
        lastReadSortKey: chat?.lastReadSortKey,
      );
    });

/// How many messages a conversation starts with: enough to show the unread
/// ones and a little before them.
int initialLimitFor(OpenInfo open) =>
    (open.unreadAtOpen + 20).clamp(TimelineWindow.pageSize, 500);

/// The conversation's rows as the timeline wants them, live.
///
/// A [StreamProvider] over the engine's windowed watch queries (messages and
/// the reactions of that window), mapped to `helix_remote_ui` view models. A
/// burst of writes is coalesced to one snapshot per short interval, so a
/// thousand messages arriving at once is a few dozen rebuilds, not a thousand.
final timelineProvider = StreamProvider.autoDispose
    .family<TimelineSnapshot, TimelineArgs>((ref, args) async* {
      final gateway = await ref.watch(chatGatewayProvider.future);
      final people = await ref.watch(chatPeopleProvider.future);
      final open = await ref.watch(
        conversationOpenProvider(args.conversationId).future,
      );
      final window = ref.watch(timelineWindowProvider(args));
      final now = ref.watch(clockProvider);
      yield* _snapshots(
        gateway: gateway,
        people: people,
        open: open,
        window: window,
        conversationId: args.conversationId,
        now: now,
      );
    });

/// How long writes are gathered before the screen is told. Short enough to
/// feel live, long enough that a burst becomes a handful of frames.
const _coalesce = Duration(milliseconds: 16);

Stream<TimelineSnapshot> _snapshots({
  required ChatGateway gateway,
  required ChatPeople people,
  required OpenInfo open,
  required TimelineWindow window,
  required String conversationId,
  required DateTime Function() now,
}) {
  final isGroup = peerOfConversation(conversationId) == null;
  final source = window.isLatest
      ? gateway.watchLatest(conversationId, window.limit)
      : gateway.watchFrom(conversationId, window.anchorKey!, window.limit);
  // Quoted messages outside the window are looked up once and remembered.
  final outside = <String, MessageRow?>{};

  late final StreamController<TimelineSnapshot> controller;
  StreamSubscription<List<MessageRow>>? messagesSub;
  StreamSubscription<List<ReactionRow>>? reactionsSub;
  var rows = const <MessageRow>[];
  var reactions = const <ReactionRow>[];
  String? reactionsFrom;
  Timer? pending;
  var first = true;
  var generation = 0;

  Future<void> compute() async {
    final mine = ++generation;
    final ctx = MapperContext(
      isGroup: isGroup,
      selfId: gateway.selfAccountId,
      people: people,
      now: now(),
    );
    final byId = {for (final r in rows) r.messageId: r};
    final quotes = <String, HelixReplyQuote>{};
    for (final row in rows) {
      final id = row.replyToId;
      if (id == null || quotes.containsKey(id)) continue;
      var target = byId[id];
      if (target == null) {
        if (!outside.containsKey(id)) {
          outside[id] = await gateway.findMessage(conversationId, id);
        }
        target = outside[id];
      }
      quotes[id] = quoteOf(row.replyToAuthor ?? '', target, ctx);
    }
    if (mine != generation || controller.isClosed) return;
    final byRowid = <int, List<ReactionRow>>{};
    for (final r in reactions) {
      (byRowid[r.messageRowid] ??= []).add(r);
    }
    controller.add(
      buildTimeline(
        rows: rows,
        ctx: ctx,
        reactions: byRowid,
        quotes: quotes,
        open: open,
        // Heuristic: a full window may have more behind it. Paging an empty
        // page back is a no-op, so being wrong costs one query.
        hasOlder: !window.isLatest || rows.length >= window.limit,
        hasNewer: !window.isLatest && rows.length >= window.limit,
      ),
    );
  }

  void schedule() {
    if (first) {
      first = false;
      unawaited(compute());
      return;
    }
    pending ??= Timer(_coalesce, () {
      pending = null;
      unawaited(compute());
    });
  }

  controller = StreamController<TimelineSnapshot>(
    onListen: () {
      messagesSub = source.listen((value) {
        rows = value;
        final start = value.isEmpty ? null : value.first.sortKey;
        if (start != reactionsFrom) {
          reactionsFrom = start;
          unawaited(reactionsSub?.cancel());
          reactionsSub = null;
          if (start == null) {
            reactions = const [];
          } else {
            reactionsSub = gateway
                .watchReactionsSince(conversationId, start)
                .listen((value) {
                  reactions = value;
                  schedule();
                });
          }
        }
        schedule();
      }, onError: controller.addError);
    },
    onCancel: () async {
      pending?.cancel();
      await messagesSub?.cancel();
      await reactionsSub?.cancel();
    },
  );
  return controller.stream;
}
