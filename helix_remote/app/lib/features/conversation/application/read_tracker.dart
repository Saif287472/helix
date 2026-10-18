import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/features/conversation/application/conversation_header.dart';

/// Marks the conversation read when the person can actually see its newest
/// messages: the app is in the foreground, the screen is open and the list is
/// scrolled to the bottom. That is what sends read receipts, so a message
/// scrolled past in the background, or above the fold, is not "read".
///
/// Also starts the disappearing timers of the messages the timeline says it
/// drew: a timer counts from first display on this device, so the rows have to
/// come from the list rather than from the database (see [displayed]).
final class ReadTracker extends Notifier<void> {
  ReadTracker(this.conversationId);

  final String conversationId;

  bool _atBottom = true;
  bool _foreground = true;
  Timer? _timer;
  final Set<int> _displayed = {};

  /// Rows the timeline has drawn whose timer has not been started yet. A
  /// message that arrives while the app is in the background was never really
  /// seen, so nothing is written then; the rows wait here until the app comes
  /// back and are started then.
  final Set<int> _onScreen = {};

  /// A little patience, so flinging past the bottom is not a read.
  static const settle = Duration(milliseconds: 300);

  @override
  void build() {
    ref.onDispose(() => _timer?.cancel());
  }

  /// The list is at (or has left) the newest message.
  void setAtBottom(bool value) {
    _atBottom = value;
    _maybeMarkRead();
  }

  /// The app came to the foreground or went away.
  void setForeground(bool value) {
    _foreground = value;
    if (value) unawaited(_startTimers());
    _maybeMarkRead();
  }

  /// New messages arrived; if the person is looking, they are read.
  void messagesChanged() => _maybeMarkRead();

  void _maybeMarkRead() {
    if (!_atBottom || !_foreground) {
      _timer?.cancel();
      return;
    }
    final chat = ref.read(conversationRowProvider(conversationId)).value;
    if (chat == null || chat.unreadCount == 0) return;
    _timer?.cancel();
    _timer = Timer(settle, () async {
      final gateway = await ref.read(chatGatewayProvider.future);
      await gateway.markRead(conversationId);
    });
  }

  /// These messages are on screen now.
  ///
  /// The timeline says which rows it drew, and nothing else does: a message
  /// the person cannot see must not start its disappearing timer. Rows drawn
  /// while the app was in the background are kept and started when it comes
  /// back (see [setForeground]).
  Future<void> displayed(Iterable<int> rowids) async {
    _onScreen.addAll(rowids);
    await _startTimers();
  }

  /// Starts the disappearing timer of everything on screen that has none.
  ///
  /// A row is only ever started once per conversation: [_displayed] holds the
  /// ones that have been, so scrolling back up does not restart a timer.
  /// Messages with no timer (everything but a disappearing-message chat) cost
  /// one query each and change nothing, which is the engine's own guard.
  Future<void> _startTimers() async {
    if (!_foreground || _onScreen.isEmpty) return;
    final fresh = [
      for (final id in _onScreen)
        if (_displayed.add(id)) id,
    ];
    _onScreen.clear();
    if (fresh.isEmpty || !ref.mounted) return;
    final gateway = await ref.read(chatGatewayProvider.future);
    for (final id in fresh) {
      await gateway.markDisplayed(id);
    }
  }
}

final readTrackerProvider = NotifierProvider.autoDispose
    .family<ReadTracker, void, String>(ReadTracker.new);
