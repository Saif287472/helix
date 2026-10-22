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
          onCall: ({required bool video}) async {
            placed = video;
            return null;
          },
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
        actions: ContactActions(
          onRename: (v) async {
            name = v;
            return RenameResult.saved;
          },
        ),
      ),
    );
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), ' Nadi ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(name, 'Nadi');
    expect(find.text('Saved.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
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

  group("the app's hooks", () {
    testWidgets('a rename that needs the phone asks, then saves there', (
      tester,
    ) async {
      final saved = <String>[];
      await show(
        tester,
        ContactScreen(
          model: contact(),
          actions: ContactActions(
            onRename: (v) async => RenameResult.needsPhonePermission,
            onSaveToPhoneContacts: (v) async {
              saved.add(v);
              return RenameResult.savedEverywhere;
            },
          ),
        ),
      );
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'Nadi');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Save in your phone contacts too?'), findsOneWidget);
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      expect(saved, ['Nadi']);
      expect(find.text('Saved, and updated in your contacts.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a block that fails says so; a call refused says why', (
      tester,
    ) async {
      await show(
        tester,
        ContactScreen(
          model: contact(),
          actions: ContactActions(
            onBlock: () async => false,
            onCall: ({required video}) async => 'You are already in a call.',
          ),
        ),
      );
      await tester.tap(find.text('Voice call'));
      await tester.pumpAndSettle();
      expect(find.text('You are already in a call.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.scrollUntilVisible(find.text('Block Nadia Rahman'), 200);
      await tester.tap(find.text('Block Nadia Rahman'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      expect(find.textContaining('That did not work'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a scanned code is checked: a mismatch says so', (
      tester,
    ) async {
      final codes = <String>[];
      late ValueChanged<String> read;
      await show(
        tester,
        ScanCodeScreen(
          model: const ScanCodeModel(),
          actions: ScanCodeActions(
            onCode: (text) async {
              codes.add(text);
              return false;
            },
          ),
          camera: (context, onCode) {
            read = onCode;
            return const SizedBox.expand();
          },
        ),
      );
      // No demo buttons over a real camera.
      expect(find.text('Simulate a match'), findsNothing);
      read('wrong');
      // A second code while the first is checked waits.
      read('again');
      await tester.pumpAndSettle();
      expect(codes, ['wrong']);
      expect(find.text('That code does not match'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      read('next');
      await tester.pumpAndSettle();
      expect(codes, ['wrong', 'next']);
    });

    testWidgets('a share code says what a scan of it does', (tester) async {
      var opened = false;
      late ValueChanged<String> read;
      await show(
        tester,
        ScanCodeScreen(
          model: const ScanCodeModel(mode: ScanMode.contact),
          actions: ScanCodeActions(
            onCode: (text) async {
              opened = true;
              return true;
            },
          ),
          camera: (context, onCode) {
            read = onCode;
            return const SizedBox.expand();
          },
        ),
      );
      read('https://helix.agiletechbd.com/u/anna');
      await tester.pumpAndSettle();
      expect(opened, isTrue);
      // Contact mode never speaks of verification: the code names a person,
      // and what happens is that their chat opens.
      expect(find.text('Found them. Opening your chat.'), findsOneWidget);
      expect(find.text('Verified. Your chat is private.'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a code that names nobody is refused, and scanning goes on', (
      tester,
    ) async {
      final codes = <String>[];
      late ValueChanged<String> read;
      await show(
        tester,
        ScanCodeScreen(
          model: const ScanCodeModel(mode: ScanMode.contact),
          actions: ScanCodeActions(
            onCode: (text) async {
              codes.add(text);
              return false;
            },
          ),
          camera: (context, onCode) {
            read = onCode;
            return const SizedBox.expand();
          },
        ),
      );
      read('https://example.com/not-a-helix-code');
      await tester.pumpAndSettle();
      expect(
        find.text('That is not a share code'),
        findsOneWidget,
        reason: 'not the safety number’s words',
      );
      expect(find.text('That code does not match'), findsNothing);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      read('https://helix.agiletechbd.com/u/anna');
      await tester.pumpAndSettle();
      expect(codes, [
        'https://example.com/not-a-helix-code',
        'https://helix.agiletechbd.com/u/anna',
      ]);
    });

    testWidgets('people search can draw the whole people panel', (
      tester,
    ) async {
      final typed = <String>[];
      var looked = 0;
      await show(
        tester,
        PeopleSearchScreen(
          model: const PeopleSearchModel(
            panel: PeoplePanelModel(mode: PeopleSearchMode.chats),
          ),
          actions: PeopleSearchActions(
            panel: PeoplePanelActions(
              onQueryChanged: typed.add,
              onLookUp: () => looked++,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(EditableText), '~nadia');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(typed, ['~nadia']);
      expect(looked, 1);
    });
  });
}
