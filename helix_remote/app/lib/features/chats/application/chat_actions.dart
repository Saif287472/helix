import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/core/security/device_auth.dart';
import 'package:helix_remote/core/security/locked_chats.dart';
import 'package:helix_remote/shared/widgets/mute_choice.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart'
    show ChatsService, EngineStateException;

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

  /// Makes the chats favourites, or not (the Favourites filter).
  Future<void> favourite(
    Iterable<String> ids, {
    required bool favourite,
  }) async {
    final gateway = await _gateway;
    for (final id in ids) {
      await gateway.setFavourite(id, favourite: favourite);
    }
  }

  /// Makes a list called [name] holding [ids]: null when it was made, else the
  /// sentence to show.
  Future<String?> createList(String name, Set<String> ids) async {
    try {
      final gateway = await _gateway;
      final id = await gateway.createChatList(name);
      if (ids.isNotEmpty) {
        await gateway.setChatsOnList(id, ids, member: true);
      }
      return null;
    } on ArgumentError {
      return 'A list name is 1 to ${ChatsService.maxChatListName} characters.';
    } on EngineStateException {
      return 'You already have a list with that name, or ten lists.';
    } on Object {
      return 'The list could not be made.';
    }
  }

  /// Renames a list: null when it was, else the sentence to show.
  Future<String?> renameList(String id, String name) async {
    try {
      await (await _gateway).renameChatList(id, name);
      return null;
    } on ArgumentError {
      return 'A list name is 1 to ${ChatsService.maxChatListName} characters.';
    } on EngineStateException {
      return 'You already have a list with that name.';
    } on Object {
      return 'The list could not be renamed.';
    }
  }

  Future<void> deleteList(String id) async =>
      (await _gateway).deleteChatList(id);

  /// Puts the chats on a list, or takes them off it.
  Future<void> setOnList(
    Iterable<String> ids,
    String listId, {
    required bool member,
  }) async => (await _gateway).setChatsOnList(listId, ids, member: member);

  /// Locks the chats, or unlocks them. Locking needs a screen lock on the
  /// phone; null when it was done, else the sentence to show.
  Future<String?> setLocked(
    Iterable<String> ids, {
    required bool locked,
  }) async {
    if (locked) {
      final why = await whyNotLock(_ref.read(deviceAuthenticatorProvider));
      if (why != null) return why;
    }
    final gateway = await _gateway;
    for (final id in ids) {
      await gateway.setLocked(id, locked: locked);
    }
    return null;
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
