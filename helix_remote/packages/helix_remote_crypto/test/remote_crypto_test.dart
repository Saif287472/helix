import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:helix_remote_crypto/helix_remote_crypto.dart';

// Shared helper: build a valid Ed25519-signed prekey bundle.
Future<
  ({
    crypto.SimpleKeyPair bobIdentityKey,
    crypto.SimpleKeyPair bobSignedPrekeyKp,
    crypto.SimplePublicKey bobSigningPublic,
    Uint8List signature,
  })
>
_buildBobBundle() async {
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
    test(
      'Alice and Bob derive the same master secret when signature is valid',
      () async {
        final aliceIdentityKey = await x25519.newKeyPair();
        final aliceEphemeralKey = await x25519.newKeyPair();
        final bobOneTimePrekeyKp = await x25519.newKeyPair();

        final bundle = await _buildBobBundle();

        final bobIdentityPublicKey = await bundle.bobIdentityKey
            .extractPublicKey();
        final bobSignedPrekeyPublic = await bundle.bobSignedPrekeyKp
            .extractPublicKey();
        final bobOneTimePrekeyPublic = await bobOneTimePrekeyKp
            .extractPublicKey();
        final aliceIdentityPublicKey = await aliceIdentityKey
            .extractPublicKey();
        final aliceEphemeralPublicKey = await aliceEphemeralKey
            .extractPublicKey();

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
      },
    );

    test(
      'DEFECT-3 fix: invalid signed prekey signature throws X3dhSignatureVerificationException',
      () async {
        final aliceIdentityKey = await x25519.newKeyPair();
        final aliceEphemeralKey = await x25519.newKeyPair();
        final bundle = await _buildBobBundle();

        final bobIdentityPublicKey = await bundle.bobIdentityKey
            .extractPublicKey();
        final bobSignedPrekeyPublic = await bundle.bobSignedPrekeyKp
            .extractPublicKey();

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
      },
    );

    test(
      'DEFECT-3 fix: signature from wrong identity key is rejected',
      () async {
        final aliceIdentityKey = await x25519.newKeyPair();
        final aliceEphemeralKey = await x25519.newKeyPair();
        final bundle = await _buildBobBundle();

        final bobIdentityPublicKey = await bundle.bobIdentityKey
            .extractPublicKey();
        final bobSignedPrekeyPublic = await bundle.bobSignedPrekeyKp
            .extractPublicKey();

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
      },
    );

    test('P2-05 transcript context changes the derived session key', () async {
      final x25519 = crypto.X25519();
      final bundle = await _buildBobBundle();
      final aliceIdentity = await x25519.newKeyPair();
      final aliceEphemeral = await x25519.newKeyPair();
      final aliceIdentityPublic = await aliceIdentity.extractPublicKey();
      final aliceEphemeralPublic = await aliceEphemeral.extractPublicKey();
      final bobIdentityPublic = await bundle.bobIdentityKey.extractPublicKey();

      final initiator = X3dhSessionInitiator();
      final aliceSecret = await initiator.initiateSession(
        aliceIdentityKey: aliceIdentity,
        aliceEphemeralKey: aliceEphemeral,
        bobIdentityPublicKey: bobIdentityPublic,
        bobIdentitySigningPublicKey: bundle.bobSigningPublic,
        bobSignedPrekey: await bundle.bobSignedPrekeyKp.extractPublicKey(),
        bobSignedPrekeySignature: bundle.signature,
        protocolVersion: '1',
        conversationId: 'conv_a',
        senderDeviceId: 'alice_device',
        recipientDeviceId: 'bob_device',
      );
      final bobSecret = await initiator.receiveSession(
        bobIdentityKey: bundle.bobIdentityKey,
        bobSignedPrekey: bundle.bobSignedPrekeyKp,
        aliceIdentityPublicKey: aliceIdentityPublic,
        aliceEphemeralPublicKey: aliceEphemeralPublic,
        protocolVersion: '1',
        conversationId: 'conv_a',
        senderDeviceId: 'alice_device',
        recipientDeviceId: 'bob_device',
      );
      final wrongContextSecret = await initiator.receiveSession(
        bobIdentityKey: bundle.bobIdentityKey,
        bobSignedPrekey: bundle.bobSignedPrekeyKp,
        aliceIdentityPublicKey: aliceIdentityPublic,
        aliceEphemeralPublicKey: aliceEphemeralPublic,
        protocolVersion: '1',
        conversationId: 'conv_b',
        senderDeviceId: 'alice_device',
        recipientDeviceId: 'bob_device',
      );

      expect(await aliceSecret.extractBytes(), await bobSecret.extractBytes());
      expect(
        await aliceSecret.extractBytes(),
        isNot(await wrongContextSecret.extractBytes()),
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

    test(
      'DEFECT-1 fix: authentication failure does NOT advance receiving chain',
      () async {
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
      },
    );

    test(
      'Scenario A (closure): corrupt → fail → original decrypts successfully',
      () async {
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

        expect(
          await bob.decrypt(valid),
          msg,
          reason: 'Session must recover after auth failure',
        );
      },
    );

    test('Malformed (too short) ciphertext throws (P9-021)', () async {
      final rootKey = crypto.SecretKey(List.generate(32, (i) => i));
      final receiveKey = crypto.SecretKey(List.generate(32, (i) => i + 20));
      final sendKey = crypto.SecretKey(List.generate(32, (i) => i + 10));

      final bob = DoubleRatchetSession(
        rootKey: rootKey,
        sendingChainKey: receiveKey,
        receivingChainKey: sendKey,
      );

      expect(
        () => bob.decrypt(Uint8List.fromList([0, 1, 2])),
        throwsA(anything),
      );
    });

    test(
      'Scenario B current symmetric chain coverage: early out-of-order delivery is decrypted successfully using skipped-keys',
      () async {
        final x25519 = crypto.X25519();
        final bobIdentityKey = await x25519.newKeyPair();
        final bobIdentityPublic = await bobIdentityKey.extractPublicKey();

        final sharedSecret = crypto.SecretKey(List.generate(32, (i) => i));

        final alice = await DoubleRatchetSession.initiate(
          sharedKey: sharedSecret,
          peerPublicKey: bobIdentityPublic,
        );
        final bob = await DoubleRatchetSession.receive(
          sharedKey: sharedSecret,
          localKeyPair: bobIdentityKey,
        );

        // Advance bob once by receiving a dummy message so his receiving chain is initialized
        final setupMsg = Uint8List.fromList('setup'.codeUnits);
        final setupCt = await alice.encrypt(setupMsg);
        expect(await bob.decrypt(setupCt), setupMsg);

        final p1 = Uint8List.fromList('message-1'.codeUnits);
        final p2 = Uint8List.fromList('message-2'.codeUnits);
        final p3 = Uint8List.fromList('message-3'.codeUnits);

        final c1 = await alice.encrypt(p1);
        final c2 = await alice.encrypt(p2);
        final c3 = await alice.encrypt(p3);

        // With skipped-key cache, 3 -> 1 -> 2 out-of-order delivery succeeds!
        expect(await bob.decrypt(c3), p3);
        expect(await bob.decrypt(c1), p1);
        expect(await bob.decrypt(c2), p2);

        // Replaying message 2 after it has been decrypted must fail.
        expect(() => bob.decrypt(c2), throwsA(anything));
      },
    );

    test(
      'Full Signal-compatible Double Ratchet session with DH ratchets',
      () async {
        final x25519 = crypto.X25519();
        final bobIdentityKey = await x25519.newKeyPair();
        final bobIdentityPublic = await bobIdentityKey.extractPublicKey();

        final sharedSecret = crypto.SecretKey(List.generate(32, (i) => i));

        // 1. Initialise Alice (initiator) and Bob (receiver)
        final alice = await DoubleRatchetSession.initiate(
          sharedKey: sharedSecret,
          peerPublicKey: bobIdentityPublic,
        );
        final bob = await DoubleRatchetSession.receive(
          sharedKey: sharedSecret,
          localKeyPair: bobIdentityKey,
        );

        // 2. Alice sends message to Bob (generates Alice's first DH key)
        final p1 = Uint8List.fromList('Message 1 from Alice'.codeUnits);
        final c1 = await alice.encrypt(p1);

        // Bob decrypts (triggers Bob's first DH ratchet step to generate Bob's local keypair)
        final d1 = await bob.decrypt(c1);
        expect(d1, p1);

        // 3. Bob replies to Alice (uses Bob's generated local keypair and Alice's public key)
        final p2 = Uint8List.fromList('Message 2 from Bob'.codeUnits);
        final c2 = await bob.encrypt(p2);

        // Alice decrypts (triggers Alice's first DH ratchet step)
        final d2 = await alice.decrypt(c2);
        expect(d2, p2);

        // 4. Alice sends another message to Bob
        final p3 = Uint8List.fromList('Message 3 from Alice'.codeUnits);
        final c3 = await alice.encrypt(p3);

        final d3 = await bob.decrypt(c3);
        expect(d3, p3);
      },
    );
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

    test(
      'DEFECT-2 fix: auth failure does NOT advance group chain state',
      () async {
        final startingKey = crypto.SecretKey(List.generate(32, (i) => i));

        final sender = GroupSenderChain(chainKey: startingKey);
        final receiver = GroupSenderChain(chainKey: startingKey);

        final msg = Uint8List.fromList('Group message'.codeUnits);
        final valid = await sender.encrypt(msg);

        final tampered = Uint8List.fromList(valid);
        tampered[tampered.length - 1] ^= 0xFF;

        expect(
          () => receiver.decrypt(tampered),
          throwsA(anything),
          reason: 'Tampered ciphertext must fail authentication',
        );

        expect(
          await receiver.decrypt(valid),
          msg,
          reason: 'Chain state must be unchanged after auth failure',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Attachment and Backup Encryption
  // ---------------------------------------------------------------------------

  group('Attachment and Backup Encryption (P9-011 / P9-012)', () {
    test('Attachment encrypt/decrypt round-trip', () async {
      final helper = RemoteAttachmentCrypto();
      final keys = await helper.generateAttachmentKeys();

      final pt = Uint8List.fromList('Private File Content'.codeUnits);
      final ct = await helper.encryptFile(pt, keys['key']!, keys['iv']!);
      expect(await helper.decryptFile(ct, keys['key']!, keys['iv']!), pt);
    });

    test('Attachment decryption with wrong key throws', () async {
      final helper = RemoteAttachmentCrypto();
      final keys = await helper.generateAttachmentKeys();
      final wrongKeys = await helper.generateAttachmentKeys();

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

      final correctKey = await helper.deriveBackupKey(
        passphrase: 'correct',
        salt: salt,
      );
      final wrongKey = await helper.deriveBackupKey(
        passphrase: 'wrong',
        salt: salt,
      );

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

    test(
      'P17 versioned backup envelope round-trips without exposing key',
      () async {
        final helper = RemoteBackupCrypto();
        final envelope = await helper.encryptBackupEnvelope(
          plaintext: Uint8List.fromList('restorable history bytes'.codeUnits),
          passphrase: 'six word recovery phrase policy',
          backupId: 'backup_p17_1',
          backupKeyHint: 'stored offline',
          salt: Uint8List.fromList(List.generate(24, (i) => i + 1)),
          deletionWatermark: 1234,
        );

        final json = envelope.toJson();
        expect(
          json['version'],
          equals(RemoteBackupCrypto.currentBackupVersion),
        );
        expect(json['kdf'], equals(RemoteBackupCrypto.currentKdf));
        expect(json.containsKey('passphrase'), isFalse);
        expect(json.containsKey('backup_key'), isFalse);
        expect(json['backup_key_hint'], equals('stored offline'));
        expect(json['deletion_watermark'], equals(1234));

        final restoredEnvelope = RemoteBackupEnvelope.fromJson(json);
        final plaintext = await helper.decryptBackupEnvelope(
          restoredEnvelope,
          passphrase: 'six word recovery phrase policy',
        );
        expect(
          String.fromCharCodes(plaintext),
          equals('restorable history bytes'),
        );
      },
    );

    test(
      'P17 recovery policy rejects weak phrase and old backup version',
      () async {
        final helper = RemoteBackupCrypto();
        expect(helper.isValidRecoverySecret('short'), isFalse);
        expect(
          helper.isValidRecoverySecret('alpha beta gamma delta epsilon zeta'),
          isTrue,
        );

        expect(
          () => helper.encryptBackupEnvelope(
            plaintext: Uint8List.fromList('data'.codeUnits),
            passphrase: 'short',
            backupId: 'backup_p17_weak',
            backupKeyHint: '',
          ),
          throwsArgumentError,
        );

        final envelope = await helper.encryptBackupEnvelope(
          plaintext: Uint8List.fromList('data'.codeUnits),
          passphrase: 'valid recovery phrase policy words',
          backupId: 'backup_p17_version',
          backupKeyHint: '',
        );
        final json = envelope.toJson()..['version'] = 999;
        expect(
          () => helper.decryptBackupEnvelope(
            RemoteBackupEnvelope.fromJson(json),
            passphrase: 'valid recovery phrase policy words',
          ),
          throwsUnsupportedError,
        );
      },
    );

    test('F2 transfer QR handshake derives matching channel keys', () async {
      final handshake = RemoteTransferHandshake();
      final offerState = await handshake.createOffer(
        sourceDeviceId: 'source_phone',
      );
      final offer = RemoteTransferOffer.fromJson(
        jsonDecode(
              utf8.decode(
                base64Url.decode(
                  base64Url.normalize(offerState.offer.toQrPayload()),
                ),
              ),
            )
            as Map<String, dynamic>,
      );
      final answerState = await handshake.acceptOffer(
        offer: offer,
        destinationDeviceId: 'destination_laptop',
      );
      final sourceKey = await handshake.completeOffer(
        state: offerState,
        answer: RemoteTransferAnswer.fromJson(answerState.answer.toJson()),
      );

      expect(
        await sourceKey.extractBytes(),
        equals(await answerState.key.extractBytes()),
      );
      expect(answerState.answer.confirmationCode, hasLength(6));
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

    test('P2-02 versioned key records expose redacted inventory', () async {
      FlutterSecureStorage.setMockInitialValues({
        'helix_remote_v1_legacy_identity_private': 'raw_legacy',
      });
      const adapter = RemoteSecureKeyStorage();

      await adapter.migrateLegacyKey(
        legacyKey: 'legacy_identity_private',
        role: 'account_identity_private',
        deviceId: 'alice_device',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      await adapter.writeKeyRecord(
        'device_signing_private',
        RemoteSecureKeyRecord(
          role: 'device_signing_private',
          version: 1,
          deviceId: 'alice_device',
          value: 'secret_value',
          createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
        ),
      );

      final migrated = await adapter.readKeyRecord('legacy_identity_private');
      expect(migrated!.rotationState, 'legacy_migrated');
      final inventory = await adapter.keyInventory();
      expect(inventory, hasLength(2));
      expect(jsonEncode(inventory), isNot(contains('secret_value')));
      expect(jsonEncode(inventory), isNot(contains('raw_legacy')));
      expect(
        inventory.map((entry) => entry['role']),
        containsAll(['account_identity_private', 'device_signing_private']),
      );
    });
  });

  group('P2-03 prekey lifecycle', () {
    test('creates signed prekey and replenishment metadata', () async {
      final manager = RemotePrekeyManager();
      final identity = await crypto.Ed25519().newKeyPair();
      final identityPublic = await identity.extractPublicKey();

      final publication = await manager.createPublication(
        accountIdentitySigningKey: identity,
        signedPrekeyId: 7,
        firstOneTimePrekeyId: 100,
        oneTimePrekeyCount: 3,
        now: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      );

      expect(publication.signedPrekeyId, 7);
      expect(publication.oneTimePrekeys.map((key) => key.keyId), [
        100,
        101,
        102,
      ]);
      expect(manager.shouldReplenish(availableOneTimePrekeyCount: 4), isTrue);
      expect(
        manager.isExpired(
          publication,
          DateTime.fromMillisecondsSinceEpoch(
            1000,
            isUtc: true,
          ).add(const Duration(days: 31)),
        ),
        isTrue,
      );

      final valid = await crypto.Ed25519().verify(
        base64Url.decode(publication.signedPrekeyPublic),
        signature: crypto.Signature(
          base64Url.decode(publication.signedPrekeySignature),
          publicKey: identityPublic,
        ),
      );
      expect(valid, isTrue);
    });
  });
}
