import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' as crypto;

/// Thrown when X3DH session establishment is rejected due to a failed
/// signed-prekey signature verification. Indicates a potential MITM attack
/// or a malformed / expired prekey bundle.
class X3dhSignatureVerificationException implements Exception {
  const X3dhSignatureVerificationException(this.message);
  final String message;

  @override
  String toString() => 'X3dhSignatureVerificationException: $message';
}

class X3dhSessionInitiator {
  final crypto.X25519 x25519 = crypto.X25519();
  final crypto.Ed25519 ed25519 = crypto.Ed25519();

  /// Alice initiating a session with Bob.
  ///
  /// SECURITY: [bobSignedPrekeySignature] is the Ed25519 signature over
  /// [bobSignedPrekey]'s raw public-key bytes, produced by Bob's account
  /// identity signing key [bobIdentitySigningPublicKey].
  ///
  /// The signature is verified BEFORE any DH computation. If verification
  /// fails, throws [X3dhSignatureVerificationException]. This prevents a
  /// man-in-the-middle from substituting an attacker-controlled prekey.
  Future<crypto.SecretKey> initiateSession({
    required crypto.SimpleKeyPair aliceIdentityKey,
    required crypto.SimpleKeyPair aliceEphemeralKey,
    required crypto.SimplePublicKey bobIdentityPublicKey,
    required crypto.SimplePublicKey bobIdentitySigningPublicKey,
    required crypto.SimplePublicKey bobSignedPrekey,
    required Uint8List bobSignedPrekeySignature,
    crypto.SimplePublicKey? bobOneTimePrekey,
    String protocolVersion = '1',
    String conversationId = '',
    String senderDeviceId = '',
    String recipientDeviceId = '',
  }) async {
    // Step 1 — verify the signed prekey signature BEFORE doing any DH work.
    final prekeyBytes = Uint8List.fromList(bobSignedPrekey.bytes);
    final signatureObj = crypto.Signature(
      bobSignedPrekeySignature,
      publicKey: bobIdentitySigningPublicKey,
    );
    final valid = await ed25519.verify(prekeyBytes, signature: signatureObj);
    if (!valid) {
      throw const X3dhSignatureVerificationException(
        'Signed prekey signature verification failed. Prekey bundle rejected.',
      );
    }

    // Step 2 — DH1 = ECDH(IK_D_Alice, SPK_Bob)
    final dh1Bytes = await x25519.sharedSecretKey(
      keyPair: aliceIdentityKey,
      remotePublicKey: bobSignedPrekey,
    );
    final dh1Data = await dh1Bytes.extractBytes();

    // Step 3 — DH2 = ECDH(EK_Alice, IK_D_Bob)
    final dh2Bytes = await x25519.sharedSecretKey(
      keyPair: aliceEphemeralKey,
      remotePublicKey: bobIdentityPublicKey,
    );
    final dh2Data = await dh2Bytes.extractBytes();

    // Step 4 — DH3 = ECDH(EK_Alice, SPK_Bob)
    final dh3Bytes = await x25519.sharedSecretKey(
      keyPair: aliceEphemeralKey,
      remotePublicKey: bobSignedPrekey,
    );
    final dh3Data = await dh3Bytes.extractBytes();

    // Step 5 — DH4 = ECDH(EK_Alice, OPK_Bob) [optional]
    Uint8List? dh4Data;
    if (bobOneTimePrekey != null) {
      final dh4Bytes = await x25519.sharedSecretKey(
        keyPair: aliceEphemeralKey,
        remotePublicKey: bobOneTimePrekey,
      );
      dh4Data = Uint8List.fromList(await dh4Bytes.extractBytes());
    }

    // Step 6 — Combine: DH1 || DH2 || DH3 [ || DH4 ]
    final ikm = BytesBuilder();
    ikm.add(dh1Data);
    ikm.add(dh2Data);
    ikm.add(dh3Data);
    if (dh4Data != null) ikm.add(dh4Data);

    final hkdf = crypto.Hkdf(
      hmac: crypto.Hmac(crypto.Sha256()),
      outputLength: 32,
    );

    return hkdf.deriveKey(
      secretKey: crypto.SecretKey(ikm.toBytes()),
      nonce: List.filled(32, 0),
      info: _sessionInfo(
        protocolVersion: protocolVersion,
        conversationId: conversationId,
        senderDeviceId: senderDeviceId,
        recipientDeviceId: recipientDeviceId,
      ),
    );
  }

  /// Bob receiving Alice's session setup request.
  ///
  /// Bob derives the exact same master shared secret. Bob does not need to
  /// verify the signed prekey signature here because Bob generated the
  /// prekey himself.
  Future<crypto.SecretKey> receiveSession({
    required crypto.SimpleKeyPair bobIdentityKey,
    required crypto.SimpleKeyPair bobSignedPrekey,
    crypto.SimpleKeyPair? bobOneTimePrekey,
    required crypto.SimplePublicKey aliceIdentityPublicKey,
    required crypto.SimplePublicKey aliceEphemeralPublicKey,
    String protocolVersion = '1',
    String conversationId = '',
    String senderDeviceId = '',
    String recipientDeviceId = '',
  }) async {
    // DH1 = ECDH(SPK_Bob, IK_D_Alice)
    final dh1Bytes = await x25519.sharedSecretKey(
      keyPair: bobSignedPrekey,
      remotePublicKey: aliceIdentityPublicKey,
    );
    final dh1Data = await dh1Bytes.extractBytes();

    // DH2 = ECDH(IK_D_Bob, EK_Alice)
    final dh2Bytes = await x25519.sharedSecretKey(
      keyPair: bobIdentityKey,
      remotePublicKey: aliceEphemeralPublicKey,
    );
    final dh2Data = await dh2Bytes.extractBytes();

    // DH3 = ECDH(SPK_Bob, EK_Alice)
    final dh3Bytes = await x25519.sharedSecretKey(
      keyPair: bobSignedPrekey,
      remotePublicKey: aliceEphemeralPublicKey,
    );
    final dh3Data = await dh3Bytes.extractBytes();

    // DH4 = ECDH(OPK_Bob, EK_Alice) [optional]
    Uint8List? dh4Data;
    if (bobOneTimePrekey != null) {
      final dh4Bytes = await x25519.sharedSecretKey(
        keyPair: bobOneTimePrekey,
        remotePublicKey: aliceEphemeralPublicKey,
      );
      dh4Data = Uint8List.fromList(await dh4Bytes.extractBytes());
    }

    final ikm = BytesBuilder();
    ikm.add(dh1Data);
    ikm.add(dh2Data);
    ikm.add(dh3Data);
    if (dh4Data != null) ikm.add(dh4Data);

    final hkdf = crypto.Hkdf(
      hmac: crypto.Hmac(crypto.Sha256()),
      outputLength: 32,
    );

    return hkdf.deriveKey(
      secretKey: crypto.SecretKey(ikm.toBytes()),
      nonce: List.filled(32, 0),
      info: _sessionInfo(
        protocolVersion: protocolVersion,
        conversationId: conversationId,
        senderDeviceId: senderDeviceId,
        recipientDeviceId: recipientDeviceId,
      ),
    );
  }

  List<int> _sessionInfo({
    required String protocolVersion,
    required String conversationId,
    required String senderDeviceId,
    required String recipientDeviceId,
  }) {
    return 'Helix-X3DH-MasterSecret-v1|protocol=$protocolVersion|conversation=$conversationId|sender=$senderDeviceId|recipient=$recipientDeviceId'
        .codeUnits;
  }
}
