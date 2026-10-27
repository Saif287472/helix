import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Privacy's "Silence unknown callers" switch.
void main() {
  late OrbitTokens orbit;
  setUpAll(() {
    orbit = OrbitTokens.fromThemeJson(
      jsonDecode(File('assets/themes/orbit.json').readAsStringSync())
          as Map<String, Object?>,
    );
  });

  Future<void> show(WidgetTester tester, PrivacyScreen screen) async {
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: OrbitTheme.of(orbit), home: screen),
    );
    await tester.pump();
  }

  PrivacyModel model({bool? silence}) => PrivacyModel(
    meName: 'Me',
    meAvatar: const HelixAvatarModel(name: 'Me'),
    silenceUnknownCalls: silence,
  );

  testWidgets('is not offered until the app can keep it', (tester) async {
    await show(tester, PrivacyScreen(model: model()));
    expect(find.text('Silence unknown callers'), findsNothing);
  });

  testWidgets('shows its state and reports a change', (tester) async {
    final changes = <(String, Object)>[];
    await show(
      tester,
      PrivacyScreen(
        model: model(silence: false),
        actions: PrivacyActions(
          onChanged: (key, value) async {
            changes.add((key, value));
            return null;
          },
        ),
      ),
    );
    expect(find.text('Silence unknown callers'), findsOneWidget);
    expect(find.textContaining('do not ring'), findsOneWidget);
    await tester.ensureVisible(find.text('Silence unknown callers'));
    await tester.tap(find.text('Silence unknown callers'));
    await tester.pump();
    expect(changes.single.$1, 'silenceCalls');
    expect(changes.single.$2, true);
  });
}
