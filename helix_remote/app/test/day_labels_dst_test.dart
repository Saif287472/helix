import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/chat/search_snippet.dart';
import 'package:helix_remote/core/format/labels.dart';

/// A calendar day is a calendar day across a clock change (AUD-14i-1), and a
/// search snippet starts on a whole character (AUD-14i-2).
///
/// The first group only means something in a zone that changes its clocks
/// between the dates it uses, so it skips itself elsewhere. CI runs it with
/// `TZ=America/New_York` and `TZ=Australia/Sydney` (`ci.yml`); a Windows
/// development machine does not honour `TZ`, so there it proves nothing.
void main() {
  /// Whether the process zone's offset differs between the two days.
  bool changes(DateTime a, DateTime b) => a.timeZoneOffset != b.timeZoneOffset;

  void acrossSpringForward(String zone, DateTime before, DateTime after) {
    final skip = changes(before, after)
        ? null
        : 'this zone has no clock change between these dates (TZ=$zone)';

    test('yesterday is yesterday the day after the clocks went forward', () {
      // 23 hours between the two midnights: `.inDays` of that is 0.
      final message = DateTime(before.year, before.month, before.day, 12);
      final read = DateTime(after.year, after.month, after.day, 10);
      expect(formatChatTime(message, read), 'Yesterday');
    }, skip: skip);

    test('two days ago is not yesterday', () {
      final message = DateTime(before.year, before.month, before.day - 1, 12);
      final read = DateTime(after.year, after.month, after.day, 10);
      expect(formatChatTime(message, read), isNot('Yesterday'));
    }, skip: skip);

    test('the same day is still the same day', () {
      final message = DateTime(after.year, after.month, after.day, 8, 15);
      final read = DateTime(after.year, after.month, after.day, 10);
      expect(formatChatTime(message, read), '08:15');
    }, skip: skip);
  }

  group('a day label across a spring clock change', () {
    // America/New_York springs forward on 2026-03-08, Australia/Sydney on
    // 2026-10-04 (both at the zone's 02:00).
    acrossSpringForward(
      'America/New_York',
      DateTime(2026, 3, 8, 12),
      DateTime(2026, 3, 9, 12),
    );
    acrossSpringForward(
      'Australia/Sydney',
      DateTime(2026, 10, 4, 12),
      DateTime(2026, 10, 5, 12),
    );
  });

  group('a snippet', () {
    test('never begins with half a character', () {
      final text = '${'😀' * 11}.needle';
      final snippet = snippetFor(text, 'needle');
      final shown = snippet.text;
      expect(shown.startsWith('...'), isTrue);
      final first = shown.substring(3).runes.first;
      expect(first, 0x1F600, reason: 'a whole emoji, not a lone low half');
      for (final range in snippet.ranges) {
        expect(
          shown.substring(range.start, range.start + range.length),
          'needle',
        );
      }
      expect(snippet.ranges, hasLength(1));
    });

    test('a cut between ordinary characters is unchanged', () {
      final snippet = snippetFor('${'a' * 30} needle here', 'needle');
      expect(snippet.text, startsWith('...'));
      expect(snippet.text.substring(3), startsWith('a' * 19));
    });
  });
}
