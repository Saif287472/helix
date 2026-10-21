import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The Orbit theme the app draws with (`core/theme/orbit_app_theme.dart`),
/// read from `orbit_ui`'s asset file so a test needs no asset bundle.
final OrbitTokens orbitTestTokens = _theme('orbit');

/// The built-in themes, as `main.dart` loads them before the first frame.
final Map<String, OrbitTokens> orbitTestThemes = {
  'orbit': orbitTestTokens,
  'night': _theme('night'),
};

OrbitTokens _theme(String id) => OrbitTokens.fromThemeJson(
  jsonDecode(
        File('../packages/orbit_ui/assets/themes/$id.json').readAsStringSync(),
      )
      as Map<String, Object?>,
);

/// The app's [ThemeData]: what `main.dart` gives `MaterialApp`.
ThemeData orbitTestTheme() => OrbitTheme.of(orbitTestTokens);

/// `MaterialApp.builder` as `main.dart` has it for the Orbit screens: the
/// page colour under the navigator.
Widget orbitTestBuilder(BuildContext context, Widget? child) =>
    Material(color: orbitTestTokens.bg, child: child);

/// A message's text in an Orbit bubble. The bubbles lay their text out
/// themselves (the time floats after the last line), so the text is found by
/// what they tell a screen reader rather than by a `Text` widget.
Finder findMessageText(String text) =>
    find.bySemanticsLabel(RegExp(RegExp.escape(text)));
