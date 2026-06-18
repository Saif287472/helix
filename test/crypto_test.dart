// test/crypto_test.dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart' as cvt;
import 'package:crypto/crypto.dart' as pkg_crypto;
import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:flutter_test/flutter_test.dart';

import 'package:helix_domain/core/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers that mirror the production logic in ProfileService
// ─────────────────────────────────────────────────────────────────────────────

/// Derives an Argon2id key from [code] + [salt] using the project constants.
/// Returns the raw hash bytes.
Future<List<int>> _deriveArgon2id(String code, Uint8List salt) async {
  final argon2 = cryptography.Argon2id(
    memory: kArgon2Memory,
    parallelism: kArgon2Parallelism,
    iterations: kArgon2Time,
    hashLength: kArgon2HashLength,
  );

  final secretKey = await argon2.deriveKey(
    secretKey: cryptography.SecretKey(utf8.encode(code)),
    nonce: salt,
  );

  return secretKey.extractBytes();
}

/// Produces a 4-character lowercase hex device suffix from [publicKeyDerBytes].
String _deviceSuffix(List<int> publicKeyDerBytes) {
  final digest = pkg_crypto.sha256.convert(publicKeyDerBytes);
  return cvt.hex.encode(digest.bytes).substring(0, 4);
}

/// Produces a 32-character lowercase hex session ID from 16 random bytes.
String _generateSessionId() {
  final rng = Random.secure();
  final bytes = Uint8List(kSessionIdBytes);
  for (var i = 0; i < kSessionIdBytes; i++) {
    bytes[i] = rng.nextInt(256);
  }
  return cvt.hex.encode(bytes);
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  // Fixed salt used for determinism tests.
  final fixedSalt = Uint8List.fromList(List.generate(kSaltBytes, (i) => i));

  group('Argon2id derivation', () {
    test(
      'produces consistent output for the same input and salt',
      () async {
        const code = 'correct horse battery staple twelve';

        final hash1 = await _deriveArgon2id(code, fixedSalt);
        final hash2 = await _deriveArgon2id(code, fixedSalt);

        expect(hash1, equals(hash2));
      },
      // Argon2id with 64 MiB memory takes ~500 ms on a fast machine — allow
      // up to 30 seconds in CI environments.
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'output is exactly kArgon2HashLength bytes',
      () async {
        const code = 'correct horse battery staple twelve';
        final hash = await _deriveArgon2id(code, fixedSalt);
        expect(hash.length, equals(kArgon2HashLength));
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'produces different output for different secret codes',
      () async {
        const code1 = 'correct horse battery staple twelve';
        const code2 = 'different passphrase entirely here';

        final hash1 = await _deriveArgon2id(code1, fixedSalt);
        final hash2 = await _deriveArgon2id(code2, fixedSalt);

        expect(hash1, isNot(equals(hash2)));
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'produces different output for same code with different salts',
      () async {
        const code = 'correct horse battery staple twelve';
        final salt2 = Uint8List.fromList(
          List.generate(kSaltBytes, (i) => i + 1),
        );

        final hash1 = await _deriveArgon2id(code, fixedSalt);
        final hash2 = await _deriveArgon2id(code, salt2);

        expect(hash1, isNot(equals(hash2)));
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );

    test(
      'output is non-zero (not an all-zero hash)',
      () async {
        const code = 'correct horse battery staple twelve';
        final hash = await _deriveArgon2id(code, fixedSalt);
        expect(hash.any((b) => b != 0), isTrue);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });

  group('Device suffix', () {
    // Simulate a minimal DER public-key blob (not a real RSA key — just bytes
    // for the fingerprinting logic).
    final fakeKeyBytes1 = List.generate(256, (i) => i & 0xFF);
    final fakeKeyBytes2 = List.generate(256, (i) => (i + 1) & 0xFF);

    test('is exactly 4 hex characters', () {
      final suffix = _deviceSuffix(fakeKeyBytes1);
      expect(suffix.length, equals(4));
    });

    test('contains only lowercase hex characters', () {
      final suffix = _deviceSuffix(fakeKeyBytes1);
      expect(RegExp(r'^[0-9a-f]{4}$').hasMatch(suffix), isTrue);
    });

    test('is deterministic for the same key bytes', () {
      final s1 = _deviceSuffix(fakeKeyBytes1);
      final s2 = _deviceSuffix(fakeKeyBytes1);
      expect(s1, equals(s2));
    });

    test('differs for different key bytes', () {
      final s1 = _deviceSuffix(fakeKeyBytes1);
      final s2 = _deviceSuffix(fakeKeyBytes2);
      expect(s1, isNot(equals(s2)));
    });
  });

  group('Session ID generation', () {
    test('is exactly 32 lowercase hex characters', () {
      final id = _generateSessionId();
      expect(id.length, equals(32));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(id), isTrue);
    });

    test('is different on successive calls (statistically)', () {
      // Generating two random 128-bit IDs that collide has a 2^-128 probability.
      final id1 = _generateSessionId();
      final id2 = _generateSessionId();
      expect(id1, isNot(equals(id2)));
    });

    test('encodes exactly kSessionIdBytes of entropy', () {
      // 32 hex chars = 16 bytes = kSessionIdBytes * 8 bits.
      final id = _generateSessionId();
      expect(id.length, equals(kSessionIdBytes * 2));
    });
  });
}
