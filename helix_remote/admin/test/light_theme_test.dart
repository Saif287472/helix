// The console is light only (AGENTS.md product rules). There is one theme,
// the app asks for light unconditionally, and no screen offers a dark-mode
// control. The source scan lives in rules_test.dart; these check the running
// app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

import 'support/harness.dart';

void main() {
  testWidgets('the app is light and registers no dark theme', (tester) async {
    final h = AdminHarness();
    await h.pumpApp(tester);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.light);
    expect(app.darkTheme, isNull);
    expect(app.theme!.brightness, Brightness.light);
    expect(app.theme!.colorScheme.brightness, Brightness.light);
  });

  testWidgets('a dark system setting does not change the console', (
    tester,
  ) async {
    final h = AdminHarness();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await h.pumpApp(tester);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    final color =
        scaffold.backgroundColor ??
        Theme.of(
          tester.element(find.byType(Scaffold).first),
        ).scaffoldBackgroundColor;
    expect(color.computeLuminance(), greaterThan(0.5));
  });

  testWidgets('the sign-in page uses the app icon blue', (tester) async {
    final h = AdminHarness();
    await h.pumpApp(tester);

    final theme = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(theme.colorScheme.primary, HelixColorTokens.signInBlue);
  });

  testWidgets('no screen offers an appearance toggle', (tester) async {
    final h = AdminHarness();
    await h.startSignedIn(tester);
    await h.goTo(tester, 'Settings');

    expect(find.text('Dark Mode'), findsNothing);
    expect(find.byIcon(Icons.dark_mode), findsNothing);
    expect(find.byIcon(Icons.light_mode), findsNothing);
  });
}
