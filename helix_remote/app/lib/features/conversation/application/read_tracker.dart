import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/features/conversation/application/conversation_header.dart';

/// Marks the conversation read when the person can actually see its newest
/// messages: the app is in the foreground, the screen is open and the list is
/// scrolled to the bottom. That is what sends read receipts, so a message
/// scrolled past in the background, or above the fold, is not "read".
///
/// Also starts the disappearing timers of messages that are on screen (a timer
/// counts from first display).
final class ReadTracker extends Notifier<void> {
  ReadTracker(this.conversationId);

  final String conversationId;

  bool _atBottom = true;
  bool _foreground = true;
  Timer? _timer;
  final Set<int> _displayed = {};

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

  /// These messages (with a disappearing timer) are on screen now.
  Future<void> displayed(Iterable<int> rowids) async {
    if (!_foreground) return;
    final fresh = [
      for (final id in rowids)
        if (_displayed.add(id)) id,
    ];
    if (fresh.isEmpty) return;
    final gateway = await ref.read(chatGatewayProvider.future);
    for (final id in fresh) {
      await gateway.markDisplayed(id);
    }
  }
}

final readTrackerProvider = NotifierProvider.autoDispose
    .family<ReadTracker, void, String>(ReadTracker.new);
