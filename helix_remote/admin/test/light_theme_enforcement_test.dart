// Phase 3 Step 3.1 — the console is light only.
//
// Dark mode is deferred for this product: Helix is meant to be light,
// vibrant and colourful. The previous arrangement could not deliver that.
// `AppTheme.dark` was defined as `AppTheme.dark = light`, so
// `ThemeMode.dark` rendered pixel-identically to light while the Dark Mode
// switch reported otherwise - and a dead branch in `AppColorsX.sunkenSurface`
// kept a near-black surface value alive that nothing could reach.
//
// These tests pin the decision so a future change has to be deliberate:
// there is one theme, the app asks for light unconditionally, and no
// dark-mode control is offered anywhere in the console.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/main.dart';
import 'package:helix_admin/theme/app_theme.dart';

/// Strips `//` line comments so a scan of the source is not defeated by prose.
///
/// This file and `lib/main.dart` both *explain* the removal in comments that
/// necessarily name the identifiers being removed. Scanning raw text would
/// make those explanations look like violations.
String _codeOnly(String source) => source
    .split('\n')
    .map((line) {
      final index = line.indexOf('//');
      return index == -1 ? line : line.substring(0, index);
    })
    .join('\n');

void main() {
  group('AppTheme', () {
    testWidgets('is light', (tester) async {
      expect(AppTheme.light.brightness, equals(Brightness.light));
    });

    test('exposes no dark theme at all', () {
      // Asserted against the source rather than by referencing `AppTheme.dark`,
      // which would not compile precisely because it is gone. The point is
      // that a caller cannot request a theme by name and silently get the
      // light theme back - the old `AppTheme.dark = light` allowed exactly
      // that.
      final source = _codeOnly(
        File('lib/theme/app_theme.dart').readAsStringSync(),
      );

      expect(
        RegExp(r'static\s+final\s+ThemeData\s+dark\b').hasMatch(source),
        isFalse,
        reason: 'a `dark` member must not exist, not even as an alias',
      );
    });

    testWidgets('pins ColorScheme.light rather than deriving from a parameter', (
      tester,
    ) async {
      expect(AppTheme.light.colorScheme.brightness, equals(Brightness.light));
    });

    testWidgets('the sunken surface fallback is a light tint', (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(extensions: const <ThemeExtension<dynamic>>[]),
          home: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final sunken = captured.sunkenSurface;
      // Light surfaces are high-luminance. A dark fallback would land well
      // below this.
      expect(sunken.computeLuminance(), greaterThan(0.5));
    });
  });

  group('the app shell', () {
    test('pins ThemeMode.light and registers no darkTheme', () {
      final source = _codeOnly(File('lib/main.dart').readAsStringSync());

      expect(
        source,
        contains('themeMode: ThemeMode.light'),
        reason: 'light must be requested unconditionally',
      );
      expect(
        source,
        isNot(contains('darkTheme:')),
        reason: 'a registered darkTheme is an invitation to reintroduce it',
      );
      expect(source, isNot(contains('ThemeMode.dark')));
    });

    test('carries no dark-mode state or callback', () {
      final source = _codeOnly(File('lib/main.dart').readAsStringSync());

      expect(source, isNot(contains('isDarkMode')));
      expect(source, isNot(contains('onDarkModeChanged')));
      expect(source, isNot(contains('_isDarkMode')));
    });

    testWidgets('boots without offering a theme switch', (tester) async {
      await tester.pumpWidget(const HelixAdminApp());
      await tester.pump();

      expect(find.text('Dark Mode'), findsNothing);
      expect(find.byIcon(Icons.dark_mode), findsNothing);
    });
  });

  group('no screen offers an appearance toggle', () {
    test('the admin UI source has no dark-mode control', () {
      final offenders = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;

        final source = _codeOnly(entity.readAsStringSync());
        for (final needle in const [
          'Dark Mode',
          'isDarkMode',
          'onDarkModeChanged',
          'AppTheme.dark',
          'ThemeMode.dark',
        ]) {
          if (source.contains(needle)) {
            offenders.add('${entity.path}: $needle');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'light-only is a product decision; reintroducing a control '
            'for a theme that does not exist should be a conscious act',
      );
    });
  });
}
