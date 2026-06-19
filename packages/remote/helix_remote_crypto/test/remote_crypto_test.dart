import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:helix_remote_crypto/helix_remote_crypto.dart';

// Shared helper: build a valid Ed25519-signed prekey bundle.
Future<({
  crypto.SimpleKeyPair bobIdentityKey,
  crypto.SimpleKeyPair bobSignedPrekeyKp,
  crypto.SimplePublicKey bobSigningPublic,
  Uint8List signature,
})> _buildBobBundle() async {
  final x25519 = crypto.X25519();
  final ed25519 = crypto.Ed25519();

  final bobIdentityKey = await x25519.newKeyPair();
  final bobSignedPrekeyKp = await x25519.newKeyPair();
  final bobSigningKp = await ed25519.newKeyPair();
  final bobSigningPublic = await bobSigningKp.extractPublicKey();

  final spkBytes = Uint8List.fromList(
    (await bobSignedPrekeyKp.extractPublicKey()).bytes,
  );
  final sig = await ed25519.sign(spkBytes, keyPair: bobSigningKp);

  return (
    bobIdentityKey: bobIdentityKey,
    bobSignedPrekeyKp: bobSignedPrekeyKp,
    bobSigningPublic: bobSigningPublic,
    signature: Uint8List.fromList(sig.bytes),
  );
}

