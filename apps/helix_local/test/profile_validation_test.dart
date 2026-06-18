// test/profile_validation_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:helix/providers/controllers/profile_service.dart';

void main() {
  // ProfileService constructor requires no arguments and has no async init for
  // validation — we can instantiate it directly in tests.
  late ProfileService svc;

  setUp(() {
    svc = ProfileService();
  });

  // ── Display name validation ────────────────────────────────────────────────

  group('Display name validation', () {
    test('accepts a valid two-character name', () {
      expect(svc.validateDisplayName('AB'), isNull);
    });

    test('accepts a valid name at the upper boundary (32 chars)', () {
      expect(svc.validateDisplayName('A' * 31 + 'B'), isNull);
    });

    test('accepts names with spaces and unicode letters', () {
      expect(svc.validateDisplayName('Alice Bob'), isNull);
      expect(svc.validateDisplayName('Ĉéñt'), isNull);
    });

    test('rejects a name that is too short (1 char)', () {
      final err = svc.validateDisplayName('A');
      expect(err, isNotNull);
      expect(err, contains('at least'));
    });

    test('rejects an empty name', () {
      final err = svc.validateDisplayName('');
      expect(err, isNotNull);
    });

    test('rejects a name that is too long (33 chars)', () {
      final err = svc.validateDisplayName('A' * 33);
      expect(err, isNotNull);
      expect(err, contains('at most'));
    });

    test('rejects a name containing a tab control character (\\t)', () {
      final err = svc.validateDisplayName('Al\tice');
      expect(err, isNotNull);
      expect(err, contains('control'));
    });

    test('rejects a name containing a newline control character (\\n)', () {
      final err = svc.validateDisplayName('Al\nice');
      expect(err, isNotNull);
    });

    test('rejects a name containing DEL (0x7F)', () {
      final err = svc.validateDisplayName('Al\x7Fice');
      expect(err, isNotNull);
    });

    test('rejects invisible-only name (single repeated space)', () {
      // A string of two spaces has runes.toSet().length == 1
      final err = svc.validateDisplayName('  ');
      expect(err, isNotNull);
    });

    test('rejects repeated-char name (all same letter)', () {
      final err = svc.validateDisplayName('AAAA');
      expect(err, isNotNull);
    });

    test('accepts a name whose chars are not all the same', () {
      expect(svc.validateDisplayName('AaB'), isNull);
    });
  });

  // ── Secret code validation ─────────────────────────────────────────────────

  group('Secret code validation', () {
    // 12 chars = minimum
    const validCode = 'correct horse'; // 13 chars, multiple unique chars
    const validLong = 'a b c d e f g h i j k'; // 21 chars

    test('accepts a valid code at minimum length (8 chars)', () {
      expect(svc.validateSecretCode('abcdefgh'), isNull);
    });

    test('accepts a valid multi-word passphrase', () {
      expect(svc.validateSecretCode(validCode), isNull);
      expect(svc.validateSecretCode(validLong), isNull);
    });

    test('accepts a code at the upper boundary (64 chars)', () {
      expect(svc.validateSecretCode('a' * 63 + 'b'), isNull);
    });

    test('rejects a code shorter than 8 chars', () {
      final err = svc.validateSecretCode('short7'); // 6 chars
      expect(err, isNotNull);
      expect(err, contains('at least'));
    });

    test('rejects an empty code', () {
      final err = svc.validateSecretCode('');
      expect(err, isNotNull);
    });

    test('rejects a code longer than 64 chars', () {
      final err = svc.validateSecretCode('a' * 65);
      expect(err, isNotNull);
      expect(err, contains('at most'));
    });

    test('rejects a code containing a control character', () {
      final err = svc.validateSecretCode('correct\nhorse battery');
      expect(err, isNotNull);
      expect(err, contains('control'));
    });

    test('rejects a repeated-char-only code (all same character)', () {
      // 8 chars all identical
      final err = svc.validateSecretCode('a' * 8);
      expect(err, isNotNull);
    });

    test('accepts a code whose chars are not all the same', () {
      // 8 chars, two distinct chars
      expect(svc.validateSecretCode('aaaaaaB1'), isNull);
    });
  });
}
