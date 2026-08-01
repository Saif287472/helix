import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto_pkg;

/// A short, single-use, time-limited code an operator generates via a
/// loopback-only call on the server (see AdminPairingModule) and types
/// into the admin app to obtain a fresh admin token. Deliberately numeric
/// and short - unlike generateInviteCode - since it's meant to be read off
/// a terminal and typed by hand; its safety comes from being single-use,
/// short-lived and rate-limited on redemption, not from raw entropy.
String generatePairingCode() {
  final random = Random.secure();
  return List.generate(16, (_) => random.nextInt(10)).join();
}

String hashPairingCode(String code) {
  return crypto_pkg.sha256.convert(utf8.encode(code)).toString();
}
