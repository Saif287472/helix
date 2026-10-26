import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/people/people_names.dart';
import 'package:helix_remote/features/chats/application/chat_search.dart';
import 'package:orbit_ui/models.dart';

import 'support/names_support.dart';

/// A group is found by its own name or by the name of someone in it.
void main() {
  final people = PeopleDirectory({
    ...directoryOf({
      'sam': const HelixPersonNames(phoneBookName: 'Sam Rahman'),
      'nadia': const HelixPersonNames(nickname: 'Nad'),
    }).byId,
    'me': const PersonName(
      accountId: 'me',
      names: HelixPersonNames(phoneBookName: 'Me Myself'),
      display: 'Me Myself',
      isSelf: true,
    ),
  });

  test('a member is found by the name shown for them', () {
    expect(memberNamed(['sam', 'nadia'], people, 'rahman'), isTrue);
    expect(memberNamed(['sam', 'nadia'], people, 'nad'), isTrue);
  });

  test('nobody in the group has that name', () {
    expect(memberNamed(['nadia'], people, 'sam'), isFalse);
    expect(memberNamed(const [], people, 'sam'), isFalse);
  });

  test('your own name finds nothing, so every group is not "yours"', () {
    expect(memberNamed(['me', 'nadia'], people, 'myself'), isFalse);
  });
}
