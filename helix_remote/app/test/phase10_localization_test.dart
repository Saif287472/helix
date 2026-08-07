// Phase 10.1 — localization.
//
// `flutter_localizations` was a declared dependency with nothing behind it,
// and the catalog was a class of ternaries on `locale.languageCode` holding a
// single string. That shape works for one message and does not survive a few
// hundred, which is why the extraction had to come with the generator.
//
// Bengali is deliberately incomplete. Machine-inventing a few hundred Bengali
// strings would produce something that looks like a finished translation and
// reads like nonsense to the people who need it, so untranslated messages fall
// back to English and the gap is recorded in `lib/l10n/untranslated.json`
// rather than hidden.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/l10n/helix_localizations.dart';

/// A `Text('...')` holding a plain literal — no interpolation.
///
/// Interpolated messages are excluded: `Text('$error')` is data rather than
/// copy, and one that mixes both needs an ICU placeholder and a human deciding
/// what the message actually says.
final _literalText = RegExp(r"""Text\(\s*'((?:[^'\\]|\\.)*)'""");

bool _isCopy(String value) =>
    RegExp(r'[A-Za-z]').hasMatch(value) && !value.contains(r'$');

void main() {
  test('P10 no screen holds a plain literal string', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // The generated catalog is where the strings live.
      if (entity.path.startsWith('lib/l10n/')) continue;

      final source = entity.readAsStringSync();
      for (final match in _literalText.allMatches(source)) {
        if (!_isCopy(match.group(1)!)) continue;
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        offenders.add('${entity.path}:$line: ${match.group(1)}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'add the string to lib/l10n/app_en.arb and read it through '
          'HelixLocalizations.of(context)',
    );
  });

  test('P10 the committed catalog is not stale', () {
    // Generated output is committed so the analyzer and the format gate can
    // see it. That only holds if it matches the ARB it came from — a key added
    // to the ARB without re-running `flutter gen-l10n` would compile against
    // the old catalog and fail confusingly at the call site instead of here.
    final arb =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    final generated = File(
      'lib/l10n/helix_localizations.dart',
    ).readAsStringSync();

    final missing = arb.keys
        .where((key) => !key.startsWith('@'))
        .where((key) => !generated.contains('String get $key'))
        .toList();

    expect(
      missing,
      isEmpty,
      reason: 'run `flutter gen-l10n` in helix_remote/app',
    );
  });

  test('P10 English is complete and Bengali falls back to it', () async {
    final en = await HelixLocalizations.delegate.load(const Locale('en'));
    final bn = await HelixLocalizations.delegate.load(const Locale('bn'));

    // The one string that is genuinely translated today.
    expect(en.appTitle, equals('Helix Remote'));
    expect(bn.appTitle, equals('হেলিক্স রিমোট'));

    // Everything else resolves rather than throwing or returning empty — that
    // is what "falls back to English" has to mean in practice.
    expect(bn.cancel, isNotEmpty);
    expect(bn.cancel, equals(en.cancel));
  });

  test('P10 the untranslated gap is recorded rather than hidden', () {
    final report = File('lib/l10n/untranslated.json');
    expect(
      report.existsSync(),
      isTrue,
      reason:
          'l10n.yaml sets untranslated-messages-file so the size of the '
          'translation debt is visible in review',
    );

    final decoded =
        jsonDecode(report.readAsStringSync()) as Map<String, dynamic>;
    expect(
      decoded.keys,
      contains('bn'),
      reason: 'Bengali is the locale carrying the debt',
    );
  });

  test('P10 the shell installs the generated delegates', () {
    final shell = File(
      'lib/app/helix_remote_app_shell.dart',
    ).readAsStringSync();

    // Hand-listed delegates drift from the catalog; these come from it.
    expect(shell, contains('HelixLocalizations.localizationsDelegates'));
    expect(shell, contains('HelixLocalizations.supportedLocales'));
  });
}
