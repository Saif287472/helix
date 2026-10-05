import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Safety numbers, passwords, attachments, backups, provisioning, blobs and
/// the prekey policy (CRYPTO_V2.md §2a, §3, §9-13).
void main() {
  Future<void> expectThrows<T>(Future<Object?> f) =>
      expectLater(f, throwsA(isA<T>()));

  group('safety numbers', () {
    test(
      'both sides see the same 60 digits; an AIK change changes them',
      () async {
        final r = SeededRandom('sn');
        final ka = (await Ed25519KeyPair.generate(r)).publicKey;
        final kb = (await Ed25519KeyPair.generate(r)).publicKey;
        final kb2 = (await Ed25519KeyPair.generate(r)).publicKey;
        final ab = SafetyNumber.compute(
          localAccount: accountA,
          localIdentityKey: ka,
          remoteAccount: accountB,
          remoteIdentityKey: kb,
        );
        final ba = SafetyNumber.compute(
          localAccount: accountB,
          localIdentityKey: kb,
          remoteAccount: accountA,
          remoteIdentityKey: ka,
        );
        expect(ab.digits, hasLength(60));
        expect(ab.digits, ba.digits);
        expect(ab.groups, hasLength(12));
        expect(ab.matchesQr(ba.qrPayload), isTrue);
        final changed = SafetyNumber.compute(
          localAccount: accountA,
          localIdentityKey: ka,
          remoteAccount: accountB,
          remoteIdentityKey: kb2,
        );
        expect(changed.digits.substring(0, 30), ab.digits.substring(0, 30));
        expect(changed.digits.substring(30), isNot(ab.digits.substring(30)));
        expect(ab.matchesQr(changed.qrPayload), isFalse);
      },
    );
  });

  group('password keys', () {
    test(
      'derive, wrap and unwrap; wrong password, account or params fail',
      () async {
        final r = SeededRandom('pw');
        final salt = PasswordKeys.newSalt(r);
        final keys = await PasswordKeys.derive(
          password: 'correct horse',
          salt: salt,
        );
        expect(keys.authKey, isNot(keys.wrapKey));
        final aik = await Ed25519KeyPair.generate(r);
        final wrapped = await keys.wrapIdentityKey(
          identityKeySeed: aik.seed,
          accountId: accountA,
          random: r,
        );
        final opened = await keys.unwrapIdentityKey(
          wrapped: wrapped,
          accountId: accountA,
          expectedPublicKey: aik.publicKey,
        );
        expect(opened.publicKey, aik.publicKey);
        await expectThrows<DecryptionFailedException>(
          keys.unwrapIdentityKey(wrapped: wrapped, accountId: accountB),
        );
        final wrong = await PasswordKeys.derive(
          password: 'wrong horse',
          salt: salt,
        );
        await expectThrows<DecryptionFailedException>(
          wrong.unwrapIdentityKey(wrapped: wrapped, accountId: accountA),
        );
        await expectThrows<MalformedCryptoInputException>(
          PasswordKeys.derive(
            password: 'x',
            salt: salt,
            params: const KdfParams(memoryKib: 1024),
          ),
        );
        // One iteration is below the floor (CRYPTO_V2.md section 11).
        await expectThrows<MalformedCryptoInputException>(
          PasswordKeys.derive(
            password: 'x',
            salt: salt,
            params: const KdfParams(iterations: 1),
          ),
        );
        await expectThrows<MalformedCryptoInputException>(
          PasswordKeys.derive(password: 'x', salt: Uint8List(8)),
        );
      },
    );
  });

  group('attachments', () {
    final key = AttachmentCrypto.newKey(SeededRandom('k'));

    Future<Uint8List> decrypt(List<int> c, {List<int>? digest}) async {
      final out = BytesBuilder();
      await for (final p in AttachmentCrypto.decrypt(
        Stream.fromIterable([
          for (var i = 0; i < c.length; i += 333)
            c.sublist(i, i + 333 > c.length ? c.length : i + 333),
        ]),
        key,
        expectedDigest: digest,
      )) {
        out.add(p);
      }
      return out.toBytes();
    }

    test('round trips across chunk boundaries', () async {
      for (final n in [0, 1, 63, 64, 65, 128, 1000]) {
        final plain = SeededRandom('p$n').nextBytes(n);
        final enc = await AttachmentCrypto.encryptBytes(
          plain,
          key,
          random: SeededRandom('e$n'),
          chunkSize: 64,
        );
        expect(await decrypt(enc.ciphertext, digest: enc.digest), plain);
        expect(
          await AttachmentCrypto.decryptBytes(
            enc.ciphertext,
            key,
            digest: enc.digest,
          ),
          plain,
        );
      }
    });

    test('tampering, truncation, reordering and extension all fail', () async {
      final plain = SeededRandom('p').nextBytes(64 * 3);
      final c = (await AttachmentCrypto.encryptBytes(
        plain,
        key,
        random: SeededRandom('e'),
        chunkSize: 64,
      )).ciphertext;
      const frame = 64 + 16;
      final cases = <Uint8List>[
        Uint8List.fromList(c)..[6] ^= 1, // header chunk size
        Uint8List.fromList(c)..[12] ^= 1, // nonce prefix
        Uint8List.fromList(c)..[20] ^= 1, // first chunk
        c.sublist(0, 16 + 2 * frame), // drop the last chunk
        c.sublist(0, c.length - 1),
        Uint8List.fromList([...c, 0]),
        Uint8List.fromList([
          ...c.sublist(0, 16),
          ...c.sublist(16 + frame, 16 + 2 * frame),
          ...c.sublist(16, 16 + frame),
          ...c.sublist(16 + 2 * frame),
        ]),
      ];
      for (final bad in cases) {
        await expectThrows<CryptoV2Exception>(decrypt(bad));
      }
      await expectThrows<DecryptionFailedException>(
        AttachmentCrypto.decryptBytes(c, key, digest: Uint8List(32)),
      );
    });
  });

  group('backups', () {
    const backupId = '0192a4f0-0000-7000-8000-0000000000bb';
    const secret = 'a long recovery secret phrase';

    test(
      'recovery secret and platform key both open it; tampering fails',
      () async {
        final r = SeededRandom('backup');
        final platform = r.nextBytes(32);
        final env = await BackupCrypto.seal(
          plaintext: utf8.encode('history'),
          backupId: backupId,
          backupVersion: 3,
          recoverySecret: secret,
          createdAt: DateTime.utc(2026, 10, 1),
          random: r,
          platformKey: platform,
        );
        final json =
            jsonDecode(jsonEncode(env.toJson())) as Map<String, Object?>;
        final text = jsonEncode(json);
        for (final f in FullBackup.forbiddenFields) {
          expect(text.contains('"$f"'), isFalse);
        }
        final back = BackupEnvelope.fromJson(JsonReader(json));
        expect(
          utf8.decode(await BackupCrypto.open(back, recoverySecret: secret)),
          'history',
        );
        expect(
          utf8.decode(await BackupCrypto.open(back, platformKey: platform)),
          'history',
        );
        await expectThrows<DecryptionFailedException>(
          BackupCrypto.open(back, recoverySecret: 'another long secret phrase'),
        );
        // Presenting it as another version or another backup fails (AAD).
        final relabelled = BackupEnvelope.fromJson(
          JsonReader({...json, 'version': 4}),
        );
        await expectThrows<DecryptionFailedException>(
          BackupCrypto.open(relabelled, platformKey: platform),
        );
        // A KDF downgrade in the envelope is refused.
        final wraps = (json['key_wraps'] as List).cast<Map<String, Object?>>();
        final weak = BackupEnvelope.fromJson(
          JsonReader({
            ...json,
            'key_wraps': [
              for (final w in wraps)
                if (w['method'] == 'recovery_secret')
                  {
                    ...w,
                    'kdf': {...(w['kdf'] as Map), 'memory_kib': 1024},
                  }
                else
                  w,
            ],
          }),
        );
        await expectThrows<MalformedCryptoInputException>(
          BackupCrypto.open(weak, recoverySecret: secret),
        );
        expect(BackupCrypto.isValidRecoverySecret('short'), isFalse);
        // Six short words are not enough any more: length is what counts.
        expect(
          BackupCrypto.isValidRecoverySecret('one two three four five six'),
          isTrue,
          reason: '27 characters',
        );
        expect(BackupCrypto.isValidRecoverySecret('a b c d e f'), isFalse);
        expect(
          BackupCrypto.isValidRecoverySecret('nineteen characters'),
          isFalse,
        );
        expect(
          BackupCrypto.isValidRecoverySecret('exactly twenty chars'),
          isTrue,
        );
      },
    );

    test('a generated recovery secret is long, random and valid', () {
      final r = SeededRandom('recovery-secret');
      final a = BackupCrypto.generateRecoverySecret(r);
      final b = BackupCrypto.generateRecoverySecret(r);
      expect(a, matches(RegExp(r'^([A-Z2-7]{4}-){7}[A-Z2-7]{4}$')));
      expect(a, isNot(b));
      expect(BackupCrypto.isValidRecoverySecret(a), isTrue);
      // 160 bits: 20 bytes in, 32 base32 characters out, no bias to one
      // character.
      final seen = {
        for (var i = 0; i < 40; i++)
          ...BackupCrypto.generateRecoverySecret(
            r,
          ).replaceAll('-', '').split(''),
      };
      expect(seen.length, greaterThan(20));
    });

    test('history backup is bound to its account and version', () async {
      final r = SeededRandom('hist');
      final seed = r.nextBytes(32);
      final data = await HistoryBackupCrypto.seal(
        identityKeySeed: seed,
        accountId: accountA,
        version: 7,
        plaintext: [1, 2, 3],
        random: r,
      );
      expect(
        await HistoryBackupCrypto.open(
          identityKeySeed: seed,
          accountId: accountA,
          version: 7,
          data: data,
        ),
        [1, 2, 3],
      );
      for (final (account, version, key) in [
        (accountA, 6, seed),
        (accountB, 7, seed),
        (accountA, 7, r.nextBytes(32)),
      ]) {
        await expectThrows<DecryptionFailedException>(
          HistoryBackupCrypto.open(
            identityKeySeed: key,
            accountId: account,
            version: version,
            data: data,
          ),
        );
      }
    });
  });

  group('provisioning', () {
    test(
      'only the right link and ephemeral key open it; seed must match',
      () async {
        final r = SeededRandom('link');
        final eNew = await X25519KeyPair.generate(r);
        const linkId = '0192a4f0-0000-7000-8000-0000000000f1';
        const otherLink = '0192a4f0-0000-7000-8000-0000000000f2';
        final aik = await Ed25519KeyPair.generate(r);
        final code = LinkCode(
          serverOrigin: 'https://helix.example',
          linkId: linkId,
          ephemeralKey: eNew.publicKey,
        );
        final approver = await LocalDeviceKeys.create(
          accountIdentityKey: aik,
          address: DeviceAddress(accountA, deviceA1),
          createdAt: DateTime.utc(2026, 10, 1),
          random: r,
        );
        final sealed = await Provisioning.seal(
          linkCode: code,
          approver: approver,
          accountKey: aik,
          profileKey: r.nextBytes(32),
          random: r,
        );
        final opened = await Provisioning.open(
          ephemeralKey: eNew,
          linkId: linkId,
          sealed: sealed,
        );
        expect(opened.identityKey, aik.publicKey);
        expect(opened.approverDeviceId, deviceA1);
        expect(Provisioning.keyCode(aik.publicKey), hasLength(24));
        expect(opened.toString(), isNot(contains(encodeBytes(aik.seed))));
        await expectThrows<DecryptionFailedException>(
          Provisioning.open(
            ephemeralKey: eNew,
            linkId: otherLink,
            sealed: sealed,
          ),
        );
        await expectThrows<DecryptionFailedException>(
          Provisioning.open(
            ephemeralKey: await X25519KeyPair.generate(r),
            linkId: linkId,
            sealed: sealed,
          ),
        );
        expect(
          () => LinkCode.parse('helix-link:1:ftp://x:$linkId:AAAA'),
          throwsA(isA<MalformedCryptoInputException>()),
        );
      },
    );

    test('the approval is checked: wrong account key, wrong link context, an '
        'approver of another account, a forged signature', () async {
      final r = SeededRandom('approval');
      final eNew = await X25519KeyPair.generate(r);
      const linkId = '0192a4f0-0000-7000-8000-0000000000f1';
      final aik = await Ed25519KeyPair.generate(r);
      final mallory = await Ed25519KeyPair.generate(r);
      final code = LinkCode(
        serverOrigin: 'https://helix.example',
        linkId: linkId,
        ephemeralKey: eNew.publicKey,
      );
      final at = DateTime.utc(2026, 10, 1);
      Future<LocalDeviceKeys> device(Ed25519KeyPair key, String account) =>
          LocalDeviceKeys.create(
            accountIdentityKey: key,
            address: DeviceAddress(account, deviceA1),
            createdAt: at,
            random: r,
          );
      Future<Uint8List> seal(
        LocalDeviceKeys approver,
        Ed25519KeyPair accountKey,
      ) => Provisioning.seal(
        linkCode: code,
        approver: approver,
        accountKey: accountKey,
        profileKey: r.nextBytes(32),
        random: r,
      );
      Future<void> rejects(Uint8List sealed) =>
          expectThrows<UntrustedIdentityException>(
            Provisioning.open(
              ephemeralKey: eNew,
              linkId: linkId,
              sealed: sealed,
            ),
          );

      // The honest case opens.
      final good = await device(aik, accountA);
      await Provisioning.open(
        ephemeralKey: eNew,
        linkId: linkId,
        sealed: await seal(good, aik),
      );

      // An approver certified by another AIK than the one it hands over.
      await rejects(await seal(await device(mallory, accountA), aik));
      // The AIK handed over is not the one the approver belongs to.
      await rejects(await seal(good, mallory));

      // An approval signed for another link or another ephemeral key
      // cannot be replayed: re-seal the same message with a different
      // approval body.
      final otherCode = LinkCode(
        serverOrigin: 'https://helix.example',
        linkId: '0192a4f0-0000-7000-8000-0000000000f2',
        ephemeralKey: eNew.publicKey,
      );
      final lifted = ProvisionMessage(
        accountId: accountA,
        identityKeySeed: aik.seed,
        identityKey: aik.publicKey,
        profileKey: r.nextBytes(32),
        approver: good.identity,
        approval: await good.signingKey.sign(
          Provisioning.approvalBody(
            linkId: otherCode.linkId,
            ephemeralKey: eNew.publicKey,
            accountId: accountA,
            identityKey: aik.publicKey,
          ),
        ),
      );
      final ephemeral = await X25519KeyPair.generate(r);
      final shared = await ephemeral.agree(eNew.publicKey);
      final sealedLifted = Uint8List.fromList([
        ...ephemeral.publicKey,
        ...await AeadKey.derive(shared, Provisioning.info).seal(
          utf8.encode(jsonEncode(lifted.toJson())),
          aad: Provisioning.associatedData(linkId),
        ),
      ]);
      await rejects(sealedLifted);
    });
  });

  group('group state and profile blobs', () {
    test('random nonces, AAD binding, padding', () async {
      final r = SeededRandom('blob');
      final gmk = newSymmetricKey(r);
      final aad = SealedBlobCipher.groupStateAad(groupG, 2, 5);
      final one = await SealedBlobCipher.groupState.seal(
        secret: gmk,
        plaintext: utf8.encode('{"name":"x"}'),
        aad: aad,
        random: r,
      );
      final two = await SealedBlobCipher.groupState.seal(
        secret: gmk,
        plaintext: utf8.encode('{"name":"x"}'),
        aad: aad,
        random: r,
      );
      expect(one, isNot(two), reason: 'a fresh nonce every time');
      expect(one, hasLength(1 + 12 + 160 + 16));
      expect(
        utf8.decode(
          await SealedBlobCipher.groupState.open(
            secret: gmk,
            blob: one,
            aad: aad,
          ),
        ),
        '{"name":"x"}',
      );
      await expectThrows<DecryptionFailedException>(
        SealedBlobCipher.groupState.open(
          secret: gmk,
          blob: one,
          aad: SealedBlobCipher.groupStateAad(groupG, 3, 5),
        ),
      );
      // The state version is bound too: an older blob cannot pass for the
      // current version.
      await expectThrows<DecryptionFailedException>(
        SealedBlobCipher.groupState.open(
          secret: gmk,
          blob: one,
          aad: SealedBlobCipher.groupStateAad(groupG, 2, 6),
        ),
      );
      expect(
        SealedBlobCipher.groupStateAad(groupG, 2, 5),
        hasLength(11 + 16 + 4 + 4),
      );
      await expectThrows<DecryptionFailedException>(
        SealedBlobCipher.profile.open(secret: gmk, blob: one, aad: aad),
      );
    });
  });

  group('prekey policy', () {
    test('replenishment thresholds and batch sizes', () {
      expect(PrekeyPolicy.oneTimePrekeysToUpload(100), 0);
      expect(PrekeyPolicy.oneTimePrekeysToUpload(20), 0);
      expect(PrekeyPolicy.oneTimePrekeysToUpload(19), 100);
      expect(PrekeyPolicy.oneTimePrekeysToUpload(0), 100);
      expect(
        PrekeyPolicy.replenishBatch,
        lessThanOrEqualTo(PrekeyPolicy.maxPerRequest),
      );
      expect(PrekeyPolicy.nextId(PrekeyPolicy.maxPrekeyId), 1);
    });

    test('SPK rotation after 7 days; old SPKs kept 30 days', () async {
      final r = SeededRandom('spk');
      final dsk = await Ed25519KeyPair.generate(r);
      final gen = PrekeyGenerator(random: r);
      final t0 = DateTime.utc(2026, 10, 1);
      final s1 = await gen.signedPrekey(
        id: 1,
        deviceSigningKey: dsk,
        createdAt: t0,
      );
      expect(
        PrekeyPolicy.signedPrekeyDue(t0, t0.add(const Duration(days: 6))),
        isFalse,
      );
      expect(
        PrekeyPolicy.signedPrekeyDue(t0, t0.add(const Duration(days: 7))),
        isTrue,
      );
      final t1 = t0.add(const Duration(days: 7));
      final s2 = await gen.signedPrekey(
        id: 2,
        deviceSigningKey: dsk,
        createdAt: t1,
      );
      expect(
        PrekeyPolicy.expiredSignedPrekeys([
          s1,
          s2,
        ], t1.add(const Duration(days: 29))),
        isEmpty,
      );
      expect(
        PrekeyPolicy.expiredSignedPrekeys([
          s2,
          s1,
        ], t1.add(const Duration(days: 30))),
        [1],
      );
      final opks = await gen.oneTimePrekeys(afterId: 0xfffffe, count: 3);
      expect([for (final k in opks) k.id], [0xffffff, 1, 2]);
      expect(
        SignedPrekeyRecord.fromJson(JsonReader(s1.toJson())).toWire().toJson(),
        s1.toWire().toJson(),
      );
    });
  });

  group('device addresses from the wire', () {
    test('a malformed address is a FormatException, not an ArgumentError', () {
      for (final source in [
        '{"account":"not-a-uuid","device":"$deviceA1"}',
        '{"account":"$accountA","device":"x"}',
        '{"account":"$accountA@","device":"$deviceA1"}',
        '{"account":"$accountA@bad domain","device":"$deviceA1"}',
      ]) {
        expect(
          () => DeviceAddress.fromJson(JsonReader.decode(source)),
          throwsA(isA<ProtocolFormatException>()),
          reason: source,
        );
      }
      final ok = DeviceAddress.fromJson(
        JsonReader.decode('{"account":"$accountA","device":"$deviceA1"}'),
      );
      expect(ok.account, accountA);
    });
  });
}
