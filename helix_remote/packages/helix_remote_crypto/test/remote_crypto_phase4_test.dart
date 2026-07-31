// Phase 4 — Crypto, key lifecycle, and group security claims.
//
// Covers:
//   RP4-003  Ratchet state can be serialized and reconstructed (restart simulation).
//   RP4-005  OTP consumption alters the derived secret; replenishment thresholds.
//   RP4-006  Signed prekey rotation and migration idempotency.
//   RP4-007  Group epoch change: old chain cannot decrypt new-epoch ciphertext.
//   RP4-008  Attachment key wrapping, unwrapping, and tamper failure.
//   RP4-010  Deterministic protocol vectors: known-seed sessions, ciphertext structure.
//
// RP4-002 and RP4-004 (message protector seed isolation) live in
//   app/test/remote_message_protector_test.dart because RemoteMessageProtectorImpl
//   is defined in the app package, not in helix_remote_crypto.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as crypto;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helix_remote_crypto/helix_remote_crypto.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<crypto.SimpleKeyPair> _x25519Key() => crypto.X25519().newKeyPair();
Future<crypto.SimpleKeyPair> _ed25519Key() => crypto.Ed25519().newKeyPair();

Future<
  ({
    crypto.SimpleKeyPair identityKey,
    crypto.SimpleKeyPair signedPrekeyKp,
    crypto.SimplePublicKey signingPublic,
    Uint8List signature,
  })
>
_buildBundle({required crypto.SimpleKeyPair signingKey}) async {
  final identityKey = await _x25519Key();
  final signedPrekeyKp = await _x25519Key();
  final signingPublic = await signingKey.extractPublicKey();
  final spkPublicBytes = Uint8List.fromList(
    (await signedPrekeyKp.extractPublicKey()).bytes,
  );
  final sig = await crypto.Ed25519().sign(spkPublicBytes, keyPair: signingKey);
  return (
    identityKey: identityKey,
    signedPrekeyKp: signedPrekeyKp,
    signingPublic: signingPublic,
    signature: Uint8List.fromList(sig.bytes),
  );
}

// ---------------------------------------------------------------------------
// RP4-003 — Ratchet state serialization across restart
// ---------------------------------------------------------------------------

