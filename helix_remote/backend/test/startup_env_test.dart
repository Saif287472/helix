// Backend startup used to check HELIX_REMOTE_JWT_SECRET alone and leave
// every other credential (SMS, FCM, TURN) silently defaulting to an inert
// fallback with no way to tell "intentionally unset" apart from "typo'd the
// variable name" until the feature failed at first use in production.
// validateStartupEnv aggregates all of that into one pass so a misconfigured
// deploy sees every problem at once, at boot, instead of one at a time in
// production logs.

import 'package:helix_remote_backend/src/startup_env.dart';
import 'package:test/test.dart';

void main() {
  group('required vars', () {
    test('missing HELIX_REMOTE_JWT_SECRET is fatal', () {
      final result = validateStartupEnv({}, devMode: false);
      expect(result.isFatal, isTrue);
      expect(
        result.fatalErrors,
        contains('HELIX_REMOTE_JWT_SECRET is required but not set.'),
      );
    });

    test('a whitespace-only secret counts as missing', () {
      final result = validateStartupEnv({
        'HELIX_REMOTE_JWT_SECRET': '   ',
      }, devMode: false);
      expect(result.isFatal, isTrue);
    });

    test('a present secret of sufficient length is not fatal on its own', () {
      final result = validateStartupEnv({
        'HELIX_REMOTE_JWT_SECRET': 'x' * 32,
      }, devMode: false);
      expect(result.isFatal, isFalse);
    });

    test('a short secret is fatal outside dev mode', () {
      final result = validateStartupEnv({
        'HELIX_REMOTE_JWT_SECRET': 'too-short',
      }, devMode: false);
      expect(result.isFatal, isTrue);
      expect(
        result.fatalErrors.any((e) => e.contains('at least 32 bytes')),
        isTrue,
      );
    });

    test('a short secret is allowed in dev mode', () {
      final result = validateStartupEnv({
        'HELIX_REMOTE_JWT_SECRET': 'dev-secret',
      }, devMode: true);
      expect(result.isFatal, isFalse);
    });

    test('missing secret is still fatal even in dev mode', () {
      final result = validateStartupEnv({}, devMode: true);
      expect(result.isFatal, isTrue);
    });
  });

  group('conditional groups', () {
    Map<String, String> baseEnv() => {'HELIX_REMOTE_JWT_SECRET': 'x' * 32};

    test('all vars in a group unset is a warning, not fatal', () {
      final result = validateStartupEnv(baseEnv(), devMode: false);
      expect(result.isFatal, isFalse);
      expect(result.warnings.any((w) => w.contains('SMS delivery')), isTrue);
    });

    test('warnings are suppressed in dev mode', () {
      final result = validateStartupEnv(baseEnv(), devMode: true);
      expect(result.warnings, isEmpty);
    });

    test('all vars in a group set is neither fatal nor a warning', () {
      final env = baseEnv()
        ..addAll({
          'HELIX_REMOTE_SMS_API_KEY': 'key',
          'HELIX_REMOTE_SMS_SENDER_ID': 'sender',
        });
      final result = validateStartupEnv(env, devMode: false);
      expect(result.isFatal, isFalse);
      expect(result.warnings.any((w) => w.contains('SMS delivery')), isFalse);
    });

    test('one var set and its pair missing is fatal', () {
      final env = baseEnv()..addAll({'HELIX_REMOTE_SMS_API_KEY': 'key'});
      final result = validateStartupEnv(env, devMode: false);
      expect(result.isFatal, isTrue);
      expect(
        result.fatalErrors.any(
          (e) =>
              e.contains('SMS delivery') &&
              e.contains('HELIX_REMOTE_SMS_SENDER_ID'),
        ),
        isTrue,
      );
    });

    test('a partial pair is fatal even in dev mode', () {
      final env = baseEnv()..addAll({'HELIX_REMOTE_FCM_PROJECT_ID': 'project'});
      final result = validateStartupEnv(env, devMode: true);
      expect(result.isFatal, isTrue);
    });

    test('quoted/CRLF-wrapped values are sanitized before being judged', () {
      final env = baseEnv()
        ..addAll({
          'HELIX_REMOTE_SMS_API_KEY': '"key"\r',
          'HELIX_REMOTE_SMS_SENDER_ID': '"sender"\r',
        });
      final result = validateStartupEnv(env, devMode: false);
      expect(result.isFatal, isFalse);
      expect(result.warnings.any((w) => w.contains('SMS delivery')), isFalse);
    });

    test('multiple problems are all reported in one pass', () {
      final env = {
        'HELIX_REMOTE_JWT_SECRET': 'too-short',
        'HELIX_REMOTE_SMS_API_KEY': 'key',
      };
      final result = validateStartupEnv(env, devMode: false);
      expect(result.fatalErrors.length, greaterThanOrEqualTo(2));
    });
  });
}
