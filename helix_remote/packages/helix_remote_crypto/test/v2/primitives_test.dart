import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as c;
import 'package:helix_remote_crypto/src/v2/primitives.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Known-answer tests for the primitives, so the vectors elsewhere rest on
/// standard behaviour.
void main() {
  test('HKDF-SHA256 matches RFC 5869 test case 1', () {
    final okm = hkdf(
      ikm: List.filled(22, 0x0b),
      salt: unhex('000102030405060708090a0b0c'),
      info: unhex('f0f1f2f3f4f5f6f7f8f9'),
      length: 42,
    );
    expect(
      hex(okm),
      '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf'
      '34007208d5b887185865',
    );
  });

  test('HKDF agrees with package:cryptography for 64-byte outputs', () async {
    final ikm = SeededRandom('hkdf').nextBytes(32);
    final salt = SeededRandom('salt').nextBytes(32);
    final info = label('helix.v2.ratchet.root');
    final theirs = await c.Hkdf(
      hmac: c.Hmac.sha256(),
      outputLength: 64,
    ).deriveKey(secretKey: c.SecretKey(ikm), nonce: salt, info: info);
    expect(
      hkdf(ikm: ikm, salt: salt, info: info, length: 64),
      await theirs.extractBytes(),
    );
  });

  test('X25519 matches RFC 7748 section 6.1', () async {
    final alice = await X25519KeyPair.fromPrivateKey(
      unhex('77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a'),
    );
    final bob = await X25519KeyPair.fromPrivateKey(
      unhex('5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb'),
    );
    expect(
      hex(alice.publicKey),
      '8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a',
    );
    expect(
      hex(bob.publicKey),
      'de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f',
    );
    const shared =
        '4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742';
    expect(hex(await alice.agree(bob.publicKey)), shared);
    expect(hex(await bob.agree(alice.publicKey)), shared);
  });

  test('X25519 rejects low-order and malformed public keys', () async {
    final pair = await X25519KeyPair.generate(SeededRandom('low'));
    await expectLater(
      pair.agree(Uint8List(32)),
      throwsA(isA<InvalidKeyException>()),
    );
    final one = Uint8List(32)..[0] = 1;
    await expectLater(pair.agree(one), throwsA(isA<InvalidKeyException>()));
    await expectLater(
      pair.agree(Uint8List(31)),
      throwsA(isA<InvalidKeyException>()),
    );
  });

  test('Ed25519 matches RFC 8032 test 1', () async {
    final pair = await Ed25519KeyPair.fromSeed(
      unhex('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60'),
    );
    expect(
      hex(pair.publicKey),
      'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
    );
    final signature = await pair.sign(const []);
    expect(
      hex(signature),
      'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155'
      '5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b',
    );
    expect(
      await ed25519Verify(
        publicKey: pair.publicKey,
        message: const [],
        signature: signature,
      ),
      isTrue,
    );
    expect(
      await ed25519Verify(
        publicKey: pair.publicKey,
        message: const [0],
        signature: signature,
      ),
      isFalse,
    );
    expect(
      await ed25519Verify(
        publicKey: pair.publicKey,
        message: const [],
        signature: signature.sublist(1),
      ),
      isFalse,
    );
  });

  test('AES-256-GCM rejects tampered ciphertext, tag and AAD', () async {
    final key = SeededRandom('k').nextBytes(32);
    final nonce = SeededRandom('n').nextBytes(12);
    final sealed = await Aead.seal(
      key: key,
      nonce: nonce,
      plaintext: [1, 2, 3],
      aad: [9],
    );
    expect(sealed, hasLength(3 + 16));
    expect(
      await Aead.open(key: key, nonce: nonce, ciphertext: sealed, aad: [9]),
      [1, 2, 3],
    );
    for (var i = 0; i < sealed.length; i++) {
      final bad = Uint8List.fromList(sealed)..[i] ^= 1;
      await expectLater(
        Aead.open(key: key, nonce: nonce, ciphertext: bad, aad: [9]),
        throwsA(isA<DecryptionFailedException>()),
      );
    }
    await expectLater(
      Aead.open(key: key, nonce: nonce, ciphertext: sealed, aad: [8]),
      throwsA(isA<DecryptionFailedException>()),
    );
    await expectLater(
      Aead.open(
        key: key,
        nonce: nonce,
        ciphertext: sealed.sublist(0, 15),
        aad: [9],
      ),
      throwsA(isA<DecryptionFailedException>()),
    );
  });

  test('integer encodings are big-endian and range-checked', () {
    expect(u32(0x01020304), [1, 2, 3, 4]);
    expect(u64(0x0102030405060708), [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(u16(0x0102), [1, 2]);
    expect(() => u32(-1), throwsArgumentError);
    expect(() => u32(0x100000000), throwsArgumentError);
    expect(() => u8(256), throwsArgumentError);
  });

  test('the seeded test random is deterministic and the secure one is not', () {
    expect(SeededRandom('x').nextBytes(40), SeededRandom('x').nextBytes(40));
    expect(
      SeededRandom('x').nextBytes(8),
      isNot(SeededRandom('y').nextBytes(8)),
    );
    final secure = SecureCryptoRandom();
    expect(secure.nextBytes(32), isNot(secure.nextBytes(32)));
  });
}