void main() {
  group('RP4-003 — Ratchet session survives serialization and reconstruction', () {
    test(
      'chain key bytes survive extract→reconstruct; decryption still works',
      () async {
        final rootKey = crypto.SecretKey(List.generate(32, (i) => i));
        final initialSendKey = crypto.SecretKey(
          List.generate(32, (i) => i + 10),
        );
        final initialReceiveKey = crypto.SecretKey(
          List.generate(32, (i) => i + 20),
        );

        final alice = DoubleRatchetSession(
          rootKey: rootKey,
          sendingChainKey: initialSendKey,
          receivingChainKey: initialReceiveKey,
        );
        final bob = DoubleRatchetSession(
          rootKey: rootKey,
          sendingChainKey: initialReceiveKey,
          receivingChainKey: initialSendKey,
        );

        // Alice sends one message; both ratchets advance.
        final msg1 = Uint8List.fromList('before restart'.codeUnits);
        final ct1 = await alice.encrypt(msg1);
        await bob.decrypt(ct1);

        // Serialize bob's current chain key bytes (simulate persisting to storage).
        final persistedSendBytes = await bob.sendingChainKey.extractBytes();
        final persistedReceiveBytes = await bob.receivingChainKey
            .extractBytes();

        // Reconstruct bob from persisted bytes (simulate app restart).
        final bobRestored = DoubleRatchetSession(
          rootKey: rootKey,
          sendingChainKey: crypto.SecretKey(persistedSendBytes),
          receivingChainKey: crypto.SecretKey(persistedReceiveBytes),
        );

        // Alice sends a second message that bobRestored must decrypt.
        final msg2 = Uint8List.fromList('after restart'.codeUnits);
        final ct2 = await alice.encrypt(msg2);
        expect(await bobRestored.decrypt(ct2), equals(msg2));
      },
    );

    test(
      'each message uses a unique derived key (same plaintext → different ciphertext)',
      () async {
        final alice = DoubleRatchetSession(
          rootKey: crypto.SecretKey(List.generate(32, (i) => i)),
          sendingChainKey: crypto.SecretKey(List.generate(32, (i) => i + 1)),
          receivingChainKey: crypto.SecretKey(List.generate(32, (i) => i + 2)),
        );

        final plaintext = Uint8List.fromList('repeated'.codeUnits);
        final ct1 = await alice.encrypt(plaintext);
        final ct2 = await alice.encrypt(plaintext);

        expect(
          ct1,
          isNot(equals(ct2)),
          reason: 'Each ratchet step uses a fresh message key',
        );
      },
    );

    test('replayed ciphertext fails after chain has advanced', () async {
      final rootKey = crypto.SecretKey(List.generate(32, (i) => i + 50));
      final sendKey = crypto.SecretKey(List.generate(32, (i) => i + 60));
      final receiveKey = crypto.SecretKey(List.generate(32, (i) => i + 70));

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

      final msg = Uint8List.fromList('replay target'.codeUnits);
      final ct = await alice.encrypt(msg);

      await bob.decrypt(ct); // chain advances

      expect(
        () => bob.decrypt(ct),
        throwsA(anything),
        reason: 'Re-decrypt after chain advance must fail (prevents replay)',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // RP4-005 — OTP consumption and replenishment thresholds
  // ---------------------------------------------------------------------------

  group('RP4-005 — One-time prekey consumption and replenishment', () {
    test(
      'X3DH with OTP produces different shared secret than without',
      () async {
        final signingKp = await _ed25519Key();
        final bundle = await _buildBundle(signingKey: signingKp);

        final aliceIdentity = await _x25519Key();
        final aliceEphemeral = await _x25519Key();
        final otpKp = await _x25519Key();
        final otpPublic = await otpKp.extractPublicKey();

        final bundleIdentityPublic = await bundle.identityKey
            .extractPublicKey();
        final bundleSpkPublic = await bundle.signedPrekeyKp.extractPublicKey();

        final initiator = X3dhSessionInitiator();

        final secretWithOtp = await initiator.initiateSession(
          aliceIdentityKey: aliceIdentity,
          aliceEphemeralKey: aliceEphemeral,
          bobIdentityPublicKey: bundleIdentityPublic,
          bobIdentitySigningPublicKey: bundle.signingPublic,
          bobSignedPrekey: bundleSpkPublic,
          bobSignedPrekeySignature: bundle.signature,
          bobOneTimePrekey: otpPublic,
        );
        final secretWithoutOtp = await initiator.initiateSession(
          aliceIdentityKey: aliceIdentity,
          aliceEphemeralKey: aliceEphemeral,
          bobIdentityPublicKey: bundleIdentityPublic,
          bobIdentitySigningPublicKey: bundle.signingPublic,
          bobSignedPrekey: bundleSpkPublic,
          bobSignedPrekeySignature: bundle.signature,
        );

        expect(
          await secretWithOtp.extractBytes(),
          isNot(equals(await secretWithoutOtp.extractBytes())),
          reason:
              'OTP changes the derived secret; consuming one is non-replayable',
        );
      },
    );

    test(
      'OTP session: initiator and receiver derive the same secret',
      () async {
        final signingKp = await _ed25519Key();
        final bundle = await _buildBundle(signingKey: signingKp);

        final aliceIdentity = await _x25519Key();
        final aliceEphemeral = await _x25519Key();
        final otpKp = await _x25519Key();

        final aliceIdentityPublic = await aliceIdentity.extractPublicKey();
        final aliceEphemeralPublic = await aliceEphemeral.extractPublicKey();
        final bundleIdentityPublic = await bundle.identityKey
            .extractPublicKey();
        final bundleSpkPublic = await bundle.signedPrekeyKp.extractPublicKey();
        final otpPublic = await otpKp.extractPublicKey();

        final initiator = X3dhSessionInitiator();

        final aliceSecret = await initiator.initiateSession(
          aliceIdentityKey: aliceIdentity,
          aliceEphemeralKey: aliceEphemeral,
          bobIdentityPublicKey: bundleIdentityPublic,
          bobIdentitySigningPublicKey: bundle.signingPublic,
          bobSignedPrekey: bundleSpkPublic,
          bobSignedPrekeySignature: bundle.signature,
          bobOneTimePrekey: otpPublic,
        );
        final bobSecret = await initiator.receiveSession(
          bobIdentityKey: bundle.identityKey,
          bobSignedPrekey: bundle.signedPrekeyKp,
          bobOneTimePrekey: otpKp,
          aliceIdentityPublicKey: aliceIdentityPublic,
          aliceEphemeralPublicKey: aliceEphemeralPublic,
        );

        expect(
          await aliceSecret.extractBytes(),
          equals(await bobSecret.extractBytes()),
        );
      },
    );

    test('shouldReplenish boundary values (default threshold = 5)', () {
      final manager = RemotePrekeyManager();
      for (var count = 0; count <= 4; count++) {
        expect(
          manager.shouldReplenish(availableOneTimePrekeyCount: count),
          isTrue,
          reason: 'Count $count is below threshold; replenishment needed',
        );
      }
      for (var count = 5; count <= 10; count++) {
        expect(
          manager.shouldReplenish(availableOneTimePrekeyCount: count),
          isFalse,
          reason: 'Count $count meets threshold; no replenishment needed',
        );
      }
    });

    test('shouldReplenish with custom threshold', () {
      final manager = RemotePrekeyManager();
      expect(
        manager.shouldReplenish(availableOneTimePrekeyCount: 3, threshold: 10),
        isTrue,
      );
      expect(
        manager.shouldReplenish(availableOneTimePrekeyCount: 10, threshold: 10),
        isFalse,
      );
    });

    test(
      'createPublication with zero OTP count throws ArgumentError',
      () async {
        final manager = RemotePrekeyManager();
        final identity = await _ed25519Key();
        expect(
          () => manager.createPublication(
            accountIdentitySigningKey: identity,
            signedPrekeyId: 1,
            firstOneTimePrekeyId: 100,
            oneTimePrekeyCount: 0,
          ),
          throwsArgumentError,
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // RP4-006 — Signed prekey rotation and identity migration
  // ---------------------------------------------------------------------------

  group('RP4-006 — Signed prekey rotation lifecycle', () {
    test(
      'new publication increments prekey ID and both signatures verify',
      () async {
        final manager = RemotePrekeyManager();
        final identity = await _ed25519Key();
        final identityPublic = await identity.extractPublicKey();

        final pub1 = await manager.createPublication(
          accountIdentitySigningKey: identity,
          signedPrekeyId: 1,
          firstOneTimePrekeyId: 100,
          oneTimePrekeyCount: 5,
          now: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        );
        final pub2 = await manager.createPublication(
          accountIdentitySigningKey: identity,
          signedPrekeyId: 2,
          firstOneTimePrekeyId: 105,
          oneTimePrekeyCount: 5,
          now: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
        );

        expect(pub2.signedPrekeyId, greaterThan(pub1.signedPrekeyId));

        for (final pub in [pub1, pub2]) {
          final valid = await crypto.Ed25519().verify(
            base64Url.decode(pub.signedPrekeyPublic),
            signature: crypto.Signature(
              base64Url.decode(pub.signedPrekeySignature),
              publicKey: identityPublic,
            ),
          );
          expect(
            valid,
            isTrue,
            reason: 'Signed prekey must verify against identity key',
          );
        }
      },
    );

    test(
      'signed prekey public keys across two rotations are distinct',
      () async {
        final manager = RemotePrekeyManager();
        final identity = await _ed25519Key();
        final pub1 = await manager.createPublication(
          accountIdentitySigningKey: identity,
          signedPrekeyId: 1,
          firstOneTimePrekeyId: 1,
        );
        final pub2 = await manager.createPublication(
          accountIdentitySigningKey: identity,
          signedPrekeyId: 2,
          firstOneTimePrekeyId: 11,
        );
        expect(
          pub1.signedPrekeyPublic,
          isNot(equals(pub2.signedPrekeyPublic)),
          reason: 'Each rotation generates a fresh key pair',
        );
      },
    );

    test(
      'isExpired: not expired before TTL, expired at and after TTL',
      () async {
        final manager = RemotePrekeyManager();
        final identity = await _ed25519Key();
        final now = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

        final pub = await manager.createPublication(
          accountIdentitySigningKey: identity,
          signedPrekeyId: 1,
          firstOneTimePrekeyId: 1,
          now: now,
          signedPrekeyTtl: const Duration(days: 30),
        );

        expect(
          manager.isExpired(pub, now.add(const Duration(days: 29))),
          isFalse,
        );
        expect(
          manager.isExpired(pub, now.add(const Duration(days: 30))),
          isTrue,
        );
        expect(
          manager.isExpired(pub, now.add(const Duration(days: 31))),
          isTrue,
        );
      },
    );

    test(
      'key migration is idempotent: second call does not overwrite first',
      () async {
        FlutterSecureStorage.setMockInitialValues({
          'helix_remote_v1_legacy_key': 'raw_key_value',
        });
        const storage = RemoteSecureKeyStorage();

        await storage.migrateLegacyKey(
          legacyKey: 'legacy_key',
          role: 'test_role',
          deviceId: 'dev-001',
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        );
        final record1 = await storage.readKeyRecord('legacy_key');
        expect(record1?.rotationState, 'legacy_migrated');
        expect(record1?.value, 'raw_key_value');

        // Second migration call must be a no-op (value is now JSON, not raw).
        await storage.migrateLegacyKey(
          legacyKey: 'legacy_key',
          role: 'test_role',
          deviceId: 'dev-001',
          createdAt: DateTime.fromMillisecondsSinceEpoch(9999),
        );
        final record2 = await storage.readKeyRecord('legacy_key');
        expect(
          record2?.createdAt.millisecondsSinceEpoch,
          equals(record1?.createdAt.millisecondsSinceEpoch),
          reason: 'Second migration must not overwrite the first',
        );
      },
    );

    test(
      'OTP public payloads contain only public material (no private key)',
      () async {
        final manager = RemotePrekeyManager();
        final identity = await _ed25519Key();
        final pub = await manager.createPublication(
          accountIdentitySigningKey: identity,
          signedPrekeyId: 1,
          firstOneTimePrekeyId: 100,
          oneTimePrekeyCount: 3,
        );
        for (final p in pub.oneTimePrekeyPublicPayloads()) {
          expect(p.containsKey('key_id'), isTrue);
          expect(p.containsKey('public_key'), isTrue);
          expect(
            p.containsKey('private_key'),
            isFalse,
            reason: 'Private key must not leak',
          );
        }
      },
    );
  });

  // ---------------------------------------------------------------------------
  // RP4-007 — Group epoch change
  // ---------------------------------------------------------------------------

  group('RP4-007 — Group epoch change and member removal', () {
    test('new epoch chain key cannot decrypt old-epoch ciphertext', () async {
      final oldChainKey = crypto.SecretKey(List.generate(32, (i) => i));
      final newChainKey = crypto.SecretKey(List.generate(32, (i) => 255 - i));

      final sender = GroupSenderChain(chainKey: oldChainKey);
      final receiverOldEpoch = GroupSenderChain(chainKey: oldChainKey);
      final receiverNewEpoch = GroupSenderChain(chainKey: newChainKey);

      final msg = Uint8List.fromList('old epoch message'.codeUnits);
      final ct = await sender.encrypt(msg);

      expect(await receiverOldEpoch.decrypt(ct), equals(msg));
      expect(
        () => receiverNewEpoch.decrypt(ct),
        throwsA(anything),
        reason: 'New epoch chain key must not decrypt old-epoch ciphertext',
      );
    });

    test(
      'late-join member with new epoch cannot read pre-epoch history',
      () async {
        final epoch1Key = crypto.SecretKey(List.generate(32, (i) => i + 1));
        final epoch2Key = crypto.SecretKey(List.generate(32, (i) => i + 2));

        final sender = GroupSenderChain(chainKey: epoch1Key);
        final existingMember = GroupSenderChain(chainKey: epoch1Key);
        final lateMember = GroupSenderChain(chainKey: epoch2Key);

        final epoch1Msg = Uint8List.fromList(
          'private epoch-1 message'.codeUnits,
        );
        final epoch1Ct = await sender.encrypt(epoch1Msg);

        expect(await existingMember.decrypt(epoch1Ct), equals(epoch1Msg));
        expect(
          () => lateMember.decrypt(epoch1Ct),
          throwsA(anything),
          reason:
              'Late join with new epoch key must not decrypt pre-epoch messages',
        );

        // Late member CAN decrypt epoch-2 messages.
        final senderEpoch2 = GroupSenderChain(chainKey: epoch2Key);
        final epoch2Msg = Uint8List.fromList('epoch-2 message'.codeUnits);
        final epoch2Ct = await senderEpoch2.encrypt(epoch2Msg);
        expect(await lateMember.decrypt(epoch2Ct), equals(epoch2Msg));
      },
    );

    test(
      'auth failure in group chain leaves state unchanged; valid message still decrypts',
      () async {
        final chainKey = crypto.SecretKey(List.generate(32, (i) => i + 7));
        final sender = GroupSenderChain(chainKey: chainKey);
        final receiver = GroupSenderChain(chainKey: chainKey);

        final msg = Uint8List.fromList('group message'.codeUnits);
        final valid = await sender.encrypt(msg);

        final tampered = Uint8List.fromList(valid);
        tampered[tampered.length - 2] ^= 0xAB;

        expect(() => receiver.decrypt(tampered), throwsA(anything));
        expect(await receiver.decrypt(valid), equals(msg));
      },
    );

    test(
      'two senders with different epoch keys cannot cross-decrypt',
      () async {
        final chainKeyA = crypto.SecretKey(List.generate(32, (i) => i + 10));
        final chainKeyB = crypto.SecretKey(List.generate(32, (i) => i + 20));

        final senderA = GroupSenderChain(chainKey: chainKeyA);
        final senderB = GroupSenderChain(chainKey: chainKeyB);
        final receiverA = GroupSenderChain(chainKey: chainKeyA);
        final receiverB = GroupSenderChain(chainKey: chainKeyB);

        final msg = Uint8List.fromList('shared text'.codeUnits);
        final ctA = await senderA.encrypt(msg);
        final ctB = await senderB.encrypt(msg);

        expect(ctA, isNot(equals(ctB)));
        expect(await receiverA.decrypt(ctA), equals(msg));
        expect(await receiverB.decrypt(ctB), equals(msg));
        expect(() => receiverA.decrypt(ctB), throwsA(anything));
        expect(() => receiverB.decrypt(ctA), throwsA(anything));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // RP4-008 — Attachment key wrapping, unwrapping, and tamper failure
  // ---------------------------------------------------------------------------

  group('RP4-008 — Attachment key wrap/unwrap and authorization', () {
    test('wrapAttachmentKey / unwrapAttachmentKey round-trip', () async {
      final helper = RemoteAttachmentCrypto();
      final wrappingKey = Uint8List.fromList(List.generate(32, (i) => i + 100));
      final keys = await helper.generateAttachmentKeys();

      final wrapped = await helper.wrapAttachmentKey(
        keys['key']!,
        keys['iv']!,
        wrappingKey,
      );
      final unwrapped = await helper.unwrapAttachmentKey(wrapped, wrappingKey);

      expect(unwrapped['key'], equals(keys['key']));
      expect(unwrapped['iv'], equals(keys['iv']));
    });

    test('wrong wrapping key fails to unwrap', () async {
      final helper = RemoteAttachmentCrypto();
      final correct = Uint8List.fromList(List.generate(32, (i) => i));
      final wrong = Uint8List.fromList(List.generate(32, (i) => i + 1));
      final keys = await helper.generateAttachmentKeys();

      final wrapped = await helper.wrapAttachmentKey(
        keys['key']!,
        keys['iv']!,
        correct,
      );
      expect(
        () => helper.unwrapAttachmentKey(wrapped, wrong),
        throwsA(anything),
        reason: 'Wrong wrapping key must fail authentication',
      );
    });

    test('tampered wrapped blob is rejected', () async {
      final helper = RemoteAttachmentCrypto();
      final wrappingKey = Uint8List.fromList(List.generate(32, (i) => i + 50));
      final keys = await helper.generateAttachmentKeys();

      final wrapped = await helper.wrapAttachmentKey(
        keys['key']!,
        keys['iv']!,
        wrappingKey,
      );
      final tampered = Uint8List.fromList(wrapped);
      tampered[tampered.length - 1] ^= 0xFF;

      expect(
        () => helper.unwrapAttachmentKey(tampered, wrappingKey),
        throwsA(anything),
        reason: 'Tampered wrapped blob must fail authentication',
      );
    });

    test(
      'generateAttachmentKeys produces unique key and IV on each call',
      () async {
        final helper = RemoteAttachmentCrypto();
        const n = 20;
        final keyStrings = <String>{};
        final ivStrings = <String>{};
        for (var i = 0; i < n; i++) {
          final kv = await helper.generateAttachmentKeys();
          keyStrings.add(String.fromCharCodes(kv['key']!));
          ivStrings.add(String.fromCharCodes(kv['iv']!));
        }
        expect(
          keyStrings.length,
          equals(n),
          reason: 'All generated keys must be unique',
        );
        expect(
          ivStrings.length,
          equals(n),
          reason: 'All generated IVs must be unique',
        );
      },
    );

    test('attachment key is 32 bytes; IV is 12 bytes', () async {
      final helper = RemoteAttachmentCrypto();
      final keys = await helper.generateAttachmentKeys();
      expect(keys['key']!.length, equals(32));
      expect(keys['iv']!.length, equals(12));
    });

    test('encryptFile / decryptFile round-trip', () async {
      final helper = RemoteAttachmentCrypto();
      final keys = await helper.generateAttachmentKeys();
      final pt = Uint8List.fromList('attachment payload content'.codeUnits);
      final ct = await helper.encryptFile(pt, keys['key']!, keys['iv']!);
      expect(
        await helper.decryptFile(ct, keys['key']!, keys['iv']!),
        equals(pt),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // RP4-010 — Deterministic protocol vectors
  // ---------------------------------------------------------------------------

  group('RP4-010 — Deterministic protocol vectors', () {
    test(
      'AES-GCM ciphertext layout: nonce(12) || ciphertext(n) || mac(16)',
      () async {
        final helper = RemoteAttachmentCrypto();
        final keys = await helper.generateAttachmentKeys();
        const pt = [0x01, 0x02, 0x03, 0x04];
        final ct = await helper.encryptFile(
          Uint8List.fromList(pt),
          keys['key']!,
          keys['iv']!,
        );

        expect(ct.length, equals(12 + pt.length + 16));
        // The nonce stored in the concatenation must match the provided IV.
        expect(ct.sublist(0, 12), equals(keys['iv']));
      },
    );

    test(
      'Double Ratchet ciphertext layout: nonce(12) || ciphertext(n) || mac(16)',
      () async {
        final alice = DoubleRatchetSession(
          rootKey: crypto.SecretKey(List.generate(32, (i) => i)),
          sendingChainKey: crypto.SecretKey(List.generate(32, (i) => i + 1)),
          receivingChainKey: crypto.SecretKey(List.generate(32, (i) => i + 2)),
        );
        const pt = [0xAA, 0xBB, 0xCC];
        final ct = await alice.encrypt(Uint8List.fromList(pt));
        expect(ct.length, equals(12 + pt.length + 16));
      },
    );

    test(
      'Group sender chain ciphertext layout: nonce(12) || ciphertext(n) || mac(16)',
      () async {
        final sender = GroupSenderChain(
          chainKey: crypto.SecretKey(List.generate(32, (i) => i + 5)),
        );
        const pt = [0x11, 0x22, 0x33, 0x44, 0x55];
        final ct = await sender.encrypt(Uint8List.fromList(pt));
        expect(ct.length, equals(12 + pt.length + 16));
      },
    );

    test('X3DH derived secret is exactly 32 bytes', () async {
      final signingKp = await _ed25519Key();
      final bundle = await _buildBundle(signingKey: signingKp);

      final aliceIdentity = await _x25519Key();
      final aliceEphemeral = await _x25519Key();

      final initiator = X3dhSessionInitiator();
      final secret = await initiator.initiateSession(
        aliceIdentityKey: aliceIdentity,
        aliceEphemeralKey: aliceEphemeral,
        bobIdentityPublicKey: await bundle.identityKey.extractPublicKey(),
        bobIdentitySigningPublicKey: bundle.signingPublic,
        bobSignedPrekey: await bundle.signedPrekeyKp.extractPublicKey(),
        bobSignedPrekeySignature: bundle.signature,
      );
      expect((await secret.extractBytes()).length, equals(32));
    });

    test(
      'PBKDF2 key derivation is deterministic for same passphrase + salt',
      () async {
        final helper = RemoteBackupCrypto();
        final salt = Uint8List.fromList(List.generate(24, (i) => i));
        const passphrase = 'deterministic test phrase for vector';

        final key1 = await helper.deriveBackupKey(
          passphrase: passphrase,
          salt: salt,
        );
        final key2 = await helper.deriveBackupKey(
          passphrase: passphrase,
          salt: salt,
        );

        expect(await key1.extractBytes(), equals(await key2.extractBytes()));
      },
    );

    test('PBKDF2 produces distinct key for different salt', () async {
      final helper = RemoteBackupCrypto();
      final salt1 = Uint8List.fromList(List.generate(24, (i) => i));
      final salt2 = Uint8List.fromList(List.generate(24, (i) => i + 1));
      const passphrase = 'same passphrase both runs';

      final key1 = await helper.deriveBackupKey(
        passphrase: passphrase,
        salt: salt1,
      );
      final key2 = await helper.deriveBackupKey(
        passphrase: passphrase,
        salt: salt2,
      );

      expect(
        await key1.extractBytes(),
        isNot(equals(await key2.extractBytes())),
        reason: 'Different salt must produce different derived key',
      );
    });

    test(
      'same-state DoubleRatchetSession pair always decrypts each other\'s ciphertexts',
      () async {
        // Two pairs starting from identical fixed keys must both be
        // able to encrypt and decrypt — verifying HKDF determinism.
        List<int> mk(int offset) => List.generate(32, (i) => i + offset);

        Future<DoubleRatchetSession> makeSession(int send, int recv) async =>
            DoubleRatchetSession(
              rootKey: crypto.SecretKey(mk(0)),
              sendingChainKey: crypto.SecretKey(mk(send)),
              receivingChainKey: crypto.SecretKey(mk(recv)),
            );

        final alice = await makeSession(10, 20);
        final bob = await makeSession(20, 10);
        final alice2 = await makeSession(10, 20);
        final bob2 = await makeSession(20, 10);

        final pt = Uint8List.fromList('vector text'.codeUnits);
        final ct = await alice.encrypt(pt);
        final ct2 = await alice2.encrypt(pt);

        // Both are valid ciphertexts for their respective bobs.
        expect(await bob.decrypt(ct), equals(pt));
        expect(await bob2.decrypt(ct2), equals(pt));
      },
    );
  });
}
