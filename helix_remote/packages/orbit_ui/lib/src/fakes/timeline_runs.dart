import 'package:orbit_ui/src/models/view_models.dart';

/// [items] with each message's run position, worked out as the prototype's
/// `UI.runPositions` does (`js/ui.js`): a message joins the one right before
/// it when both are from the same side and sender within 5 minutes, and
/// anything between them (a date, a notice) breaks the run.
List<HelixTimelineItem> orbitWithRuns(List<HelixTimelineItem> items) {
  const gapMs = 5 * 60 * 1000;
  bool same(HelixTimelineItem? a, HelixTimelineItem? b) {
    if (a is! HelixMessageItem || b is! HelixMessageItem) return false;
    final x = a.message, y = b.message;
    return x.outgoing == y.outgoing &&
        (x.authorId ?? '') == (y.authorId ?? '') &&
        (y.sentAtMs - x.sentAtMs).abs() <= gapMs;
  }

  return [
    for (final (i, it) in items.indexed)
      if (it is HelixMessageItem)
        HelixMessageItem(
          it.message,
          selected: it.selected,
          position: switch ((
            same(i > 0 ? items[i - 1] : null, it),
            same(it, i + 1 < items.length ? items[i + 1] : null),
          )) {
            (true, true) => HelixRunPosition.middle,
            (true, false) => HelixRunPosition.last,
            (false, true) => HelixRunPosition.first,
            (false, false) => HelixRunPosition.single,
          },
        )
      else
        it,
  ];
}
