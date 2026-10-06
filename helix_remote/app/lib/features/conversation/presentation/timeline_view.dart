import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/features/conversation/application/conversation_header.dart';
import 'package:helix_remote/features/conversation/application/message_actions.dart';
import 'package:helix_remote/features/conversation/application/timeline_builder.dart';
import 'package:helix_remote/features/conversation/application/timeline_provider.dart';
import 'package:helix_remote/features/conversation/presentation/timeline_row.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The messages of a conversation: bottom-anchored, built lazily, paged up
/// (and down after a jump), with a button to return to the newest.
class TimelineView extends ConsumerStatefulWidget {
  const TimelineView({
    super.key,
    required this.args,
    required this.ui,
    required this.onAtBottomChanged,
    required this.onVisibleMessages,
  });

  final TimelineArgs args;
  final ConversationUi ui;

  /// The list reached or left the newest message.
  final ValueChanged<bool> onAtBottomChanged;

  /// New snapshot: the newest messages are on screen (for read tracking).
  final VoidCallback onVisibleMessages;

  @override
  ConsumerState<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends ConsumerState<TimelineView> {
  final ScrollController _scroll = ScrollController();
  bool _atBottom = true;
  TimelineSnapshot _snapshot = TimelineSnapshot.empty;
  int _olderRequestedAtLength = -1;
  String? _newestId;
  bool _keepPosition = false;

  /// The row a jump is bringing into view, and the key that finds it.
  String? _focusItemId;
  GlobalKey? _focusKey;
  bool _openedAtUnread = false;
  bool _seenFirst = false;

  /// The row widget built for each item, reused while nothing about the item
  /// changed (see [TimelineRowView]).
  final Map<String, _CachedRow> _rows = {};

  String get _conversationId => widget.args.conversationId;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // A conversation opened at a message (a search hit, a quote): the jump
    // was requested before this view existed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final jump = ref.read(timelineJumpProvider(_conversationId));
      if (jump != null) _scrollToMessageWhenLoaded(jump.messageId);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    // The list is reversed: pixels 0 is the newest message.
    final atBottom = pos.pixels <= 60;
    if (atBottom != _atBottom) {
      setState(() => _atBottom = atBottom);
      widget.onAtBottomChanged(atBottom);
    }
    final window = ref.read(timelineWindowProvider(widget.args).notifier);
    if (pos.maxScrollExtent - pos.pixels < 800 &&
        _snapshot.hasOlder &&
        _olderRequestedAtLength != _snapshot.newestFirst.length) {
      _olderRequestedAtLength = _snapshot.newestFirst.length;
      window.loadOlder();
    }
    if (pos.pixels < 800 && _snapshot.hasNewer) window.loadNewer();
  }

