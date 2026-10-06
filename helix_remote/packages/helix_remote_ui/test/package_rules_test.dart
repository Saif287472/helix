// Source-level rules for the UI package, in the style of the app's
// phase5_design_tokens_test and phase7_accessibility_test: no colour literals
// outside the token files, a tooltip on every IconButton, and no screenshot
// blocking or localisation layer creeping in.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// The only files allowed to define colours.
const _tokenFiles = {'lib/helix_remote_ui.dart', 'lib/src/chat_tokens.dart'};

final _rawColour = RegExp(r'(?<![\w.])Colors\.\w+|(?<![\w.])Color\(0x');

Iterable<File> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

String _rel(File f) => f.path.replaceAll(r'\', '/');

void main() {
  test('colour literals live only in the token files', () {
    final offenders = <String>[];
    for (final file in _libFiles()) {
      if (_tokenFiles.contains(_rel(file))) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (_rawColour.hasMatch(lines[i])) {
          offenders.add('${_rel(file)}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Use Theme.of(context).colorScheme or add a named token to '
          'helix_remote_ui.dart / chat_tokens.dart. Not even '
          'Colors.transparent: use Material(type: transparency) or a null '
          'colour.',
    );
  });

  test('the token files are the only place that defines Color(0x...)', () {
    // Guards the scan above against a path-spelling change quietly exempting
    // everything: both token files must exist and really hold literals.
    for (final path in _tokenFiles) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
    expect(
      File('lib/src/chat_tokens.dart').readAsStringSync(),
      contains('Color(0x'),
    );
  });

  test('every IconButton carries a tooltip', () {
    final offenders = <String>[];
    for (final file in _libFiles()) {
      for (final line in unlabelledIconButtonLines(file.readAsStringSync())) {
        offenders.add('${_rel(file)}:$line');
      }
    }
    expect(offenders, isEmpty);
  });

  test('the scanner itself catches an unlabelled IconButton', () {
    expect(
      unlabelledIconButtonLines(
        "IconButton(\n  onPressed: () {},\n  icon: x)\n",
      ),
      [1],
    );
    expect(
      unlabelledIconButtonLines(
        "IconButton.filled(\n icon: x,\n tooltip: 'Send')",
      ),
      isEmpty,
    );
    expect(unlabelledIconButtonLines("IconButton.filled(\n icon: x)"), [1]);
  });

  test('no screenshot blocking and no localisation layer', () {
    const forbidden = [
      'FLAG_SECURE',
      'setDisplayAffinity',
      'flutter_localizations',
      'AppLocalizations',
      'gen-l10n',
    ];
    for (final file in _libFiles()) {
      final source = file.readAsStringSync();
      for (final word in forbidden) {
        expect(source, isNot(contains(word)), reason: '${_rel(file)}: $word');
      }
    }
    expect(
      File('pubspec.yaml').readAsStringSync(),
      isNot(contains('flutter_localizations')),
    );
  });

  test('the package depends on Flutter only', () {
    final pubspec = File(
      'pubspec.yaml',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final deps = RegExp(
      r'^dependencies:\n((?:  .*\n)+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;
    expect(deps, contains('flutter:'));
    expect(RegExp(r'^  \w+:', multiLine: true).allMatches(deps), hasLength(1));
  });

  test('library files import nothing from the engine, db, api or crypto', () {
    for (final file in _libFiles()) {
      final source = file.readAsStringSync();
      expect(
        RegExp(r"import\s+'package:helix_remote_(?!ui)\w+").hasMatch(source),
        isFalse,
        reason: _rel(file),
      );
    }
  });
}
