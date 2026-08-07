class RemoteAccountValidation {
  const RemoteAccountValidation._();

  static const displayNameRules = 'Use 1-80 characters.';
  static const phoneNumberRules =
      'Enter your number in international format, e.g. +15551234567.';

  static final RegExp _e164Pattern = RegExp(r'^\+[1-9]\d{7,14}$');

  /// Canonicalizes the app's supported phone-number forms to E.164.
  ///
  /// Bangladesh local/mobile forms are accepted because Helix Remote's
  /// current user base stores contacts interchangeably as `017...`,
  /// `88017...`, and `+88017...`. Other countries must include an
  /// international prefix so the client and server hash the same string.
  static String normalizePhoneNumber(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';

    var cleaned = trimmed.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.startsWith('00')) {
      cleaned = '+${cleaned.substring(2)}';
    }
    if (cleaned.startsWith('+')) {
      return '+${cleaned.substring(1).replaceAll(RegExp(r'\D'), '')}';
    }

    final digits = cleaned.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (_looksLikeBangladeshLocal(digits)) {
      return '+880${digits.substring(1)}';
    }
    if (_looksLikeBangladeshInternational(digits)) return '+$digits';
    return '+$digits';
  }

  static bool _looksLikeBangladeshLocal(String digits) =>
      digits.length == 11 && digits.startsWith('01');

  static bool _looksLikeBangladeshInternational(String digits) =>
      digits.length == 13 && digits.startsWith('8801');

  static String normalizeDisplayName(String value) => value.trim();

  static String? phoneNumberError(String value) {
    final phoneNumber = normalizePhoneNumber(value);
    if (phoneNumber.isEmpty) return 'Phone number cannot be empty.';
    if (!_e164Pattern.hasMatch(phoneNumber)) {
      return 'Enter a valid phone number in international format.';
    }
    return null;
  }

  static String? displayNameError(String value) {
    final displayName = normalizeDisplayName(value);
    if (displayName.isEmpty) return 'Display name cannot be empty.';
    if (displayName.length > 80) {
      return 'Display name must be 80 characters or less.';
    }
    return null;
  }

  static bool isValidPhoneNumber(String value) =>
      phoneNumberError(value) == null;
}
