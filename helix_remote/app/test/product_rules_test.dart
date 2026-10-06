import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The product rules that were true of v1 and must stay true in v2 (plan §7,
/// AGENTS.md). Each is a source scan, because the thing being forbidden is a
/// *way of writing code*, which no widget test can see.

/// `Colors.transparent` is not a colour decision; it is "no colour", and the
/// only literal allowed in the app.
final _allowedColour = RegExp(r'Colors\.transparent');

/// A raw colour literal: `Colors.<name>` or `Color(0x…)`. The lookbehind is
/// what lets a token reference such as `HelixStatusColors.danger` through.
final _rawColour = RegExp(r'(?<![\w.])Colors\.\w+|(?<![\w.])Color\(0x');

Iterable<File> _sources(
  String dir, [
  List<String> extensions = const ['.dart'],
]) => Directory(dir)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => extensions.any(file.path.endsWith));

/// Everything after `//` is prose, so a rule may explain itself in a comment.
String _code(String source) => source
    .split('\n')
    .map((line) {
      final index = line.indexOf('//');
      return index == -1 ? line : line.substring(0, index);
    })
    .join('\n');

void main() {
  test('P5 screens use design tokens, not colour literals', () {
    final offenders = <String>[];
    for (final file in _sources('lib')) {
      final lines = file.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        for (final match in _rawColour.allMatches(lines[i])) {
          if (_allowedColour.matchAsPrefix(lines[i], match.start) != null) {
            continue;
          }
          offenders.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Add a named token to packages/helix_remote_ui instead, or use '
          'Theme.of(context).colorScheme. Pick the group by what the colour '
          'means: HelixScrimColors for content over a dark backdrop, '
          'HelixStatusColors for severity, HelixCallColors for call state, '
          'HelixNeutralColors for fixed chrome.',
    );
  });

  test('P7 every icon button carries a label', () {
    final offenders = <String>[];
    for (final file in _sources('lib')) {
      for (final line in _unlabelledIconButtonLines(file.readAsStringSync())) {
        offenders.add('${file.path}:$line');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'these IconButtons announce nothing to a screen reader; give each a '
          'tooltip',
    );
  });

  test('the app never clamps text scaling', () {
    // A clamped scale makes text unreadable for somebody who needs it larger,
    // which is exactly who the accessibility setting exists for.
    final offenders = <String>[
      for (final file in _sources('lib'))
        if (file.readAsStringSync().contains('withClampedTextScaling'))
          file.path,
    ];
    expect(offenders, isEmpty);
  });

  test('screenshots are allowed everywhere', () {
    // Capture blocking was removed on 2026-09-30: people need to screenshot
    // chats. These three are the Android, Windows and Dart halves of it.
    for (final file in _sources('android/app/src', ['.kt', '.java'])) {
      expect(
        file.readAsStringSync(),
        isNot(contains('FLAG_SECURE')),
        reason: '${file.path} blocks screenshots',
      );
    }
    for (final file in _sources('windows/runner', ['.cpp', '.h'])) {
      expect(
        file.readAsStringSync(),
        isNot(contains('SetWindowDisplayAffinity')),
        reason: '${file.path} hides the window from capture',
      );
    }
    for (final file in _sources('lib')) {
      expect(
        file.readAsStringSync(),
        isNot(contains('screen_security')),
        reason: '${file.path} keeps a screen-security channel',
      );
    }
  });

  test('English only: there is no localization layer', () {
    final offenders = <String>[];
    for (final file in _sources('lib')) {
      final code = _code(file.readAsStringSync());
      for (final needle in const [
        'flutter_localizations',
        'package:intl',
        'AppLocalizations',
        'GlobalMaterialLocalizations',
        'localizationsDelegates',
        'supportedLocales',
        'gen_l10n',
      ]) {
        if (code.contains(needle)) offenders.add('${file.path}: $needle');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'UI text is plain English literals; there is no translation layer',
    );

    // Normalised first: a Windows checkout has CRLF line ends, and the section
    // below is found by splitting on a line.
    final pubspec = File(
      'pubspec.yaml',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(pubspec, isNot(contains('flutter_localizations')));
    expect(pubspec, isNot(contains('intl:')));
    // `generate: true` under `flutter:` is what turns on gen-l10n. The
    // launcher-icons block has a `generate:` of its own, so only the Flutter
    // section is checked.
    final flutterSection = pubspec.split('\nflutter:\n').last;
    expect(flutterSection, isNot(contains('generate: true')));
    expect(
      Directory('.')
          .listSync(recursive: true)
          .where((entity) => entity.path.endsWith('.arb')),
      isEmpty,
      reason: 'no ARB files: nothing is generated from them',
    );
  });

  test('light theme only: no dark theme is declared or selected', () {
    final offenders = <String>[];
    for (final file in _sources('lib')) {
      final code = _code(file.readAsStringSync());
      for (final needle in const [
        'darkTheme:',
        'ThemeMode.dark',
        'ThemeMode.system',
        'Brightness.dark',
        'highContrastDark',
      ]) {
        if (code.contains(needle)) offenders.add('${file.path}: $needle');
      }
    }
    expect(offenders, isEmpty, reason: 'Helix is light theme only');

    // And the one place it must be pinned positively.
    expect(
      File('lib/main.dart').readAsStringSync(),
      contains('themeMode: ThemeMode.light'),
      reason: 'the light theme is the app theme, not merely the default',
    );
  });

  test(
    'P8 HIGH-3 Android manifest disables backup and declares extraction rules',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();

      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:dataExtractionRules='));
      expect(manifest, contains('android:fullBackupContent='));
    },
  );

  test('release manifest forbids cleartext and carries no inert pin', () {
    // Certificate pinning is off by default and lives in Dart
    // (tls_pinning.dart, tls_pinning_test.dart); Android's network security
    // config would not apply to Dart's sockets, so it holds no pin.
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final networkConfig = File(
      'android/app/src/main/res/xml/helix_remote_network_security.xml',
    ).readAsStringSync();

    expect(manifest, contains('networkSecurityConfig'));
    expect(networkConfig, contains('cleartextTrafficPermitted="false"'));
    expect(networkConfig, isNot(contains('<pin-set')));
  });

  test('LOW-4 no foreground-service permission is requested unused', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    // Comments are stripped first. The manifest explains the removal in prose
    // that necessarily names the very elements being searched for, so a raw
    // substring search reads the explanation as a declaration.
    final declarations = manifest.replaceAll(
      RegExp(r'<!--.*?-->', dotAll: true),
      '',
    );

    // Asserted as a pair: the permissions are only defensible alongside a
    // service element that actually needs them.
    final declaresService = declarations.contains('<service');
    for (final permission in const [
      'android.permission.FOREGROUND_SERVICE',
      'android.permission.FOREGROUND_SERVICE_CAMERA',
      'android.permission.FOREGROUND_SERVICE_MICROPHONE',
    ]) {
      expect(
        declarations.contains('<uses-permission android:name="$permission"'),
        equals(declaresService),
        reason: declaresService
            ? '$permission is needed once a foreground service exists'
            : '$permission is requested but no service element is declared; '
                  'Play Console requires a justification per foreground '
                  'service type',
      );
    }
  });
}

/// The 1-based lines of every `IconButton(` whose argument list carries no
/// `tooltip:`.
List<int> _unlabelledIconButtonLines(String source) {
  final lines = <int>[];
  for (final match in RegExp(r'IconButton\(').allMatches(source)) {
    var index = match.end;
    var depth = 1;
    while (index < source.length && depth > 0) {
      final char = source[index];
      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
      }
      index++;
    }
    if (!source.substring(match.end, index).contains('tooltip:')) {
      lines.add('\n'.allMatches(source.substring(0, match.start)).length + 1);
    }
  }
  return lines;
}
