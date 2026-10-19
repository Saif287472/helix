import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/people/presentation/people_search_screen.dart';

import 'support/people_fakes.dart';

/// The standalone people search on Orbit: the field over the same panel as
/// the Chats search, which finds people as you type and opens their chat.
void main() {
  late FakePeopleGateway gateway;
  late FakeSeams seams;

  setUp(() {
    gateway = FakePeopleGateway()
      ..put(personRow('mum', phonebook: 'Mum', phone: '+8801711000001'))
      ..put(personRow('sam', nickname: 'Sam Smith', helix: 'sam_s'))
      ..put(personRow('blocked', phonebook: 'Sam Blocked', blocked: true));
    seams = FakeSeams();
  });

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('finds people as you type and opens their chat', (tester) async {
    await pumpPeople(
      tester,
      const PeopleSearchScreen(),
      gateway: gateway,
      seams: seams,
    );
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);

    await type(tester, 'sam');
    expect(find.text('Sam Smith'), findsOneWidget);
    expect(find.text('Mum'), findsNothing);
    // Blocked people are never offered.
    expect(find.text('Sam Blocked'), findsNothing);

    await tester.tap(find.text('Sam Smith'));
    await tester.pump();
    await tester.pump();
    expect(seams.opened, ['direct:sam']);
  });

  testWidgets('nobody who matches says so', (tester) async {
    await pumpPeople(
      tester,
      const PeopleSearchScreen(),
      gateway: gateway,
      seams: seams,
    );
    await tester.pump();
    await type(tester, 'zzz');
    expect(find.text('Sam Smith'), findsNothing);
    expect(find.textContaining('zzz'), findsWidgets);
  });
}
