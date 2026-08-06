/// Strips secrets out of diagnostic log lines.
///
/// `docs/security/LOG_REDACTION.md` requires that production logs and
/// diagnostic exports never carry decrypted payloads, key material, or access
/// tokens. Nothing enforced that: [AppLogger] flattened newlines and appended
/// the message verbatim to a plaintext file, which the settings screen then
/// hands to an arbitrary app through the share sheet.
///
/// Redaction lives here, applied at the single write boundary rather than at
/// the ~46 call sites, because a rule that depends on every future caller
/// remembering it is not a control. The uncaught-error handler alone routes
/// arbitrary exception text here — including `RemoteRestException`, which
/// carries a whole response body and request URI — so the boundary is the only
/// place with a complete view of what is about to be written.
///
/// The approach is deliberately conservative: it over-redacts. A log line that
/// loses a value which happened to look like a token is a support
/// inconvenience; one that keeps a real token is the thing the policy exists
/// to prevent.
library;

/// Replacement written in place of a redacted value. Distinctive on purpose,
/// so it is obvious in an exported log that redaction ran rather than that the
/// field was empty.
const String kRedacted = '[redacted]';

/// Patterns applied in order. Ordering matters: the more specific rules (a
/// labelled `token=` assignment, a bearer header) run before the generic
/// high-entropy sweep, so the output names what was removed instead of
/// reducing everything to an anonymous blob.
final List<_RedactionRule> _rules = [
  // Authorization headers, in either the header or the Dart-map rendering.
  _RedactionRule(
    RegExp(r'(Bearer\s+)[A-Za-z0-9._\-+/=]+', caseSensitive: false),
    (m) => '${m[1]}$kRedacted',
  ),

  // key=value and "key": "value" for anything sensitive by name. Covers query
  // strings, JSON bodies, and Dart's Map.toString() in one rule each.
  _RedactionRule(
    RegExp(
      r'([?&](?:token|access_token|refresh_token|otp|otp_code|code|'
      r'invite_code|phone|phone_number|phone_hash|password|passphrase|'
      r'secret|key|signature)=)[^&\s]+',
      caseSensitive: false,
    ),
    (m) => '${m[1]}$kRedacted',
  ),
  _RedactionRule(
    RegExp(
      r'(["\x27](?:token|access_token|refresh_token|otp|otp_code|'
      r'invite_code|phone|phone_number|phone_hash|password|passphrase|'
      r'secret|secret_key|private_key|backup_key|recovery_phrase|'
      r'ciphertext|plaintext|body|message_text|signature)["\x27]\s*:\s*)'
      r'["\x27][^"\x27]*["\x27]',
      caseSensitive: false,
    ),
    (m) => '${m[1]}"$kRedacted"',
  ),

  // International phone numbers. Matched before the generic digit sweep so a
  // number is not mistaken for an id.
  _RedactionRule(RegExp(r'\+\d[\d\s\-().]{7,}\d'), (_) => kRedacted),

  // High-entropy blobs: base64url/base64 and hex runs long enough to be key
  // material, a signature, a token segment, or a fingerprint. The length
  // floors are set above what ordinary identifiers in this codebase reach -
  // conversation and message ids are shorter, and the client's own account id
  // is 16 hex characters, so the hex floor sits above it deliberately.
  _RedactionRule(RegExp(r'\b[A-Fa-f0-9]{32,}\b'), (_) => kRedacted),
  _RedactionRule(RegExp(r'\b[A-Za-z0-9_\-]{40,}={0,2}\b'), (_) => kRedacted),
];

/// Redacts a single log line.
///
/// Safe to call on any string, including one that has already been redacted -
/// [kRedacted] contains no character class that any rule matches, so the
/// operation is idempotent.
String redactLogLine(String input) {
  if (input.isEmpty) return input;
  var out = input;
  for (final rule in _rules) {
    out = out.replaceAllMapped(rule.pattern, rule.replace);
  }
  return out;
}

/// Truncates an oversized message to [maxLength], appending a marker.
///
/// A `RemoteRestException` carries the entire response body, so a server
/// error can otherwise write kilobytes into a log the user is asked to share.
/// Redaction removes secrets; this bounds the volume.
String truncateForLog(String input, {int maxLength = 512}) {
  if (input.length <= maxLength) return input;
  return '${input.substring(0, maxLength)}… [truncated '
      '${input.length - maxLength} chars]';
}

class _RedactionRule {
  const _RedactionRule(this.pattern, this.replace);

  final RegExp pattern;
  final String Function(Match) replace;
}
