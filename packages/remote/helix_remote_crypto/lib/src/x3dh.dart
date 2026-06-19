import 'dart:typed_data';
import 'package:cryptography/cryptography.dart' as crypto;

class X3dhSessionInitiator {
  final crypto.X25519 x25519 = crypto.X25519();
  final crypto.Ed25519 ed25519 = crypto.Ed25519();

  /// Alice initiating a session with Bob.
  /// Generates ephemeral keys, computes X3DH DH1, DH2, DH3, DH4 outputs,
  /// and derives the master shared secret key via HKDF-SHA256.
  Future<crypto.SecretKey> initiateSession({
    required crypto.SimpleKeyPair aliceIdentityKey,
    required crypto.SimpleKeyPair aliceEphemeralKey,
    required crypto.SimplePublicKey bobIdentityPublicKey,
    required crypto.SimplePublicKey bobSignedPrekey,
    crypto.SimplePublicKey? bobOneTimePrekey,
  }) async {
    // 1. DH1 = ECDH(IK_D_Alice, SPK_Bob)
    final dh1Bytes = await x25519.sharedSecretKey(
      keyPair: aliceIdentityKey,
      remotePublicKey: bobSignedPrekey,
    );
    final dh1Data = await dh1Bytes.extractBytes();

    // 2. DH2 = ECDH(EK_Alice, IK_D_Bob)
    final dh2Bytes = await x25519.sharedSecretKey(
      keyPair: aliceEphemeralKey,
      remotePublicKey: bobIdentityPublicKey,
    );
    final dh2Data = await dh2Bytes.extractBytes();

    // 3. DH3 = ECDH(EK_Alice, SPK_Bob)
    final dh3Bytes = await x25519.sharedSecretKey(
      keyPair: aliceEphemeralKey,
      remotePublicKey: bobSignedPrekey,
    );
    final dh3Data = await dh3Bytes.extractBytes();

    // 4. DH4 = ECDH(EK_Alice, OPK_Bob) [optional]
    Uint8List? dh4Data;
    if (bobOneTimePrekey != null) {
      final dh4Bytes = await x25519.sharedSecretKey(
        keyPair: aliceEphemeralKey,
        remotePublicKey: bobOneTimePrekey,
      );
      dh4Data = Uint8List.fromList(await dh4Bytes.extractBytes());
    }

    // Combine secrets: DH1 || DH2 || DH3 [ || DH4 ]
    final ikm = BytesBuilder();
    ikm.add(dh1Data);
    ikm.add(dh2Data);
    ikm.add(dh3Data);
    if (dh4Data != null) {
      ikm.add(dh4Data);
    }

    // HKDF-Extract & Expand to derive master secret key (256-bit)
    final hkdf = crypto.Hkdf(
      hmac: crypto.Hmac(crypto.Sha256()),
      outputLength: 32,
    );

    return hkdf.deriveKey(
      secretKey: crypto.SecretKey(ikm.toBytes()),
      nonce: List.filled(32, 0), // zero salt
      info: 'Helix-X3DH-MasterSecret-v1'.codeUnits,
    );
  }

  /// Bob receiving Alice's session setup request.
  /// Bob derives the exact same master shared secret key.
  Future<crypto.SecretKey> receiveSession({
    required crypto.SimpleKeyPair bobIdentityKey,
    required crypto.SimpleKeyPair bobSignedPrekey,
    crypto.SimpleKeyPair? bobOneTimePrekey,
    required crypto.SimplePublicKey aliceIdentityPublicKey,
    required crypto.SimplePublicKey aliceEphemeralPublicKey,
  }) async {
    // 1. DH1 = ECDH(SPK_Bob, IK_D_Alice)
    final dh1Bytes = await x25519.sharedSecretKey(
      keyPair: bobSignedPrekey,
      remotePublicKey: aliceIdentityPublicKey,
    );
    final dh1Data = await dh1Bytes.extractBytes();

    // 2. DH2 = ECDH(IK_D_Bob, EK_Alice)
    final dh2Bytes = await x25519.sharedSecretKey(
      keyPair: bobIdentityKey,
      remotePublicKey: aliceEphemeralPublicKey,
    );
    final dh2Data = await dh2Bytes.extractBytes();

    // 3. DH3 = ECDH(SPK_Bob, EK_Alice)
    final dh3Bytes = await x25519.sharedSecretKey(
      keyPair: bobSignedPrekey,
      remotePublicKey: aliceEphemeralPublicKey,
    );
    final dh3Data = await dh3Bytes.extractBytes();

    // 4. DH4 = ECDH(OPK_Bob, EK_Alice) [optional]
    Uint8List? dh4Data;
    if (bobOneTimePrekey != null) {
      final dh4Bytes = await x25519.sharedSecretKey(
        keyPair: bobOneTimePrekey,
        remotePublicKey: aliceEphemeralPublicKey,
      );
      dh4Data = Uint8List.fromList(await dh4Bytes.extractBytes());
    }

    // Combine secrets: DH1 || DH2 || DH3 [ || DH4 ]
    final ikm = BytesBuilder();
    ikm.add(dh1Data);
    ikm.add(dh2Data);
    ikm.add(dh3Data);
    if (dh4Data != null) {
      ikm.add(dh4Data);
    }

    final hkdf = crypto.Hkdf(
      hmac: crypto.Hmac(crypto.Sha256()),
      outputLength: 32,
    );

    return hkdf.deriveKey(
      secretKey: crypto.SecretKey(ikm.toBytes()),
      nonce: List.filled(32, 0),
      info: 'Helix-X3DH-MasterSecret-v1'.codeUnits,
    );
  }
}
