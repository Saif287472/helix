import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// Chats > Links > Link previews.
void main() {
  late OrbitTokens orbit;
  setUpAll(() {
    orbit = OrbitTokens.fromThemeJson(
      jsonDecode(File('assets/themes/orbit.json').readAsStringSync())
          as Map<String, Object?>,
    );
  });

  Future<void> show(WidgetTester tester, ChatsSettingsScreen screen) async {
    tester.view.physicalSize = const Size(412, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: OrbitTheme.of(orbit), home: screen),
    );
    await tester.pump();
  }

  testWidgets('is not offered until the app can keep it', (tester) async {
    await show(tester, const ChatsSettingsScreen(model: ChatsSettingsModel()));
    expect(find.text('Link previews'), findsNothing);
  });

  testWidgets('says who sees what, and reports a change', (tester) async {
    final changes = <bool>[];
    await show(
      tester,
      ChatsSettingsScreen(
        model: const ChatsSettingsModel(linkPreviews: false),
        actions: ChatsSettingsActions(onLinkPreviews: changes.add),
      ),
    );
    expect(find.text('Link previews'), findsOneWidget);
    expect(find.textContaining('the site sees your phone'), findsOneWidget);
    expect(
      find.textContaining('Nothing is fetched when you receive'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Link previews'));
    await tester.tap(find.text('Link previews'));
    await tester.pump();
    expect(changes, [true]);
  });
}
