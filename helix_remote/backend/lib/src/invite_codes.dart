import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto_pkg;

/// Non-secret row identifier for an invite credential - safe to log or show
/// in an admin audit list.
String generateInviteId() {
  final random = Random.secure();
  final bytes = List<int>.generate(12, (_) => random.nextInt(256));
  return 'inv_${base64Url.encode(bytes).replaceAll('=', '')}';
}

/// The secret redemption credential. Only ever returned once, at issuance
/// time - the server persists only its hash (see `hashInviteCode`).
String generateInviteCode() {
  final random = Random.secure();
  final bytes = List<int>.generate(24, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

String hashInviteCode(String code) {
  return crypto_pkg.sha256.convert(utf8.encode(code)).toString();
}
