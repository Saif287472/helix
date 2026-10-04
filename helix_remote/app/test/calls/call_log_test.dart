import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/people/name_lookup.dart';
import 'package:helix_remote/features/calls/application/call_copy.dart';
import 'package:helix_remote/features/calls/application/call_log.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import '../support/call_support.dart';

/// The call log as the Calls tab shows it: the engine's rows mapped to the UI
/// package's items, folded, named by the people-naming order and dated.
void main() {
  final now = DateTime(2026, 10, 3, 15, 30);

  PeopleNames names() => const PeopleNames({
    'peer-1': HelixPersonNames(
      phoneBookName: 'Ada Lovelace',
      number: '+8801711000001',
    ),
    'peer-2': HelixPersonNames(nickname: 'Bob', number: '+8801711000002'),
    'peer-3': HelixPersonNames(number: '+8801711000003'),
    'peer-4': HelixPersonNames(helixName: 'carol'),
  });

  group('direction', () {
    test('an outgoing answered call is outgoing, with its duration', () {
      final entries = buildCallLog(
        [
          logRow(
            'a',
            at: DateTime(2026, 10, 3, 14, 5),
            answeredAfterSeconds: 4,
            talkSeconds: 252,
          ),
        ],
        names(),
        now,
      );
      expect(entries.single.item.direction, HelixCallDirection.outgoing);
      expect(entries.single.item.durationLabel, '04:12');
    });

    test('an incoming call nobody answered is missed', () {
      final entries = buildCallLog(
        [
          logRow(
            'a',
            direction: 'incoming',
            state: 'ended',
            at: DateTime(2026, 10, 3, 14, 5),
          ),
        ],
        names(),
        now,
      );
      expect(entries.single.item.direction, HelixCallDirection.missed);
      expect(entries.single.item.durationLabel, isNull);
    });

    test('a call the table marks missed is missed, even if outgoing', () {
      final entries = buildCallLog(
        [logRow('a', direction: 'missed', at: DateTime(2026, 10, 3, 14))],
        names(),
        now,
      );
      expect(entries.single.item.direction, HelixCallDirection.missed);
    });

    test('declined and failed calls are their own rows', () {
      final entries = buildCallLog(
        [
          logRow(
            'a',
            state: 'declined',
            at: DateTime(2026, 10, 3, 14),
            peer: 'peer-1',
          ),
          logRow(
            'b',
            state: 'failed',
            at: DateTime(2026, 10, 3, 13),
            peer: 'peer-2',
          ),
        ],
        names(),
        now,
      );
      expect(entries[0].item.direction, HelixCallDirection.declined);
      expect(entries[1].item.direction, HelixCallDirection.failed);
    });

    test('an outgoing call nobody answered is still an outgoing row', () {
      final entries = buildCallLog(
        [logRow('a', state: 'unanswered', at: DateTime(2026, 10, 3, 14))],
        names(),
        now,
      );
      expect(entries.single.item.direction, HelixCallDirection.outgoing);
    });

    test('the detail page keeps the finer outcome', () {
      expect(
        detailDirectionOf(
          logRow('a', state: 'unanswered', at: DateTime(2026, 10, 3)),
        ),
        CallLogDirection.noAnswer,
      );
      expect(
        detailDirectionOf(
          logRow('a', state: 'cancelled', at: DateTime(2026, 10, 3)),
        ),
        CallLogDirection.cancelled,
      );
      expect(
        detailDirectionOf(
          logRow(
            'a',
            direction: 'incoming',
            state: 'cancelled',
            at: DateTime(2026, 10, 3),
          ),
        ),
        CallLogDirection.missed,
      );
    });
  });

  group('folding', () {
    test('consecutive calls with one person, one way, one day are one row', () {
      final entries = buildCallLog(
        [
          logRow(
            'c',
            at: DateTime(2026, 10, 3, 14),
            answeredAfterSeconds: 1,
            talkSeconds: 5,
          ),
          logRow(
            'b',
            at: DateTime(2026, 10, 3, 12),
            answeredAfterSeconds: 1,
            talkSeconds: 5,
          ),
          logRow(
            'a',
            at: DateTime(2026, 10, 3, 9),
            answeredAfterSeconds: 1,
            talkSeconds: 5,
          ),
        ],
        names(),
        now,
      );
      expect(entries, hasLength(1));
      expect(entries.single.item.count, 3);
      expect(entries.single.callIds, ['c', 'b', 'a']);
      // The newest call names the row; a folded row has no single duration.
      expect(entries.single.id, 'c');
      expect(entries.single.item.durationLabel, isNull);
    });

    test('a different person, direction or day breaks the run', () {
      final entries = buildCallLog(
        [
          logRow('d', at: DateTime(2026, 10, 3, 14), peer: 'peer-1'),
          logRow('c', at: DateTime(2026, 10, 3, 13), peer: 'peer-2'),
          logRow(
            'b',
            at: DateTime(2026, 10, 3, 12),
            peer: 'peer-2',
            direction: 'incoming',
            state: 'declined',
          ),
          logRow(
            'a',
            at: DateTime(2026, 10, 2, 12),
            peer: 'peer-2',
            direction: 'incoming',
            state: 'declined',
          ),
        ],
        names(),
        now,
      );
      expect(entries.map((e) => e.callIds), [
        ['d'],
        ['c'],
        ['b'],
        ['a'],
      ]);
    });
  });

  group('naming', () {
    test('follows the order phone book, nickname, number, ~Helix name', () {
      final entries = buildCallLog(
        [
          logRow('a', peer: 'peer-1', at: DateTime(2026, 10, 3, 14)),
          logRow('b', peer: 'peer-2', at: DateTime(2026, 10, 3, 13)),
          logRow('c', peer: 'peer-3', at: DateTime(2026, 10, 3, 12)),
          logRow('d', peer: 'peer-4', at: DateTime(2026, 10, 3, 11)),
        ],
        names(),
        now,
      );
      expect(entries.map((e) => e.item.title), [
        'Ada Lovelace',
        'Bob',
        '+8801711000003',
        '~carol',
      ]);
    });

    test('an unknown person shows the name the log kept, as a ~name', () {
      final entries = buildCallLog(
        [
          logRow(
            'a',
            peer: 'stranger',
            at: DateTime(2026, 10, 3, 14),
            name: 'Dan',
          ),
        ],
        names(),
        now,
      );
      expect(entries.single.item.title, '~Dan');
    });

    test('a person nothing is known about is a Helix user', () {
      final entries = buildCallLog(
        [logRow('a', peer: 'stranger', at: DateTime(2026, 10, 3, 14))],
        names(),
        now,
      );
      expect(entries.single.item.title, 'Helix user');
    });
  });

  group('time labels', () {
    test('today, yesterday, weekday, date, and another year', () {
      expect(callTimeLabel(DateTime(2026, 10, 3, 14, 5), now), 'Today, 14:05');
      expect(
        callTimeLabel(DateTime(2026, 10, 2, 9, 7), now),
        'Yesterday, 09:07',
      );
      expect(callTimeLabel(DateTime(2026, 9, 30, 9, 7), now), 'Wed, 09:07');
      expect(callTimeLabel(DateTime(2026, 9, 12, 18, 0), now), '12 Sep, 18:00');
      expect(
        callTimeLabel(DateTime(2025, 12, 31, 23, 59), now),
        '31 Dec 2025, 23:59',
      );
    });

    test('durations read as m:ss and h:mm:ss', () {
      expect(formatCallDuration(const Duration(seconds: 7)), '00:07');
      expect(
        formatCallDuration(const Duration(minutes: 4, seconds: 12)),
        '04:12',
      );
      expect(
        formatCallDuration(const Duration(hours: 1, minutes: 4, seconds: 9)),
        '1:04:09',
      );
      expect(
        spokenCallDuration(const Duration(hours: 1, minutes: 4, seconds: 9)),
        '1 hr 4 min 9 sec',
      );
      expect(spokenCallDuration(Duration.zero), '0 sec');
    });
  });
}
