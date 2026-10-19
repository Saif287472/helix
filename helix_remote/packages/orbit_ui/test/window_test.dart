import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Phase 4 batch 10: the wide Windows layout. How it looks is checked
/// against the prototype by the compare tool (`--device window-m` and
/// `window-l`).
void main() {
  late OrbitTokens orbit;
  setUpAll(() {
    orbit = OrbitTokens.fromThemeJson(
      jsonDecode(File('assets/themes/orbit.json').readAsStringSync())
          as Map<String, Object?>,
    );
  });

  Future<void> show(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: OrbitTheme.of(orbit),
        home: Scaffold(body: child),
      ),
    );
    await tester.pump();
  }

  Widget page(String title) =>
      OrbitPage(title: title, children: [Text('$title body')]);

  testWidgets('nothing picked: the right pane says what to pick', (
    tester,
  ) async {
    await show(
      tester,
      const Size(1280, 800),
      OrbitWindowScaffold(
        list: page('List'),
        placeholder: OrbitPlaceholderKind.calls,
      ),
    );
    expect(find.text('Pick a call'), findsOneWidget);
  });

  testWidgets('the first page on the right has no back arrow', (tester) async {
    await show(
      tester,
      const Size(1280, 800),
      OrbitWindowScaffold(list: page('List'), detail: page('Detail')),
    );
    final detail = find.ancestor(
      of: find.text('Detail body'),
      matching: find.byType(OrbitPage),
    );
    expect(
      find.descendant(of: detail, matching: find.byTooltip('Back')),
      findsNothing,
    );
  });

  testWidgets('the info pane sits beside from 1200px and closes', (
    tester,
  ) async {
    await show(
      tester,
      const Size(1280, 800),
      OrbitWindowScaffold(
        list: page('List'),
        detail: page('Detail'),
        info: page('Info'),
      ),
    );
    expect(find.text('Detail body'), findsOneWidget);
    expect(find.text('Info body'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    await show(
      tester,
      const Size(960, 720),
      OrbitWindowScaffold(
        list: page('List'),
        detail: page('Detail'),
        info: page('Info'),
      ),
    );
    expect(find.text('Detail body'), findsNothing);
    expect(find.text('Info body'), findsOneWidget);
  });

  testWidgets('a sheet on a window is a centred card without a handle', (
    tester,
  ) async {
    await show(
      tester,
      const Size(1280, 800),
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showOrbitSheet(
            context,
            title: 'Mute',
            items: const [
              OrbitMenuItem(icon: OrbitIcons.bellSlash, label: '8 hours'),
            ],
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final r = tester.getRect(find.byType(OrbitSheetPanel));
    expect(r.width, 440);
    expect(r.center.dx, closeTo(640, 1));
    expect(r.center.dy, closeTo(400, 1));
  });

  testWidgets('the open chat is marked in the list', (tester) async {
    await show(
      tester,
      const Size(412, 200),
      OrbitCurrentScope(
        id: OrbitFakes.chats.first.id,
        child: OrbitChatListTile(item: OrbitFakes.chats.first),
      ),
    );
    final m = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(OrbitChatListTile),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(m.color, orbit.accentSoft);
  });
}
