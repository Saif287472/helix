// Small formatters shared by the settings-side pages. Pure functions of their
// arguments: a widget never reads a clock, so the caller passes `now`.

/// "2.4 MB", for the size of a backup.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  return '${(mb / 1024).toStringAsFixed(1)} GB';
}

/// "5 minutes ago", "Yesterday" - computed against [now] by the caller so a
/// widget never reads a clock.
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
