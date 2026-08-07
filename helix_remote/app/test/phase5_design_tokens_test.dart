// Phase 5 — "zero hardcoded colours outside helix_remote_ui".
//
// The roadmap states that as the success criterion and it was never enforced,
// so the count drifted from 194 down to 127 and stopped. Component appearance
// being decided per screen is the actual defect (§19): three screens each
// picking their own "white-ish" is how the product ended up with three
// slightly different action bars.
//
// This test is the criterion, expressed as a gate.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `Colors.transparent` is not a colour decision — it means "draw nothing",
/// and routing it through a token would obscure that. It is the only literal
/// allowed to survive in screen code.
final _allowed = RegExp(r'Colors\.transparent');

/// A raw colour literal: `Colors.<name>` or `Color(0x...)`, but not the
/// tail of a token reference such as `HelixStatusColors.danger`.
final _rawColour = RegExp(r'(?<![\w.])Colors\.\w+|(?<![\w.])Color\(0x');

void main() {
  test('P5 screens use design tokens, not colour literals', () {
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsStringSync().split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        for (final match in _rawColour.allMatches(line)) {
          if (_allowed.matchAsPrefix(line, match.start) != null) continue;
          offenders.add('${entity.path}:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Add a named token to packages/helix_remote_ui instead. Pick the '
          'group by what the colour means: HelixScrimColors for content over '
          'a dark backdrop, HelixStatusColors for severity, HelixCallColors '
          'for call state, HelixNeutralColors for fixed chrome. If none fits, '
          'the colour probably wants Theme.of(context).colorScheme.',
    );
  });
}
