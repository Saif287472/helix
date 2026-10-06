import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The chats ticked in the list. Empty means no selection is in progress.
///
/// A long press starts one; while it is not empty a tap toggles a row instead
/// of opening it.
final class ChatSelection extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String id) {
    final next = {...state};
    if (!next.remove(id)) next.add(id);
    state = next;
  }

  void start(String id) => state = {id};

  void clear() {
    if (state.isNotEmpty) state = const {};
  }
}

final chatSelectionProvider = NotifierProvider<ChatSelection, Set<String>>(
  ChatSelection.new,
);
