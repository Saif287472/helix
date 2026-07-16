class RemoteAccountValidation {
  const RemoteAccountValidation._();

  static const usernameRules =
      'Use 3-30 lowercase letters, numbers, or underscores.';
  static const displayNameRules = 'Use 1-80 characters.';

  static final RegExp _usernamePattern = RegExp(r'^[a-z0-9_]+$');

  static String normalizeUsername(String value) => value.trim().toLowerCase();

  static String normalizeDisplayName(String value) => value.trim();

  static String? usernameError(String value) {
    final username = normalizeUsername(value);
    if (username.isEmpty) return 'Username cannot be empty.';
    if (username.length < 3) return 'Username must be at least 3 characters.';
    if (username.length > 30) return 'Username must be 30 characters or less.';
    if (username.startsWith('helix_')) {
      return 'Usernames starting with helix_ are reserved.';
    }
    if (!_usernamePattern.hasMatch(username)) {
      return 'Use lowercase letters, numbers, and underscores only.';
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

  static bool isValidUsername(String value) => usernameError(value) == null;
}
