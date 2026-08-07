// Phase 7 — accessibility.
//
// The original version of this suite pumped three widgets in isolation — a
// FilledButton, one already-tooltipped IconButton and a status badge — and
// asserted the guidelines against that. It passed while the product had one
// Semantics widget in ~30k lines and twelve unlabelled icon buttons, because
// nothing it rendered was a screen anyone ships.
//
// What follows checks the product instead: a source-level sweep that no icon
// button anywhere can be unlabelled, and guideline assertions against real
// screens and the shared component set.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/screens/server_choice_screen.dart';
import 'package:helix_remote_ui/helix_remote_ui.dart';

/// Every `IconButton(` in [source], paired with its 1-based line, whose
/// argument list carries no `tooltip:`.
///
/// A crude bracket match rather than a parse: it only has to be right about
/// where one constructor's arguments end, and it is exact for that.
List<int> unlabelledIconButtonLines(String source) {
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

void main() {
  test('P7 every icon button carries a label', () {
    // An IconButton renders no text, so its tooltip is what TalkBack and
    // Narrator announce. Without one the control is announced as "button"
    // and a screen-reader user has no way to tell what it does.
    //
    // Checked over source rather than by rendering because most of these live
    // on screens that need a composition root to build. The trade is that
    // this cannot see a tooltip passed as an empty string; nothing else here
    // would catch a missing one at all.
    final offenders = <String>[];
    for (final directory in const ['lib', '../admin/lib']) {
      final root = Directory(directory);
      if (!root.existsSync()) continue;
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        for (final line in unlabelledIconButtonLines(
          entity.readAsStringSync(),
        )) {
          offenders.add('${entity.path}:$line');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'these IconButtons announce nothing to a screen reader; give '
          'each a tooltip',
    );
  });

  testWidgets('P7 the first screen a user meets satisfies the guidelines', (
    tester,
  ) async {
    // ServerChoiceScreen is the first-launch screen and builds without a
    // composition root, which makes it the one real screen this suite can
    // hold to the guidelines directly.
    await tester.pumpWidget(
      MaterialApp(theme: HelixThemes.light(), home: const ServerChoiceScreen()),
    );

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });

  testWidgets('P7 the same screen holds up in the dark theme', (tester) async {
    // Contrast is a property of the colour pair, so a palette that passes in
    // light says nothing about dark. Both theme builders ship.
    await tester.pumpWidget(
      MaterialApp(theme: HelixThemes.dark(), home: const ServerChoiceScreen()),
    );

    await expectLater(tester, meetsGuideline(textContrastGuideline));
  });

  testWidgets('P7 shared controls meet text contrast and touch targets', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: HelixThemes.light(),
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(onPressed: () {}, child: const Text('Continue')),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                ),
                const HelixStatusBadge(label: 'End-to-end encrypted'),
                const HelixEmptyState(
                  icon: Icons.forum_outlined,
                  title: 'No conversations yet',
                  message: 'Start a secure conversation with a contact.',
                ),
                const HelixErrorState(message: 'The server is unavailable.'),
              ],
            ),
          ),
        ),
      ),
    );

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });

  testWidgets('P7 the high-contrast themes also meet contrast', (tester) async {
    for (final theme in [
      HelixThemes.highContrastLight(),
      HelixThemes.highContrastDark(),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(onPressed: () {}, child: const Text('Continue')),
                  const HelixStatusBadge(label: 'End-to-end encrypted'),
                ],
              ),
            ),
          ),
        ),
      );
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    }
  });

  testWidgets('P7 shared controls remain usable at 2× text scale', (
    tester,
  ) async {
    // The 1.3× cap this replaced was an accessibility guarantee traded away to
    // paper over fixed-size layouts. Android and WCAG expect usability to ~2×,
    // and nothing in the app clamps textScaler any more.
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          theme: HelixThemes.light(),
          home: Scaffold(
            body: FilledButton(onPressed: () {}, child: const Text('Continue')),
          ),
        ),
      ),
    );

    expect(find.text('Continue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('P7 no text scale is clamped anywhere in the shell', (
    tester,
  ) async {
    // Guards the removal itself. A reintroduced clamp would not fail any of
    // the assertions above, because they set the scaler directly rather than
    // going through the shell.
    final shellSources = Directory('lib/app')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in shellSources) {
      final source = file.readAsStringSync();
      expect(
        source.contains('withClampedTextScaling'),
        isFalse,
        reason: '${file.path} clamps text scaling; see MED-5',
      );
    }
  });
}
