import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The Review 3.3 parts: the overlays and the state kit. What they do is
/// tested here; how they look is checked against the prototype by the
/// compare tool (`kit-overlays-*` and `state-kit`).
void main() {
  late OrbitTokens orbit;
  setUpAll(() {
    orbit = OrbitTokens.fromThemeJson(
      jsonDecode(File('assets/themes/orbit.json').readAsStringSync())
          as Map<String, Object?>,
    );
  });

  /// A page with one button that runs [open] with the page's context.
  Future<void> page(
    WidgetTester tester,
    void Function(BuildContext) open,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OrbitTheme.of(orbit),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('a sheet closes when a row is picked, then runs it', (
    tester,
  ) async {
    var picked = '';
    await page(
      tester,
      (context) => showOrbitSheet(
        context,
        title: 'Mute notifications',
        items: [
          for (final o in const ['8 hours', '1 week', 'Always'])
            OrbitMenuItem(
              icon: OrbitIcons.bellSlash,
              label: o,
              onTap: () => picked = o,
            ),
        ],
      ),
    );
    expect(find.text('Mute notifications'), findsOneWidget);
    await tester.tap(find.text('1 week'));
    await tester.pumpAndSettle();
    expect(find.text('Mute notifications'), findsNothing);
    await tester.pump(const Duration(milliseconds: 60));
    expect(picked, '1 week');
  });

  testWidgets('the chosen row of a choice sheet is ticked', (tester) async {
    await page(
      tester,
      (context) => showOrbitSheet(
        context,
        title: 'Disappearing messages',
        items: const [
          OrbitMenuItem(icon: OrbitIcons.timer, label: 'Off', on: true),
          OrbitMenuItem(icon: OrbitIcons.timer, label: '1 day'),
        ],
      ),
    );
    expect(find.byIcon(OrbitIcons.check.bold), findsOneWidget);
  });

  testWidgets('tapping the scrim closes a sheet', (tester) async {
    await page(
      tester,
      (context) => showOrbitSheet(
        context,
        title: 'Group picture',
        items: const [
          OrbitMenuItem(icon: OrbitIcons.image, label: 'Choose a picture'),
        ],
      ),
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Group picture'), findsNothing);
  });

  testWidgets('a menu has its rules and closes on a pick', (tester) async {
    var opened = false;
    await page(
      tester,
      (context) => showOrbitMenu(context, [
        const OrbitMenuItem(icon: OrbitIcons.usersThree, label: 'New group'),
        OrbitMenuItem.divider,
        OrbitMenuItem(
          icon: OrbitIcons.archive,
          label: 'Archived chats (3)',
          onTap: () => opened = true,
        ),
      ]),
    );
    await tester.tap(find.text('Archived chats (3)'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 60));
    expect(opened, isTrue);
    expect(find.text('New group'), findsNothing);
  });

  testWidgets("a dialog's buttons close it and run their action", (
    tester,
  ) async {
    var deleted = false;
    await page(
      tester,
      (context) => showOrbitDialog(
        context,
        title: 'Delete this chat?',
        actions: [
          const OrbitDialogAction('Cancel'),
          OrbitDialogAction(
            'Delete',
            kind: OrbitButtonKind.danger,
            onPressed: () => deleted = true,
          ),
        ],
      ),
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this chat?'), findsNothing);
    expect(deleted, isFalse);
  });

  testWidgets('an input dialog gives back what was typed', (tester) async {
    String? name;
    await page(
      tester,
      (context) => showOrbitInputDialog(
        context,
        title: 'Rename',
        label: 'Name',
        value: 'Nadia',
        onConfirm: (v) => name = v,
      ),
    );
    await tester.enterText(find.byType(TextField), 'Nadia R');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 60));
    expect(name, 'Nadia R');
  });

  testWidgets('a toast goes after 2.8s, and its action runs and hides it', (
    tester,
  ) async {
    await page(tester, (context) => showOrbitToast(context, 'Chat muted'));
    expect(find.text('Chat muted'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2900));
    expect(find.text('Chat muted'), findsNothing);

    var undone = false;
    await page(
      tester,
      (context) => showOrbitToast(
        context,
        'Chat archived',
        actionLabel: 'Undo',
        onAction: () => undone = true,
      ),
    );
    await tester.tap(find.text('UNDO'));
    await tester.pump();
    expect(undone, isTrue);
    expect(find.text('Chat archived'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('an error toast is marked and stays longer', (tester) async {
    await page(
      tester,
      (context) => showOrbitToast(context, 'Not sent', error: true),
    );
    expect(find.byIcon(OrbitIcons.warningCircle.fill), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 3000));
    expect(find.text('Not sent'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('Not sent'), findsNothing);
  });

  group('the state kit', () {
    Future<void> show(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        theme: OrbitTheme.of(orbit),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

    testWidgets('a skeleton says what is loading', (tester) async {
      await show(tester, const OrbitSkeleton(count: 3, label: 'Loading chats'));
      expect(find.bySemanticsLabel('Loading chats'), findsOneWidget);
    });

    testWidgets('a failed load offers Try again', (tester) async {
      var tries = 0;
      await show(
        tester,
        OrbitLoadFailed(
          title: 'Your chats could not be loaded.',
          onRetry: () => tries++,
        ),
      );
      await tester.tap(find.text('Try again'));
      expect(tries, 1);
    });

    testWidgets('a permission card asks, and after a refusal opens settings', (
      tester,
    ) async {
      await show(
        tester,
        const Column(
          children: [
            OrbitPermissionCard(kind: OrbitPermission.contacts),
            OrbitPermissionCard(kind: OrbitPermission.camera, denied: true),
          ],
        ),
      );
      expect(find.text('Allow your contacts'), findsOneWidget);
      expect(find.text('Allow'), findsOneWidget);
      expect(find.text('Orbit can’t use your camera'), findsOneWidget);
      expect(find.text('Open settings'), findsOneWidget);
    });
  });
}
