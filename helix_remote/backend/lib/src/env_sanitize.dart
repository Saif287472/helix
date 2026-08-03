/// Cleans an environment variable's raw value the way a shell would, unlike
/// Docker Compose's `env_file` - which does neither. A value like
/// `HELIX_REMOTE_SMS_SENDER_ID="880964890985"` in an `.env` file is passed
/// through *including* the quote characters, and a file last saved on
/// Windows can leave a trailing `\r` on every value. Both are invisible in
/// a text editor but silently break exact-match checks like BulkSMSBD's
/// sender ID lookup - stripping them here means a credential that looks
/// right in the file actually behaves right too.
String sanitizeEnvValue(String? rawValue) {
  var value = rawValue?.trim() ?? '';
  if (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'")))) {
    value = value.substring(1, value.length - 1).trim();
  }
  return value;
}
