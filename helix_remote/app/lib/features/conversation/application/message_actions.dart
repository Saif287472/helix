import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/features/conversation/application/conversation_header.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ContentLimits;

/// Well-known ids for the message menu, so the rules here and the screen that
/// draws them switch on the same constants.
abstract final class MessageActionIds {
  static const reply = 'reply';
  static const forward = 'forward';
  static const copy = 'copy';
  static const edit = 'edit';
  static const star = 'star';
  static const info = 'info';
  static const select = 'select';
  static const deleteForMe = 'delete_for_me';
  static const deleteForEveryone = 'delete_for_everyone';
}

/// The long-press menu of one message: which actions apply to it right now,
/// and the reaction this account already gave.
@immutable
class MessageMenu {
  const MessageMenu({
    required this.actions,
    required this.allowReactions,
    this.currentReaction,
  });

  /// The action ids, in menu order.
  final List<String> actions;
  final bool allowReactions;
  final String? currentReaction;
}

/// What a person can do to the messages of one conversation.
///
/// The rules the engine enforces (edit within 15 minutes, delete for
/// everyone within two days, group admins may delete anyone's message) are
/// worked out here too, so the menu offers only what will succeed; the engine
/// still checks.
final class ConversationActions {
  ConversationActions(this._ref, this.conversationId);

  final Ref _ref;
  final String conversationId;

  Future<ChatGateway> get _gateway => _ref.read(chatGatewayProvider.future);

  static const _sentStates = {
    MessageStatus.sent,
    MessageStatus.delivered,
    MessageStatus.read,
    MessageStatus.viewed,
  };

  /// The menu for [rowid], or null when the message is gone.
  Future<MessageMenu?> menuFor(int rowid) async {
    final gateway = await _gateway;
    final row = await gateway.message(rowid);
    if (row == null) return null;
    final now = _ref.read(clockProvider)();
    final deleted = row.deletedAt != null;
    final broken = row.kind == 'undecryptable' || row.kind == 'unsupported';
    final viewOnce = row.viewOnceState != null;
    final sent = row.outgoing ? _sentStates.contains(row.status) : true;

    final canEdit =
        row.outgoing &&
        !deleted &&
        !viewOnce &&
        (row.kind == 'text' || row.kind == 'media') &&
        _sentStates.contains(row.status) &&
        now.difference(row.sentAt) <= ContentLimits.editWindow;

    var admin = false;
    final group = groupIdOf(row.conversationId);
    if (!row.outgoing && group != null) {
      admin = await gateway.isGroupAdmin(group);
    }
    final canDeleteForEveryone =
        !deleted &&
        (row.outgoing || admin) &&
        sent &&
        now.difference(row.sentAt) <= ContentLimits.deleteWindow;

    final hasText = !deleted && !viewOnce && (row.body ?? '').isNotEmpty;
    final all = [
      MessageActionIds.reply,
      if (hasText) MessageActionIds.copy,
      MessageActionIds.forward,
      MessageActionIds.star,
      if (canEdit) MessageActionIds.edit,
      if (row.outgoing) MessageActionIds.info,
      MessageActionIds.select,
      MessageActionIds.deleteForMe,
      if (canDeleteForEveryone) MessageActionIds.deleteForEveryone,
    ];
    final canForward =
        !deleted && !viewOnce && (row.kind == 'text' || row.kind == 'media');
    final actions = [
      for (final action in all)
        if (_offered(
          action,
          deleted: deleted,
          broken: broken,
          viewOnce: viewOnce,
          canForward: canForward,
        ))
          action,
    ];
    String? current;
    if (!deleted && !broken) {
      final self = gateway.selfAccountId;
      for (final r in await gateway.reactionsOf(rowid)) {
        if (r.reactor == self) current = r.emoji;
      }
    }
    return MessageMenu(
      actions: actions,
      allowReactions: !deleted && !broken,
      currentReaction: current,
    );
  }

  bool _offered(
    String id, {
    required bool deleted,
    required bool broken,
    required bool viewOnce,
    required bool canForward,
  }) {
    switch (id) {
      // The engine keeps no stars, so the menu does not offer one.
      case MessageActionIds.star:
        return false;
      case MessageActionIds.reply:
        return !deleted && !broken && !viewOnce;
      case MessageActionIds.forward:
        return canForward;
      default:
        return true;
    }
  }

  /// React with [emoji]; reacting again with the same one takes it back.
  Future<void> react(int rowid, String emoji) async {
    final gateway = await _gateway;
    final self = gateway.selfAccountId;
    final mine = (await gateway.reactionsOf(
      rowid,
    )).where((r) => r.reactor == self).firstOrNull;
    await gateway.react(rowid, mine?.emoji == emoji ? null : emoji);
  }

  /// Takes this account's reaction off [rowid] ("Tap to remove").
  Future<void> removeMyReaction(int rowid) async =>
      (await _gateway).react(rowid, null);

  /// The text of [rowids] (a selection), oldest first, one message per line,
  /// for the clipboard.
  Future<String> textOf(Iterable<int> rowids) async {
    final gateway = await _gateway;
    final rows = <MessageRow>[];
    for (final id in rowids) {
      final row = await gateway.message(id);
      if (row != null && row.deletedAt == null && (row.body ?? '').isNotEmpty) {
        rows.add(row);
      }
    }
    rows.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return rows.map((r) => r.body!).join('\n');
  }

  Future<void> copy(Iterable<int> rowids) async {
    final text = await textOf(rowids);
    if (text.isNotEmpty) await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> deleteForMe(Iterable<int> rowids) async =>
      (await _gateway).deleteForMe(rowids);

  /// Deletes for everyone; false when it is no longer allowed.
  Future<bool> deleteForEveryone(int rowid) async {
    try {
      await (await _gateway).deleteForEveryone(rowid);
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> retry(int rowid) async => (await _gateway).retrySend(rowid);

  /// Re-queues every action on [rowid] that failed for good (a delete for
  /// everyone the others never saw). The engine names the target on each
  /// action op, so the message's own retry does not find them.
  Future<void> retryActions(int rowid) async {
    final gateway = await _gateway;
    for (final f in await gateway.failedActions(conversationId)) {
      if (f.targetRowid == rowid) await gateway.retryAction(f.opId);
    }
  }

  /// Sends [rowids] on to every conversation in [targets]; returns how many
  /// sends failed (a view-once or deleted message cannot be forwarded).
  Future<int> forward(
    Iterable<int> rowids,
    Iterable<String> targets, {
    Iterable<String> peersToOpen = const [],
  }) async {
    final gateway = await _gateway;
    var failed = 0;
    final destinations = [...targets];
    for (final peer in peersToOpen) {
      destinations.add(await gateway.openDirect(peer));
    }
    final ordered = await _inSendOrder(gateway, rowids);
    for (final destination in destinations) {
      for (final rowid in ordered) {
        try {
          await gateway.forward(rowid, destination);
        } on Object {
          failed++;
        }
      }
    }
    return failed;
  }

  Future<List<int>> _inSendOrder(
    ChatGateway gateway,
    Iterable<int> rowids,
  ) async {
    final rows = <MessageRow>[];
    for (final id in rowids) {
      final row = await gateway.message(id);
      if (row != null) rows.add(row);
    }
    rows.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return [for (final r in rows) r.localRowid];
  }
}

/// Not auto-disposed: its methods run `await`s that outlive the widget that
/// asked, and must still reach the engine when they finish.
final conversationActionsProvider =
    Provider.family<ConversationActions, String>(ConversationActions.new);
