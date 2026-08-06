import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/services/log_redaction.dart';

/// Regression suite for HIGH-1 in
/// docs/operations/ENTERPRISE_READINESS_AUDIT_2026-08-06.md.
///
/// AppLogger appended messages verbatim to a plaintext file that the settings
/// screen then hands to an arbitrary app through the share sheet, while
/// docs/security/LOG_REDACTION.md required tokens, key material and payloads
/// to be redacted. These cases are the specific shapes that reached that file.
void main() {
  group('secrets are removed', () {
    test('bearer tokens', () {
      final out = redactLogLine(
        'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJhY2NvdW50X2lkIjoiYSJ9.sig',
      );
      expect(out, contains(kRedacted));
      expect(out, isNot(contains('eyJhbGciOiJIUzI1NiJ9')));
      // The label survives, so the line still says what was removed.
      expect(out.toLowerCase(), contains('bearer'));
    });

    test('OTP codes and phone numbers in a query string', () {
      final out = redactLogLine(
        'POST https://hr.example.com/api/v1/accounts/phone/otp/request'
        '?phone_number=+8801712345678&otp_code=482913',
      );
      expect(out, isNot(contains('8801712345678')));
      expect(out, isNot(contains('482913')));
      expect(out, contains('otp_code=$kRedacted'));
    });

    test('invite codes in a URL — the LOW-3 leak path', () {
      final out = redactLogLine(
        'uri = https://hr.example.com/api/v1/accounts/invite/lookup'
        '?invite_code=HELIX-7Q2M-88XZ',
      );
      expect(out, isNot(contains('HELIX-7Q2M-88XZ')));
      expect(out, contains('invite_code=$kRedacted'));
    });

    test('sensitive JSON fields in a server error body', () {
      final out = redactLogLine(
        '{"error":"bad","refresh_token":"abc123def456","ciphertext":"AAAABBBB"}',
      );
      expect(out, isNot(contains('abc123def456')));
      expect(out, isNot(contains('AAAABBBB')));
      // Non-sensitive fields are left alone so the line stays diagnostic.
      expect(out, contains('"error":"bad"'));
    });

    test('bare phone numbers in free text', () {
      final out = redactLogLine('OTP request failed for +880 171 234 5678');
      expect(out, isNot(contains('5678')));
      expect(out, contains(kRedacted));
    });

    test('high-entropy key material', () {
      const hex =
          'a3f5c1d9e8b7a6f4c3d2e1b0a9f8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2a1f0';
      const b64 = 'dGhpc19pc19hX3ZlcnlfbG9uZ19iYXNlNjRfa2V5X2Jsb2JfdmFsdWU';
      expect(redactLogLine('key=$hex'), isNot(contains(hex)));
      expect(redactLogLine('blob $b64'), isNot(contains(b64)));
    });
  });

  group('diagnostic value is preserved', () {
    test('ordinary log lines pass through untouched', () {
      const lines = [
        'WSClient connecting generation=2 host=hr.example.com path=/api/v1/ws',
        'engine create_offer begin video=false cid=3f930a34',
        'closed — close_code=1002 reason=none',
        'sync applied 12 events, cursor=8891',
      ];
      for (final line in lines) {
        expect(
          redactLogLine(line),
          equals(line),
          reason: 'diagnostics must survive redaction',
        );
      }
    });

    test('short identifiers are not mistaken for secrets', () {
      // Call ids, message ids and the client's own 16-hex account id all sit
      // below the entropy floors on purpose.
      const line = 'cid=3f930a34 account=a1b2c3d4e5f60718 msg=msg_42';
      expect(redactLogLine(line), equals(line));
    });

    test('redaction is idempotent', () {
      const input = 'Authorization: Bearer sometokenvalue123456';
      final once = redactLogLine(input);
      expect(redactLogLine(once), equals(once));
    });

    test('empty input is handled', () {
      expect(redactLogLine(''), equals(''));
    });
  });

  group('volume is bounded', () {
    test('long messages are truncated with a marker', () {
      final long = 'x' * 2000;
      final out = truncateForLog(long, maxLength: 100);
      expect(out.length, lessThan(200));
      expect(out, contains('truncated'));
    });

    test('short messages are untouched', () {
      const short = 'REST 503';
      expect(truncateForLog(short), equals(short));
    });
  });

  group('the exact shapes from the anomaly log', () {
    // Reproduced from docs/operations/HELIX_REMEDIATION_PLAN.md, which quotes
    // a real captured log line carrying a full API URI and server body.
    test('an uncaught HttpException with URI and body', () {
      const line =
          '[uncaught] HttpException: {"error":"TURN is not configured",'
          '"turn_configured":false}, uri = '
          'https://hr.example.com/api/v1/calls/turn-credentials';
      final out = redactLogLine(line);
      // Nothing secret in this particular one, so it must survive: the point
      // is that redaction does not destroy the diagnostics that made this
      // finding traceable in the first place.
      expect(out, contains('TURN is not configured'));
      expect(out, contains('turn-credentials'));
    });

    test('the same shape carrying a token stays redacted', () {
      const line =
          '[uncaught] HttpException: {"refresh_token":"v4.public.longvalue"}, '
          'uri = https://hr.example.com/api/v1/accounts/refresh?token=abc123';
      final out = redactLogLine(line);
      expect(out, isNot(contains('v4.public.longvalue')));
      expect(out, isNot(contains('abc123')));
      expect(out, contains('accounts/refresh'));
    });
  });
}
