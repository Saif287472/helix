import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:helix_remote/core/engine/runtime_providers.dart';
import 'package:helix_remote_db/helix_remote_db.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// The chat list, as the components want it.
///
/// Every list in this app is a [StreamProvider] over a drift watch query
/// (plan §6.4): the engine owns the query, this maps rows into the plain
/// value objects in `helix_remote_ui`, and the widgets never see a row, a
/// column or a clock.
///
/// Dates and times arrive already formatted, because a component must not do
/// work in `build` and has no clock.
final chatListProvider = StreamProvider<List<HelixChatListItem>>((ref) async* {
  final runtime = await ref.watch(runtimeProvider.future);
  final now = DateTime.now();
  yield* runtime.engine.chats.watchChats().map(
    (rows) => [for (final row in rows) _toListItem(row, now)],
  );
});

HelixChatListItem _toListItem(ConversationListItem row, DateTime now) {
  final chat = row.conversation;
  final title = chat.title?.trim();
  final preview = chat.lastMessagePreview?.trim();
  return HelixChatListItem(
    id: chat.id,
    // A direct chat with no title yet is the peer; the full naming order
    // (phone-book name, then nickname, then number, then ~Helix name) is A2's
    // work and lands in this same mapper.
    title: (title == null || title.isEmpty) ? 'Helix' : title,
    avatar: HelixAvatarModel(
      name: title ?? chat.id,
      isGroup: chat.kind.name == 'group',
    ),
    preview: preview == null || preview.isEmpty
        ? null
        : HelixChatPreview(text: preview),
    timeLabel: formatChatTime(chat.lastMessageAt, now),
    unreadCount: chat.unreadCount,
    hasMention: chat.mentionCount > 0,
    pinned: chat.pinnedAt != null,
    muted: (chat.mutedUntil?.isAfter(now) ?? false),
    archived: chat.archived,
  );
}

/// The time a chat row shows, already shortened the way a person reads a chat
/// list: a clock time for today, "Yesterday", a weekday inside the week, and
/// a numeric date beyond it.
String formatChatTime(DateTime? at, DateTime now) {
  if (at == null) return '';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final difference = today.difference(day).inDays;
  if (difference == 0) {
    return '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
  }
  if (difference == 1) return 'Yesterday';
  if (difference < 7) return _weekday(at.weekday);
  return '${at.day.toString().padLeft(2, '0')}/'
      '${at.month.toString().padLeft(2, '0')}/'
      '${(at.year % 100).toString().padLeft(2, '0')}';
}

String _weekday(int weekday) => switch (weekday) {
  DateTime.monday => 'Mon',
  DateTime.tuesday => 'Tue',
  DateTime.wednesday => 'Wed',
  DateTime.thursday => 'Thu',
  DateTime.friday => 'Fri',
  DateTime.saturday => 'Sat',
  _ => 'Sun',
};

/// The account this device is signed in as: its id, its `~Helix name` and the
/// server it is on. The Settings tab's header.
final selfAccountProvider = StreamProvider<HelixProfileSummary>((ref) async* {
  final runtime = await ref.watch(runtimeProvider.future);
  yield* runtime.engine.account.watch().map(
    (account) => account == null
        ? const HelixProfileSummary()
        : HelixProfileSummary(
            accountId: account.accountId,
            phoneNumber: account.phoneNumber,
            profileName: account.profileName ?? '',
            helixName: account.helixName,
          ),
  );
});

/// What the Settings tab needs about the signed-in account.
///
/// A projection, not a widget's private state, so both the header and
/// anything else that needs the account reads one thing.
class HelixProfileSummary {
  const HelixProfileSummary({
    this.accountId = '',
    this.phoneNumber,
    this.profileName = '',
    this.helixName,
  });

  final String accountId;
  final String? phoneNumber;

  /// The name this person chose at sign-up.
  final String profileName;

  /// The `~Helix name` they claimed on the server.
  final String? helixName;

  /// What the Settings header shows: the profile name if there is one, then
  /// the Helix name, then a plain default.
  String get displayName {
    if (profileName.isNotEmpty) return profileName;
    final helix = helixName;
    if (helix != null && helix.isNotEmpty) return '~$helix';
    return 'Helix';
  }
}

/// The number of unread messages across all non-archived chats, for the tab
/// badge.
final unreadCountProvider = StreamProvider<int>((ref) async* {
  final runtime = await ref.watch(runtimeProvider.future);
  yield* runtime.engine.chats.watchUnread().map((totals) => totals.messages);
});
