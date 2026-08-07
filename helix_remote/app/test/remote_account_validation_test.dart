import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/remote_account_validation.dart';

void main() {
  group('RemoteAccountValidation', () {
    test('normalizes and validates phone numbers consistently', () {
      expect(
        RemoteAccountValidation.normalizePhoneNumber(' +1 (555) 123-4567 '),
        '+15551234567',
      );
      expect(
        RemoteAccountValidation.normalizePhoneNumber('01712-345678'),
        '+8801712345678',
      );
      expect(
        RemoteAccountValidation.normalizePhoneNumber('+880 (1712) 345-678'),
        '+8801712345678',
      );
      expect(
        RemoteAccountValidation.normalizePhoneNumber('8801712345678'),
        '+8801712345678',
      );
      expect(RemoteAccountValidation.phoneNumberError('+15551234567'), isNull);
      expect(
        RemoteAccountValidation.phoneNumberError(''),
        contains('cannot be empty'),
      );
      expect(
        RemoteAccountValidation.phoneNumberError('12345'),
        contains('valid phone number'),
      );
      expect(
        RemoteAccountValidation.phoneNumberError('+0123'),
        contains('valid phone number'),
      );
      expect(
        RemoteAccountValidation.isValidPhoneNumber('+15551234567'),
        isTrue,
      );
    });

    test('validates display names with backend limits', () {
      expect(RemoteAccountValidation.normalizeDisplayName(' Alice '), 'Alice');
      expect(RemoteAccountValidation.displayNameError('Alice'), isNull);
      expect(
        RemoteAccountValidation.displayNameError('   '),
        contains('cannot be empty'),
      );
      expect(
        RemoteAccountValidation.displayNameError(List.filled(81, 'a').join()),
        contains('80 characters or less'),
      );
    });
  });
}
