import 'dart:async';

import 'package:helix_remote_engine/src/context.dart';
import 'package:helix_remote_engine/src/events.dart';
import 'package:helix_remote_engine/src/groups/group_ids.dart';
import 'package:helix_remote_engine/src/groups/group_sender.dart';
import 'package:helix_remote_engine/src/messaging/sender.dart';
import 'package:helix_remote_engine/src/settings_keys.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

/// Typing indicators (ephemeral: delivered only to online devices, never
/// stored, CONTENT_V2.md §4) in both directions.
///
/// **Receiving:** the inbound pipeline calls [onTyping]; an indicator
/// expires by itself after `EngineConfig.typingExpiry` unless refreshed.
/// **Sending:** [sendTyping] sends `started` at most once per
/// `typingSendInterval` per chat and `stopped` on request. It never starts
/// a session or fetches keys: if any of the peer's devices has no session
/// yet, the signal is skipped (the first real message sets sessions up).
/// Failures are ignored; typing is best effort.
final class PresenceService {
  PresenceService(this._ctx, this._sender, this._groups);

  final EngineContext _ctx;
  final MessageSender _sender;
  final GroupMessageSender _groups;

  final Map<String, Map<String, Timer>> _typing = {};
  final StreamController<String> _changes = StreamController.broadcast();
  final Map<String, DateTime> _lastSent = {};

  /// Accounts currently typing in [conversationId].
  Set<String> typingIn(String conversationId) =>
      Set.unmodifiable(_typing[conversationId]?.keys ?? const <String>[]);

  /// Emits the set of accounts typing in [conversationId] whenever it
  /// changes (and once at the start).
  Stream<Set<String>> watchTyping(String conversationId) async* {
    yield typingIn(conversationId);
    await for (final changed in _changes.stream) {
      if (changed == conversationId) yield typingIn(conversationId);
    }
  }

  /// Called by the inbound pipeline.
  void onTyping(String conversationId, String account, {required bool typing}) {
    final chat = _typing.putIfAbsent(conversationId, () => {});
    chat.remove(account)?.cancel();
    if (typing) {
      chat[account] = Timer(_ctx.config.typingExpiry, () {
        chat.remove(account);
        if (!_changes.isClosed) _changes.add(conversationId);
      });
    }
    if (chat.isEmpty) _typing.remove(conversationId);
    _ctx.emit(
      TypingEvent(
        conversationId: conversationId,
        account: account,
        typing: typing,
      ),
    );
    if (!_changes.isClosed) _changes.add(conversationId);
  }

  /// Tells the peer of [conversationId] (a direct chat) or the members of
  /// the group that this user started or stopped typing. A group indicator
  /// is encrypted once under the sender key and delivered to online devices
  /// only (it carries no key distribution, so a member that lacks the key
  /// simply does not see it).
  Future<void> sendTyping(String conversationId, {required bool typing}) async {
    const prefix = 'direct:';
    final group = GroupIds.isGroupConversation(conversationId);
    if (!group && !conversationId.startsWith(prefix)) return;
    if (!await _ctx.db.settingsDao.get(EngineSettings.sendTyping)) return;
    final now = _ctx.now();
    if (typing) {
      final last = _lastSent[conversationId];
      if (last != null &&
          now.difference(last) < _ctx.config.typingSendInterval) {
        return;
      }
      _lastSent[conversationId] = now;
    } else {
      _lastSent.remove(conversationId);
    }
    if (group) {
      await _sendGroupTyping(GroupIds.groupIdOf(conversationId), typing, now);
      return;
    }
    final peer = conversationId.substring(prefix.length);
    try {
      if (!await _sender.readyWithoutSetup(peer)) return;
      final content = ContentMessage(
        id: _ctx.ids.next(),
        sentAt: now,
        conversation: DirectConversation(to: peer),
        body: TypingBody(
          state: typing ? TypingState.started : TypingState.stopped,
        ),
      );
      await _sender.send(
        requestId: content.id,
        content: content.encode(),
        accounts: [peer],
        ephemeral: true,
        urgent: false,
      );
    } on Object {
      // Best effort.
    }
  }

  Future<void> _sendGroupTyping(
    String groupId,
    bool typing,
    DateTime now,
  ) async {
    try {
      if (await _ctx.db.groupsDao.byId(groupId) == null) return;
      final content = ContentMessage(
        id: _ctx.ids.next(),
        sentAt: now,
        conversation: GroupConversation(group: groupId),
        body: TypingBody(
          state: typing ? TypingState.started : TypingState.stopped,
        ),
      );
      await _groups.send(
        groupId: groupId,
        requestId: content.id,
        content: content,
        urgent: false,
        ephemeral: true,
      );
    } on Object {
      // Best effort.
    }
  }

  Future<void> close() async {
    for (final chat in _typing.values) {
      for (final timer in chat.values) {
        timer.cancel();
      }
    }
    _typing.clear();
    await _changes.close();
  }
}
