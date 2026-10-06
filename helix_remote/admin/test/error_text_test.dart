import 'package:flutter_test/flutter_test.dart';
import 'package:helix_admin/src/api/error_text.dart';
import 'package:helix_remote_api/v2.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';

ApiException api(
  ErrorCode code, {
  Duration? retryAfter,
  DateTime? lockedUntil,
  String? requestId,
}) => ApiException(
  status: code.status,
  code: code,
  message: 'SECRET-SERVER-WORDING',
  retryAfter: retryAfter,
  details: lockedUntil == null
      ? null
      : {'locked_until': toWireTime(lockedUntil)},
  requestId: requestId,
);

void main() {
  final now = DateTime.utc(2026, 10, 2, 12);

  test('describeWait rounds up and never says zero', () {
    expect(describeWait(Duration.zero), '1 second');
    expect(describeWait(const Duration(seconds: 1)), '1 second');
    expect(describeWait(const Duration(seconds: 45)), '45 seconds');
    expect(describeWait(const Duration(seconds: 61)), '2 minutes');
    expect(describeWait(const Duration(minutes: 15)), '15 minutes');
    expect(describeWait(const Duration(minutes: 61)), '2 hours');
    expect(describeWait(const Duration(hours: 24)), '24 hours');
  });

  group('lockout', () {
    test('uses Retry-After when the server sent it', () {
      expect(
        describeAdminError(
          api(
            ErrorCode.passwordLocked,
            retryAfter: const Duration(minutes: 15),
          ),
          now: () => now,
        ),
        'Sign-in is locked after too many wrong passwords. Try again in '
        '15 minutes.',
      );
    });

    test('falls back to locked_until', () {
      expect(
        describeAdminError(
          api(
            ErrorCode.passwordLocked,
            lockedUntil: now.add(const Duration(hours: 2)),
          ),
          now: () => now,
        ),
        contains('in 2 hours'),
      );
    });

    test('says "later" when there is no time at all', () {
      expect(
        describeAdminError(api(ErrorCode.passwordLocked), now: () => now),
        endsWith('Try again later.'),
      );
    });
  });

  test('never repeats the server wording', () {
    for (final code in ErrorCode.values) {
      expect(
        describeAdminError(api(code, requestId: 'req-1')),
        isNot(contains('SECRET-SERVER-WORDING')),
        reason: code.wire,
      );
    }
  });

  test('server problems carry the request id for the server log', () {
    expect(
      describeAdminError(api(ErrorCode.internal, requestId: 'req-42')),
      'The server had a problem. Try again later. (request req-42)',
    );
    // A refusal the operator can act on needs no id.
    expect(
      describeAdminError(api(ErrorCode.notFound, requestId: 'req-42')),
      'That item no longer exists.',
    );
  });

  test('network and protocol failures', () {
    expect(
      describeAdminError(const NetworkException()),
      contains('Could not reach the server'),
    );
    expect(
      describeAdminError(const NetworkException(timedOut: true)),
      contains('took too long'),
    );
    expect(
      describeAdminError(const MalformedResponseException(path: 'x')),
      contains('Helix v2 server'),
    );
    expect(describeAdminError(StateError('boom')), 'Something went wrong.');
  });

  group('endsAdminSession', () {
    test('a rejected token ends it', () {
      expect(
        endsAdminSession(
          const SignedOutException(SignedOutReason.sessionEnded),
        ),
        isTrue,
      );
      expect(endsAdminSession(api(ErrorCode.unauthenticated)), isTrue);
      expect(endsAdminSession(api(ErrorCode.tokenExpired)), isTrue);
    });

    test('a wrong password (also a 401) does not', () {
      expect(endsAdminSession(api(ErrorCode.invalidCredentials)), isFalse);
    });

    test('other failures do not', () {
      expect(endsAdminSession(api(ErrorCode.forbidden)), isFalse);
      expect(endsAdminSession(api(ErrorCode.internal)), isFalse);
      expect(endsAdminSession(const NetworkException()), isFalse);
    });
  });
}
