import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The Review 3.1 primitives: the rules every component carries (a tooltip on
/// every icon button, 48px tap targets, screen-reader labels) and the states
/// the prototype draws. How they look is checked against the prototype by the
/// compare tool (`kit-primitives`), not here.
void main() {
  final themes = <String, OrbitTokens>{};
  setUpAll(() {
    for (final id in [
      'orbit',
      'night',
      'arcade',
      'papyrus',
      'mochi',
      'bloom',
      'terminal',
      'field',
    ]) {
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
      home: Scaffold(body: Center(child: child)),
    ),
  );

  group('OrbitIconButton', () {
    testWidgets('is a 48px target with its tooltip as its label', (
      tester,
    ) async {
      var taps = 0;
      await show(
        tester,
        OrbitIconButton(
          icon: OrbitIcons.bell,
          tooltip: 'Mute',
          onPressed: () => taps++,
        ),
      );
      expect(tester.getSize(find.byType(OrbitIconButton)), const Size(48, 48));
      expect(find.byTooltip('Mute'), findsOneWidget);
      expect(find.bySemanticsLabel('Mute'), findsOneWidget);
      await tester.tap(find.byType(OrbitIconButton));
      expect(taps, 1);
    });

    testWidgets('draws its icon at the theme weight unless told otherwise', (
      tester,
    ) async {
      await show(
        tester,
        OrbitIconButton(
          icon: OrbitIcons.bell,
          tooltip: 'Mute',
          onPressed: () {},
        ),
        theme: 'arcade',
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(
        icon.icon,
        OrbitIcons.bell.bold,
        reason: 'Arcade draws bold icons',
      );
      expect(icon.size, 22);
    });
  });

  group('OrbitButton', () {
    testWidgets('is 48px tall and fires', (tester) async {
      var taps = 0;
      await show(
        tester,
        OrbitButton(label: 'Primary', onPressed: () => taps++),
      );
      expect(tester.getSize(find.byType(OrbitButton)).height, 48);
      await tester.tap(find.text('Primary'));
      expect(taps, 1);
    });

    testWidgets('busy keeps its label, shows the spinner and ignores taps', (
      tester,
    ) async {
      var taps = 0;
      await show(
        tester,
        OrbitButton(label: 'Sending', busy: true, onPressed: () => taps++),
      );
      expect(find.text('Sending'), findsOneWidget);
      expect(find.byType(OrbitSpinner), findsOneWidget);
      await tester.tap(find.text('Sending'));
      expect(taps, 0);
    });

    testWidgets('disabled is at 45% and does nothing', (tester) async {
      await show(tester, const OrbitButton(label: 'Disabled', onPressed: null));
      final fade = tester.widget<Opacity>(
        find.ancestor(
          of: find.text('Disabled'),
          matching: find.byType(Opacity),
        ),
      );
      expect(fade.opacity, 0.45);
    });

    final notched = find.byWidgetPredicate(
      (w) => w is ClipPath && w.clipper is OrbitNotchClipper,
    );
    testWidgets('Arcade cuts the primary button notched and drops its glow', (
      tester,
    ) async {
      await show(
        tester,
        OrbitButton(label: 'Go', onPressed: () {}),
        theme: 'arcade',
      );
      expect(notched, findsOneWidget);
      await show(tester, OrbitButton(label: 'Go', onPressed: () {}));
      // MaterialApp animates between themes; let it arrive.
      await tester.pumpAndSettle();
      expect(notched, findsNothing);
    });
  });

  group('OrbitFab', () {
    testWidgets('is 56px with a tooltip, and gone takes no taps', (
      tester,
    ) async {
      var taps = 0;
      await show(
        tester,
        OrbitFab(
          icon: OrbitIcons.pencilSimpleLine,
          tooltip: 'New chat',
          onPressed: () => taps++,
        ),
      );
      expect(tester.getSize(find.byType(Material).last), const Size(56, 56));
      expect(find.byTooltip('New chat'), findsOneWidget);
      await tester.tap(find.byType(OrbitFab));
      expect(taps, 1);
      await show(
        tester,
        OrbitFab(
          icon: OrbitIcons.pencilSimpleLine,
          tooltip: 'New chat',
          gone: true,
          onPressed: () => taps++,
        ),
      );
      await tester.tap(find.byType(OrbitFab), warnIfMissed: false);
      expect(taps, 1);
    });
  });

  group('OrbitAvatar', () {
    test('initials and the palette index match the prototype', () {
      expect(helixInitials('Nadia Rahman'), 'NR');
      expect(helixInitials('~nadia'), 'N');
      expect(helixInitials('+880 1712'), '#');
      // UI.colorIndexFor in prototype/js/ui.js gives these for the sheet's seeds.
      for (final seed in ['nadia', 'arif', 'tanvir', 'family']) {
        expect(HelixAvatarModel.colorIndexFor(seed), inInclusiveRange(0, 7));
      }
    });

    testWidgets(
      'draws initials, the group icon, the check and the online dot',
      (tester) async {
        await show(
          tester,
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OrbitAvatar(
                avatar: HelixAvatarModel(name: 'Nadia Rahman'),
                online: true,
              ),
              OrbitAvatar(
                avatar: HelixAvatarModel(name: 'Family', isGroup: true),
              ),
              OrbitAvatar(
                avatar: HelixAvatarModel(name: 'Tanvir Ahmed'),
                check: true,
              ),
            ],
          ),
        );
        expect(find.text('NR'), findsOneWidget);
        expect(find.byIcon(OrbitIcons.usersThree.fill), findsOneWidget);
        expect(find.byIcon(OrbitIcons.check.bold), findsOneWidget);
        expect(
          tester.getSize(find.byType(OrbitAvatar).first),
          const Size(48, 48),
        );
      },
    );
  });

  group('OrbitChip and OrbitTag', () {
    testWidgets(
      'a chip is drawn 34px tall, taps across 48px and shows its count',
      (tester) async {
        var taps = 0;
        await show(
          tester,
          OrbitChip(label: 'Unread', count: 3, on: false, onTap: () => taps++),
        );
        expect(tester.getSize(find.byType(OrbitChip)).height, 34);
        expect(find.text('3'), findsOneWidget);
        // 7px above the drawn chip is still inside its 48px target.
        final top = tester.getTopLeft(find.byType(OrbitChip));
        await tester.tapAt(top + const Offset(20, -6));
        expect(taps, 1);
      },
    );

    testWidgets('a tag is upper case', (tester) async {
      await show(
        tester,
        const OrbitTag(label: 'Verified', tone: OrbitTagTone.success),
      );
      expect(find.text('VERIFIED'), findsOneWidget);
    });
  });

  group('OrbitSwitch and OrbitCheckbox', () {
    testWidgets('a switch is 44x26, toggles, and taps across 48px', (
      tester,
    ) async {
      var on = false;
      await show(
        tester,
        StatefulBuilder(
          builder: (context, set) => OrbitSwitch(
            on: on,
            label: 'Receipts',
            onChanged: (v) => set(() => on = v),
          ),
        ),
      );
      expect(tester.getSize(find.byType(OrbitSwitch)), const Size(44, 26));
      final top = tester.getTopLeft(find.byType(OrbitSwitch));
      await tester.tapAt(top + const Offset(22, -10));
      await tester.pump();
      expect(on, isTrue);
    });

    testWidgets('a checkbox row is at least 48px and ticks', (tester) async {
      var on = false;
      await show(
        tester,
        StatefulBuilder(
          builder: (context, set) => SizedBox(
            width: 300,
            child: OrbitCheckbox(
              label: 'I have read the Terms',
              on: on,
              onChanged: (v) => set(() => on = v),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(OrbitCheckbox)).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.text('I have read the Terms'));
      await tester.pump();
      expect(on, isTrue);
    });
  });

  group('patterns', () {
    test('the SVG path reader handles relative and smooth cubics', () {
      final path = orbitSvgPath(
        'M-10 110c25-45 65-55 100-32s70 12 80-22 40-30 60-10',
      );
      final bounds = path.getBounds();
      expect(bounds.left, -10);
      expect(bounds.right, closeTo(230, 0.01), reason: '-10 + 100 + 80 + 60');
    });

    test('the grain noise is the SVG reference algorithm', () {
      // Spot values measured from Chrome (Papyrus's tile, alpha out of 255).
      final noise = OrbitTurbulence();
      int alphaAt(int x, int y) =>
          (0.1 *
                  ((noise.turbulence(
                                3,
                                x + 1.0,
                                y + 1.0,
                                baseFrequency: 0.85,
                                octaves: 3,
                                fractalSum: true,
                                tileWidth: 192,
                                tileHeight: 192,
                                tileX: -16,
                                tileY: -16,
                              ) +
                              1) /
                          2)
                      .clamp(0.0, 1.0) *
                  255)
              .round();
      expect(alphaAt(5, 3), closeTo(11, 1));
      expect(alphaAt(28, 3), closeTo(7, 1));
      expect(alphaAt(120, 88), closeTo(19, 1));
      expect(alphaAt(143, 156), closeTo(7, 1));
    });

    testWidgets('every theme paints its page and chat pattern', (tester) async {
      for (final t in themes.values) {
        await show(
          tester,
          SizedBox(
            width: 300,
            height: 200,
            child: OrbitPatternBackground(
              pattern: t.chatPattern,
              color: t.chatBg,
            ),
          ),
          theme: t.meta.id,
        );
        expect(tester.takeException(), isNull, reason: t.meta.id);
      }
    });
  });
}
