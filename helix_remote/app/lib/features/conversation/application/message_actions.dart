import 'dart:io' show File;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/chat/message_semantics.dart' show payloadOf;
import 'package:helix_remote/core/location/live_location_service.dart';
import 'package:helix_remote/core/platform/attachment_picker.dart'
    show PickedFile, PickedKind;
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote/features/conversation/application/conversation_header.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_engine/helix_remote_engine.dart' show ChatsService;
import 'package:helix_remote_protocol/helix_remote_protocol.dart'
    show ContentLimits, RsvpState;
import 'package:orbit_ui/models.dart';

/// Well-known ids for the message menu, so the rules here and the screen that
/// draws them switch on the same constants.
abstract final class MessageActionIds {
  static const reply = 'reply';
  static const forward = 'forward';
  static const copy = 'copy';
  static const edit = 'edit';
  static const star = 'star';
  static const pin = 'pin';
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
    this.starred = false,
    this.pinned = false,
  });

  /// The action ids, in menu order.
  final List<String> actions;
  final bool allowReactions;
  final String? currentReaction;

  /// The message is starred / pinned now, so the menu offers to undo it.
  final bool starred;
  final bool pinned;
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

  /// The GIFs on this phone for the tray: those whose file is still there.
  Future<List<({int id, String path})>> savedGifs() async {
    final rows = await (await _gateway).recentGifs();
    return [
      for (final row in rows)
        if (row.localPath != null && File(row.localPath!).existsSync())
          (id: row.id, path: row.localPath!),
    ];
  }

  /// A GIF from the tray as a file to send, or null when it is gone.
  Future<PickedFile?> gifFile(int attachmentId) async {
    final path = await (await _gateway).localPathOf(attachmentId);
    if (path == null) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return PickedFile(
      path: path,
      name: 'GIF.gif',
      mime: 'image/gif',
      size: file.lengthSync(),
      kind: PickedKind.image,
    );
  }

  /// Stars or unstars a message (a private bookmark).
  Future<void> star(int rowid, {required bool starred}) async {
    try {
      await (await _gateway).setStarred(rowid, starred: starred);
    } on Object {
      // The message is gone; the menu closes on a list that no longer has it.
    }
  }

  /// Pins or unpins a message for everyone in the chat: null when it went,
  /// else the sentence to show. A chat keeps three.
  Future<String?> pin(int rowid, {required bool pinned}) async {
    try {
      final gateway = await _gateway;
      if (pinned) {
        final row = await gateway.message(rowid);
        if (row != null && row.pinnedAt == null) {
          final held = await gateway.watchPinned(row.conversationId).first;
          if (held.length >= ChatsService.maxPinnedMessages) {
            return 'A chat keeps three pinned messages. Unpin one first.';
          }
        }
      }
      await gateway.pinMessage(rowid, pinned: pinned);
      return null;
    } on Object {
      return pinned
          ? 'The message could not be pinned.'
          : 'The message could not be unpinned.';
    }
  }

  /// Votes in a poll. A poll that is gone, or an answer it does not have, is
  /// not an error worth showing: the bubble redraws from what is stored.
  Future<void> vote(int rowid, List<String> optionIds) async {
    try {
      await (await _gateway).vote(rowid, optionIds);
    } on Object {
      // Nothing to vote on any more.
    }
  }

  /// Answers an event invitation, the same way.
  Future<void> rsvp(int rowid, HelixRsvp answer) async {
    try {
      await (await _gateway).rsvp(rowid, switch (answer) {
        HelixRsvp.going => RsvpState.going,
        HelixRsvp.maybe => RsvpState.maybe,
        HelixRsvp.declined => RsvpState.declined,
      });
    } on Object {
      // Nothing to answer any more.
    }
  }

  /// Sends a poll: null when it went, else the sentence to show.
  Future<String?> sendPoll(HelixPollDraft draft) async {
    try {
      await (await _gateway).sendPoll(
        conversationId,
        question: draft.question,
        options: draft.options,
        multiple: draft.multiple,
      );
      return null;
    } on Object {
      return 'The poll could not be sent.';
    }
  }

  /// Sends an event: null when it went, else the sentence to show.
  Future<String?> sendEvent(HelixEventDraft draft) async {
    try {
      await (await _gateway).sendEvent(
        conversationId,
        title: draft.title,
        startsAt: draft.startsAt,
        place: draft.place,
      );
      return null;
    } on Object {
      return 'The event could not be sent.';
    }
  }

  /// Shares where the phone is: once ([live] null) or live for [live]. Null
  /// when it went, else the sentence to show.
  Future<String?> shareLocation(Duration? live) {
    final service = _ref.read(liveLocationServiceProvider);
    return live == null
        ? service.sendOnce(conversationId)
        : service.startLive(conversationId, live);
  }

  /// Stops the live location in [rowid].
  Future<void> stopLive(int rowid) =>
      _ref.read(liveLocationServiceProvider).stop(rowid);

  /// Where a maps app should open for the location in [rowid]: a `geo:` link
  /// on Android (which maps app is the phone's choice), a map page elsewhere.
  /// Null when the message holds no place (a live share that has ended).
  Future<Uri?> mapLinkOf(int rowid, {required bool android}) async {
    final row = await (await _gateway).message(rowid);
    if (row == null) return null;
    final payload = payloadOf(row);
    final lat = payload['lat_e7'];
    final lng = payload['lng_e7'];
    if (lat is! int || lng is! int || (lat == 0 && lng == 0)) return null;
    final at =
        '${(lat / 1e7).toStringAsFixed(6)},${(lng / 1e7).toStringAsFixed(6)}';
    return android
        ? Uri.parse('geo:$at?q=$at')
        : Uri.parse(
            'https://www.openstreetmap.org/?mlat=${at.split(',')[0]}'
            '&mlon=${at.split(',')[1]}#map=16/${at.replaceFirst(',', '/')}',
          );
  }

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
      MessageActionIds.pin,
      if (canEdit) MessageActionIds.edit,
      // Receipts are of what you sent; an edited message also has a history.
      if (row.outgoing || row.editedAt != null) MessageActionIds.info,
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
      starred: row.starredAt != null,
      pinned: row.pinnedAt != null,
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
      // A star or a pin is of a message that is there and stays: not a deleted
      // or broken one, and not a view-once photo that will not.
      case MessageActionIds.star:
      case MessageActionIds.pin:
        return !deleted && !broken && !viewOnce;
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

  /// The account whose changed (verified) safety number holds [rowid], if any.
  Future<String?> heldContact(int rowid) async =>
      (await _gateway).keyHoldOf(rowid);

  /// "Send anyway": ends the hold on [account], and what waited goes out.
  Future<void> sendAnyway(String account) async =>
      (await _gateway).releaseKeyHold(account);

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
