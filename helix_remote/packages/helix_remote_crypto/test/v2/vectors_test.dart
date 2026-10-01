import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Golden vectors in `test/v2/vectors/`, generated from seeded randomness.
/// Each test regenerates its vector and compares it with the file, then
/// consumes the file independently (keys and ciphertexts read back from the
/// JSON). Regenerate deliberately with `HELIX_UPDATE_VECTORS=1 dart test
/// test/v2` and review the diff: a changed vector is a wire change.
void main() {
  final t0 = DateTime.utc(2026, 10, 1, 12);
  String b64(List<int> b) => encodeBytes(b);
  Uint8List unb64(Object? s) => decodeBytes(s! as String);
  JsonMap obj(Object? o) => (o! as Map).cast<String, Object?>();

  test('primitives: KDF_RK, KDF_CK, message keys', () {
    final rk = SeededRandom('vec-rk').nextBytes(32);
    final dh = SeededRandom('vec-dh').nextBytes(32);
    final (rk2, ck) = kdfRoot(rk, dh);
    final (mk, ck2) = kdfChain(ck);
    final key = ratchetMessageKey(mk);
    final sk = GroupSenderChain.messageKey(mk);
    expectVector('primitives', {
      'kdf_rk': {
        'rk': b64(rk),
        'dh': b64(dh),
        'rk_out': b64(rk2),
        'ck': b64(ck),
      },
      'kdf_ck': {'ck': b64(ck), 'mk': b64(mk), 'ck_out': b64(ck2)},
      'message_key': {'key': b64(key.key), 'nonce': b64(key.nonce)},
      'sender_key_message_key': {'key': b64(sk.key), 'nonce': b64(sk.nonce)},
    });
  });

  group('pairwise session', () {
    Future<(TestDevice, TestDevice)> devices() async {
      final clock = TestClock(t0);
      final keys = SeededRandom('vec-keys');
      final alice = await TestAccount.create(accountA, keys);
      final bob = await TestAccount.create(accountB, keys);
      final a = await TestDevice.create(
        alice,
        deviceA1,
        keys,
        clock,
        oneTimePrekeys: 1,
      );
      final b = await TestDevice.create(
        bob,
        deviceB1,
        keys,
        clock,
        oneTimePrekeys: 1,
      );
      return (a, b);
    }

    DeviceSessionManager manager(
      TestDevice d,
      String seed, {
      MemoryPrekeyStore? prekeys,
      MemoryIdentityResolver? identities,
      LocalDeviceKeys? keys,
    }) => DeviceSessionManager(
      local: keys ?? d.keys,
      sessions: d.sessions,
      prekeys: prekeys ?? d.prekeys,
      identities: identities ?? d.identities,
      random: SeededRandom(seed),
      clock: () => t0,
    );

    test('X3DH + Double Ratchet conversation', () async {
      final (a, b) = await devices();
      a.trust(b);
      b.trust(a);
      final am = manager(a, 'vec-a-session');
      final bm = manager(b, 'vec-b-session');
      final messages = <JsonMap>[];

      Future<void> send(
        DeviceSessionManager from,
        TestDevice fromDevice,
        DeviceSessionManager to,
        TestDevice toDevice,
        String text,
      ) async {
        final out = await from.encrypt(toDevice.address, utf8.encode(text));
        fromDevice.sessions.save(out.sessions);
        final got = await to.decrypt(
          sender: fromDevice.address,
          payload: SealedPayload.decode(out.payload.encode()),
        );
        toDevice.sessions.save(got.sessions);
        expect(utf8.decode(got.content), text);
        messages.add({
          'from': fromDevice.address.toString(),
          'content': text,
          'payload': out.payload.toJson(),
        });
      }

      a.sessions.save(await am.startSession(await b.verifiedBundle()));
      await send(am, a, bm, b, 'Hello Bob');
      await send(am, a, bm, b, 'Are you there?');
      await send(bm, b, am, a, 'Hi Alice');
      await send(am, a, bm, b, 'Ratchet turned');

      expectVector('pairwise', {
        'description':
            'Alice (initiator) and Bob; Bob decrypts the A->B payloads with '
            'the keys below and, with rng "vec-b-session", re-encrypts the '
            'B->A payload byte for byte.',
        'time': toWireTime(t0),
        'alice': {
          'aik': b64(a.account.aik.publicKey),
          'device': a.keys.identity.toJson(),
        },
        'bob': {
          'aik': b64(b.account.aik.publicKey),
          'device_keys': b.keys.toJson(),
          'signed_prekey': b.prekeys.signed[1]!.toJson(),
          'one_time_prekey': b.prekeys.oneTime[1]!.toJson(),
        },
        'messages': messages,
      });

      // Consume the file.
      final v = readVector('pairwise');
      final bobJson = obj(v['bob']);
      final bobKeys = LocalDeviceKeys.fromJson(
        JsonReader(obj(bobJson['device_keys'])),
      );
      final prekeys = MemoryPrekeyStore()
        ..signed[1] = SignedPrekeyRecord.fromJson(
          JsonReader(obj(bobJson['signed_prekey'])),
        )
        ..oneTime[1] = OneTimePrekeyRecord.fromJson(
          JsonReader(obj(bobJson['one_time_prekey'])),
        );
      final aliceIdentity = DeviceIdentity.fromJson(
        JsonReader(obj(obj(v['alice'])['device'])),
      );
      final identities = MemoryIdentityResolver()
        ..known[aliceIdentity.address] = aliceIdentity;
      final store = MemorySessionStore();
      final fresh = DeviceSessionManager(
        local: bobKeys,
        sessions: store,
        prekeys: prekeys,
        identities: identities,
        random: SeededRandom('vec-b-session'),
        clock: () => t0,
      );
      for (final raw in (v['messages']! as List).cast<Map<String, Object?>>()) {
        final m = raw.cast<String, Object?>();
        final payloadBytes = utf8.encode(jsonEncode(m['payload']));
        if (m['from'] == aliceIdentity.address.toString()) {
          final got = await fresh.decrypt(
            sender: aliceIdentity.address,
            payload: SealedPayload.decode(payloadBytes),
          );
          store.save(got.sessions);
          expect(utf8.decode(got.content), m['content']);
        } else {
          final out = await fresh.encrypt(
            aliceIdentity.address,
            utf8.encode(m['content']! as String),
          );
          store.save(out.sessions);
          expect(out.payload.encode(), payloadBytes);
        }
      }
    });
  });

  test('sender keys: distribution and messages', () async {
    final state0 = await SenderKeyState.create(
      roster: GroupRoster(
        groupId: groupG,
        members: {accountA, accountB},
        devices: {DeviceAddress(accountB, deviceB1)},
      ),
      random: SeededRandom('vec-sk'),
      now: t0,
    );
    var state = state0;
    final messages = <JsonMap>[];
    for (final text in ['one', 'two', 'three']) {
      final (m, next) = await GroupSenderChain.encrypt(
        state,
        utf8.encode(text),
      );
      state = next;
      messages.add({'content': text, 'payload': m.toJson()});
    }
    expectVector('sender_keys', {
      'group_id': groupG,
      'sender': DeviceAddress(accountA, deviceA1).toJson(),
      'distribution': state0.distribution().toJson(),
      'messages': messages,
    });

    final v = readVector('sender_keys');
    var key = ReceivedSenderKey.fromDistribution(
      DeviceAddress.fromJson(JsonReader(obj(v['sender']))),
      SenderKeyDistributionBody.fromJson(JsonReader(obj(v['distribution']))),
      t0,
    );
    final list = (v['messages']! as List).cast<Map<String, Object?>>();
    for (final i in [2, 0, 1]) {
      final m = list[i].cast<String, Object?>();
      final payload = SealedPayload.decode(
        utf8.encode(jsonEncode(m['payload'])),
      );
      final (content, next) = await GroupSenderChain.decrypt(
        key,
        payload as SenderKeyMessage,
        now: t0,
      );
      key = next;
      expect(utf8.decode(content), m['content']);
    }
  });

  test('safety number', () async {
    final r = SeededRandom('vec-sn');
    final ka = await Ed25519KeyPair.generate(r);
    final kb = await Ed25519KeyPair.generate(r);
    final number = SafetyNumber.compute(
      localAccount: accountB,
      localIdentityKey: kb.publicKey,
      remoteAccount: accountA,
      remoteIdentityKey: ka.publicKey,
    );
    expectVector('safety_number', {
      'account_a': accountA,
      'aik_a': b64(ka.publicKey),
      'account_b': accountB,
      'aik_b': b64(kb.publicKey),
      'digits': number.digits,
      'qr': b64(number.qrPayload),
    });
    final v = readVector('safety_number');
    expect(
      SafetyNumber.compute(
        localAccount: accountA,
        localIdentityKey: unb64(v['aik_a']),
        remoteAccount: accountB,
        remoteIdentityKey: unb64(v['aik_b']),
      ).digits,
      v['digits'],
    );
  });

  test('attachment, blobs, provisioning, backups and password', () async {
    final r = SeededRandom('vec-misc');
    final attKey = AttachmentCrypto.newKey(r);
    final attPlain = Uint8List.fromList(List.generate(150, (i) => i));
    final att = await AttachmentCrypto.encryptBytes(
      attPlain,
      attKey,
      random: r,
      chunkSize: 64,
    );

    final profileKey = newSymmetricKey(r);
    final profile = await SealedBlobCipher.profile.seal(
      secret: profileKey,
      plaintext: utf8.encode('{"name":"Alice"}'),
      aad: SealedBlobCipher.profileAad(accountA, 1),
      random: r,
    );

    final eNew = await X25519KeyPair.generate(r);
    const linkId = '0192a4f0-0000-7000-8000-0000000000f1';
    final aik = await Ed25519KeyPair.generate(r);
    final provision = await Provisioning.seal(
      linkCode: LinkCode(
        serverOrigin: 'https://helix.example',
        linkId: linkId,
        ephemeralKey: eNew.publicKey,
      ),
      message: ProvisionMessage(
        accountId: accountA,
        identityKeySeed: aik.seed,
        identityKey: aik.publicKey,
        profileKey: profileKey,
        approverDeviceId: deviceA1,
      ),
      random: r,
    );

    const backupId = '0192a4f0-0000-7000-8000-0000000000bb';
    const secret = 'vector recovery secret words';
    final backup = await BackupCrypto.seal(
      plaintext: utf8.encode('backup payload'),
      backupId: backupId,
      backupVersion: 1,
      recoverySecret: secret,
      createdAt: t0,
      random: r,
    );
    final history = await HistoryBackupCrypto.seal(
      identityKeySeed: aik.seed,
      accountId: accountA,
      version: 1,
      plaintext: utf8.encode('history payload'),
      random: r,
    );

    final salt = PasswordKeys.newSalt(r);
    final pw = await PasswordKeys.derive(
      password: 'vector password',
      salt: salt,
    );
    final wrapped = await pw.wrapIdentityKey(
      identityKeySeed: aik.seed,
      accountId: accountA,
      random: r,
    );

    expectVector('misc', {
      'attachment': {
        'key': b64(attKey),
        'chunk_size': 64,
        'plaintext': b64(attPlain),
        'ciphertext': b64(att.ciphertext),
        'digest': b64(att.digest),
      },
      'profile_blob': {
        'account': accountA,
        'version': 1,
        'key': b64(profileKey),
        'blob': b64(profile),
      },
      'provisioning': {
        'link_id': linkId,
        'e_new_private': b64(eNew.privateKey),
        'sealed': b64(provision),
      },
      'full_backup': {'secret': secret, 'envelope': backup.toJson()},
      'history_backup': {
        'aik_seed': b64(aik.seed),
        'account': accountA,
        'version': 1,
        'data': b64(history),
      },
      'password': {
        'password': 'vector password',
        'salt': b64(salt),
        'kdf': const KdfParams().toJson(),
        'auth_key': b64(pw.authKey),
        'wrapped_aik': wrapped.toJson(),
        'aik': b64(aik.publicKey),
      },
    });

    final v = readVector('misc');
    final va = obj(v['attachment']);
    expect(
      await AttachmentCrypto.decryptBytes(
        unb64(va['ciphertext']),
        unb64(va['key']),
        digest: unb64(va['digest']),
      ),
      unb64(va['plaintext']),
    );
    final vp = obj(v['profile_blob']);
    expect(
      utf8.decode(
        await SealedBlobCipher.profile.open(
          secret: unb64(vp['key']),
          blob: unb64(vp['blob']),
          aad: SealedBlobCipher.profileAad(accountA, 1),
        ),
      ),
      '{"name":"Alice"}',
    );
    final vl = obj(v['provisioning']);
    final opened = await Provisioning.open(
      ephemeralKey: await X25519KeyPair.fromPrivateKey(
        unb64(vl['e_new_private']),
      ),
      linkId: vl['link_id']! as String,
      sealed: unb64(vl['sealed']),
    );
    expect(opened.accountId, accountA);
    final vb = obj(v['full_backup']);
    expect(
      utf8.decode(
        await BackupCrypto.open(
          BackupEnvelope.fromJson(JsonReader(obj(vb['envelope']))),
          recoverySecret: vb['secret']! as String,
        ),
      ),
      'backup payload',
    );
    final vh = obj(v['history_backup']);
    expect(
      utf8.decode(
        await HistoryBackupCrypto.open(
          identityKeySeed: unb64(vh['aik_seed']),
          accountId: accountA,
          version: 1,
          data: unb64(vh['data']),
        ),
      ),
      'history payload',
    );
    final vw = obj(v['password']);
    final derived = await PasswordKeys.derive(
      password: vw['password']! as String,
      salt: unb64(vw['salt']),
      params: KdfParams.fromJson(JsonReader(obj(vw['kdf']))),
    );
    expect(derived.authKey, unb64(vw['auth_key']));
    final unwrapped = await derived.unwrapIdentityKey(
      wrapped: WrappedKey.fromJson(JsonReader(obj(vw['wrapped_aik']))),
      accountId: accountA,
      expectedPublicKey: unb64(vw['aik']),
    );
    expect(unwrapped.publicKey, unb64(vw['aik']));
  });
}
