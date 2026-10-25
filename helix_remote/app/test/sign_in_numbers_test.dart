import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_copy.dart';
import 'package:helix_remote/features/sign_in/application/sign_in_state.dart';
import 'package:helix_remote_api/v2.dart' show ApiException;
import 'package:helix_remote_domain/models.dart' as domain;
import 'package:helix_remote_protocol/helix_remote_protocol.dart' as protocol;

/// What the sign-in page sends and says, as pure functions (B17).
void main() {
  group('the number the page sends (AUD-15-1)', () {
    String? sent(String typed, {String code = '+880'}) =>
        SignInState(countryCode: code, digits: typed).e164;

    test(
      'a number typed the way the country writes it loses its trunk zero',
      () {
        expect(sent('01711000001'), '+8801711000001');
        expect(sent('01711 000001'), '+8801711000001');
        expect(sent('01711-000-001'), '+8801711000001');
      },
    );

    test('the same number without the zero, and pasted whole, is the same', () {
      expect(sent('1711000001'), '+8801711000001');
      expect(sent('+8801711000001'), '+8801711000001');
      expect(sent('+880 1711 000001'), '+8801711000001');
      expect(sent('008801711000001'), '+8801711000001');
    });

    test('a pasted number from another country ignores the dialling code', () {
      expect(sent('+14155550123'), '+14155550123');
    });

    test('nothing typed, or only a zero, is not a number', () {
      expect(sent(''), isNull);
      expect(sent('0'), isNull);
      expect(sent('  '), isNull);
    });

    test('only one zero is the trunk prefix', () {
      expect(sent('001711000001', code: '+1'), isNot('+11711000001'));
      expect(sent('0171', code: '+880'), '+880171');
    });
  });

  group('the lockout sentence (AUD-15-2)', () {
    test('names the minute the server said, from milliseconds', () {
      final until = DateTime.now().add(const Duration(minutes: 15));
      final text = SignInCopy.passwordRejected(
        ApiException(
          status: 429,
          code: protocol.ErrorCode.passwordLocked,
          details: {'locked_until': until.toUtc().millisecondsSinceEpoch},
        ),
      );
      final hh = until.hour.toString().padLeft(2, '0');
      final mm = until.minute.toString().padLeft(2, '0');
      expect(text, contains('after $hh:$mm'));
    });

    test('without a time it still says to wait', () {
      final text = SignInCopy.passwordRejected(
        const ApiException(
          status: 429,
          code: protocol.ErrorCode.passwordLocked,
        ),
      );
      expect(text, SignInCopy.passwordLocked);
    });
  });

  test('the terms shown are the terms registration sends (AUD-15-3)', () {
    expect(
      domain.HelixLegalDocuments.termsVersion,
      protocol.HelixLegalDocuments.termsVersion,
    );
    expect(
      domain.HelixLegalDocuments.privacyVersion,
      protocol.HelixLegalDocuments.privacyVersion,
    );
  });
}
