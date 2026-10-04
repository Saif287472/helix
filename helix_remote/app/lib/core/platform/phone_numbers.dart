import 'package:helix_remote_engine/helix_remote_engine.dart' show maskPhone;

/// Phone numbers as the engine wants them: E.164 (`+8801711000001`).
///
/// Discovery hashes `HMAC-SHA256(salt, E.164)`, so a number that is not in
/// exactly that form finds nobody. The people a person types and the contacts
/// a phone stores are written every way there is (`01711-000001`,
/// `+880 1711 000001`, `00880…`), which is what this normalises.
///
/// There is no libphonenumber here, on purpose: it is a large dependency for
/// one job. The one thing a bare national number needs is the caller's own
/// country code, and that is the prefix of this account's own number.
abstract final class PhoneNumbers {
  // Calling codes are prefix-free: one digit (1, 7), two digits (the set
  // below) or three. That is all the structure splitting a number needs.
  static const _oneDigit = {'1', '7'};
  static const _twoDigit = {
    '20', '27', //
    '30', '31', '32', '33', '34', '36', '39', //
    '40', '41', '43', '44', '45', '46', '47', '48', '49', //
    '51', '52', '53', '54', '55', '56', '57', '58', //
    '60', '61', '62', '63', '64', '65', '66', //
    '81', '82', '84', '86', //
    '90', '91', '92', '93', '94', '95', '98',
  };

  static final _international = RegExp(r'^\+[1-9]\d{6,14}$');
  static final _separators = RegExp(r'[\s()\-.]');
  static final _typedNumber = RegExp(r'^\+?[\d\s().\-]+$');

  /// The country calling code at the start of [e164] (`880` for
  /// `+8801711000001`), or null when it is not an E.164 number.
  static String? callingCodeOf(String e164) {
    if (!_international.hasMatch(e164)) return null;
    final digits = e164.substring(1);
    if (_oneDigit.contains(digits[0])) return digits[0];
    final two = digits.substring(0, 2);
    if (_twoDigit.contains(two)) return two;
    return digits.substring(0, 3);
  }

  /// [raw] as E.164, or null when it is not a number this app can match on.
  ///
  /// - `+…` and `00…` are international already.
  /// - A single leading `0` is the national trunk prefix: it is replaced by
  ///   [defaultCallingCode] (`01711000001` -> `+8801711000001`). Without a
  ///   default the number cannot be placed in a country, so it is refused
  ///   rather than guessed.
  /// - Anything else is the digits of an international number without its
  ///   `+`, unless [guessNational] is set and it is short enough to be a
  ///   national number (at most ten digits) that does not already start with
  ///   [defaultCallingCode]. Typing a number into search guesses; reading the
  ///   address book does not, because attaching a stranger's name to the wrong
  ///   account is worse than missing a match.
  static String? normalize(
    String raw, {
    String? defaultCallingCode,
    bool guessNational = false,
  }) {
    var digits = raw.trim().replaceAll(_separators, '');
    if (digits.isEmpty) return null;
    if (digits.startsWith('+')) return _checked(digits);
    if (!RegExp(r'^\d+$').hasMatch(digits)) return null;
    if (digits.startsWith('00')) return _checked('+${digits.substring(2)}');
    final code = defaultCallingCode;
    if (digits.startsWith('0')) {
      if (code == null) return null;
      digits = digits.substring(1);
      return digits.isEmpty ? null : _checked('+$code$digits');
    }
    if (guessNational &&
        code != null &&
        !digits.startsWith(code) &&
        digits.length <= 10) {
      return _checked('+$code$digits');
    }
    return _checked('+$digits');
  }

  static String? _checked(String candidate) =>
      _international.hasMatch(candidate) ? candidate : null;

  /// Whether the text a person typed is written as a phone number (digits
  /// and the usual separators, at least three digits) rather than a name.
  static bool looksLikeNumber(String query) {
    final text = query.trim();
    if (!_typedNumber.hasMatch(text)) return false;
    return text.replaceAll(RegExp(r'\D'), '').length >= 3;
  }

  /// `+880 1711000001`: the number with its country code set apart, for
  /// reading. Anything that is not E.164 comes back unchanged.
  static String display(String number) {
    final code = callingCodeOf(number);
    if (code == null) return number;
    return '+$code ${number.substring(1 + code.length)}';
  }

  /// A number safe to put in a log line or an error: the same mask the engine
  /// uses (`+88017*****01`). Screens show the whole number to its owner;
  /// nothing else may.
  static String masked(String number) => maskPhone(number);
}

/// The country code a bare national number is read in, shared between the
/// phone-book adapter the engine holds and the search box.
///
/// It is the prefix of this account's own number, so it is only known once
/// signed in; the people-sync controller sets it before it asks the engine to
/// read the address book.
final class PhoneCountry {
  String? callingCode;

  void setFromOwnNumber(String? ownNumber) {
    callingCode = ownNumber == null
        ? null
        : PhoneNumbers.callingCodeOf(ownNumber);
  }
}
