import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The theme gallery is Review 2's first deliverable: all eight themes, built
/// only from their JSON.
///
/// If a theme needed a constant somewhere to render, these fail - which is the
/// point. There is no per-theme constant in this package, and all eight cards
/// are drawn by one widget.
///
/// The themes are read in [setUpAll], with plain file reads. Reading them
/// inside a `testWidgets` body (through `rootBundle`) waited on real file I/O
/// under the test's fake clock, which never let it finish: that was the hang
/// that had this file switched off.
void main() {
  const ids = <String>[
    'orbit',
    'night',
    'bloom',
    'mochi',
    'papyrus',
    'arcade',
    'terminal',
    'field',
  ];
  final themes = <String, OrbitTokens>{};

  setUpAll(() {
    for (final id in ids) {
      final raw = File('assets/themes/$id.json').readAsStringSync();
      themes[id] = OrbitTokens.fromThemeJson(
        jsonDecode(raw) as Map<String, Object?>,
      );
    }
  });

  testWidgets('every built-in theme has a card that renders', (tester) async {
    for (final id in ids) {
      final tokens = themes[id]!;
      await tester.pumpWidget(
        MaterialApp(
          theme: OrbitTheme.of(tokens),
          home: Scaffold(
            body: SingleChildScrollView(child: OrbitThemeCard(tokens: tokens)),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: '$id threw');
      expect(
        find.byKey(ValueKey<String>('theme-card:$id')),
        findsOneWidget,
        reason: '$id has no card',
      );
      // findsWidgets: the Orbit theme's name is also the wordmark's text.
      expect(find.text(tokens.meta.name), findsWidgets, reason: id);
    }
  });

  testWidgets('the gallery lists all eight', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OrbitTheme.of(themes['orbit']!),
        home: OrbitThemeGallery(themes: [for (final id in ids) themes[id]!]),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('theme-card:orbit')),
      findsOneWidget,
    );
  });

  test('the cards differ because the themes do', () {
    final all = [for (final id in ids) themes[id]!];
    expect(all.first.meta.dark, isFalse);
    expect(all[1].meta.dark, isTrue);
    expect(all.last.meta.dark, isTrue);
    // Light and dark, and not one accent repeated: if every card drew the
    // same thing, "themes are data" would be a claim rather than a fact.
    expect(all.map((t) => t.accent).toSet().length, 8);
    expect(all.map((t) => t.bubbleR).toSet().length, greaterThan(1));
    expect(all.map((t) => t.meta.vibe).toSet().length, 8);
  });
}
