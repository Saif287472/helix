import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote/core/platform/phone_numbers.dart';
import 'package:helix_remote/features/people/application/people_search.dart';

/// Numbers as the engine wants them (E.164), and a search box read the way a
/// person meant it.
void main() {
  group('PhoneNumbers.normalize', () {
    String? n(String raw, {String? code, bool guess = false}) =>
        PhoneNumbers.normalize(
          raw,
          defaultCallingCode: code,
          guessNational: guess,
        );

    test('international forms', () {
      expect(n('+8801711000001'), '+8801711000001');
      expect(n('+880 1711-000001'), '+8801711000001');
      expect(n('(+880) 1711 000 001'), '+8801711000001');
      expect(n('008801711000001'), '+8801711000001');
      expect(n('+1 (202) 555-0123'), '+12025550123');
    });

    test('a leading zero is the national prefix of the account\'s country', () {
      expect(n('01711000001', code: '880'), '+8801711000001');
      expect(n('01711-000001', code: '880'), '+8801711000001');
      expect(n('020 7946 0958', code: '44'), '+442079460958');
    });

    test('without a country a national number is refused, not guessed', () {
      expect(n('01711000001'), isNull);
      expect(n('01711000001', guess: true), isNull);
    });

    test('digits without a plus are international unless guessing', () {
      expect(n('8801711000001', code: '880'), '+8801711000001');
      expect(n('8801711000001'), '+8801711000001');
      // The address book never guesses...
      expect(n('1711000001', code: '880'), '+1711000001');
      // ...a typed search does, when it is short enough to be national.
      expect(n('1711000001', code: '880', guess: true), '+8801711000001');
      expect(n('8801711000001', code: '880', guess: true), '+8801711000001');
    });

    test('things that are not numbers', () {
      expect(n(''), isNull);
      expect(n('   '), isNull);
      expect(n('Sam'), isNull);
      expect(n('+88017'), isNull, reason: 'too short');
      expect(n('+0123456789'), isNull, reason: 'no country starts with 0');
      expect(n('+1234567890123456'), isNull, reason: 'longer than E.164');
      expect(n('0'), isNull);
    });
  });

  group('PhoneNumbers calling codes', () {
    test('are split by the prefix-free structure', () {
      expect(PhoneNumbers.callingCodeOf('+8801711000001'), '880');
      expect(PhoneNumbers.callingCodeOf('+12025550123'), '1');
      expect(PhoneNumbers.callingCodeOf('+79991234567'), '7');
      expect(PhoneNumbers.callingCodeOf('+442079460958'), '44');
      expect(PhoneNumbers.callingCodeOf('+919876543210'), '91');
      expect(PhoneNumbers.callingCodeOf('+353871234567'), '353');
      expect(PhoneNumbers.callingCodeOf('01711000001'), isNull);
    });

    test('display sets the country code apart; the mask hides the middle', () {
      expect(PhoneNumbers.display('+8801711000001'), '+880 1711000001');
      expect(PhoneNumbers.display('not a number'), 'not a number');
      final masked = PhoneNumbers.masked('+8801711000001');
      expect(masked, isNot(contains('1711000')));
      expect(masked, endsWith('01'));
    });

    test('PhoneCountry follows the account\'s own number', () {
      final country = PhoneCountry()..setFromOwnNumber('+8801711000000');
      expect(country.callingCode, '880');
      country.setFromOwnNumber(null);
      expect(country.callingCode, isNull);
    });
  });

  group('PhoneNumbers.looksLikeNumber', () {
    test('digits and separators are a number, words are not', () {
      expect(PhoneNumbers.looksLikeNumber('+880 1711-000001'), isTrue);
      expect(PhoneNumbers.looksLikeNumber('(017) 11'), isTrue);
      expect(PhoneNumbers.looksLikeNumber('01'), isFalse);
      expect(PhoneNumbers.looksLikeNumber('Sam 12345'), isFalse);
      expect(PhoneNumbers.looksLikeNumber('~sam'), isFalse);
      expect(PhoneNumbers.looksLikeNumber(''), isFalse);
    });
  });

  group('PeopleQuery.parse', () {
    PeopleQuery q(String text, {String? code = '880'}) =>
        PeopleQuery.parse(text, callingCode: code);

    test('nothing typed browses', () {
      expect(q('').intent, SearchIntent.browse);
      expect(q('   ').isBrowse, isTrue);
    });

    test('~name is a Helix name lookup, lower-cased', () {
      final query = q('~Sam_R');
      expect(query.intent, SearchIntent.helixName);
      expect(query.helixName, 'sam_r');
      expect(query.canLookUp, isTrue);
    });

    test('a ~name that cannot be a Helix name is searched locally only', () {
      final query = q('~a');
      expect(query.intent, SearchIntent.helixName);
      expect(query.helixName, isNull);
      expect(query.canLookUp, isFalse);
      expect(query.text, 'a');
    });

    test('a number is read in the account\'s country', () {
      final query = q('01711-000001');
      expect(query.intent, SearchIntent.phone);
      expect(query.e164, '+8801711000001');
      expect(query.digits, '1711000001');
      expect(query.canLookUp, isTrue);
    });

    test('a number that cannot be placed yet is not looked up', () {
      expect(q('01711000001', code: null).e164, isNull);
      expect(q('01711000001', code: null).canLookUp, isFalse);
      expect(q('017').e164, isNull, reason: 'too short');
    });

    test('a name that could be a Helix name offers the lookup', () {
      final query = q('Sam');
      expect(query.intent, SearchIntent.text);
      expect(query.helixName, 'sam');
      expect(query.canLookUp, isTrue);
      expect(q('Sam Smith').helixName, isNull, reason: 'a space');
      expect(q('Sam Smith').canLookUp, isFalse);
    });
  });
}
