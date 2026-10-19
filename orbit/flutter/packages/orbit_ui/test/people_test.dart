import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Phase 4 batch 6: contact info, the safety number, the scanner and people
/// search. How they look is checked against the prototype by the compare
/// tool.
void main() {
  late OrbitTokens orbit;
  setUpAll(() {
    orbit = OrbitTokens.fromThemeJson(
      jsonDecode(File('assets/themes/orbit.json').readAsStringSync())
          as Map<String, Object?>,
    );
  });

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(412, 866);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(412, 866),
          disableAnimations: true,
        ),
        child: MaterialApp(
          theme: OrbitTheme.of(orbit),
          home: Scaffold(body: screen),
        ),
      ),
    );
    await tester.pump();
  }

  ContactModel contact({
    TrustState trust = TrustState.unverified,
    bool blockedByThem = false,
    bool blocked = false,
  }) => ContactModel(
    accountId: 'nadia',
    name: 'Nadia Rahman',
    avatar: const HelixAvatarModel(name: 'Nadia Rahman'),
    secondary: '+880 1712-458921',
    numberLabel: '+880 1712-458921',
    trust: trust,
    blocked: blocked,
    blockedByThem: blockedByThem,
    commonGroups: const [(id: 'group:design', title: 'Design team')],
  );

  testWidgets('contact info places calls and lists groups in common', (
    tester,
  ) async {
    bool? placed;
    String? group;
    await show(
      tester,
      ContactScreen(
        model: contact(),
        actions: ContactActions(
          onCall: ({required bool video}) => placed = video,
          onOpenGroup: (g) => group = g,
        ),
      ),
    );
    await tester.tap(find.text('Video call'));
    expect(placed, isTrue);
    await tester.scrollUntilVisible(find.text('Design team'), 200);
    await tester.tap(find.text('Design team'));
    expect(group, 'group:design');
  });

  testWidgets('someone who blocked you: no call tiles, and why', (
    tester,
  ) async {
    await show(tester, ContactScreen(model: contact(blockedByThem: true)));
    expect(find.text('Voice call'), findsNothing);
    expect(find.textContaining('has blocked you.'), findsOneWidget);
  });

  testWidgets('a changed key shows the banner with Review', (tester) async {
    var reviewed = 0;
    await show(
      tester,
      ContactScreen(
        model: contact(trust: TrustState.keyChanged),
        actions: ContactActions(onOpenSafetyNumber: () => reviewed++),
      ),
    );
    expect(find.text('Safety number changed'), findsWidgets);
    await tester.tap(find.text('Review'));
    expect(reviewed, 1);
  });

  testWidgets('Rename saves through a dialog', (tester) async {
    String? name;
    await show(
      tester,
      ContactScreen(
        model: contact(),
        actions: ContactActions(onRename: (v) => name = v),
      ),
    );
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), ' Nadi ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(name, 'Nadi');
  });

  testWidgets('the safety number shows 60 digits and toggles verified', (
    tester,
  ) async {
    bool? verified;
    await show(
      tester,
      SafetyNumberScreen(
        model: SafetyNumberModel(
          name: 'Arif',
          groups: List.generate(12, (i) => '${10000 + i}'),
        ),
        actions: SafetyNumberActions(onSetVerified: (v) => verified = v),
      ),
    );
    expect(find.text('10000'), findsOneWidget);
    expect(find.text('10011'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Mark as verified'), 200);
    await tester.tap(find.text('Mark as verified'));
    expect(verified, isTrue);
  });

  testWidgets('no key yet: the safety number says to send a message', (
    tester,
  ) async {
    await show(
      tester,
      const SafetyNumberScreen(
        model: SafetyNumberModel(name: 'Sadia', trust: TrustState.noKey),
      ),
    );
    expect(find.text('No safety number yet'), findsOneWidget);
  });

  testWidgets('the scanner explains a missing or refused camera', (
    tester,
  ) async {
    await show(
      tester,
      const ScanCodeScreen(
        model: ScanCodeModel(mode: ScanMode.contact, hasCamera: false),
      ),
    );
    expect(find.textContaining('Orbit link instead'), findsOneWidget);
    await show(
      tester,
      const ScanCodeScreen(model: ScanCodeModel(cameraRefused: true)),
    );
    expect(find.text('Open settings'), findsOneWidget);
  });

  testWidgets('people search filters as you type', (tester) async {
    await show(
      tester,
      PeopleSearchScreen(
        model: PeopleSearchModel(
          people: [OrbitFakes.people['nadia']!, OrbitFakes.people['arif']!],
        ),
      ),
    );
    expect(find.text('Arif Hossain'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'nad');
    await tester.pump();
    expect(find.text('Arif Hossain'), findsNothing);
    expect(find.text('Nadia Rahman'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'zz');
    await tester.pump();
    expect(find.text('No matches'), findsOneWidget);
  });
}
