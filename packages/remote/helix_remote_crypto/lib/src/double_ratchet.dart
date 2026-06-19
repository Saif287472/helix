import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' as crypto;

class DoubleRatchetSession {
  DoubleRatchetSession({
    required this.rootKey,
    required this.sendingChainKey,
    required this.receivingChainKey,
  });

  final crypto.SecretKey rootKey;
  crypto.SecretKey sendingChainKey;
  crypto.SecretKey receivingChainKey;

  final crypto.AesGcm aesGcm = crypto.AesGcm.with256bits();
  final crypto.Hkdf hkdf = crypto.Hkdf(
    hmac: crypto.Hmac(crypto.Sha256()),
    outputLength: 32,
  );

  /// Encrypt a payload using the next Sending Chain key.
  /// Ratchets the sending chain forward.
  Future<Uint8List> encrypt(Uint8List plaintext) async {
    // Derive Message Key (MK) and next Chain Key from current Chain Key
    final derived = await _ratchetSymmetric(sendingChainKey, 'sending-message-key');
    sendingChainKey = derived.nextChainKey;

    final mkBytes = await derived.messageKey.extractBytes();
    final nonce = aesGcm.newNonce();

    final box = await aesGcm.encrypt(
      plaintext,
      secretKey: crypto.SecretKey(mkBytes),
      nonce: nonce,
    );

    return Uint8List.fromList(box.concatenation());
  }

  /// Decrypt a ciphertext using the next Receiving Chain key.
  /// Ratchets the receiving chain forward.
  Future<Uint8List> decrypt(Uint8List ciphertextBytes) async {
    final derived = await _ratchetSymmetric(receivingChainKey, 'sending-message-key');
    receivingChainKey = derived.nextChainKey;

    final mkBytes = await derived.messageKey.extractBytes();
    
    // Parse nonce & tag from GCM ciphertext concatenation: nonce (12B) || cipher || tag (16B)
    final box = crypto.SecretBox.fromConcatenation(
      ciphertextBytes,
      nonceLength: 12,
      macLength: 16,
    );

    final plaintext = await aesGcm.decrypt(
      box,
      secretKey: crypto.SecretKey(mkBytes),
    );

    return Uint8List.fromList(plaintext);
  }

  Future<_RatchetStepResult> _ratchetSymmetric(crypto.SecretKey chainKey, String info) async {
    final mk = await hkdf.deriveKey(
      secretKey: chainKey,
      nonce: List.filled(32, 0),
      info: '$info-mk'.codeUnits,
    );
    final nextCk = await hkdf.deriveKey(
      secretKey: chainKey,
      nonce: List.filled(32, 0),
      info: '$info-next-ck'.codeUnits,
    );
    return _RatchetStepResult(messageKey: mk, nextChainKey: nextCk);
  }
}

class _RatchetStepResult {
  const _RatchetStepResult({
    required this.messageKey,
    required this.nextChainKey,
  });
  final crypto.SecretKey messageKey;
  final crypto.SecretKey nextChainKey;
}
