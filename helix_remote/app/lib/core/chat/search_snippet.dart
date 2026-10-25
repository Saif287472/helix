import 'package:orbit_ui/models.dart';

/// A short piece of [text] around the first word of [query] that matches, with
/// every matching word marked.
HelixHighlightedText snippetFor(String text, String query) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final words = RegExp(
    r'[\p{L}\p{N}\p{M}]+',
    unicode: true,
  ).allMatches(query.toLowerCase()).map((m) => m[0]!).toList();
  if (words.isEmpty) return HelixHighlightedText(flat);
  final lower = flat.toLowerCase();
  var first = -1;
  for (final word in words) {
    final at = lower.indexOf(word);
    if (at >= 0 && (first < 0 || at < first)) first = at;
  }
  // Show a little context before the first hit, so the match is not at the
  // far edge of a one-line row.
  var start = first > 20 ? first - 20 : 0;
  // Never cut a character in two: a cut between the halves of a surrogate pair
  // would begin the row with a lone low half (AUD-14i-2). The whole character
  // is kept.
  if (start > 0 && _isLowSurrogate(flat.codeUnitAt(start))) start--;
  final shown = start == 0 ? flat : '...${flat.substring(start)}';
  final shift = start == 0 ? 0 : 3 - start;
  final ranges = <HelixTextRange>[];
  for (final word in words) {
    var from = 0;
    while (true) {
      final at = lower.indexOf(word, from);
      if (at < 0) break;
      final shiftedStart = at + shift;
      if (shiftedStart >= (start == 0 ? 0 : 3)) {
        ranges.add(HelixTextRange(shiftedStart, word.length));
      }
      from = at + word.length;
    }
  }
  ranges.sort((a, b) => a.start.compareTo(b.start));
  return HelixHighlightedText(shown, ranges);
}

bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;