void main() {
  final x25519 = crypto.X25519();
  final ed25519 = crypto.Ed25519();
  final initiator = X3dhSessionInitiator();

  // ---------------------------------------------------------------------------
  // X3DH — signed prekey verification (DEFECT-3 fix)
  // ---------------------------------------------------------------------------

  group('X3DH Key Agreement — signed prekey verification (P9-003)', () {
    test('Alice and Bob derive the same master secret when signature is valid', () async {
      final aliceIdentityKey = await x25519.newKeyPair();
      final aliceEphemeralKey = await x25519.newKeyPair();
      final bobOneTimePrekeyKp = await x25519.newKeyPair();

      final bundle = await _buildBobBundle();

      final bobIdentityPublicKey = await bundle.bobIdentityKey.extractPublicKey();
      final bobSignedPrekeyPublic = await bundle.bobSignedPrekeyKp.extractPublicKey();
      final bobOneTimePrekeyPublic = await bobOneTimePrekeyKp.extractPublicKey();
      final aliceIdentityPublicKey = await aliceIdentityKey.extractPublicKey();
      final aliceEphemeralPublicKey = await aliceEphemeralKey.extractPublicKey();

      final aliceSecret = await initiator.initiateSession(
        aliceIdentityKey: aliceIdentityKey,
        aliceEphemeralKey: aliceEphemeralKey,
        bobIdentityPublicKey: bobIdentityPublicKey,
        bobIdentitySigningPublicKey: bundle.bobSigningPublic,
        bobSignedPrekey: bobSignedPrekeyPublic,
        bobSignedPrekeySignature: bundle.signature,
        bobOneTimePrekey: bobOneTimePrekeyPublic,
      );

      final bobSecret = await initiator.receiveSession(
        bobIdentityKey: bundle.bobIdentityKey,
        bobSignedPrekey: bundle.bobSignedPrekeyKp,
        bobOneTimePrekey: bobOneTimePrekeyKp,
        aliceIdentityPublicKey: aliceIdentityPublicKey,
        aliceEphemeralPublicKey: aliceEphemeralPublicKey,
      );

      final aliceBytes = await aliceSecret.extractBytes();
      final bobBytes = await bobSecret.extractBytes();

      expect(aliceBytes, bobBytes);
      expect(aliceBytes.length, 32);
    });

    test('DEFECT-3 fix: invalid signed prekey signature throws X3dhSignatureVerificationException', () async {
      final aliceIdentityKey = await x25519.newKeyPair();
      final aliceEphemeralKey = await x25519.newKeyPair();
      final bundle = await _buildBobBundle();

      final bobIdentityPublicKey = await bundle.bobIdentityKey.extractPublicKey();
      final bobSignedPrekeyPublic = await bundle.bobSignedPrekeyKp.extractPublicKey();

      // Tamper with the signature
      final tampered = Uint8List.fromList(bundle.signature);
      tampered[tampered.length ~/ 2] ^= 0xFF;

      expect(
        () => initiator.initiateSession(
          aliceIdentityKey: aliceIdentityKey,
          aliceEphemeralKey: aliceEphemeralKey,
          bobIdentityPublicKey: bobIdentityPublicKey,
          bobIdentitySigningPublicKey: bundle.bobSigningPublic,
          bobSignedPrekey: bobSignedPrekeyPublic,
          bobSignedPrekeySignature: tampered,
        ),
        throwsA(isA<X3dhSignatureVerificationException>()),
      );
    });

    test('DEFECT-3 fix: signature from wrong identity key is rejected', () async {
      final aliceIdentityKey = await x25519.newKeyPair();
      final aliceEphemeralKey = await x25519.newKeyPair();
      final bundle = await _buildBobBundle();

      final bobIdentityPublicKey = await bundle.bobIdentityKey.extractPublicKey();
      final bobSignedPrekeyPublic = await bundle.bobSignedPrekeyKp.extractPublicKey();

      // Use a completely different signing key for verification
      final wrongSigningKp = await ed25519.newKeyPair();
      final wrongSigningPublic = await wrongSigningKp.extractPublicKey();

      expect(
        () => initiator.initiateSession(
          aliceIdentityKey: aliceIdentityKey,
          aliceEphemeralKey: aliceEphemeralKey,
          bobIdentityPublicKey: bobIdentityPublicKey,
          bobIdentitySigningPublicKey: wrongSigningPublic,
          bobSignedPrekey: bobSignedPrekeyPublic,
          bobSignedPrekeySignature: bundle.signature,
        ),
        throwsA(isA<X3dhSignatureVerificationException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Double Ratchet — state preservation on authentication failure (DEFECT-1 fix)
  // ---------------------------------------------------------------------------

  group('Double Ratchet Protocol — state preservation (P9-004)', () {
    test('Encrypt and decrypt a series of bidirectional messages', () async {
      final rootKey = crypto.SecretKey(List.generate(32, (i) => i));
      final sendKey = crypto.SecretKey(List.generate(32, (i) => i + 10));
      final receiveKey = crypto.SecretKey(List.generate(32, (i) => i + 20));

      final alice = DoubleRatchetSession(
        rootKey: rootKey,
        sendingChainKey: sendKey,
        receivingChainKey: receiveKey,
      );
      final bob = DoubleRatchetSession(
        rootKey: rootKey,
        sendingChainKey: receiveKey,
        receivingChainKey: sendKey,
      );

      final p1 = Uint8List.fromList('Hello Bob!'.codeUnits);
      expect(await bob.decrypt(await alice.encrypt(p1)), p1);

      final p2 = Uint8List.fromList('Hi Alice!'.codeUnits);
      expect(await alice.decrypt(await bob.encrypt(p2)), p2);
    });

    test('DEFECT-1 fix: authentication failure does NOT advance receiving chain', () async {
      final rootKey = crypto.SecretKey(List.generate(32, (i) => i));
      final sendKey = crypto.SecretKey(List.generate(32, (i) => i + 10));
      final receiveKey = crypto.SecretKey(List.generate(32, (i) => i + 20));

      final alice = DoubleRatchetSession(
        rootKey: rootKey,
        sendingChainKey: sendKey,
        receivingChainKey: receiveKey,
      );
      final bob = DoubleRatchetSession(
        rootKey: rootKey,
        sendingChainKey: receiveKey,
        receivingChainKey: sendKey,
      );

      final msg = Uint8List.fromList('Valid message'.codeUnits);
      final valid = await alice.encrypt(msg);

      // Corrupt ciphertext
      final corrupt = Uint8List.fromList(valid);
      corrupt[corrupt.length - 1] ^= 0xFF;

      // Auth failure must throw
      expect(() => bob.decrypt(corrupt), throwsA(anything));

      // After failure, original message must still decrypt — state is unchanged
      final result = await bob.decrypt(valid);
      expect(result, msg);
    });

    test('Scenario A (closure): corrupt → fail → original decrypts successfully', () async {
      final rootKey = crypto.SecretKey(List.generate(32, (i) => i + 5));
      final sendKey = crypto.SecretKey(List.generate(32, (i) => i + 15));
      final receiveKey = crypto.SecretKey(List.generate(32, (i) => i + 25));

      final alice = DoubleRatchetSession(
        rootKey: rootKey,
        sendingChainKey: sendKey,
        receivingChainKey: receiveKey,
      );
      final bob = DoubleRatchetSession(
        rootKey: rootKey,
        sendingChainKey: receiveKey,
        receivingChainKey: sendKey,
      );

      final msg = Uint8List.fromList('Scenario A message'.codeUnits);
      final valid = await alice.encrypt(msg);

      final corrupt = Uint8List.fromList(valid);
      corrupt[corrupt.length - 3] ^= 0xAA;

      Object? err;
      try {
        await bob.decrypt(corrupt);
      } catch (e) {
        err = e;
      }
      expect(err, isNotNull, reason: 'Corrupt ciphertext must fail');

      expect(await bob.decrypt(valid), msg, reason: 'Session must recover after auth failure');
    });

    test('Malformed (too short) ciphertext throws (P9-021)', () async {
      final rootKey = crypto.SecretKey(List.generate(32, (i) => i));
      final receiveKey = crypto.SecretKey(List.generate(32, (i) => i + 20));
      final sendKey = crypto.SecretKey(List.generate(32, (i) => i + 10));

      final bob = DoubleRatchetSession(
        rootKey: rootKey,
        sendingChainKey: receiveKey,
        receivingChainKey: sendKey,
      );

      expect(() => bob.decrypt(Uint8List.fromList([0, 1, 2])), throwsA(anything));
    });
  });

  // ---------------------------------------------------------------------------
  // Group sender chain — state preservation on auth failure (DEFECT-2 fix)
  // ---------------------------------------------------------------------------

  group('Group Sender Keys — state preservation (P9-010)', () {
    test('Encrypt and decrypt fanned-out group messages', () async {
      final startingKey = crypto.SecretKey(List.generate(32, (i) => i));

      final sender = GroupSenderChain(chainKey: startingKey);
      final receiver = GroupSenderChain(chainKey: startingKey);

      final pt = Uint8List.fromList('Hello Group!'.codeUnits);
      expect(await receiver.decrypt(await sender.encrypt(pt)), pt);
    });

    test('DEFECT-2 fix: auth failure does NOT advance group chain state', () async {
      final startingKey = crypto.SecretKey(List.generate(32, (i) => i));

      final sender = GroupSenderChain(chainKey: startingKey);
      final receiver = GroupSenderChain(chainKey: startingKey);

      final msg = Uint8List.fromList('Group message'.codeUnits);
      final valid = await sender.encrypt(msg);

      final tampered = Uint8List.fromList(valid);
      tampered[tampered.length - 1] ^= 0xFF;

      expect(() => receiver.decrypt(tampered), throwsA(anything),
          reason: 'Tampered ciphertext must fail authentication');

      expect(await receiver.decrypt(valid), msg,
          reason: 'Chain state must be unchanged after auth failure');
    });
  });

  // ---------------------------------------------------------------------------
  // Attachment and Backup Encryption
  // ---------------------------------------------------------------------------

  group('Attachment and Backup Encryption (P9-011 / P9-012)', () {
    test('Attachment encrypt/decrypt round-trip', () async {
      final helper = RemoteAttachmentCrypto();
      final keys = helper.generateAttachmentKeys();

      final pt = Uint8List.fromList('Private File Content'.codeUnits);
      final ct = await helper.encryptFile(pt, keys['key']!, keys['iv']!);
      expect(await helper.decryptFile(ct, keys['key']!, keys['iv']!), pt);
    });

    test('Attachment decryption with wrong key throws', () async {
      final helper = RemoteAttachmentCrypto();
      final keys = helper.generateAttachmentKeys();
      final wrongKeys = helper.generateAttachmentKeys();

      final ct = await helper.encryptFile(
        Uint8List.fromList('secret'.codeUnits),
        keys['key']!,
        keys['iv']!,
      );

      expect(
        () => helper.decryptFile(ct, wrongKeys['key']!, keys['iv']!),
        throwsA(anything),
        reason: 'Wrong key must fail authentication',
      );
    });

    test('Backup key derivation and encrypt/decrypt round-trip', () async {
      final helper = RemoteBackupCrypto();
      final salt = Uint8List.fromList(List.generate(16, (i) => i));

      final key = await helper.deriveBackupKey(
        passphrase: 'strong recovery sentence',
        salt: salt,
      );

      final pt = Uint8List.fromList('Local SQLite Database Bytes'.codeUnits);
      final ct = await helper.encryptBackup(pt, key);
      expect(await helper.decryptBackup(ct, key), pt);
    });

    test('Backup decryption with wrong passphrase throws', () async {
      final helper = RemoteBackupCrypto();
      final salt = Uint8List.fromList(List.generate(16, (i) => i));

      final correctKey = await helper.deriveBackupKey(passphrase: 'correct', salt: salt);
      final wrongKey = await helper.deriveBackupKey(passphrase: 'wrong', salt: salt);

      final ct = await helper.encryptBackup(
        Uint8List.fromList('backup data'.codeUnits),
        correctKey,
      );
      expect(
        () => helper.decryptBackup(ct, wrongKey),
        throwsA(anything),
        reason: 'Wrong passphrase must fail authentication',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Secure Key Storage Containment
  // ---------------------------------------------------------------------------

  group('Secure Key Storage Containment (P9-022)', () {
    test('Remote keys are prefixed; Local prefix is never touched', () async {
      FlutterSecureStorage.setMockInitialValues({});
      const adapter = RemoteSecureKeyStorage();

      await adapter.writeKey('alice_identity_key', 'mykeycontent');
      expect(
        await adapter.storage.read(key: 'helix_remote_v1_alice_identity_key'),
        'mykeycontent',
      );
      expect(await adapter.readKey('alice_identity_key'), 'mykeycontent');
      expect(
        await adapter.storage.read(key: 'helix_local_v1_alice_identity_key'),
        isNull,
        reason: 'Local key must not be touched',
      );
      expect(() => adapter.readKey('../local_key'), throwsArgumentError);
      expect(() => adapter.writeKey('key\\path', 'val'), throwsArgumentError);
    });

    test('deleteKey removes only the scoped Remote key', () async {
      FlutterSecureStorage.setMockInitialValues({
        'helix_remote_v1_key_a': 'value_a',
        'helix_remote_v1_key_b': 'value_b',
        'helix_local_v1_key_c': 'local_value',
      });
      const adapter = RemoteSecureKeyStorage();

      await adapter.deleteKey('key_a');

      expect(await adapter.readKey('key_a'), isNull);
      expect(await adapter.readKey('key_b'), 'value_b');
      expect(
        await adapter.storage.read(key: 'helix_local_v1_key_c'),
        'local_value',
        reason: 'Local key must survive Remote deleteKey',
      );
    });

    test('clearAllRemoteKeys removes only Remote-prefixed keys', () async {
      FlutterSecureStorage.setMockInitialValues({
        'helix_remote_v1_identity': 'remote_val',
        'helix_remote_v1_session': 'remote_session',
        'helix_local_v1_local_key': 'local_val',
        'some_other_key': 'other',
      });
      const adapter = RemoteSecureKeyStorage();

      await adapter.clearAllRemoteKeys();

      expect(await adapter.readKey('identity'), isNull);
      expect(await adapter.readKey('session'), isNull);
      expect(
        await adapter.storage.read(key: 'helix_local_v1_local_key'),
        'local_val',
        reason: 'Local key must survive Remote clearAll',
      );
      expect(
        await adapter.storage.read(key: 'some_other_key'),
        'other',
        reason: 'Unrelated key must survive Remote clearAll',
      );
    });
  });
}
