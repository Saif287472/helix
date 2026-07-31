import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Computes a salted HMAC-SHA256 hash of an E.164 phone number - the only
/// form in which a phone number should ever be sent to the server. Must stay
/// byte-for-byte identical to the backend's `phoneHash()`
/// (backend/lib/src/phone_hash.dart) given the same salt and number, since
/// the server recomputes and compares this hash.
String phoneHash(String discoverySaltBase64, String e164Number) {
  final saltBytes = base64.decode(discoverySaltBase64);
  final hmac = Hmac(sha256, saltBytes);
  return hmac.convert(utf8.encode(e164Number)).toString();
}
