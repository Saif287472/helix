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

  /// The eleven themes in `assets/themes`, by the ids the theme table uses.
  const ids = [
    'orbit',
    'night',
    'bloom',
    'mochi',
    'papyrus',
    'arcade',
    'terminal',
    'field',
    'jungle',
    'ocean',
    'metal',
  ];

  Future<Map<String, Object?>> loadJson(String id) async {
    final raw = await rootBundle.loadString('assets/themes/$id.json');
    return jsonDecode(raw) as Map<String, Object?>;
  }

  Future<OrbitTokens> load(String id) async =>
      OrbitTokens.fromThemeJson(await loadJson(id));

  /// A theme document to break one thing in: the nested groups are fresh on
  /// every call, so a test cannot leak a mutation into the next one.
  Future<Map<String, Object?>> mutable(String id) async =>
      Map.of(await loadJson(id));

  Map<Object?, Object?> groupOf(Map<String, Object?> doc, String group) =>
      (doc['tokens']! as Map)[group] as Map<Object?, Object?>;

  Map<Object?, Object?> paramsOf(Map<String, Object?> doc) =>
      (groupOf(doc, 'pattern')['chat-pattern']
              as Map<Object?, Object?>)['params']
          as Map<Object?, Object?>;

  test('every built-in theme loads', () async {
    for (final id in ids) {
      final tokens = await load(id);
      expect(
        tokens.meta.id,
        id,
        reason:
            '$id loaded but says it is something '
            'else',
      );
      expect(
        tokens.meta.name,
        isNotEmpty,
        reason:
            '$id has no name for the '
            'picker',
      );
    }
  });

  test('every token of every theme is read, and none invented', () async {
    for (final id in ids) {
      final json = await loadJson(id);
      final tokens = await load(id);
      final raw = json['tokens']! as Map<String, Object?>;
      final inJson = {
        for (final group in raw.entries)
          for (final token in (group.value! as Map).keys)
            '${group.key}.${token as String}',
      };
      // The contract the generator writes and the parse enforces: every theme
      // carries exactly the same tokens, spelled `group.key`.
      expect(
        inJson,
        orbitRequiredTokenNames,
        reason:
            '$id: the JSON and the generated contract disagree; regenerate '
            'with tools/gen_orbit_tokens.py',
      );
      // `values` is keyed by the bare name, so the counts must match even
      // though the spellings differ.
      expect(
        tokens.values.length,
        inJson.length,
        reason:
            '$id: the JSON has ${inJson.length} tokens and the loaded '
            'theme has ${tokens.values.length}; a token was dropped or '
            'invented',
      );
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
    expect(
      orbit.glow.single.blurRadius,
      0.0,
      reason: "Orbit's glow is a glow of nothing",
    );
    expect(orbit.font.families.first, 'Geist');
    expect(orbit.mono.families.first, 'Geist Mono');
    expect(orbit.av0Bg, const Color(0xFFE3ECFD));
    expect(orbit.inBubble, const Color(0xFFFFFFFF));
  });

  test('a shadow keeps every layer, and a gradient every stop', () async {
    final terminal = await load('terminal');
    expect(
      terminal.shadowFloat,
      hasLength(2),
      reason: 'the floating shadow is two layers',
    );
    expect(terminal.glow.single.color, const Color(0x5939FF88));

    final orbit = await load('orbit');
    expect(orbit.wordmarkGradient.colors, hasLength(3));
    expect(orbit.wordmarkGradient.stops, [0.0, 0.48, 1.0]);
    expect(
      orbit.brandGradient.colors,
      [orbit.callTop, orbit.callMid, orbit.callBottom],
      reason: 'the brand gradient is built from the call colours',
    );
  });

  test('a pattern is a name and its settings, never a picture', () async {
    expect((await load('orbit')).chatPattern.kind, 'none');
    expect((await load('orbit')).chatPattern.size.isAuto, isTrue);

    final bloom = await load('bloom');
    expect(bloom.chatPattern.kind, 'grain');
    expect(
      bloom.chatPattern.paramColour('a'),
      isNull,
      reason: 'grain mixes raw numbers, not a colour',
    );
    expect(bloom.chatPattern.size.size, const Size(160, 160));

    final terminal = await load('terminal');
    expect(terminal.chatPattern.kind, 'scanlines');
    expect(
      terminal.chatPattern.size.isAuto,
      isTrue,
      reason: 'scanlines carry their own period',
    );

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
    expect(cursor.param<Map<Object?, Object?>>('colour'), {
      'kind': 'token',
      'name': 'accent',
    });
    expect(OrbitColour.token('accent').resolve(terminal), terminal.accent);

    final field = await load('field');
    expect(field.meta.has('bubbleStripe'), isTrue);
    expect(field.meta.has('ornament'), isTrue);

    for (final id in ids) {
      final meta = (await load(id)).meta;
      for (final e in meta.effects) {
        expect(
          OrbitEffects.byName(e.kind),
          isNotNull,
          reason: '$id switches on an effect this build has not got',
        );
      }
    }
  });

  test('the six patterns are the ones the themes actually use', () async {
    final used = <String>{};
    for (final id in ids) {
      used.add((await load(id)).chatPattern.kind);
    }
    expect(
      used,
      OrbitEffects.patterns.map((p) => p.name).toSet(),
      reason:
          'a registered pattern is used by no theme, or a theme uses one '
          'that is not registered',
    );
  });

  test('a theme missing a token is refused, not left half-loaded', () async {
    // A theme is chosen and saved, so a token discovered missing at draw time
    // would throw above the router on every later launch. The contract the
    // generator writes is the list every document must carry.
    final thin = await mutable('orbit');
    groupOf(thin, 'colour').remove('accent');
    expect(
      () => OrbitTokens.fromThemeJson(thin),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('colour.accent'),
        ),
      ),
    );

    // A screen that reads a name no token carries is still a bug in the
    // screen, and reading a token as the wrong type too.
    final orbit = await load('orbit');
    expect(() => orbit.value<Color>('no-such-token'), throwsArgumentError);
    expect(() => orbit.value<Color>('r-md'), throwsArgumentError);
  });

  test('a malformed token value fails the load', () async {
    // Each document is a real theme with exactly one thing broken, so the
    // refusal cannot be the completeness check in disguise.
    final noAlpha = await mutable('orbit');
    (groupOf(noAlpha, 'colour')['accent'] as Map).remove('alpha');
    expect(
      () => OrbitTokens.fromThemeJson(noAlpha),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('no alpha'),
        ),
      ),
    );

    final notANumber = await mutable('orbit');
    groupOf(notANumber, 'lengthPx')['r-md'] = 'wide';
    expect(
      () => OrbitTokens.fromThemeJson(notANumber),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('not a number'),
        ),
      ),
    );

    // And a document with no tokens group at all.
    expect(() => OrbitTokens.fromThemeJson({'id': 'x'}), throwsFormatException);
  });

  test('an effect this build has not got is refused, not ignored', () async {
    // Only data is ever downloaded, so a pack cannot bring an effect type.
    final future = await mutable('orbit');
    future['id'] = 'from-a-pack';
    future['effects'] = [
      {'kind': 'discoBall', 'params': <String, Object?>{}},
    ];
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

  test('two groups may not share a token name', () async {
    // The getters look a token up by its short name, so a second group with
    // the same leaf would shadow the first silently (AUD-16-3).
    final collided = await mutable('orbit');
    groupOf(collided, 'em')['accent'] = 0.1;
    expect(
      () => OrbitTokens.fromThemeJson(collided),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains('accent'), contains('colour'), contains('em')),
        ),
      ),
    );
  });

  test(
    'a pattern is refused when a setting its painter reads is missing',
    () async {
      // `pattern_painter.dart` reads these with `!`: a theme accepted without
      // one throws during paint, after it has been chosen and saved.
      final noColour = await mutable('terminal');
      paramsOf(noColour).remove('colour');
      expect(
        () => OrbitTokens.fromThemeJson(noColour),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('scanlines'), contains('colour')),
          ),
        ),
      );

      final badAlpha = await mutable('terminal');
      paramsOf(badAlpha)['a'] = 'lots';
      expect(() => OrbitTokens.fromThemeJson(badAlpha), throwsFormatException);

      final noTile = await mutable('arcade');
      paramsOf(noTile).remove('size');
      expect(
        () => OrbitTokens.fromThemeJson(noTile),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('size'),
          ),
        ),
      );
    },
  );

  test('a gradient stop that names no colour is refused', () async {
    // A stop may refer to another token; a reference to a token this document
    // does not carry, or to a non-colour, used to be a TypeError that escaped
    // as a crashed folder read rather than a refused theme.
    final wrongType = await mutable('orbit');
    final stops =
        (groupOf(wrongType, 'gradientRef')['brand-gradient'] as Map)['stops']
            as List;
    (stops.first as Map)['token'] = 'r-md';
    expect(
      () => OrbitTokens.fromThemeJson(wrongType),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('not a colour token'),
        ),
      ),
    );

    final absent = await mutable('orbit');
    final absentStops =
        (groupOf(absent, 'gradientRef')['brand-gradient'] as Map)['stops']
            as List;
    (absentStops.first as Map)['token'] = 'no-such-colour';
    expect(() => OrbitTokens.fromThemeJson(absent), throwsFormatException);
  });

  test(
    'a transform or a meta field this build cannot read is a FormatException',
    () async {
      final transform = await mutable('orbit');
      groupOf(transform, 'transform')['display-transform'] = 'wobble';
      expect(
        () => OrbitTokens.fromThemeJson(transform),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('transform'),
          ),
        ),
      );

      final meta = await mutable('orbit');
      meta['name'] = 42;
      expect(
        () => OrbitTokens.fromThemeJson(meta),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('not a string'),
          ),
        ),
      );
    },
  );

  test('themes cross-fade colours and lengths, and switch the rest', () async {
    final a = await mutable('orbit');
    final b = await mutable('orbit');
    (groupOf(a, 'colour')['accent'] as Map)
      ..['hex'] = '#000000'
      ..['alpha'] = 1;
    (groupOf(b, 'colour')['accent'] as Map)
      ..['hex'] = '#FFFFFF'
      ..['alpha'] = 1;
    groupOf(a, 'lengthPx')['r-md'] = 10;
    groupOf(b, 'lengthPx')['r-md'] = 20;
    final orbit = OrbitTokens.fromThemeJson(a);
    final night = OrbitTokens.fromThemeJson(b);

    final half = orbit.lerp(night, 0.5);
    expect(half.accent, isNot(orbit.accent));
    expect(half.accent, isNot(night.accent));
    expect(half.rMd, 15.0);
    expect(orbit.lerp(night, 0), same(night));
    expect(orbit.lerp(night, 1), same(orbit));
  });
}
