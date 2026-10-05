import 'dart:convert';
import 'dart:typed_data';

import 'package:helix_remote_crypto/src/v2/primitives.dart';
import 'package:helix_remote_crypto/v2.dart';
import 'package:helix_remote_protocol/helix_remote_protocol.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Rebuilds the byte layouts of CRYPTO_V2.md by hand (independently of the
/// implementation's helpers) and checks the implementation and the protocol
/// DTOs agree with them.
void main() {
  final ascii8 = ascii.encode;
  Uint8List be32(int v) => Uint8List(4)..buffer.asByteData().setUint32(0, v);
  Uint8List be64(int v) => Uint8List(8)..buffer.asByteData().setUint64(0, v);
  Uint8List uuid16(String u) => unhex(u.replaceAll('-', ''));

  late TestClock clock;
  late TestAccount alice;
  late TestAccount bob;
  late TestDevice a;
  late TestDevice b;

  setUp(() async {
    clock = TestClock();
    final random = SeededRandom('layout');
    alice = await TestAccount.create(accountA, random);
    bob = await TestAccount.create(accountB, random);
    a = await TestDevice.create(alice, deviceA1, random, clock);
    b = await TestDevice.create(bob, deviceB1, random, clock);
    b.trust(a);
  });

  test('§2 device certificate, DSK proof and SPK signature bodies', () async {
    final keys = a.keys;
    final body = [
      ...ascii8('helix.v2.device-cert'),
      1,
      ...uuid16(accountA),
      ...uuid16(deviceA1),
      ...keys.identityKey.publicKey,
      ...keys.signingKey.publicKey,
      ...be64(clock.now.millisecondsSinceEpoch),
    ];
    expect(
      await ed25519Verify(
        publicKey: alice.aik.publicKey,
        message: body,
        signature: keys.certificate.signature,
      ),
      isTrue,
    );
    final registration = await keys.registration(
      name: 'test',
      platform: DevicePlatform.cli,
    );
    expect(
      await ed25519Verify(
        publicKey: keys.signingKey.publicKey,
        message: body,
        signature: registration.proof,
      ),
      isTrue,
    );
    final spk = b.prekeys.signed[1]!;
    expect(
      await ed25519Verify(
        publicKey: b.keys.signingKey.publicKey,
        message: [
          ...ascii8('helix.v2.spk'),
          ...be32(1),
          ...spk.keyPair.publicKey,
        ],
        signature: spk.signature,
      ),
      isTrue,
    );
  });

  test('§4-5 X3DH, AD, header bytes and the first message by hand', () async {
    // Replay the initiator's randomness: EK, then the first DHs.
    final rngSeed = 'x3dh-by-hand';
    final bundle = await b.verifiedBundle();
    final manager = DeviceSessionManager(
      local: a.keys,
      sessions: a.sessions,
      prekeys: a.prekeys,
      identities: a.identities,
      random: SeededRandom(rngSeed),
      clock: clock.call,
    );
    a.sessions.save(await manager.startSession(bundle));
    final out = await manager.encrypt(b.address, utf8.encode('by hand'));
    final message = out.payload as PrekeyMessage;

    final replay = SeededRandom(rngSeed);
    final ek = await X25519KeyPair.fromPrivateKey(replay.nextBytes(32));
    final dhs = await X25519KeyPair.fromPrivateKey(replay.nextBytes(32));
    expect(message.ephemeralKey, ek.publicKey);
    expect(message.header.ratchetKey, dhs.publicKey);

    final spkB = b.prekeys.signed[1]!.keyPair.publicKey;
    final opkB = b.prekeys.oneTime[1]!.keyPair.publicKey;
    final sk = hkdf(
      ikm: [
        ...List.filled(32, 0xff),
        ...await a.keys.identityKey.agree(spkB),
        ...await ek.agree(b.keys.identityKey.publicKey),
        ...await ek.agree(spkB),
        ...await ek.agree(opkB),
      ],
      salt: Uint8List(32),
      info: ascii8('helix.v2.x3dh'),
      length: 32,
    );
    final ad = [
      ...ascii8('helix.v2.ad'),
      ...uuid16(accountA),
      ...uuid16(deviceA1),
      ...a.keys.identityKey.publicKey,
      ...uuid16(accountB),
      ...uuid16(deviceB1),
      ...b.keys.identityKey.publicKey,
    ];
    final session = DeviceSessions.decode(a.sessions.rows[b.address]!).active!;
    expect(session.associatedData, ad);

    final root = hkdf(
      ikm: await dhs.agree(spkB),
      salt: sk,
      info: ascii8('helix.v2.ratchet.root'),
      length: 64,
    );
    final cks = root.sublist(32);
    final mk = hmacSha256(cks, [1]);
    final keyNonce = hkdf(
      ikm: mk,
      salt: Uint8List(32),
      info: ascii8('helix.v2.message'),
      length: 44,
    );
    final headerBytes = [
      ...ascii8('helix.v2.hdr'),
      ...dhs.publicKey,
      ...be32(0),
      ...be32(0),
    ];
    expect(message.header.toAuthenticatedBytes(), headerBytes);
    final padded = await Aead.open(
      key: keyNonce.sublist(0, 32),
      nonce: keyNonce.sublist(32),
      ciphertext: message.ciphertext,
      aad: [...ad, ...headerBytes],
    );
    // §6 padding: content ‖ 0x80 ‖ 0x00… to a multiple of 160.
    expect(padded, hasLength(160));
    expect(utf8.decode(padded.sublist(0, 7)), 'by hand');
    expect(padded[7], 0x80);
    expect(padded.sublist(8).every((x) => x == 0), isTrue);
  });

  test('§8 sealed payload JSON shapes match the protocol DTOs', () async {
    await a.startSessionWith(b);
    final prekey = jsonDecode(utf8.decode(await a.send(b, 'x'))) as Map;
    expect(prekey.keys.toSet(), {
      'v',
      't',
      'dik',
      'ek',
      'spk',
      'opk',
      'h',
      'ct',
    });
    expect(prekey['v'], 2);
    expect(prekey['t'], 'prekey');
    expect((prekey['h'] as Map).keys.toSet(), {'dh', 'pn', 'n'});
    await b.receive(a, utf8.encode(jsonEncode(prekey)));
    a.trust(b);
    final ratchet = jsonDecode(utf8.decode(await b.send(a, 'y'))) as Map;
    expect(ratchet.keys.toSet(), {'v', 't', 'h', 'ct'});
    expect(ratchet['t'], 'ratchet');

    final roster = GroupRoster(
      groupId: groupG,
      members: {accountA, accountB},
      devices: {b.address},
    );
    final group = SenderKeyGroupProtocol(
      self: a.address,
      store: _NoKeys(),
      random: SeededRandom('g'),
    );
    final out = await group.encrypt(roster: roster, content: [1]);
    final sk = jsonDecode(utf8.decode(out.payload.encode())) as Map;
    expect(sk.keys.toSet(), {'v', 't', 'dist', 'it', 'ct', 'sig'});
    expect(sk['t'], 'sender_key');
  });

  test('§6 padded ciphertext sizes hide lengths in 160-byte steps', () async {
    await a.startSessionWith(b);
    for (final (length, padded) in [(0, 160), (159, 160), (160, 320)]) {
      final out = await a.manager.encrypt(b.address, Uint8List(length));
      a.sessions.save(out.sessions);
      expect((out.payload as PrekeyMessage).ciphertext, hasLength(padded + 16));
    }
  });

  test('§7 sender-key AAD, signature input and message key by hand', () async {
    final state = await SenderKeyState.create(
      roster: GroupRoster(groupId: groupG, members: {accountA}, devices: {}),
      random: SeededRandom('sk'),
      now: clock.now,
    );
    final (message, _) = await GroupSenderChain.encrypt(
      state,
      utf8.encode('g'),
    );
    final dist = uuid16(state.distributionId);
    final aad = [
      ...ascii8('helix.v2.sk'),
      ...uuid16(groupG),
      ...dist,
      ...be32(0),
    ];
    final sigInput = [
      ...ascii8('helix.v2.sk-sig'),
      ...uuid16(groupG),
      ...dist,
      ...be32(0),
      ...message.ciphertext,
    ];
    expect(
      await ed25519Verify(
        publicKey: state.signingKey.publicKey,
        message: sigInput,
        signature: message.signature,
      ),
      isTrue,
    );
    final mk = hmacSha256(state.chainKey, [1]);
    final kn = hkdf(
      ikm: mk,
      salt: Uint8List(32),
      info: ascii8('helix.v2.sender-key'),
      length: 44,
    );
    final padded = await Aead.open(
      key: kn.sublist(0, 32),
      nonce: kn.sublist(32),
      ciphertext: message.ciphertext,
      aad: aad,
    );
    expect(padded.first, utf8.encode('g').single);
    // The distribution DTO carries exactly the state the receiver needs.
    final d = state.distribution();
    expect(d.iteration, 0);
    expect(d.chainKey, state.chainKey);
    expect(d.signingKey, state.signingKey.publicKey);
  });

  test('§2a provisioning and §11 wrapped AIK by hand', () async {
    final random = SeededRandom('prov');
    final eNew = await X25519KeyPair.generate(random);
    const linkId = '0192a4f0-0000-7000-8000-0000000000f1';
    final code = LinkCode(
      serverOrigin: 'https://helix.example:8443',
      linkId: linkId,
      ephemeralKey: eNew.publicKey,
    );
    expect(
      code.encode(),
      startsWith('helix-link:1:https://helix.example:8443:'),
    );
    expect(LinkCode.parse(code.encode()).linkId, linkId);
    final sealed = await Provisioning.seal(
      linkCode: code,
      approver: a.keys,
      accountKey: alice.aik,
      profileKey: Uint8List(32),
      phoneMask: '+88017*****01',
      helixName: 'alice',
      random: random,
    );
    final kn = hkdf(
      ikm: await eNew.agree(sealed.sublist(0, 32)),
      salt: Uint8List(32),
      info: ascii8('helix.v2.provision'),
      length: 44,
    );
    final json = await Aead.open(
      key: kn.sublist(0, 32),
      nonce: kn.sublist(32),
      ciphertext: sealed.sublist(32),
      aad: [...ascii8('helix.v2.provision'), ...uuid16(linkId)],
    );
    final provision = (jsonDecode(utf8.decode(json)) as Map)
        .cast<String, Object?>();
    expect(provision.keys.toSet(), {
      'account_id',
      'identity_key_private',
      'identity_key',
      'profile_key',
      'approver',
      'approval',
      'phone_mask',
      'helix_name',
    });
    // The approval is the approver's DSK signature over
    // label ‖ link_id ‖ E_new ‖ account ‖ AIK.
    expect(
      Provisioning.approvalBody(
        linkId: linkId,
        ephemeralKey: eNew.publicKey,
        accountId: accountA,
        identityKey: alice.aik.publicKey,
      ),
      [
        ...ascii8('helix.v2.provision-approval'),
        ...uuid16(linkId),
        ...eNew.publicKey,
        ...uuid16(accountA),
        ...alice.aik.publicKey,
      ],
    );
    expect(
      await ed25519Verify(
        publicKey: a.keys.signingKey.publicKey,
        message: Provisioning.approvalBody(
          linkId: linkId,
          ephemeralKey: eNew.publicKey,
          accountId: accountA,
          identityKey: alice.aik.publicKey,
        ),
        signature: decodeBytes(provision['approval']! as String),
      ),
      isTrue,
    );
  });

  test('§12 attachment header layout and ciphertext length', () async {
    final key = AttachmentCrypto.newKey(SeededRandom('att'));
    for (final length in [0, 1, 1024, 4096, 5000]) {
      final out = await AttachmentCrypto.encryptBytes(
        Uint8List(length),
        key,
        random: SeededRandom('att$length'),
        chunkSize: 1024,
      );
      final c = out.ciphertext;
      expect(ascii.decode(c.sublist(0, 4)), 'HXS2');
      expect(c[4], 2);
      expect(ByteData.sublistView(c).getUint32(5), 1024);
      expect(
        c,
        hasLength(AttachmentCrypto.ciphertextLength(length, chunkSize: 1024)),
      );
      expect(out.digest, sha256(c));
    }
  });
}

final class _NoKeys implements SenderKeyStore {
  @override
  Future<SenderKeyState?> ownKey(String groupId) async => null;

  @override
  Future<ReceivedSenderKey?> receivedKey(
    DeviceAddress sender,
    String groupId,
    String distributionId,
  ) async => null;
}
