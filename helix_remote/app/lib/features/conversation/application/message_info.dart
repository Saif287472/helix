import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/chat/chat_gateway.dart';
import 'package:helix_remote/core/chat/chat_naming.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/core/format/labels.dart';
import 'package:helix_remote/core/platform/chat_platform.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// One person's receipts for a message.
@immutable
class ReceiptLine {
  const ReceiptLine({
    required this.name,
    required this.avatar,
    this.deliveredLabel,
    this.readLabel,
  });

  final String name;
  final HelixAvatarModel avatar;

  /// "Today, 14:05", or null when not delivered to them yet.
  final String? deliveredLabel;
  final String? readLabel;
}

/// "Message info": when it was sent and who has received and read it.
@immutable
class MessageInfo {
  const MessageInfo({
    required this.sentLabel,
    required this.lines,
    required this.preview,
  });

  final String sentLabel;
  final List<ReceiptLine> lines;

  /// What the message said (text or caption), for the header of the page.
  final String preview;
}

/// The info of the message with database id [rowid]; null when it is gone.
final messageInfoProvider = FutureProvider.autoDispose
    .family<MessageInfo?, int>((ref, rowid) async {
      final gateway = await ref.watch(chatGatewayProvider.future);
      final people = await ref.watch(peopleDirectoryProvider.future);
      final row = await gateway.message(rowid);
      if (row == null) return null;
      final now = ref.read(clockProvider)();
      final receipts = await gateway.receiptsOf(rowid);
      final byAccount = {for (final r in receipts) r.accountId: r};
      // A direct chat has one recipient even before any receipt came in.
      final peer = peerOfConversation(row.conversationId);
      final accounts = <String>[
        ?peer,
        for (final r in receipts)
          if (r.accountId != peer) r.accountId,
      ];
      String? label(DateTime? at) =>
          at == null ? null : formatDateTime(at, now);
      return MessageInfo(
        sentLabel: formatDateTime(row.sentAt, now),
        preview: (row.body ?? '').replaceAll(RegExp(r'\s+'), ' ').trim(),
        lines: [
          for (final account in accounts)
            ReceiptLine(
              name: people.displayOf(account),
              avatar: people.avatarOf(account),
              deliveredLabel: label(byAccount[account]?.deliveredAt),
              readLabel: label(
                byAccount[account]?.readAt ?? byAccount[account]?.viewedAt,
              ),
            ),
        ],
      );
    });

/// One person's reaction to a message.
@immutable
class ReactionLine {
  const ReactionLine({
    required this.emoji,
    required this.name,
    required this.avatar,
    this.mine = false,
  });

  final String emoji;
  final String name;
  final HelixAvatarModel avatar;
  final bool mine;
}

/// Who reacted to the message with database id [rowid], and with what.
final reactionDetailsProvider = FutureProvider.autoDispose
    .family<List<ReactionLine>, int>((ref, rowid) async {
      final gateway = await ref.watch(chatGatewayProvider.future);
      final people = await ref.watch(peopleDirectoryProvider.future);
      final self = gateway.selfAccountId;
      return [
        for (final r in await gateway.reactionsOf(rowid))
          ReactionLine(
            emoji: r.emoji,
            name: r.reactor == self ? 'You' : people.displayOf(r.reactor),
            avatar: people.avatarOf(r.reactor),
            mine: r.reactor == self,
          ),
      ];
    });
