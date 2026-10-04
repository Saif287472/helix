import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/features/people/application/people_search.dart';
import 'package:helix_remote/shared/widgets/people_search_panel.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import 'support/people_fakes.dart';

/// The budgets that matter for people: a big address book must not make the
/// search slow or the lists build every row. Relative checks (how much was
/// built, how much work was done), not wall-clock asserts.
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

  testWidgets('a 5,000-person list builds only the rows on screen', (
    tester,
  ) async {
    final gateway = FakePeopleGateway();
    for (var i = 0; i < 5000; i++) {
      gateway.people['acc$i'] = personRow('acc$i', phonebook: 'Person $i');
    }
    await pumpPeople(
      tester,
      const PeopleSearchPanel(query: ''),
      gateway: gateway,
    );
    expect(find.byType(HelixPersonTile).evaluate().length, lessThan(60));
    expect(find.byType(HelixPersonTile), findsWidgets);
  });
}
