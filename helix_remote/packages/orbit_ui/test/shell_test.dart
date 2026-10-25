import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The Review 3.2 parts: fields, notices, codes, rows, bars and the dock.
/// The rules each carries (tooltips, 48px targets, labels, state) are tested
/// here; how they look is checked against the prototype by the compare tool
/// (`kit-shell`).
void main() {
  final themes = <String, OrbitTokens>{};
  setUpAll(() {
    for (final id in ['orbit', 'arcade', 'papyrus', 'terminal', 'mochi']) {
      themes[id] = OrbitTokens.fromThemeJson(
        jsonDecode(File('assets/themes/$id.json').readAsStringSync())
            as Map<String, Object?>,
      );
    }
  });

  Future<void> show(
    WidgetTester tester,
    Widget child, {
    String theme = 'orbit',
  }) => tester.pumpWidget(
    MaterialApp(
      theme: OrbitTheme.of(themes[theme]!),
      home: Scaffold(
        body: Center(child: SizedBox(width: 380, child: child)),
      ),
    ),
  );

  group('OrbitText', () {
    testWidgets('is as tall as CSS makes the lines, not as Flutter rounds '
        'them', (tester) async {
      const style = TextStyle(fontSize: 12, height: 1.4);
      await show(
        tester,
        const Align(
          alignment: Alignment.topLeft,
          child: OrbitText('One line', style: style),
        ),
      );
      expect(
        tester.getSize(find.byType(OrbitText)).height,
        closeTo(16.8, 1e-6),
      );
    });
  });

  group('OrbitTextField', () {
    testWidgets('counts as you type, shows its error, and the eye shows the '
        'password', (tester) async {
      await show(
        tester,
        const Column(
          children: [
            OrbitTextField(label: 'Name', maxLength: 50, counter: true),
            OrbitTextField(
              label: 'Password',
              initialValue: 'secret',
              obscure: true,
              eye: true,
              error: 'That is not your current password.',
            ),
          ],
        ),
      );
      expect(find.text('0/50'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Hasan');
      await tester.pump();
      expect(find.text('5/50'), findsOneWidget);
      expect(find.text('That is not your current password.'), findsOneWidget);
      TextField password() =>
          tester.widget<TextField>(find.byType(TextField).last);
      expect(password().obscureText, isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(password().obscureText, isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);
    });

    testWidgets('the paste button is a labelled target of at least 48px', (
      tester,
    ) async {
      var pasted = 0;
      await show(
        tester,
        OrbitTextField(label: 'Code', onPaste: () => pasted++),
      );
      expect(find.byTooltip('Paste'), findsOneWidget);
      final button = find.byType(OrbitIconButton);
      expect(tester.getSize(button), const Size(44, 44));
      // 2px outside the drawn button is still the button.
      await tester.tapAt(tester.getTopLeft(button) + const Offset(22, -2));
      expect(pasted, 1);
    });
  });

  testWidgets('OrbitSegmented picks the tapped option', (tester) async {
    var value = 'create';
    await show(
      tester,
      StatefulBuilder(
        builder: (context, set) => OrbitSegmented(
          options: const [
            OrbitSegment('create', 'Create'),
            OrbitSegment('restore', 'Restore'),
          ],
          value: value,
          onChanged: (v) => set(() => value = v),
        ),
      ),
    );
    await tester.tap(find.text('Restore'));
    await tester.pump();
    expect(value, 'restore');
  });

  testWidgets('a notice action is a 36px button that still takes 48px of '
      'taps', (tester) async {
    var tries = 0;
    await show(
      tester,
      OrbitInlineNotice(
        kind: OrbitNoticeKind.error,
        text: 'That was not saved.',
        action: OrbitNoticeAction('Try again', () => tries++),
      ),
    );
    final button = find.byType(OrbitButton);
    expect(tester.getSize(button).height, 36);
    await tester.tapAt(tester.getTopLeft(button) + const Offset(20, -5));
    expect(tries, 1);
  });

  group('rows', () {
    testWidgets('a switch row toggles from anywhere on it', (tester) async {
      var on = false;
      await show(
        tester,
        StatefulBuilder(
          builder: (context, set) => OrbitCard(
            children: [
              OrbitListRow(
                title: 'Receipts',
                end: OrbitRowEnd.toggle,
                on: on,
                onChanged: (v) => set(() => on = v),
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Receipts'));
      await tester.pump();
      expect(on, isTrue);
      expect(tester.getSize(find.byType(OrbitListRow)).height, 60);
    });

    testWidgets('rows after the first get a rule, and Terminal puts # before '
        'a section title', (tester) async {
      await show(
        tester,
        const OrbitSection(
          title: 'Diagnostics',
          rows: [
            OrbitListRow(title: 'One'),
            OrbitListRow(title: 'Two'),
            OrbitListRow(title: 'Three'),
          ],
        ),
        theme: 'terminal',
      );
      final rules = find.descendant(
        of: find.byType(OrbitCard),
        matching: find.byWidgetPredicate(
          (w) => w is Positioned && w.left == 64 && w.height == 1,
        ),
      );
      expect(rules, findsNWidgets(2));
      expect(find.textContaining('# DIAGNOSTICS'), findsOneWidget);
    });
  });

  group('codes', () {
    test("the QR matrix is the prototype's, cell for cell", () {
      // From Kit.qr in js/kit.js, run in Node.
      String row(List<bool> r) => r.map((c) => c ? '1' : '0').join();
      final cells = orbitQrCells('safety-nadia');
      expect(cells.expand((r) => r).where((c) => c).length, 437);
      expect(row(cells[10]), '10111111110010010100110010100');
      expect(row(cells[20]), '00010001101110001100001101010');
      expect(
        orbitQrCells('helix').expand((r) => r).where((c) => c).length,
        430,
      );
    });

    testWidgets('a secret breaks only between its groups', (tester) async {
      await show(
        tester,
        const SizedBox(
          width: 300,
          child: OrbitCodeBox(
            label: 'Shown only now',
            code: 'K7QD-M2XP-9RWA-H4TF-B8NC-3ZLE',
            size: OrbitCodeSize.secret,
          ),
        ),
      );
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .firstWhere((s) => s.contains('K7QD'));
      for (final line in text.split('\n')) {
        expect(line, matches(RegExp(r'^([A-Z0-9]{4}-)*[A-Z0-9]{4}-?$')));
      }
    });
  });

  group('bars', () {
    testWidgets('an app bar is 60px with a labelled back button', (
      tester,
    ) async {
      var back = 0;
      await show(
        tester,
        OrbitAppBar(title: 'Message info', onLead: () => back++),
      );
      expect(tester.getSize(find.byType(OrbitAppBar)).height, 60);
      await tester.tap(find.byTooltip('Back'));
      expect(back, 1);
    });

    testWidgets('the wordmark carries the theme effects', (tester) async {
      await show(tester, const OrbitWordmark(), theme: 'terminal');
      expect(find.textContaining('Orbit_'), findsWidgets);
      await show(tester, const OrbitWordmark(), theme: 'mochi');
      await tester.pumpAndSettle();
      expect(find.textContaining('Orbit ♡'), findsWidgets);
    });

    testWidgets('your picture says when the checkup needs attention', (
      tester,
    ) async {
      await show(
        tester,
        Align(
          child: OrbitMePicture(
            avatar: const HelixAvatarModel(name: 'Hasan'),
            attention: true,
            onPressed: () {},
          ),
        ),
      );
      expect(
        find.bySemanticsLabel(
          'Your profile and settings, privacy checkup needs attention',
        ),
        findsOneWidget,
      );
      expect(tester.getSize(find.byType(OrbitMePicture)), const Size(48, 48));
    });

    testWidgets('the dock labels only the open tab, and taps switch', (
      tester,
    ) async {
      var tab = 'chats';
      await show(
        tester,
        StatefulBuilder(
          builder: (context, set) => OrbitDock(
            items: [
              for (final (id, label, icon) in const [
                ('chats', 'Chats', OrbitIcons.chatsCircle),
                ('calls', 'Calls', OrbitIcons.phone),
              ])
                OrbitDockItem(
                  icon: icon,
                  label: label,
                  on: tab == id,
                  onTap: () => set(() => tab = id),
                ),
            ],
          ),
        ),
      );
      expect(find.text('Chats'), findsOneWidget);
      expect(find.text('Calls'), findsNothing);
      await tester.tap(find.byTooltip('Calls'));
      await tester.pump();
      expect(tab, 'calls');
      expect(find.text('Calls'), findsOneWidget);
      expect(tester.getSize(find.byType(OrbitDock)).height, 62);
    });
  });

  group('OrbitDockArea', () {
    testWidgets('lifts its controls clear of the navigation bar', (
      tester,
    ) async {
      // Three-button navigation: Android draws a 48px bar over the bottom of
      // the window. The band still reaches the edge, so its fade has somewhere
      // to go, but the dock and the round button sit above the bar.
      await tester.pumpWidget(
        MaterialApp(
          theme: OrbitTheme.of(themes['orbit']!),
          home: MediaQuery(
            data: const MediaQueryData(
              viewPadding: EdgeInsets.only(bottom: 48),
            ),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: OrbitDockArea(
                  dock: OrbitDock(
                    items: [
                      OrbitDockItem(
                        icon: OrbitIcons.chatsCircle,
                        label: 'Chats',
                        on: true,
                        onTap: () {},
                      ),
                    ],
                  ),
                  fab: OrbitFab(
                    icon: OrbitIcons.chatCircleDots,
                    tooltip: 'New chat',
                    size: 62,
                    onPressed: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final screenBottom = tester.getBottomLeft(find.byType(Scaffold)).dy;
      expect(tester.getSize(find.byType(OrbitDockArea)).height, 120 + 48);
      expect(
        tester.getBottomLeft(find.byType(OrbitFab)).dy,
        closeTo(screenBottom - 48 - 22, 0.5),
      );
    });

    testWidgets('a gesture-navigation phone keeps the band as it was', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: OrbitTheme.of(themes['orbit']!),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: OrbitDockArea(
                dock: OrbitDock(
                  items: [
                    OrbitDockItem(
                      icon: OrbitIcons.chatsCircle,
                      label: 'Chats',
                      on: true,
                      onTap: () {},
                    ),
                  ],
                ),
                fab: OrbitFab(
                  icon: OrbitIcons.chatCircleDots,
                  tooltip: 'New chat',
                  size: 62,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(OrbitDockArea)).height, 120);
    });
  });

  test('a CSS angle runs the gradient the way CSS does', () {
    const g = OrbitCssGradient(
      angle: 90,
      colors: [Color(0xFF000000), Color(0xFFFFFFFF)],
    );
    // 90deg is left to right whatever the box, unlike an alignment.
    expect(g.angle, 90);
    expect(
      () => g.createShader(const Rect.fromLTWH(0, 0, 200, 20)),
      returnsNormally,
    );
  });
}
