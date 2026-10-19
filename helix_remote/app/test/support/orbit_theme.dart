import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:orbit_ui/orbit_ui.dart';

/// The Orbit theme the app draws with (`core/theme/orbit_app_theme.dart`),
/// read from `orbit_ui`'s asset file so a test needs no asset bundle.
final OrbitTokens orbitTestTokens = OrbitTokens.fromThemeJson(
  jsonDecode(
        File(
          '../packages/orbit_ui/assets/themes/orbit.json',
        ).readAsStringSync(),
      )
      as Map<String, Object?>,
);

/// The app's [ThemeData]: what `main.dart` gives `MaterialApp`.
ThemeData orbitTestTheme() => OrbitTheme.of(orbitTestTokens);

/// `MaterialApp.builder` as `main.dart` has it for the Orbit screens: the
/// page colour under the navigator.
Widget orbitTestBuilder(BuildContext context, Widget? child) =>
    Material(color: orbitTestTokens.bg, child: child);
