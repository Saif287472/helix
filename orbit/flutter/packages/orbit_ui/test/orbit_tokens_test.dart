import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_ui/src/theme/effects.dart';
import 'package:orbit_ui/src/theme/orbit_tokens.dart';

/// The theme layer's contract with the generator.
///
/// `orbit/prototype/tools/themes.py` writes the JSON, `tools/gen_orbit_tokens.py`
/// writes the getters, and this checks the two against each other and against
/// what the app can actually draw. A theme that half-loads must fail loudly: it
/// would look like a design decision, and it would not be one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The eight built-in themes, by the ids the theme table uses.
  const ids = [
    'orbit',
    'night',
    'bloom',
    'mochi',
    'papyrus',
    'arcade',
    'terminal',
    'field',
  ];

  Future<Map<String, Object?>> loadJson(String id) async {
    final raw = await rootBundle.loadString('assets/themes/$id.json');
    return jsonDecode(raw) as Map<String, Object?>;
  }

  Future<OrbitTokens> load(String id) async =>
      OrbitTokens.fromThemeJson(await loadJson(id));

  test('every built-in theme loads', () async {
    for (final id in ids) {
      final tokens = await load(id);
      expect(tokens.meta.id, id, reason: '$id loaded but says it is something '
          'else');
      expect(tokens.meta.name, isNotEmpty, reason: '$id has no name for the '
          'picker');
    }
  });

  test('every token of every theme is read, and none invented', () async {
    for (final id in ids) {
      final json = await loadJson(id);
      final tokens = await load(id);
      final raw = json['tokens']! as Map<String, Object?>;
      final inJson = {
        for (final group in raw.entries)
          for (final token in (group.value! as Map).keys) '$group.${token as String}',
      };
      // The JSON is keyed `group.key`; `values` is keyed by the bare name, so
      // the counts must match even though the spellings differ.
      expect(tokens.values.length, inJson.length,
          reason: '$id: the JSON has ${inJson.length} tokens and the loaded '
              'theme has ${tokens.values.length}; a token was dropped or '
              'invented');
    }
  });

  test('the generated getters name the tokens the JSON has', () async {
    // A getter is the only way a screen reads a token, so a getter that reads
    // the wrong name would draw the wrong colour and compile fine. This checks
    // a spread of every value kind against the JSON by hand.
    final orbit = await load('orbit');

    expect(orbit.accent, const Color(0xFF2563EB));
    expect(orbit.ink, const Color(0xFF131722));
    expect(orbit.chatBg, const Color(0xFFF4F6F9));
    expect(orbit.scrim, const Color(0x6B0D1019), reason: 'rgba at 42% alpha');
    expect(orbit.hover, const Color(0x09131722), reason: 'rgba at 3.5% alpha');
    expect(orbit.rMd, 14.0);
    expect(orbit.rPill, 999.0);
    expect(orbit.bubbleR, 9.0);
    expect(orbit.avatarR, 25.0, reason: 'a percentage, not pixels');
    expect(orbit.displayWeight, 650);
    expect(orbit.wordmarkTracking, -0.045);
    expect(orbit.displayTransform, OrbitTextTransform.none);
    expect(orbit.shadowCard, hasLength(1));
    expect(orbit.glow, hasLength(1));
    expect(orbit.glow.single.blurRadius, 0.0,
        reason: "Orbit's glow is a glow of nothing");
    expect(orbit.font.families.first, 'Geist');
    expect(orbit.mono.families.first, 'Geist Mono');
    expect(orbit.av0Bg, const Color(0xFFE3ECFD));
    expect(orbit.inBubble, const Color(0xFFFFFFFF));
  });

  test('a shadow keeps every layer, and a gradient every stop', () async {
    final terminal = await load('terminal');
    expect(terminal.shadowFloat, hasLength(2),
        reason: 'the floating shadow is two layers');
    expect(terminal.glow.single.color, const Color(0x5939FF88));

    final orbit = await load('orbit');
    expect(orbit.wordmarkGradient.colors, hasLength(3));
    expect(orbit.wordmarkGradient.stops, [0.0, 0.48, 1.0]);
    expect(orbit.brandGradient.colors,
        [orbit.callTop, orbit.callMid, orbit.callBottom],
        reason: 'the brand gradient is built from the call colours');
  });

  test('a pattern is a name and its settings, never a picture', () async {
    expect((await load('orbit')).chatPattern.kind, 'none');
    expect((await load('orbit')).chatPattern.size.isAuto, isTrue);

    final bloom = await load('bloom');
    expect(bloom.chatPattern.kind, 'grain');
    expect(bloom.chatPattern.paramColour('a'), isNull,
        reason: 'grain mixes raw numbers, not a colour');
    expect(bloom.chatPattern.size.size, const Size(160, 160));

    final terminal = await load('terminal');
    expect(terminal.chatPattern.kind, 'scanlines');
    expect(terminal.chatPattern.size.isAuto, isTrue,
        reason: 'scanlines carry their own period');

    final arcade = await load('arcade');
    expect(arcade.chatPattern.kind, 'neonGrid');
    expect(arcade.chatPattern.paramColour('h'), isNotNull);
  });

  test('effects are names from the fixed registry', () async {
    // Orbit and Orbit Night switch nothing on.
    expect((await load('orbit')).meta.effects, isEmpty);
    expect((await load('night')).meta.effects, isEmpty);

    final terminal = await load('terminal');
    expect(terminal.meta.has('cursor'), isTrue);
    final cursor = terminal.meta.effect('cursor')!;
    expect(cursor.kind, 'cursor');
    expect(cursor.param<String>('glyph'), '_');
    expect(cursor.param<String>('period'), '1s');
    // Terminal's cursor colour reads a token rather than naming one, so a
    // theme can follow it if the accent ever changes.
    expect(cursor.param<Map<Object?, Object?>>('colour'),
        {'kind': 'token', 'name': 'accent'});
    expect(OrbitColour.token('accent').resolve(terminal), terminal.accent);

    final field = await load('field');
    expect(field.meta.has('bubbleStripe'), isTrue);
    expect(field.meta.has('ornament'), isTrue);

    for (final id in ids) {
      final meta = (await load(id)).meta;
      for (final e in meta.effects) {
        expect(OrbitEffects.byName(e.kind), isNotNull,
            reason: '$id switches on an effect this build has not got');
      }
    }
  });

  test('the six patterns are the ones the themes actually use', () async {
    final used = <String>{};
    for (final id in ids) {
      used.add((await load(id)).chatPattern.kind);
    }
    expect(used, OrbitEffects.patterns.map((p) => p.name).toSet(),
        reason: 'a registered pattern is used by no theme, or a theme uses one '
            'that is not registered');
  });

  test('a theme that is missing a token fails instead of defaulting', () {
    // The loader is data-driven, so it cannot know which tokens a theme ought
    // to have. What it can do is refuse to invent one: reading a token the
    // theme does not carry is an error, not a default.
    final thin = OrbitTokens.fromThemeJson({
      'id': 'thin',
      'tokens': {
        'colour': {
          'accent': {'hex': '#2563EB', 'alpha': 1},
        },
      },
      'motion': {
        'duration': {'short': 0.18, 'page': 0.26},
        'curve': [0.2, 0.7, 0.2, 1.0],
      },
    });
    expect(thin.accent, isNotNull);
    expect(() => thin.value<Color>('r-md'), throwsArgumentError,
        reason: 'a screen reading a token this theme lacks is a bug in the '
            'screen, not something to paper over');
    expect(() => thin.value<Color>('accent'), returnsNormally);
  });

  test('a malformed token value fails the load', () {
    // A colour with no alpha, and a number where a number should be.
    final noAlpha = <String, Object?>{
      'tokens': {
        'colour': {
          'accent': {'hex': '#2563EB'},
        },
      },
    };
    expect(() => OrbitTokens.fromThemeJson(noAlpha), throwsFormatException);

    final notANumber = <String, Object?>{
      'tokens': {
        'lengthPx': {'r-md': 'wide'},
      },
    };
    expect(
      () => OrbitTokens.fromThemeJson(notANumber),
      throwsFormatException,
    );

    // And a document with no tokens group at all.
    expect(
      () => OrbitTokens.fromThemeJson({'id': 'x'}),
      throwsFormatException,
    );
  });

  test('an effect this build has not got is refused, not ignored', () async {
    // Only data is ever downloaded, so a pack cannot bring an effect type.
    final future = <String, Object?>{
      'id': 'from-a-pack',
      'tokens': {
        'pattern': {
          'chat-pattern': {'kind': 'none', 'params': <String, Object?>{}},
        },
      },
      'motion': {
        'duration': {'short': 0.18, 'page': 0.26},
        'curve': [0.2, 0.7, 0.2, 1.0],
      },
      'effects': [
        {
          'kind': 'discoBall',
          'params': <String, Object?>{},
        },
      ],
    };
    expect(
      () => OrbitTokens.fromThemeJson(future),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('discoBall'),
        ),
      ),
    );
  });

  test('themes cross-fade colours and lengths, and switch the rest', () {
    final orbit = OrbitTokens.fromThemeJson({
      'id': 'a',
      'tokens': {
        'colour': {'accent': {'hex': '#000000', 'alpha': 1}},
        'lengthPx': {'r-md': 10},
      },
      'motion': {
        'duration': {'short': 0.18, 'page': 0.26},
        'curve': [0.2, 0.7, 0.2, 1.0],
      },
    });
    final night = OrbitTokens.fromThemeJson({
      'id': 'b',
      'dark': true,
      'tokens': {
        'colour': {'accent': {'hex': '#FFFFFF', 'alpha': 1}},
        'lengthPx': {'r-md': 20},
      },
      'motion': {
        'duration': {'short': 0.18, 'page': 0.26},
        'curve': [0.2, 0.7, 0.2, 1.0],
      },
    });

    final half = orbit.lerp(night, 0.5);
    expect(half.accent, isNot(orbit.accent));
    expect(half.accent, isNot(night.accent));
    expect(half.rMd, 15.0);
    expect(orbit.lerp(night, 0), same(night));
    expect(orbit.lerp(night, 1), same(orbit));
  });
}