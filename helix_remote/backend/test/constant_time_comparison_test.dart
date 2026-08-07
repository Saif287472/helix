// MED-3 — non-constant-time comparison of secrets.
//
// `jwt.dart` compared HMAC signatures with `!=` on String, and
// `server_impl.dart` compared the raw admin bearer token and its SHA-256 hex
// the same way. String equality short-circuits at the first differing byte,
// which times how much of a forged value was correct.
//
// This does not attempt to measure timing — a wall-clock assertion in a test
// suite is a flake generator, and on a JIT VM it measures the optimiser as
// much as the algorithm. What it pins is the two things that are actually
// checkable: the comparator is correct for every case a naive `==` would
// handle, and the call sites still use it.

import 'dart:io';

import 'package:test/test.dart';
import 'package:helix_remote_backend/src/constant_time.dart';

void main() {
  group('constantTimeStringEqual agrees with == on every case', () {
    test('identical strings compare equal', () {
      expect(constantTimeStringEqual('', ''), isTrue);
      expect(constantTimeStringEqual('a', 'a'), isTrue);
      expect(constantTimeStringEqual('c1cbd06a51a4', 'c1cbd06a51a4'), isTrue);
    });

    test('a difference anywhere is caught', () {
      // First byte, last byte, and the middle. A short-circuiting comparison
      // gets all three right too — the point is that this one must not
      // regress into being merely *fast* at the first case.
      expect(constantTimeStringEqual('xbcdef', 'abcdef'), isFalse);
      expect(constantTimeStringEqual('abcdex', 'abcdef'), isFalse);
      expect(constantTimeStringEqual('abcxef', 'abcdef'), isFalse);
    });

    test('different lengths are unequal, including prefixes', () {
      expect(constantTimeStringEqual('abc', 'abcdef'), isFalse);
      expect(constantTimeStringEqual('abcdef', 'abc'), isFalse);
      expect(constantTimeStringEqual('', 'a'), isFalse);
      expect(constantTimeStringEqual('a', ''), isFalse);
    });

    test('non-ASCII is compared by the same rule', () {
      expect(constantTimeStringEqual('হেলিক্স', 'হেলিক্স'), isTrue);
      expect(constantTimeStringEqual('হেলিক্স', 'হেলিকস'), isFalse);
    });
  });

  group('the call sites still use it', () {
    // Source assertions rather than behavioural ones: a reintroduced `==`
    // would be behaviourally identical and silently reopen the finding.
    test('JWT signature comparison is constant time', () {
      final jwt = File('lib/src/jwt.dart').readAsStringSync();

      expect(jwt, contains('constantTimeStringEqual(signature'));
      expect(
        RegExp(r'signature\s*!=\s*expectedSignature').hasMatch(jwt),
        isFalse,
        reason:
            'short-circuiting equality times how much of a forged '
            'signature was correct',
      );
    });

    test('admin token comparison is constant time', () {
      final server = File('lib/src/server_impl.dart').readAsStringSync();

      // Both the raw bearer token and its stored hash.
      expect(
        'constantTimeStringEqual'.allMatches(server).length,
        greaterThanOrEqualTo(2),
      );
      expect(
        RegExp(r'token\s*==\s*adminTokenOverride').hasMatch(server),
        isFalse,
      );
    });
  });
}
