import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:helix_remote_crypto/helix_remote_crypto.dart';

void main() {
  group('X3DH Key Agreement (P9-019 / P9-003)', () {
    final initiator = X3dhSessionInitiator();
    final x25519 = crypto.X25519();

    test('Alice and Bob asynchronously derive the exact same master secret', () async {
      // Setup key pairs
      final aliceIdentityKey = await x25519.newKeyPair();
      final aliceEphemeralKey = await x25519.newKeyPair();

      final bobIdentityKey = await x25519.newKeyPair();
      final bobSignedPrekey = await x25519.newKeyPair();
      final bobOneTimePrekey = await x25519.newKeyPair();

      final bobIdentityPublicKey = await bobIdentityKey.extractPublicKey();
      final bobSignedPrekeyPublic = await bobSignedPrekey.extractPublicKey();
      final bobOneTimePrekeyPublic = await bobOneTimePrekey.extractPublicKey();

      final aliceIdentityPublicKey = await aliceIdentityKey.extractPublicKey();
      final aliceEphemeralPublicKey = await aliceEphemeralKey.extractPublicKey();

      // Alice initiates session
      final aliceSecret = await initiator.initiateSession(
        aliceIdentityKey: aliceIdentityKey,
        aliceEphemeralKey: aliceEphemeralKey,
        bobIdentityPublicKey: bobIdentityPublicKey,
        bobSignedPrekey: bobSignedPrekeyPublic,
        bobOneTimePrekey: bobOneTimePrekeyPublic,
      );

      // Bob receives session
      final bobSecret = await initiator.receiveSession(
        bobIdentityKey: bobIdentityKey,
        bobSignedPrekey: bobSignedPrekey,
        bobOneTimePrekey: bobOneTimePrekey,
        aliceIdentityPublicKey: aliceIdentityPublicKey,
        aliceEphemeralPublicKey: aliceEphemeralPublicKey,
      );

      final aliceBytes = await aliceSecret.extractBytes();
      final bobBytes = await bobSecret.extractBytes();

      expect(aliceBytes, bobBytes);
      expect(aliceBytes.length, 32); // 256-bit key
    });
  });

  group('Double Ratchet Protocol (P9-004 / P9-019)', () {
    test('Encrypt and decrypt a series of messages', () async {
      final rootKey = crypto.SecretKey(List.generate(32, (i) => i));
      final sendKey = crypto.SecretKey(List.generate(32, (i) => i + 10));
      final receiveKey = crypto.SecretKey(List.generate(32, (i) => i + 20));

      final aliceSession = DoubleRatchetSession(
        rootKey: rootKey,
        sendingChainKey: sendKey,
        receivingChainKey: receiveKey,
      );

      // Bob's sending/receiving keys are reversed relative to Alice
      final bobSession = DoubleRatchetSession(
        rootKey: rootKey,
        sendingChainKey: receiveKey,
        receivingChainKey: sendKey,
      );

      final plaintext1 = Uint8List.fromList('Hello Bob!'.codeUnits);
      final ciphertext1 = await aliceSession.encrypt(plaintext1);
      
      final decrypted1 = await bobSession.decrypt(ciphertext1);
      expect(decrypted1, plaintext1);

      final plaintext2 = Uint8List.fromList('Hi Alice!'.codeUnits);
      final ciphertext2 = await bobSession.encrypt(plaintext2);

      final decrypted2 = await aliceSession.decrypt(ciphertext2);
      expect(decrypted2, plaintext2);
    });

    test('Malformed ciphertext throws exception (P9-021)', () async {
      final rootKey = crypto.SecretKey(List.generate(32, (i) => i));
      final sendKey = crypto.SecretKey(List.generate(32, (i) => i + 10));
      final receiveKey = crypto.SecretKey(List.generate(32, (i) => i + 20));

      final aliceSession = DoubleRatchetSession(
        rootKey: rootKey,
        sendingChainKey: sendKey,
        receivingChainKey: receiveKey,
      );

      final bobSession = DoubleRatchetSession(
        rootKey: rootKey,
        sendingChainKey: receiveKey,
        receivingChainKey: sendKey,
      );

      final ciphertext = await aliceSession.encrypt(Uint8List.fromList('Secret'.codeUnits));
      
      // Modify one byte in the ciphertext payload
      ciphertext[ciphertext.length - 5] ^= 0xAA;

      expect(
        () => bobSession.decrypt(ciphertext),
        throwsException,
      );
    });
  });

  group('Group Sender Keys Protocol (P9-010)', () {
    test('Encrypt and decrypt fanned-out group messages', () async {
      final startingKey = crypto.SecretKey(List.generate(32, (i) => i));

      final aliceChain = GroupSenderChain(chainKey: startingKey);
      final bobChain = GroupSenderChain(chainKey: startingKey);

      final plaintext = Uint8List.fromList('Hello Group!'.codeUnits);
      final ciphertext = await aliceChain.encrypt(plaintext);

      final decrypted = await bobChain.decrypt(ciphertext);
      expect(decrypted, plaintext);
    });
  });

  group('Attachment and Backup Encryption (P9-011 / P9-012)', () {
    test('Attachment encrypt and decrypt', () async {
      final helper = RemoteAttachmentCrypto();
      final keys = helper.generateAttachmentKeys();

      final plaintext = Uint8List.fromList('Private File Content'.codeUnits);
      final ciphertext = await helper.encryptFile(plaintext, keys['key']!, keys['iv']!);
      final decrypted = await helper.decryptFile(ciphertext, keys['key']!, keys['iv']!);

      expect(decrypted, plaintext);
    });

    test('Backup key derivation and encryption', () async {
      final helper = RemoteBackupCrypto();
      final salt = Uint8List.fromList(List.generate(16, (i) => i));

      final derivedKey = await helper.deriveBackupKey(
        passphrase: 'strong recovery sentence',
        salt: salt,
      );

      final plaintext = Uint8List.fromList('Local SQLite Database Bytes'.codeUnits);
      final ciphertext = await helper.encryptBackup(plaintext, derivedKey);
      final decrypted = await helper.decryptBackup(ciphertext, derivedKey);

      expect(decrypted, plaintext);
    });
  });

  group('Secure Key Storage Containment (P9-022)', () {
    test('Remote keys are prefixed and do not leak or travers', () async {
      // Mock storage
      FlutterSecureStorage.setMockInitialValues({});
      const adapter = RemoteSecureKeyStorage();

      await adapter.writeKey('alice_identity_key', 'mykeycontent');
      final raw = await adapter.storage.read(key: 'helix_remote_v1_alice_identity_key');
      expect(raw, 'mykeycontent');

      final read = await adapter.readKey('alice_identity_key');
      expect(read, 'mykeycontent');

      // Verify that local prefix is not touched or accessed
      final localVal = await adapter.storage.read(key: 'helix_local_v1_alice_identity_key');
      expect(localVal, isNull);

      // Verify traversal checks
      expect(() => adapter.readKey('../local_key'), throwsArgumentError);
      expect(() => adapter.writeKey('key\\path', 'val'), throwsArgumentError);
    });
  });
}
