import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto_pkg;

/// Server-config key the per-deployment discovery salt is stored under
/// (see `ContactsModule._discoverySaltHandler`). Shared with the phone-OTP
/// handler, which needs the same salt to verify a client-supplied
/// `phone_number` actually matches its `phone_hash` before sending SMS to it.
const discoverySaltConfigKey = 'contacts_discovery_salt';

/// Default hardened hashing algorithm for contact discovery to resist rainbow tables.
const defaultHashAlgorithm = 'hardened_hmac_sha256';

/// Default work factor (iterations) for hardened phone hashing.
const defaultHashIterations = 10000;

/// Computes a salted HMAC-SHA256 hash of an E.164 phone number (single iteration).
///
/// Maintained for backwards compatibility with existing client implementations.
String phoneHash(String discoverySaltBase64, String e164Number) {
  final saltBytes = base64.decode(discoverySaltBase64);
  final hmac = crypto_pkg.Hmac(crypto_pkg.sha256, saltBytes);
  return hmac.convert(utf8.encode(e164Number)).toString();
}

/// Computes a rainbow-table resistant key-stretched phone hash using
/// iterative HMAC-SHA256 stretching across [iterations] rounds.
///
/// By imposing non-trivial computation cost (several milliseconds per hash),
/// this renders exhaustive GPU rainbow table attacks on the $10^{10}$ global
/// phone number space computationally infeasible.
String phoneHashHardened(
  String discoverySaltBase64,
  String e164Number, {
  int iterations = defaultHashIterations,
}) {
  final saltBytes = base64.decode(discoverySaltBase64);
  final hmac = crypto_pkg.Hmac(crypto_pkg.sha256, saltBytes);
  var current = hmac.convert(utf8.encode(e164Number)).bytes;
  for (var i = 1; i < iterations; i++) {
    current = hmac.convert(current).bytes;
  }
  return crypto_pkg.Digest(current).toString();
}

/// Verifies whether an incoming phone hash matches an E.164 number,
/// supporting both hardened and legacy single-iteration hashes.
bool verifyPhoneHash(
  String discoverySaltBase64,
  String e164Number,
  String expectedHash, {
  int iterations = defaultHashIterations,
}) {
  if (expectedHash ==
      phoneHashHardened(
        discoverySaltBase64,
        e164Number,
        iterations: iterations,
      )) {
    return true;
  }
  if (expectedHash == phoneHash(discoverySaltBase64, e164Number)) {
    return true;
  }
  return false;
}

/// Generates a fresh random 32-byte discovery salt, base64-encoded.
String generateDiscoverySalt() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64.encode(bytes);
}
