class RemoteAccountValidation {
  const RemoteAccountValidation._();

  static const displayNameRules = 'Use 1-80 characters.';
  static const phoneNumberRules =
      'Enter your number in international format, e.g. +15551234567.';

  static final RegExp _e164Pattern = RegExp(r'^\+[1-9]\d{7,14}$');

  /// Strips everything but digits and a leading `+`, adding the `+` if the
  /// user omitted it. This is intentionally a light touch, not a full
  /// libphonenumber-style parser - good enough for E.164 validation without
  /// pulling in a new dependency for this alone.
  static String normalizePhoneNumber(String value) {
    final digitsAndPlus = value.trim().replaceAll(RegExp(r'[^\d+]'), '');
    if (digitsAndPlus.startsWith('+')) return digitsAndPlus;
    if (digitsAndPlus.isEmpty) return '';
    return '+$digitsAndPlus';
  }

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
