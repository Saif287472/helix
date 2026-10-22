import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/features/people/application/people_search.dart';

import 'support/people_fakes.dart';

/// The budgets that matter for people: a big address book must not make the
/// search slow. The Orbit people panel builds every row it is given, so the
/// build-count check this file used to make cannot hold on the new look; see
/// `orbit/DEVIATIONS.md`, "The lists are eager".
void main() {
  PeopleDirectory directory(int count) => PeopleDirectory.fromRows([
    for (var i = 0; i < count; i++)
      personRow(
        'acc$i',
        phonebook: 'Person $i',
        phone: '+88017${(10000000 + i).toString()}',
      ),
  ]);

  test('5,000 people filter in one pass, and an empty result is empty', () {
    final big = directory(5000);
    final browse = searchPeople(big, const [], PeopleQuery.parse(''));
    expect(browse.people, hasLength(5000));
    final one = searchPeople(big, const [], PeopleQuery.parse('person 4999'));
    expect(one.people.map((p) => p.accountId), ['acc4999']);
    final none = searchPeople(big, const [], PeopleQuery.parse('zzzz'));
    expect(none.isEmpty, isTrue);
    final byNumber = searchPeople(
      big,
      const [],
      PeopleQuery.parse('1710004999', callingCode: '880'),
    );
    expect(byNumber.people, isNotEmpty);
  });
}
