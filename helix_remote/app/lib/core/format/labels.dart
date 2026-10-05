/// The short strings a chat screen shows for times, sizes and lengths.
///
/// Components never format anything (`helix_remote_ui` view models carry
/// finished strings), so every label in the chat screens is made here, once,
/// from a stored UTC time and an injected "now". Times are shown in the
/// phone's local zone.
library;

/// The time a chat row shows: a clock time for today, "Yesterday", a weekday
/// inside the week, and a numeric date beyond it.
String formatChatTime(DateTime? at, DateTime now) {
  if (at == null) return '';
  final local = at.toLocal();
  final days = _daysBetween(local, now.toLocal());
  if (days == 0) return formatClock(local);
  if (days == 1) return 'Yesterday';
  if (days > 1 && days < 7) return _weekdayShort(local.weekday);
  return '${_two(local.day)}/${_two(local.month)}/${_two(local.year % 100)}';
}

/// "14:05".
String formatClock(DateTime at) {
  final local = at.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}';
}

/// The date separator above a day's messages: "Today", "Yesterday", a
/// weekday inside the week, and "12 September 2026" beyond it.
String formatDateSeparator(DateTime at, DateTime now) {
  final local = at.toLocal();
  final days = _daysBetween(local, now.toLocal());
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days > 1 && days < 7) return _weekdayLong(local.weekday);
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// The line under a person's name in a conversation header.
String formatLastSeen(DateTime at, DateTime now) {
  final local = at.toLocal();
  final days = _daysBetween(local, now.toLocal());
  final clock = formatClock(local);
  if (days == 0) return 'last seen today at $clock';
  if (days == 1) return 'last seen yesterday at $clock';
  return 'last seen ${local.day} ${_months[local.month - 1]}';
}

/// "0:07", "12:30", "1:02:03".
String formatDurationMs(int? milliseconds) {
  final total = ((milliseconds ?? 0) / 1000).round();
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  if (hours > 0) return '$hours:${_two(minutes)}:${_two(seconds)}';
  return '$minutes:${_two(seconds)}';
}

/// "2.3 MB" for storage and server limits, which are binary (1 MB is 1024
/// KB): a 100 MiB upload limit reads "100 MB", as the server states it.
/// [formatFileSize] is the decimal one, for a file's size in a chat.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  return '${(mb / 1024).toStringAsFixed(1)} GB';
}

/// "812 B", "482 KB", "3.4 MB": the size a sender sees on their phone, which
/// counts in thousands. See [formatBytes] for storage and limits.
String formatFileSize(int bytes) {
  if (bytes < 1000) return '$bytes B';
  if (bytes < 1000 * 1000) return '${(bytes / 1000).round()} KB';
  if (bytes < 1000 * 1000 * 1000) {
    final mb = bytes / (1000 * 1000);
    return '${mb < 10 ? mb.toStringAsFixed(1) : mb.round()} MB';
  }
  return '${(bytes / (1000 * 1000 * 1000)).toStringAsFixed(1)} GB';
}

/// The disappearing-message marker on a bubble: "30s", "5m", "1h", "1d",
/// "1w".
String formatDisappearing(int seconds) {
  if (seconds >= 7 * 86400 && seconds % (7 * 86400) == 0) {
    return '${seconds ~/ (7 * 86400)}w';
  }
  if (seconds >= 86400 && seconds % 86400 == 0) return '${seconds ~/ 86400}d';
  if (seconds >= 3600 && seconds % 3600 == 0) return '${seconds ~/ 3600}h';
  if (seconds >= 60 && seconds % 60 == 0) return '${seconds ~/ 60}m';
  return '${seconds}s';
}

/// The sentence for a timer setting: "1 day", "5 minutes".
String describeDisappearing(int? seconds) {
  if (seconds == null || seconds <= 0) return 'Off';
  String unit(int count, String one) =>
      count == 1 ? '1 $one' : '$count ${one}s';
  if (seconds % (7 * 86400) == 0) return unit(seconds ~/ (7 * 86400), 'week');
  if (seconds % 86400 == 0) return unit(seconds ~/ 86400, 'day');
  if (seconds % 3600 == 0) return unit(seconds ~/ 3600, 'hour');
  if (seconds % 60 == 0) return unit(seconds ~/ 60, 'minute');
  return unit(seconds, 'second');
}

/// A day in a date-and-time line: "3 Oct, 14:05" (message info).
String formatDateTime(DateTime at, DateTime now) {
  final local = at.toLocal();
  final days = _daysBetween(local, now.toLocal());
  final clock = formatClock(local);
  if (days == 0) return 'Today, $clock';
  if (days == 1) return 'Yesterday, $clock';
  return '${local.day} ${_months[local.month - 1].substring(0, 3)}, $clock';
}

/// A moment in a log row: "Today, 14:05", "Yesterday, 14:05", "Mon, 14:05"
/// inside the week, then "12 Sep, 14:05" (and the year when it is not this
/// one). The call log, a group's join requests and its bans read it.
String formatWhen(DateTime at, DateTime now) {
  final local = at.toLocal();
  final clock = formatClock(local);
  final days = _daysBetween(local, now.toLocal());
  if (days == 0) return 'Today, $clock';
  if (days == 1) return 'Yesterday, $clock';
  if (days > 1 && days < 7) return '${_weekdayShort(local.weekday)}, $clock';
  final date = '${local.day} ${_months[local.month - 1].substring(0, 3)}';
  return local.year == now.toLocal().year
      ? '$date, $clock'
      : '$date ${local.year}, $clock';
}

/// "5 minutes ago", "Yesterday" - computed against [now] by the caller so a
/// widget never reads a clock. Null is "Never".
String formatAgo(DateTime? at, DateTime now) {
  if (at == null) return 'Never';
  final diff = now.difference(at);
  if (diff.inSeconds < 60) return 'Just now';
  if (diff.inMinutes < 60) {
    final m = diff.inMinutes;
    return m == 1 ? '1 minute ago' : '$m minutes ago';
  }
  if (diff.inHours < 24) {
    final h = diff.inHours;
    return h == 1 ? '1 hour ago' : '$h hours ago';
  }
  final d = diff.inDays;
  return d == 1 ? 'Yesterday' : '$d days ago';
}

int _daysBetween(DateTime day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(day.year, day.month, day.day);
  return today.difference(that).inDays;
}

String _two(int value) => value.toString().padLeft(2, '0');

String _weekdayShort(int weekday) => _weekdayLong(weekday).substring(0, 3);

String _weekdayLong(int weekday) => switch (weekday) {
  DateTime.monday => 'Monday',
  DateTime.tuesday => 'Tuesday',
  DateTime.wednesday => 'Wednesday',
  DateTime.thursday => 'Thursday',
  DateTime.friday => 'Friday',
  DateTime.saturday => 'Saturday',
  _ => 'Sunday',
};

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
