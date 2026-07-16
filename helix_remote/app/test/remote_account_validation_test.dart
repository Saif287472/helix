import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/app/remote_account_validation.dart';

void main() {
  group('RemoteAccountValidation', () {
    test('normalizes and validates usernames consistently', () {
      expect(
        RemoteAccountValidation.normalizeUsername(' Alice_01 '),
        'alice_01',
      );
      expect(RemoteAccountValidation.usernameError('alice_01'), isNull);
      expect(
        RemoteAccountValidation.usernameError('ab'),
        contains('at least 3'),
      );
      expect(
        RemoteAccountValidation.usernameError('helix_admin'),
        contains('reserved'),
      );
      expect(
        RemoteAccountValidation.usernameError('bad-name'),
        contains('underscores only'),
      );
      expect(
        RemoteAccountValidation.usernameError(List.filled(31, 'a').join()),
        contains('30 characters or less'),
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
