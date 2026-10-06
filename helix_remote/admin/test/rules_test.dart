// Product and security rules for the operator console, checked over the
// source (AGENTS.md "Product rules" and "Security invariants", plan §7).
// The widget tests exercise behaviour; these keep a later edit from quietly
// breaking a rule no screen test would notice.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strips `//` comments so a rule is not tripped by prose that explains it.
String _code(String source) => source
    .split('\n')
    .map((line) {
      final index = line.indexOf('//');
      return index == -1 ? line : line.substring(0, index);
    })
    .join('\n');

Map<String, String> _sources(String dir) => {
  for (final e in Directory(dir).listSync(recursive: true))
    if (e is File && e.path.endsWith('.dart'))
      e.path.replaceAll(r'\', '/'): e.readAsStringSync(),
};

/// Every `IconButton(` whose argument list has no `tooltip:`.
List<int> _unlabelledIconButtons(String source) {
  final lines = <int>[];
  for (final match in RegExp(r'IconButton\(').allMatches(source)) {
    var index = match.end;
    var depth = 1;
    while (index < source.length && depth > 0) {
      final char = source[index];
      if (char == '(') depth++;
      if (char == ')') depth--;
      index++;
    }
    if (!source.substring(match.end, index).contains('tooltip:')) {
      lines.add('\n'.allMatches(source.substring(0, match.start)).length + 1);
    }
  }
  return lines;
}

void main() {
  final lib = _sources('lib');

  test('the rules scan the console sources', () {
    expect(lib.keys, contains('lib/main.dart'));
    expect(lib.length, greaterThan(25));
  });

  group('product rules', () {
    test('colours come from the theme and design tokens, not literals', () {
      // `Colors.transparent` means "draw nothing"; it is the only literal.
      final raw = RegExp(r'(?<![\w.])Colors\.\w+|(?<![\w.])Color\(0x');
      final offenders = <String>[];
      lib.forEach((path, source) {
        final lines = source.split('\n');
        for (var i = 0; i < lines.length; i++) {
          for (final m in raw.allMatches(lines[i])) {
            if (lines[i].startsWith('Colors.transparent', m.start)) continue;
            offenders.add('$path:${i + 1}: ${lines[i].trim()}');
          }
        }
      });
      expect(
        offenders,
        isEmpty,
        reason:
            'use Theme.of(context).colorScheme or a token from '
            'helix_remote_ui (HelixStatusColors, ...)',
      );
    });

    test('every IconButton has a tooltip', () {
      final offenders = <String>[];
      lib.forEach((path, source) {
        for (final line in _unlabelledIconButtons(source)) {
          offenders.add('$path:$line');
        }
      });
      expect(offenders, isEmpty);
    });

    test('tap targets are never shrunk below 48 px', () {
      final shrink = RegExp(
        r'MaterialTapTargetSize\.shrinkWrap|VisualDensity\.compact|'
        r'minimumSize:\s*(const\s+)?Size\(\s*(\d{1,2}|4[0-7])\s*,|'
        r'minimumSize:\s*Size\.zero',
      );
      final offenders = <String>[];
      lib.forEach((path, source) {
        for (final m in shrink.allMatches(_code(source))) {
          offenders.add('$path: ${m.group(0)}');
        }
      });
      expect(offenders, isEmpty);
    });

    test('English only: no localization layer', () {
      final offenders = <String>[];
      lib.forEach((path, source) {
        final code = _code(source);
        for (final needle in const [
          'flutter_localizations',
          'package:intl',
          'AppLocalizations',
          'GlobalMaterialLocalizations',
          'localizationsDelegates',
          'supportedLocales',
          'gen_l10n',
        ]) {
          if (code.contains(needle)) offenders.add('$path: $needle');
        }
      });
      expect(offenders, isEmpty);

      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('flutter_localizations')));
      expect(pubspec, isNot(contains('intl:')));
      expect(pubspec, isNot(contains('generate: true')));
      expect(
        Directory(
          '.',
        ).listSync(recursive: true).where((e) => e.path.endsWith('.arb')),
        isEmpty,
      );
    });

    test('light theme only: no dark theme, no dark control', () {
      final offenders = <String>[];
      lib.forEach((path, source) {
        final code = _code(source);
        for (final needle in const [
          'darkTheme:',
          'ThemeMode.dark',
          'ThemeMode.system',
          'Brightness.dark',
          'isDarkMode',
          'Dark Mode',
          'highContrastDark',
        ]) {
          if (code.contains(needle)) offenders.add('$path: $needle');
        }
      });
      expect(offenders, isEmpty);
      expect(
        _code(lib['lib/src/app.dart']!),
        contains('themeMode: ThemeMode.light'),
      );
    });

    test('screenshots stay allowed: no capture blocking', () {
      final offenders = <String>[];
      lib.forEach((path, source) {
        final code = _code(source);
        for (final needle in const [
          'FLAG_SECURE',
          'setWindowDisplayAffinity',
          'flutter_windowmanager',
          'secureApplicationController',
        ]) {
          if (code.contains(needle)) offenders.add('$path: $needle');
        }
      });
      expect(offenders, isEmpty);
    });
  });

  group('security rules', () {
    test('nothing is logged or printed', () {
      final offenders = <String>[];
      lib.forEach((path, source) {
        final code = _code(source);
        for (final m in RegExp(
          r'(?<![\w.])(print|debugPrint|debugPrintStack|log)\(|'
          r'developer\.log|dart:developer|stderr|stdout',
        ).allMatches(code)) {
          offenders.add('$path: ${m.group(0)}');
        }
      });
      expect(offenders, isEmpty, reason: 'the console logs nothing');
    });

    test('no dart:io, no files and no raw HTTP or WebSocket use', () {
      final offenders = <String>[];
      lib.forEach((path, source) {
        final code = _code(source);
        for (final needle in const [
          'dart:io',
          'dart:html',
          'dart:js',
          'package:http/',
          'package:web_socket_channel',
          'package:path_provider',
          'File(',
          'Directory(',
          'HttpClient',
        ]) {
          if (code.contains(needle)) offenders.add('$path: $needle');
        }
      });
      expect(
        offenders,
        isEmpty,
        reason: 'all network use goes through helix_remote_api (plan §8)',
      );
    });

    test(
      'no code reads the bearer token: it moves only as a whole session',
      () {
        final readers = <String>[
          for (final e in lib.entries)
            if (RegExp(r'\.token\b|\btoken:').hasMatch(_code(e.value))) e.key,
        ];
        expect(readers, isEmpty);
      },
    );

    test('the vault uses secure storage and settings never hold a token', () {
      final vault = _code(lib['lib/src/services/token_vault.dart']!);
      expect(vault, contains('FlutterSecureStorage'));
      expect(vault, isNot(contains('SharedPreferences')));
      final settings = _code(lib['lib/src/services/admin_settings.dart']!);
      expect(settings.toLowerCase(), isNot(contains('token')));
    });

    test('one-time codes are read only where they are shown', () {
      List<String> readers(String field) => [
        for (final e in lib.entries)
          if (_code(e.value).contains('.$field')) e.key,
      ];
      expect(readers('recoveryCode'), [
        'lib/src/features/accounts/account_detail_screen.dart',
      ]);
      expect(readers('inviteCode'), [
        'lib/src/features/invites/invites_screen.dart',
      ]);
    });

    test('no controller keeps a one-time code in a field', () {
      for (final path in const [
        'lib/src/features/accounts/accounts_controller.dart',
        'lib/src/features/invites/invites_controller.dart',
      ]) {
        final code = _code(lib[path]!);
        expect(
          RegExp(
            r'^  (final\s+|late\s+)?(AdminRecoveryCode|CreatedInvite)\??\s+_?\w+\s*[;=]',
            multiLine: true,
          ).hasMatch(code),
          isFalse,
          reason: '$path must hand codes to the caller, not keep them',
        );
      }
    });

    test('only the last four phone digits are ever handled', () {
      final offenders = <String>[];
      lib.forEach((path, source) {
        final code = _code(source);
        for (final needle in const [
          'phoneNumber',
          'phone_number',
          'PhoneNumber',
          'phoneHash',
          'phone_hash',
        ]) {
          if (code.contains(needle)) offenders.add('$path: $needle');
        }
      });
      expect(offenders, isEmpty);
    });

    test('the password is never put in a string, a field or a message', () {
      // Passwords are read from a text controller and passed straight to the
      // API: no interpolation, no storage.
      final offenders = <String>[];
      lib.forEach((path, source) {
        final code = _code(source);
        for (final m in RegExp(
          r'\$\{?_?(password|newPassword|current|next|confirm\w*)(?!\.)|'
          r"'[^']*\+\s*\w*[pP]assword",
        ).allMatches(code)) {
          offenders.add('$path: ${m.group(0)}');
        }
      });
      expect(offenders, isEmpty);
    });

    test('an http address is accepted only for this machine', () {
      final code = _code(lib['lib/src/api/server_address.dart']!);
      expect(code, contains("parsed.scheme == 'http'"));
      expect(code, contains('_isLocalHost'));
    });
  });
}
