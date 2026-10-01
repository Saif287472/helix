/// Failures of v2 crypto operations (CRYPTO_V2.md).
///
/// Messages never contain key material, plaintext or ciphertext. Every
/// operation that throws one of these leaves its input state unchanged: state
/// is only returned (for the caller to commit) after authentication succeeds.
sealed class CryptoV2Exception implements Exception {
  const CryptoV2Exception(this.message);

  final String message;

  /// Whether the receiver should ask the sender for a fresh session
  /// (CRYPTO_V2.md §13a): the message is authentic as far as we can tell,
  /// but we lack the state to read it.
  bool get requestsSessionReset => false;

  @override
  String toString() => '$runtimeType: $message';
}

/// Bytes that do not parse as the expected structure (wrong lengths, bad
/// integers, unknown versions).
final class MalformedCryptoInputException extends CryptoV2Exception {
  const MalformedCryptoInputException(super.message);
}

/// An AEAD tag did not verify: tampering, a wrong key, or wrong associated
/// data.
final class DecryptionFailedException extends CryptoV2Exception {
  const DecryptionFailedException([super.message = 'authentication failed']);
}

/// An Ed25519 signature did not verify.
final class InvalidSignatureException extends CryptoV2Exception {
  const InvalidSignatureException(super.message);
}

/// A device or account key is not the one we trust: the device certificate
/// does not verify under the account's AIK, or a prekey message names a
/// device identity key that does not match the device.
final class UntrustedIdentityException extends CryptoV2Exception {
  const UntrustedIdentityException(super.message);
}

/// A public key is malformed or of low order (the X25519 output is all
/// zeros).
final class InvalidKeyException extends CryptoV2Exception {
  const InvalidKeyException(super.message);
}

/// A prekey message names a signed or one-time prekey this device does not
/// have (expired, already used, or never issued). There is no fallback to
/// another prekey (CRYPTO_V2.md §3).
final class UnknownPrekeyException extends CryptoV2Exception {
  const UnknownPrekeyException(super.message);

  @override
  bool get requestsSessionReset => true;
}

/// No session with the sending device can read this message.
final class NoSessionException extends CryptoV2Exception {
  const NoSessionException(super.message);

  @override
  bool get requestsSessionReset => true;
}

/// The message key was already used (a replay) or was evicted or expired.
/// The two cases are indistinguishable by design; the engine de-duplicates
/// envelopes by delivery id before decrypting, so reaching this means the
/// key is gone.
final class DuplicateOrExpiredMessageException extends CryptoV2Exception {
  const DuplicateOrExpiredMessageException(super.message);

  @override
  bool get requestsSessionReset => true;
}

/// The message would need more skipped keys than the caps allow
/// (CRYPTO_V2.md §5, §7).
final class TooManySkippedMessagesException extends CryptoV2Exception {
  const TooManySkippedMessagesException(super.message);
}

/// No sender key is known for this group message's distribution id.
final class NoSenderKeyException extends CryptoV2Exception {
  const NoSenderKeyException(super.message);

  @override
  bool get requestsSessionReset => true;
}
