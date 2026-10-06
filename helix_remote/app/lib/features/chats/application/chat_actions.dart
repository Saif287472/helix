import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/shared/widgets/mute_choice.dart';

/// What a person can do to chats from the list: the swipe actions, the
/// selection bar and the long-press menu all land here.
///
/// A plain object over the gateway, not a notifier: it holds no state, and the
/// list updates itself from the engine's watch query when a write lands.
final class ChatActions {
  ChatActions(this._ref);

  final Ref _ref;

  Future<ChatGateway> get _gateway => _ref.read(chatGatewayProvider.future);

  Future<void> pin(Iterable<String> ids, {required bool pinned}) async {
    final gateway = await _gateway;
    for (final id in ids) {
      await gateway.setPinned(id, pinned: pinned);
    }
  }

  Future<void> archive(Iterable<String> ids, {required bool archived}) async {
    final gateway = await _gateway;
    for (final id in ids) {
      await gateway.setArchived(id, archived: archived);
    }
  }

  /// Mutes the chats for [length], or unmutes them when it is null.
  Future<void> mute(Iterable<String> ids, MuteFor? length) async {
    final gateway = await _gateway;
    final now = _ref.read(clockProvider)();
    final until = length?.until(now);
    for (final id in ids) {
      await gateway.setMutedUntil(id, until);
    }
  }

  /// Deletes the chats and their messages from this device.
  Future<void> delete(Iterable<String> ids) async {
    final gateway = await _gateway;
    for (final id in ids) {
      await gateway.deleteChat(id);
    }
  }

  /// Marks the chats read (and sends read receipts when the setting allows).
  Future<void> markRead(Iterable<String> ids) async {
    final gateway = await _gateway;
    for (final id in ids) {
      await gateway.markRead(id);
    }
  }
}

final chatActionsProvider = Provider<ChatActions>(ChatActions.new);