  /// A new snapshot arrived: stay put, follow the newest message, or open at
  /// the unread divider.
  void _onSnapshot(TimelineSnapshot snapshot) {
    final newest = snapshot.newestFirst.isEmpty
        ? null
        : snapshot.newestFirst.first.item.id;
    final grewAtBottom = _newestId != null && newest != _newestId;
    final newestEntry = snapshot.newestFirst.isEmpty
        ? null
        : snapshot.newestFirst.first;
    final newestMine =
        newestEntry?.item is HelixMessageItem &&
        (newestEntry!.item as HelixMessageItem).message.outgoing;
    _newestId = newest;
    _snapshot = snapshot;
    if (grewAtBottom && snapshot.hasNewer == false) {
      if (_atBottom || newestMine) {
        // Follow: a message you sent, or one that arrived while you were at
        // the bottom, is shown.
        _keepPosition = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.animateTo(
              0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            );
          }
        });
      } else {
        // Reading further up: keep what is on screen where it is.
        _keepPosition = true;
      }
    }
    if (!_openedAtUnread && snapshot.unreadDividerIndex != null) {
      _openedAtUnread = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollTo('unread'));
    }
    widget.onVisibleMessages();
  }

  /// Brings the row [itemId] into view, even when it is far from what is built.
  void _scrollTo(String itemId, {int attempt = 0}) {
    if (!mounted || !_scroll.hasClients) return;
    final index = _snapshot.indexOfId[itemId];
    if (index == null) {
      if (attempt < 8) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollTo(itemId, attempt: attempt + 1),
        );
      }
      return;
    }
    if (_focusItemId != itemId) {
      setState(() {
        _focusItemId = itemId;
        _focusKey = GlobalKey();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _focusKey?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.35,
          duration: const Duration(milliseconds: 250),
        );
        return;
      }
      if (attempt < 6 && _scroll.hasClients) {
        // Not built yet: jump close by an estimate, so it gets built.
        final estimate = index * 90.0;
        _scroll.jumpTo(estimate.clamp(0.0, _scroll.position.maxScrollExtent));
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollTo(itemId, attempt: attempt + 1),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshotAsync = ref.watch(timelineProvider(widget.args));
    ref.listen(timelineProvider(widget.args), (previous, next) {
      final value = next.value;
      if (value != null) _onSnapshot(value);
    });
    ref.listen(timelineJumpProvider(_conversationId), (previous, next) {
      if (next == null) return;
      final index = _snapshot.indexOfMessage(next.messageId);
      if (index != null) {
        _scrollTo(_snapshot.newestFirst[index].item.id);
      } else {
        // Not in the window yet: the jump below opens a window around it, and
        // the next snapshot carries it.
        ref
            .read(timelineWindowProvider(widget.args).notifier)
            .jumpTo(next.messageId)
            .then((_) => _scrollToMessageWhenLoaded(next.messageId));
      }
    });
    final highlight = ref.watch(timelineJumpProvider(_conversationId));
    final selection = ref.watch(messageSelectionProvider(_conversationId));
    final typing =
        ref
            .watch(conversationTypingProvider(_conversationId))
            .value
            ?.isNotEmpty ??
        false;
    final unread =
        ref
            .watch(conversationRowProvider(_conversationId))
            .value
            ?.unreadCount ??
        0;

    final snapshot = snapshotAsync.value;
    if (snapshot == null) {
      if (snapshotAsync.hasError) {
        return const HelixErrorState(
          message: 'This conversation could not be loaded.',
        );
      }
      return const ColoredBox(
        color: HelixChatColors.page,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!identical(_snapshot, snapshot)) {
      // Forget rows that left the window.
      _rows.removeWhere((id, _) => !snapshot.indexOfId.containsKey(id));
    }
    _snapshot = snapshot;
    if (!_seenFirst) {
      _seenFirst = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onSnapshot(snapshot);
      });
    }
    if (snapshot.newestFirst.isEmpty) {
      return const ColoredBox(
        color: HelixChatColors.page,
        child: Center(
          child: HelixSystemNotice(
            text: 'Messages are end-to-end encrypted. Say hello.',
            icon: Icons.lock_outline,
          ),
        ),
      );
    }

    final selecting = selection.isNotEmpty;
    final extra = typing ? 1 : 0;
    return Stack(
      children: [
        ColoredBox(
          color: HelixChatColors.page,
          child: ListView.builder(
            reverse: true,
            controller: _scroll,
            physics: _KeepVisiblePhysics(
              anchor: () {
                final keep = _keepPosition;
                _keepPosition = false;
                return keep;
              },
            ),
            addAutomaticKeepAlives: false,
            padding: const EdgeInsets.symmetric(vertical: HelixSpace.xs),
            itemCount: snapshot.newestFirst.length + extra,
            findChildIndexCallback: (key) {
              if (key is ValueKey<String>) {
                final i = snapshot.indexOfId[key.value];
                return i == null ? null : i + extra;
              }
              return null;
            },
            itemBuilder: (context, index) {
              if (typing && index == 0) return const HelixTypingIndicator();
              final entry = snapshot.newestFirst[index - extra];
              final id = entry.item.id;
              final rowid = entry.messageRowid;
              final isSelected = rowid != null && selection.contains(rowid);
              final isHighlighted =
                  highlight != null && entry.messageId == highlight.messageId;
              final cached = _rows[id];
              final Widget row;
              if (cached != null &&
                  cached.entry == entry &&
                  cached.selected == isSelected &&
                  cached.selecting == selecting &&
                  cached.highlighted == isHighlighted) {
                row = cached.widget;
              } else {
                row = TimelineRowView(
                  entry: entry,
                  ui: widget.ui,
                  selected: isSelected,
                  selectionMode: selecting,
                  highlighted: isHighlighted,
                );
                _rows[id] = _CachedRow(
                  entry,
                  isSelected,
                  selecting,
                  isHighlighted,
                  row,
                );
              }
              if (id == _focusItemId && _focusKey != null) {
                return KeyedSubtree(key: _focusKey, child: row);
              }
              return KeyedSubtree(key: ValueKey(id), child: row);
            },
          ),
        ),
        PositionedDirectional(
          end: HelixSpace.md,
          bottom: HelixSpace.md,
          child: HelixScrollToBottomButton(
            visible: !_atBottom || snapshot.hasNewer,
            unreadCount: unread,
            onPressed: () {
              if (snapshot.hasNewer) {
                ref
                    .read(timelineWindowProvider(widget.args).notifier)
                    .jumpToLatest();
              }
              if (_scroll.hasClients) {
                _scroll.animateTo(
                  0,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                );
              }
            },
          ),
        ),
      ],
    );
  }

  /// After a jump opened a new window: wait for the snapshot that has the
  /// message, then scroll to it.
  void _scrollToMessageWhenLoaded(String messageId, {int attempt = 0}) {
    if (!mounted) return;
    final index = _snapshot.indexOfMessage(messageId);
    if (index != null) {
      _scrollTo(_snapshot.newestFirst[index].item.id);
    } else if (attempt < 20) {
      Future<void>.delayed(
        const Duration(milliseconds: 60),
        () => _scrollToMessageWhenLoaded(messageId, attempt: attempt + 1),
      );
    }
  }
}

/// A clamping scroll that, when told to, keeps what the person is reading
/// where it is while messages are added below it. In a reversed list the
/// offset counts from the newest message, so a message arriving at the bottom
/// would push everything up; growing the offset by the same amount cancels it.
class _KeepVisiblePhysics extends ClampingScrollPhysics {
  const _KeepVisiblePhysics({super.parent, required this.anchor});

  /// Whether the next change of the list's size is messages arriving at the
  /// bottom. Reading it clears it.
  final bool Function() anchor;

  @override
  _KeepVisiblePhysics applyTo(ScrollPhysics? ancestor) =>
      _KeepVisiblePhysics(parent: buildParent(ancestor), anchor: anchor);

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final base = super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
    final grew = newPosition.maxScrollExtent - oldPosition.maxScrollExtent;
    if (grew > 0 && !isScrolling && oldPosition.pixels > 60 && anchor()) {
      return base + grew;
    }
    return base;
  }
}

class _CachedRow {
  const _CachedRow(
    this.entry,
    this.selected,
    this.selecting,
    this.highlighted,
    this.widget,
  );

  final TimelineEntry entry;
  final bool selected;
  final bool selecting;
  final bool highlighted;
  final Widget widget;
}
