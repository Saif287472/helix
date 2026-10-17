import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// A full phone number at rest, for the operator console (ADR-030).
///
/// AES-256-GCM under `HELIX_PHONE_KEY` (kept outside the database), with the
/// account id as associated data, so a sealed number moved to another
/// account's row does not open. Stored as nonce (12) || ciphertext || tag
/// (16). A database dump without the key shows no numbers.
final class PhoneSeal {
  PhoneSeal(List<int> key) : _key = SecretKey(List<int>.unmodifiable(key));

  static final _aead = AesGcm.with256bits();

  final SecretKey _key;

  static List<int> _aad(String accountId) =>
      utf8.encode('helix.v2.phone-number\n$accountId');

  Future<Uint8List> seal(String accountId, String e164) async {
    final box = await _aead.encrypt(
      utf8.encode(e164),
      secretKey: _key,
      aad: _aad(accountId),
    );
    return Uint8List.fromList(box.concatenation());
  }

  /// The number, or null when [sealed] does not open (another key, another
  /// account, tampered).
  Future<String?> open(String accountId, List<int> sealed) async {
    try {
      final box = SecretBox.fromConcatenation(
        sealed,
        nonceLength: _aead.nonceLength,
        macLength: _aead.macAlgorithm.macLength,
      );
      return utf8.decode(
        await _aead.decrypt(box, secretKey: _key, aad: _aad(accountId)),
      );
    } on Object {
      return null;
    }
  }
}
