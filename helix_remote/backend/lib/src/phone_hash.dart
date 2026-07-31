import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto_pkg;

/// Computes a salted HMAC-SHA256 hash of an E.164 phone number.
///
/// This is the only form in which a phone number should ever be sent to,
/// stored by, or compared on the server: callers must never transmit a raw
/// phone number for matching purposes. The salt is a per-deployment,
/// non-secret value distributed via the discovery-salt endpoint so clients
/// can compute the same hash locally.
String phoneHash(String discoverySaltBase64, String e164Number) {
  final saltBytes = base64.decode(discoverySaltBase64);
  final hmac = crypto_pkg.Hmac(crypto_pkg.sha256, saltBytes);
  return hmac.convert(utf8.encode(e164Number)).toString();
}

/// Generates a fresh random 32-byte discovery salt, base64-encoded.
String generateDiscoverySalt() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64.encode(bytes);
}
