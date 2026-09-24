import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:helix_remote_backend/src/constant_time.dart';

/// Generates a cryptographically secure random 16-byte salt, Base64URL-encoded.
String generatePasswordSalt() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Hashes an admin password with a given salt using SHA-256.
String hashAdminPassword(String password, String salt) {
  final bytes = utf8.encode('$salt:$password');
  return crypto_pkg.sha256.convert(bytes).toString();
}

/// Verifies a plain password against a stored salt and expected SHA-256 hash
/// in constant time to prevent timing attacks.
bool verifyAdminPassword(String password, String salt, String expectedHash) {
  final computed = hashAdminPassword(password, salt);
  return constantTimeStringEqual(computed, expectedHash);
}
