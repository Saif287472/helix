import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The sign-in country picker filters as you type, by name or by code, and a
/// pick closes it and says which code was chosen.
void main() {
  late OrbitTokens orbit;
  setUpAll(() {
    orbit = OrbitTokens.fromThemeJson(
      jsonDecode(File('assets/themes/orbit.json').readAsStringSync())
          as Map<String, Object?>,
    );
  });

  const countries = [
    ('+880', 'Bangladesh'),
    ('+91', 'India'),
    ('+44', 'United Kingdom'),
    ('+1', 'United States / Canada'),
    ('+234', 'Nigeria'),
    ('+94', 'Sri Lanka'),
  ];

  Future<List<String>> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final picked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: OrbitTheme.of(orbit),
        home: Material(
          child: SignInScreen(
            model: const SignInModel(
              step: SignInStep.phone,
              countries: countries,
            ),
            actions: SignInActions(onCountryChanged: picked.add),
            openSheet: SignInSheet.countries,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return picked;
  }

  testWidgets('the whole list shows until something is typed', (tester) async {
    await open(tester);
    for (final (_, name) in countries) {
      expect(find.text(name), findsOneWidget);
    }
  });

  testWidgets('typing part of a name narrows it, from the start of a word', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(TextField).last, 'sri');
    await tester.pumpAndSettle();
    expect(find.text('Sri Lanka'), findsOneWidget);
    expect(find.text('India'), findsNothing);

    await tester.enterText(find.byType(TextField).last, 'canada');
    await tester.pumpAndSettle();
    expect(
      find.text('United States / Canada'),
      findsOneWidget,
      reason: 'a name after a slash is found too',
    );
  });

  testWidgets('a code finds its country, with or without the plus', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byType(TextField).last, '+94');
    await tester.pumpAndSettle();
    expect(find.text('Sri Lanka'), findsOneWidget);
    expect(find.text('Bangladesh'), findsNothing);

    await tester.enterText(find.byType(TextField).last, '234');
    await tester.pumpAndSettle();
    expect(find.text('Nigeria'), findsOneWidget);
  });

  testWidgets('nothing matching says so', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField).last, 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No country matches that.'), findsOneWidget);
  });

  testWidgets('a pick closes the sheet and reports the code', (tester) async {
    final picked = await open(tester);
    await tester.tap(find.text('Nigeria'));
    await tester.pumpAndSettle();
    expect(find.text('Country code'), findsNothing);
    expect(picked, ['+234']);
  });
}
